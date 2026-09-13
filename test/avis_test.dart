import 'package:flutter_test/flutter_test.dart';

import 'package:ferha/core/router/routes.dart';
import 'package:ferha/features/booking/reservation.dart';
import 'package:ferha/features/notifications/notification_ferha.dart';
import 'package:ferha/features/owner/demande_detail.dart';
import 'package:ferha/features/reviews/avis.dart';

import 'avis_fakes.dart';
import 'owner_fakes.dart';

/// Ce que les modèles des avis promettent, sans écran ni réseau.
///
/// LE GROUPE LE PLUS IMPORTANT EST « L'ANONYMAT ». Il ne remplace pas le test
/// SQL — c'est `avis_de_la_salle()` qui garantit qu'aucun nom entier ne sort de
/// la base — mais il vérifie l'autre moitié : que l'application ne RECOMPOSE
/// rien à partir de ce qu'elle reçoit. Les initiales de la pastille se
/// calculent depuis « Amina H. », jamais depuis un nom qu'on serait allé
/// chercher ailleurs.
void main() {
  group('Ce que la base renvoie', () {
    test('un avis se lit entier, sous-notes comprises', () {
      final avis = AvisPublie.depuisJson(<String, dynamic>{
        'id': 'a1',
        'author': 'Sarah B.',
        'rating': 5,
        'rating_cleanliness': 5,
        'rating_service': 4,
        'body': 'Salle impeccable.',
        'created_at': '2026-08-20T10:00:00Z',
        'owner_reply': 'Merci Sarah.',
        'owner_replied_at': '2026-08-22T09:00:00Z',
      });

      expect(avis.auteur, 'Sarah B.');
      expect(avis.note, 5);
      expect(avis.sousNotes[SousNote.proprete], 5);
      expect(avis.sousNotes[SousNote.service], 4);
      // LES DEUX AUTRES SONT ABSENTES, PAS À ZÉRO. Une sous-note qu'on n'a pas
      // donnée n'est pas un zéro sur cinq, et l'écran n'affiche pas sa barre.
      expect(avis.sousNotes.containsKey(SousNote.rapportQualitePrix), isFalse);
      expect(avis.sousNotes.containsKey(SousNote.conformite), isFalse);
      expect(avis.aUneReponse, isTrue);
    });

    test('une salle sans avis n’est pas une salle mal notée', () {
      final salle = AvisDeLaSalle.depuisJson(<String, dynamic>{
        'venue_id': 'v1',
        'venue_name': 'Salle neuve',
        'rating': null,
        'review_count': 0,
        'reviews': <dynamic>[],
      });

      expect(salle.note, isNull);
      expect(salle.nombre, 0);
      // C'est ce booléen qui empêche l'écran d'écrire « 0,0 » sous cinq étoiles
      // vides.
      expect(salle.estNotee, isFalse);
    });

    test('la fenêtre et l’avis déjà écrit arrivent ensemble', () {
      final aDeposer = AvisADeposer.depuisJson(<String, dynamic>{
        'group_id': 'g1',
        'booking_id': 'b1',
        'venue_id': 'v1',
        'venue_name': 'Salle El Bahia',
        'commune': 'Oran',
        'wilaya_name': 'Oran',
        'event_date': '2026-08-14',
        'requested_slot': 'soir',
        'guest_count': 300,
        'ouvre_le': '2026-08-15',
        'ferme_le': '2026-09-13',
        'fenetre_ouverte': true,
        'modifiable': true,
        'avis_id': 'a1',
        'rating': 4,
        'rating_service': 3,
        'body': 'Très bien dans l’ensemble.',
      });

      expect(aDeposer.dejaDepose, isTrue);
      expect(aDeposer.note, 4);
      expect(aDeposer.sousNotes[SousNote.service], 3);
      expect(aDeposer.fermeLe, DateTime(2026, 9, 13));
      expect(aDeposer.figeParLaReponse, isFalse);
    });

    test('un avis auquel on a répondu est figé', () {
      final aDeposer = aDeposerDeTest(
        bookingId: 'b1',
        venueId: 'v1',
        avisId: 'a1',
        note: 4,
        modifiable: false,
        reponse: 'Merci pour votre passage.',
      );

      expect(aDeposer.figeParLaReponse, isTrue);
      expect(aDeposer.modifiable, isFalse);
    });
  });

  group('L’anonymat', () {
    test('les initiales viennent du nom raccourci, et de rien d’autre', () {
      expect(avisDeTest(id: 'a', auteur: 'Amina H.').initiales, 'AH');
      expect(avisDeTest(id: 'a', auteur: 'Sarah').initiales, 'S');
      // Le cas d'un compte fermé : la base rend « Client » (§9), et la pastille
      // doit quand même s'afficher.
      expect(avisDeTest(id: 'a', auteur: 'Client').initiales, 'C');
    });

    test('le mois suffit à situer une soirée', () {
      final avis = avisDeTest(id: 'a', publieLe: DateTime(2026, 8, 20));
      expect(avis.moisDePublication, 'août 2026');
    });
  });

  group('Où mène « Racontez votre soirée »', () {
    NotificationFerha invitation({String? bookingId = 'bkg-1'}) =>
        NotificationFerha.depuisJson(<String, dynamic>{
          'id': 'n1',
          'type': 'review_invitation',
          'created_at': '2026-08-15T08:00:00Z',
          'read_at': null,
          'payload': <String, dynamic>{
            'role': 'client',
            if (bookingId != null) 'booking_id': bookingId,
            'venue_name': 'Salle El Bahia',
          },
        });

    test('à l’écran de dépôt, et non plus au suivi des réservations', () {
      // C'EST LE POINT DU J17. La notification existait depuis 004 et
      // atterrissait sur « Mes réservations », faute d'écran — une invitation à
      // écrire qui laissait retrouver soi-même la bonne carte dans une liste.
      expect(invitation().destination, FerhaRoutes.deposerAvisDe('bkg-1'));
    });

    test('sans réservation rattachée, on retombe sur le suivi', () {
      // Un écran ouvert vaut mieux qu'un appui sans effet.
      expect(
        invitation(bookingId: null).destination,
        FerhaRoutes.mesReservations,
      );
    });
  });

  group('Ce que le bouton de « Mes réservations » lit', () {
    Reservation reservation({
      required String status,
      bool avisDepose = false,
      bool avisPossible = false,
    }) => Reservation.depuisJson(<String, dynamic>{
      'group_id': 'g1',
      'booking_id': 'b1',
      'venue_id': 'v1',
      'venue_name': 'Salle El Bahia',
      'commune': 'Oran',
      'event_date': '2026-08-14',
      'requested_slot': 'soir',
      'guest_count': 300,
      'status': status,
      'quoted_amount': 205000,
      'created_at': '2026-06-01T10:00:00Z',
      'avis_depose': avisDepose,
      'avis_possible': avisPossible,
    });

    test('les deux colonnes arrivent telles quelles', () {
      final r = reservation(
        status: 'completed',
        avisDepose: true,
        avisPossible: true,
      );
      expect(r.avisDepose, isTrue);
      expect(r.avisPossible, isTrue);
    });

    test('une base qui ne les connaît pas encore ne casse pas l’écran', () {
      // Les colonnes datent de 026 ; un client resté sur une base plus ancienne
      // ne doit pas voir un écran vide, il doit voir un écran sans ce bouton.
      final r = Reservation.depuisJson(<String, dynamic>{
        'group_id': 'g1',
        'booking_id': 'b1',
        'venue_id': 'v1',
        'venue_name': 'Salle El Bahia',
        'commune': 'Oran',
        'event_date': '2026-08-14',
        'requested_slot': 'soir',
        'guest_count': 300,
        'status': 'completed',
        'quoted_amount': 205000,
        'created_at': '2026-06-01T10:00:00Z',
      });

      expect(r.avisDepose, isFalse);
      expect(r.avisPossible, isFalse);
    });
  });

  group('Quand « L’événement a eu lieu » se propose', () {
    DemandeDetail demande({
      required EtatReservation etat,
      required int jours,
    }) => detailDeTest(
      id: '1',
      venueId: 'v1',
      etat: etat,
      date: DateTime.now().add(Duration(days: jours)),
    );

    test('sur une réservation confirmée dont la date est passée', () {
      expect(
        demande(etat: EtatReservation.confirmee, jours: -2).honorable,
        isTrue,
      );
    });

    test('le jour même compte, comme en base', () {
      // `complete_booking()` refuse `event_date > current_date` : un mariage du
      // 14 août se marque honoré le 14 au soir, pas le 15. Les deux côtés
      // doivent dire la même chose, sans quoi le bouton apparaîtrait un jour
      // trop tard — ou mènerait à FE073 un jour trop tôt.
      expect(
        demande(etat: EtatReservation.confirmee, jours: 0).honorable,
        isTrue,
      );
    });

    test('jamais avant l’événement', () {
      expect(
        demande(etat: EtatReservation.confirmee, jours: 1).honorable,
        isFalse,
      );
    });

    test('jamais sur une demande qui n’est pas confirmée', () {
      for (final etat in <EtatReservation>[
        EtatReservation.enAttente,
        EtatReservation.acceptee,
        EtatReservation.terminee,
        EtatReservation.annulee,
        EtatReservation.expiree,
        EtatReservation.refusee,
      ]) {
        expect(
          demande(etat: etat, jours: -2).honorable,
          isFalse,
          reason: 'l’état « ${etat.code} » ne se marque pas honoré',
        );
      }
    });
  });
}
