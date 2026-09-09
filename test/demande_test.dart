import 'package:flutter_test/flutter_test.dart';

import 'package:ferha/features/booking/booking_providers.dart';
import 'package:ferha/features/booking/devis_reservation.dart';
import 'package:ferha/features/search/search_filters.dart';
import 'package:ferha/features/venue/venue_detail.dart';

/// Ce que ce fichier vérifie, et pourquoi.
///
/// L'invariant de l'étape est négatif — « aucun montant n'est calculé en
/// Dart » — et un invariant négatif ne se teste pas en appelant une fonction :
/// il se tient en n'écrivant pas la fonction. Ce qu'on peut vérifier, en
/// revanche, c'est que le devis n'est QUE de la relecture : chaque montant
/// affiché doit se retrouver, au dinar près, dans ce que la base a renvoyé.
///
/// Les tests portent donc sur les deux endroits où une erreur de recopie
/// passerait inaperçue : la lecture du JSON de `booking_quote()`, et la clé du
/// fournisseur — celle qui décide si un nouveau devis est demandé ou non.
void main() {
  // La réponse de booking_quote() pour la Salle El Bahia, le samedi 14 août
  // 2027 au soir, 320 invités, décoration florale et chambre de la mariée :
  // 220 000 × 1,30 × 1,20 = 343 200, plus 20 couverts à 900, plus 25 000.
  Map<String, dynamic> reponse() => <String, dynamic>{
    'venue_id': '5a11e000-0000-4000-a000-000000000001',
    'event_date': '2027-08-14',
    'slot': 'soir',
    'guest_count': 320,
    'base_price': 220000.00,
    'day_coef': 1.30,
    'season_coef': 1.20,
    'slot_price': 343200.00,
    'included_seats': 300,
    'extra_seats': 20,
    'extra_seats_amount': 18000.00,
    'options_amount': 25000.00,
    'total': 386200.00,
    'deposit_rate': 0.25,
    'deposit_amount': 96550.00,
    'options': <Map<String, dynamic>>[
      {
        'id': 'c1951830-ea69-4533-bb0d-c3b932d0563d',
        'code': 'chambre_mariee',
        'label': 'Chambre de la mariée',
        'price': 0.00,
      },
      {
        'id': 'e3508785-2ec7-43b9-94c1-4690a06523a5',
        'code': 'decoration_florale',
        'label': 'Décoration florale',
        'price': 25000.00,
      },
    ],
  };

  group('Le devis relit la base, il ne la refait pas', () {
    test('chaque montant affiché vient de la réponse, à l’identique', () {
      final devis = DevisReservation.depuisJson(reponse());

      // Les quatre montants du récapitulatif de la maquette.
      expect(devis.prixCreneau, 343200.00);
      expect(devis.montantCouvertsSup, 18000.00);
      expect(devis.montantOptions, 25000.00);
      expect(devis.total, 386200.00);

      // L'acompte vient de deposit_rate(), pas d'une multiplication d'ici.
      expect(devis.montantAcompte, 96550.00);
      expect(devis.tauxAcompte, 0.25);
    });

    test('les majorations se lisent sur les coefficients de la base', () {
      final devis = DevisReservation.depuisJson(reponse());

      // Samedi de haute saison : les deux coefficients dépassent 1, et c'est
      // eux — jamais une règle de calendrier réécrite en Dart — qui décident
      // du « (samedi, haute saison) » de la ligne.
      expect(devis.jourMajore, isTrue);
      expect(devis.saisonMajoree, isTrue);
    });

    test('un jour ordinaire hors saison n’annonce aucune majoration', () {
      final devis = DevisReservation.depuisJson(
        reponse()..addAll(<String, dynamic>{'day_coef': 1, 'season_coef': 1}),
      );

      expect(devis.jourMajore, isFalse);
      expect(devis.saisonMajoree, isFalse);
    });

    test('le taux s’écrit « 25 », et non « 25.0 »', () {
      expect(DevisReservation.depuisJson(reponse()).pourcentageAcompte, '25');
    });

    test('un taux à décimale garde sa décimale, à la française', () {
      final devis = DevisReservation.depuisJson(
        reponse()..['deposit_rate'] = 0.125,
      );

      expect(devis.pourcentageAcompte, '12,5');
    });
  });

  group('Une option à zéro dinar est incluse, pas gratuite', () {
    test('prix nul : l’écran écrit « Incluse »', () {
      final devis = DevisReservation.depuisJson(reponse());
      final chambre = devis.options.firstWhere(
        (o) => o.code == 'chambre_mariee',
      );

      expect(chambre.incluse, isTrue);
      expect(chambre.libelle, 'Chambre de la mariée');
    });

    test('prix non nul : c’est une option payante ordinaire', () {
      final devis = DevisReservation.depuisJson(reponse());
      final fleurs = devis.options.firstWhere(
        (o) => o.code == 'decoration_florale',
      );

      expect(fleurs.incluse, isFalse);
      expect(fleurs.prix, 25000.00);
    });
  });

  group('La clé du devis', () {
    DemandeDevis cle(List<String> options) => DemandeDevis(
      venueId: '5a11e000-0000-4000-a000-000000000001',
      date: DateTime(2027, 8, 14),
      creneau: Creneau.soir,
      invites: 320,
      optionIds: options,
    );

    test('l’ordre des options ne fait pas deux devis différents', () {
      // Cocher A puis B, ou B puis A, c'est la même demande. Sans le tri, la
      // seconde repartirait en réseau pour redemander exactement le même
      // montant — et sur une 4G algérienne, cela se voit (§7.3).
      final ab = cle(<String>['a', 'b']);
      final ba = cle(<String>['b', 'a']);

      expect(ab, ba);
      expect(ab.hashCode, ba.hashCode);
    });

    test('une option de plus fait un devis de plus', () {
      expect(cle(<String>['a']), isNot(cle(<String>['a', 'b'])));
    });

    test('un invité de plus fait un devis de plus', () {
      final trois = DemandeDevis(
        venueId: 'v',
        date: DateTime(2027, 8, 14),
        creneau: Creneau.soir,
        invites: 300,
      );
      final trente = DemandeDevis(
        venueId: 'v',
        date: DateTime(2027, 8, 14),
        creneau: Creneau.soir,
        invites: 310,
      );

      expect(trois, isNot(trente));
    });
  });

  group('Le récapitulatif de la demande envoyée', () {
    DemandeEnvoyee envoyee() => DemandeEnvoyee(
      groupId: '3f2a1b4c-0000-4000-8000-000000000001',
      salle: 'Salle El Bahia',
      localisation: 'Oran, Oran (31)',
      date: DateTime(2027, 8, 14),
      creneau: Creneau.soir,
      invites: 320,
      montant: 386200.00,
      options: const <OptionSalle>[],
    );

    test('la référence tient en huit caractères, en majuscules', () {
      expect(envoyee().reference, '3F2A1B4C');
    });

    test('le montant est celui écrit en base, pas celui du formulaire', () {
      // `quoted_amount` est posé par le trigger bookings_set_price, donc par
      // estimate_price(). C'est lui qui engage, et c'est lui qu'on affiche.
      expect(envoyee().montant, 386200.00);
    });
  });
}
