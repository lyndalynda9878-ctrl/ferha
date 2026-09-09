import 'package:flutter_test/flutter_test.dart';

import 'package:ferha/features/owner/demande_en_attente.dart';
import 'package:ferha/features/owner/indicateurs_salle.dart';
import 'package:ferha/features/owner/salle_du_proprietaire.dart';
import 'package:ferha/features/search/search_filters.dart';

/// Ce que la base dit d'une salle, et ce que l'écran en fait.
///
/// LE TEST QUI COMPTE ICI EST CELUI QUI BALAIE `StatutSalle` EN ENTIER. Le jour
/// où un cinquième statut apparaîtra dans la contrainte CHECK de
/// `venues.status`, il doit faire échouer ce fichier — pas se transformer en
/// écran vide chez Karim. Une énumération écrite à la main contre une colonne
/// de la base ne tient que si quelque chose vérifie qu'elles se ressemblent
/// encore.
void main() {
  group('StatutSalle, balayée en entier', () {
    test('chaque statut se retrouve par son code', () {
      for (final statut in StatutSalle.values) {
        expect(
          StatutSalle.depuisCode(statut.code),
          statut,
          reason: 'Le code « ${statut.code} » ne revient pas sur son statut.',
        );
      }
    });

    test('aucun statut n’affiche son code brut', () {
      for (final statut in StatutSalle.values) {
        expect(statut.libelle, isNotEmpty);
        expect(
          statut.libelle,
          isNot(equals(statut.code)),
          reason:
              '« ${statut.code} » est une valeur de colonne, pas une phrase. '
              'Elle ne doit jamais atteindre l’écran.',
        );
      }
    });

    test('les codes sont ceux de la contrainte CHECK de venues.status', () {
      // Écrits ici en toutes lettres, et non dérivés de l'énumération : un test
      // qui lirait `StatutSalle.values` pour se vérifier lui-même ne
      // remarquerait jamais qu'un code a changé de nom. Ces quatre chaînes
      // viennent de la migration 002.
      expect(StatutSalle.values.map((s) => s.code).toList(), <String>[
        'draft',
        'pending',
        'published',
        'suspended',
      ]);
    });

    test('un code inconnu lève, il ne se devine pas', () {
      expect(
        () => StatutSalle.depuisCode('archived'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('« publiée » est le seul statut qui met la salle au catalogue', () {
      final auCatalogue = StatutSalle.values
          .where((s) => s.estAuCatalogue)
          .toList();
      expect(auCatalogue, <StatutSalle>[StatutSalle.publiee]);
    });
  });

  group('SalleDuProprietaire, depuis owner_venues()', () {
    Map<String, dynamic> ligne({
      String? wilaya = 'Oran',
      String statut = 'published',
      int enAttente = 3,
    }) => <String, dynamic>{
      'venue_id': '5a11e000-0000-4000-a000-000000000001',
      'name': 'Salle El Bahia',
      'commune': 'Bir El Djir',
      'wilaya_name': wilaya,
      'status': statut,
      'cover_photo': 'salles/el-bahia/1.jpg',
      'pending_count': enAttente,
    };

    test('lit la ligne telle qu’elle arrive', () {
      final salle = SalleDuProprietaire.depuisJson(ligne());

      expect(salle.nom, 'Salle El Bahia');
      expect(salle.commune, 'Bir El Djir');
      expect(salle.statut, StatutSalle.publiee);
      expect(salle.demandesEnAttente, 3);
      expect(salle.photo, 'salles/el-bahia/1.jpg');
    });

    test('« Oran, Oran » ne s’écrit pas', () {
      final salle = SalleDuProprietaire.depuisJson(<String, dynamic>{
        ...ligne(),
        'commune': 'Oran',
      });
      expect(salle.localisation, 'Oran');
    });

    test('la commune et la wilaya s’écrivent quand elles diffèrent', () {
      expect(
        SalleDuProprietaire.depuisJson(ligne()).localisation,
        'Bir El Djir, Oran',
      );
    });

    test('une wilaya absente laisse la commune seule', () {
      expect(
        SalleDuProprietaire.depuisJson(ligne(wilaya: null)).localisation,
        'Bir El Djir',
      );
    });
  });

  group('IndicateursSalle : les null sont des réponses', () {
    test('une salle sans avis n’a pas une note de zéro', () {
      final i = IndicateursSalle.depuisJson(<String, dynamic>{
        'month': '2026-09-01',
        'occupancy_rate': null,
        'occupancy_delta': null,
        'revenue': 0,
        'revenue_dates': 0,
        'revenue_delta': null,
        'rating': null,
        'review_count': 0,
        'acceptance_rate': null,
        'acceptance_delta': null,
        'decided_count': 0,
        'pending_count': 0,
      });

      // Zéro et « pas de réponse » ne se lisent pas pareil : 0,0 serait la pire
      // note possible, et « — » dit qu'il n'y a encore rien à en dire.
      expect(i.note, isNull);
      expect(i.tauxOccupation, isNull);
      expect(i.tauxAcceptation, isNull);
      expect(i.variationRevenu, isNull);
      expect(i.revenu, 0);
      expect(i.nombreAvis, 0);
    });

    test('les chiffres arrivent tels quels, sans recalcul', () {
      final i = IndicateursSalle.depuisJson(<String, dynamic>{
        'month': '2026-09-01',
        'occupancy_rate': 0.6800,
        'occupancy_delta': 9.0,
        'revenue': 1840000,
        'revenue_dates': 12,
        'revenue_delta': 0.1400,
        'rating': 4.6,
        'review_count': 34,
        'acceptance_rate': 0.4100,
        'acceptance_delta': -6.0,
        'decided_count': 17,
        'pending_count': 3,
      });

      expect(i.mois, DateTime(2026, 9));
      expect(i.tauxOccupation, 0.68);
      expect(i.variationOccupation, 9);
      expect(i.variationRevenu, 0.14);
      expect(i.variationAcceptation, -6);
      expect(i.demandesEnAttente, 3);
    });
  });

  group('DemandeEnAttente', () {
    final arrivee = DateTime(2026, 9, 10, 9);

    DemandeEnAttente demande(DateTime creeLe) =>
        DemandeEnAttente.depuisJson(<String, dynamic>{
          'group_id': 'g1',
          'booking_id': 'b1',
          'client_name': 'Amina K.',
          'event_date': '2027-08-14',
          'requested_slot': 'soir',
          'slots': <String>['soir'],
          'guest_count': 300,
          'event_type': 'wedding',
          'event_label': 'Mariage',
          'quoted_amount': 205000,
          'created_at': creeLe.toUtc().toIso8601String(),
        });

    test('le libellé du référentiel passe devant le code', () {
      expect(demande(arrivee).typeEvenement, 'Mariage');
    });

    test('un type hors référentiel s’affiche quand même', () {
      final d = DemandeEnAttente.depuisJson(<String, dynamic>{
        'group_id': 'g1',
        'booking_id': 'b1',
        'client_name': 'Yacine M.',
        'event_date': '2027-08-14',
        'requested_slot': 'midi',
        'slots': <String>['midi'],
        'guest_count': 180,
        'event_type': 'reunion-familiale',
        'event_label': null,
        'quoted_amount': 90000,
        'created_at': arrivee.toUtc().toIso8601String(),
      });

      expect(d.typeEvenement, 'reunion-familiale');
      expect(d.creneau, Creneau.midi);
    });

    test('l’attente se dit en français, à chaque échelle', () {
      String depuis(Duration ecart) =>
          demande(arrivee.subtract(ecart)).attendDepuis(arrivee);

      expect(depuis(const Duration(seconds: 20)), 'à l’instant');
      expect(depuis(const Duration(minutes: 40)), 'il y a 40 min');
      expect(depuis(const Duration(hours: 2)), 'il y a 2 h');
      expect(depuis(const Duration(hours: 30)), 'hier');
      expect(depuis(const Duration(days: 4)), 'il y a 4 jours');
    });

    test('une horloge en retard ne fait pas parler au futur', () {
      // Un téléphone à l'heure près peut recevoir une demande horodatée
      // quelques secondes plus tard que sa propre montre.
      expect(
        demande(arrivee.add(const Duration(minutes: 5))).attendDepuis(arrivee),
        'à l’instant',
      );
    });

    test('« Nouveau » tient vingt-quatre heures, pas une de plus', () {
      expect(
        demande(
          arrivee.subtract(const Duration(hours: 23)),
        ).estNouvelle(arrivee),
        isTrue,
      );
      expect(
        demande(
          arrivee.subtract(const Duration(hours: 25)),
        ).estNouvelle(arrivee),
        isFalse,
      );
    });
  });
}
