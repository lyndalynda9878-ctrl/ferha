import 'package:flutter_test/flutter_test.dart';

import 'textes_traduits.dart';
import 'package:ferha/features/booking/reservation.dart';
import 'package:ferha/features/booking/widgets/compte_a_rebours.dart';
import 'package:ferha/features/search/search_filters.dart';

/// Les deux règles de cet écran qui ne se voient pas à l'œil nu.
///
/// La première est une interdiction : aucun code de la base n'atteint l'écran.
/// Elle se teste en balayant l'énumération entière plutôt qu'un cas, parce
/// qu'un septième état ajouté demain doit échouer ici et non en production.
///
/// La seconde est le téléphone du §9. Le test ne vérifie pas que l'écran le
/// cache — il vérifie qu'il n'a rien à cacher : `client_bookings()` renvoie une
/// colonne vide tant que la demande n'est pas acceptée, et le modèle n'invente
/// pas ce qui n'est pas venu.
void main() {
  Map<String, dynamic> ligne({
    String statut = 'pending',
    String? telephone,
    String? expire,
    num? acompte,
    String? motif,
    String? evenement = 'Mariage',
  }) => <String, dynamic>{
    'group_id': 'e279c5d6-0743-409b-a18e-f90aa5ddddfe',
    'booking_id': 'b1000000-0000-4000-8000-000000000001',
    'venue_id': '5a11e000-0000-4000-a000-000000000001',
    'venue_name': 'Salle El Bahia',
    'commune': 'Oran',
    'wilaya_name': 'Oran',
    'cover_photo': 'https://example.test/photo.jpg',
    'event_date': '2026-11-08',
    'requested_slot': 'soir',
    'slots': <String>['soir'],
    'guest_count': 320,
    'event_type': 'mariage',
    'event_label': evenement,
    'status': statut,
    'status_reason': motif,
    'quoted_amount': 238000.00,
    'deposit_amount': acompte,
    'option_expires_at': expire,
    'created_at': '2026-09-09T17:45:00+00:00',
    'owner_name': 'Karim Belhadj',
    'owner_phone': telephone,
    'phone_available': telephone != null,
  };

  group('Aucun code de la base n’atteint l’écran', () {
    test('les sept états ont un libellé français, et aucun n’est un code', () {
      for (final etat in EtatReservation.values) {
        expect(
          etat.libelle,
          isNot(equals(etat.code)),
          reason: '${etat.code} s’afficherait tel quel',
        );
        expect(etat.libelle, isNotEmpty);
        expect(etat.explication, isNotEmpty);

        // Les sept codes de bookings.status sont tous en anglais : aucun ne
        // doit se retrouver dans un texte affiché, ni seul ni au milieu d’une
        // phrase.
        for (final code in EtatReservation.values.map((e) => e.code)) {
          expect(etat.libelle.toLowerCase(), isNot(contains(code)));
          expect(etat.explication.toLowerCase(), isNot(contains(code)));
        }
      }
    });

    test('« pending » se lit « En attente de réponse »', () {
      expect(
        EtatReservation.depuisCode('pending').libelle,
        'En attente de réponse',
      );
    });

    test('un code inconnu est une erreur de programme, pas un état', () {
      // La contrainte CHECK de bookings.status interdit tout le reste : si
      // cette valeur arrivait, ce serait un bug, et il vaut mieux qu’il se voie.
      expect(
        () => EtatReservation.depuisCode('brouillon'),
        throwsArgumentError,
      );
    });
  });

  group('Le téléphone du propriétaire (§9)', () {
    test('une demande en attente n’en porte aucun', () {
      final r = Reservation.depuisJson(ligne());

      expect(r.etat, EtatReservation.enAttente);
      expect(r.telephone, isNull);
      // Le nom, lui, vient de booking_contact() dans tous les états : c’est
      // déjà le cas depuis 006, et cet écran ne l’élargit pas.
      expect(r.proprietaire, 'Karim Belhadj');
    });

    test('une demande acceptée le porte', () {
      final r = Reservation.depuisJson(
        ligne(statut: 'accepted', telephone: '0770 11 22 33'),
      );

      expect(r.etat, EtatReservation.acceptee);
      expect(r.telephone, '0770 11 22 33');
    });
  });

  group('Ce que le client peut encore faire', () {
    test('une demande en attente s’annule', () {
      expect(EtatReservation.enAttente.annulableParLeClient, isTrue);
    });

    test('les six autres états ne s’annulent pas d’un tap', () {
      // « acceptée » et « confirmée » restent annulables par cancel_booking(),
      // mais il y a un acompte en jeu et le barème du §5.3 s’applique : ce
      // n’est pas un bouton de liste.
      for (final etat in EtatReservation.values.where(
        (e) => e != EtatReservation.enAttente,
      )) {
        expect(etat.annulableParLeClient, isFalse, reason: etat.code);
      }
    });
  });

  group('Le compte à rebours des 72 h', () {
    test('les heures ne se convertissent pas en jours', () {
      // « 2 j 23 h » demande un calcul mental pour savoir si l’on tient
      // jusqu’à demain soir ; « 71 h » se compare directement aux 72 h
      // annoncées. C’est le choix de la maquette.
      expect(
        resteEnMots(textesFr, const Duration(hours: 71, minutes: 12)),
        '71 h 12 min',
      );
    });

    test('les minutes gardent deux chiffres derrière des heures', () {
      // Sinon la ligne danse d’une seconde à l’autre.
      expect(
        resteEnMots(textesFr, const Duration(hours: 71, minutes: 7)),
        '71 h 07 min',
      );
    });

    test('sous une heure, les heures disparaissent', () {
      expect(resteEnMots(textesFr, const Duration(minutes: 12)), '12 min');
    });

    test('sous une minute, on le dit avec des mots', () {
      expect(
        resteEnMots(textesFr, const Duration(seconds: 40)),
        'moins d’une minute',
      );
    });

    test('passé l’échéance, jamais de compteur négatif', () {
      // expire_options() tourne à l’heure (§7.2) : entre l’échéance et son
      // passage, l’écran doit dire « délai écoulé » plutôt que « -0 h 03 min ».
      expect(
        resteEnMots(textesFr, const Duration(minutes: -3)),
        'délai écoulé',
      );
      expect(resteEnMots(textesFr, Duration.zero), 'délai écoulé');
    });
  });

  group('La lecture d’une ligne de client_bookings()', () {
    test('une réservation acceptée porte son acompte et son échéance', () {
      final r = Reservation.depuisJson(
        ligne(
          statut: 'accepted',
          telephone: '0770 11 22 33',
          acompte: 59500.00,
          expire: '2026-09-12T17:48:00+00:00',
        ),
      );

      expect(r.acompte, 59500.00);
      expect(r.optionEnCours, isTrue);
      expect(r.montant, 238000.00);
      expect(r.creneau, Creneau.soir);
      expect(r.invites, 320);
    });

    test('une demande en attente n’a ni acompte ni échéance', () {
      final r = Reservation.depuisJson(ligne());

      expect(r.acompte, isNull);
      expect(r.optionExpireLe, isNull);
      expect(r.optionEnCours, isFalse);
    });

    test('un type d’événement hors référentiel garde son code', () {
      // bookings.event_type est du texte libre depuis 004 : une valeur sans
      // libellé vaut mieux affichée que perdue.
      final r = Reservation.depuisJson(ligne(evenement: null));
      expect(r.typeEvenement, 'mariage');
    });

    test('le motif d’un refus remonte, quand il y en a un', () {
      final r = Reservation.depuisJson(
        ligne(statut: 'refused', motif: 'Déjà réservé par un proche'),
      );

      expect(r.etat, EtatReservation.refusee);
      expect(r.motif, 'Déjà réservé par un proche');
    });
  });
}
