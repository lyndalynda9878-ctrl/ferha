import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ferha/core/theme/ferha_theme.dart';
import 'package:ferha/features/booking/mes_reservations_providers.dart';
import 'package:ferha/features/booking/mes_reservations_screen.dart';
import 'package:ferha/features/booking/reservation.dart';
import 'package:ferha/features/search/search_filters.dart';

/// L'écran « Mes réservations », monté sur une liste de test.
///
/// LE TEST LE PLUS IMPORTANT DE CE FICHIER EST CELUI QUI NE MONTRE RIEN : une
/// demande en attente ne doit afficher aucun numéro. Il est doublé côté base
/// — `booking_contact()` n'en renvoie pas avant « accepted » — mais un écran
/// qui afficherait un champ vide, ou une carte de contact sans numéro, dirait
/// quand même quelque chose de faux.
void main() {
  Reservation reservation({
    required EtatReservation etat,
    String? telephone,
    DateTime? expire,
    num? acompte,
  }) => Reservation(
    groupId: 'grp-${etat.code}',
    bookingId: 'bkg-${etat.code}',
    venueId: '5a11e000-0000-4000-a000-000000000001',
    salle: 'Salle El Bahia',
    commune: 'Oran',
    wilayaNom: 'Oran',
    photo: null,
    date: DateTime(2026, 11, 8),
    creneau: Creneau.soir,
    invites: 320,
    typeEvenement: 'Mariage',
    etat: etat,
    montant: 238000,
    acompte: acompte,
    optionExpireLe: expire,
    creeLe: DateTime(2026, 9, 9),
    proprietaire: 'Karim Belhadj',
    telephone: telephone,
  );

  /// Un notifier de test : `build()` rend la liste qu'on lui donne, sans
  /// réseau et sans abonnement Realtime.
  ///
  /// On ne simule pas le temps réel ici — il n'y a rien à tester dans un faux
  /// canal. Ce que ce fichier vérifie, c'est ce que l'écran fait d'une liste ;
  /// que la liste arrive par un abonnement ou par un rechargement ne change
  /// rien à son rendu.
  Future<void> ouvre(
    WidgetTester tester,
    List<Reservation> liste, {
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mesReservationsProvider.overrideWith(
            () => _MesReservationsDeTest(liste),
          ),
        ],
        child: MaterialApp(
          theme: theme ?? FerhaTheme.light(),
          home: const MesReservationsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('Le téléphone du propriétaire (§9)', () {
    testWidgets('une demande en attente n’affiche aucun numéro', (
      tester,
    ) async {
      await ouvre(tester, <Reservation>[
        reservation(etat: EtatReservation.enAttente),
      ]);

      expect(find.text('En attente de réponse'), findsOneWidget);
      expect(find.text('0770 11 22 33'), findsNothing);
      expect(find.text('Appeler'), findsNothing);
      expect(find.text('Copier'), findsNothing);
    });

    testWidgets('une demande acceptée l’affiche, avec ses deux boutons', (
      tester,
    ) async {
      await ouvre(tester, <Reservation>[
        reservation(
          etat: EtatReservation.acceptee,
          telephone: '0770 11 22 33',
          acompte: 59500,
          expire: DateTime.now().add(const Duration(hours: 71, minutes: 12)),
        ),
      ]);

      expect(find.text('Acceptée — acompte à verser'), findsOneWidget);
      // Le numéro en clair ET sélectionnable : sur un navigateur d’ordinateur,
      // un lien tel: ne fait presque rien, et il faut pouvoir le recopier.
      expect(find.text('0770 11 22 33'), findsOneWidget);
      expect(find.byType(SelectableText), findsOneWidget);
      expect(find.text('Appeler'), findsOneWidget);
      expect(find.text('Copier'), findsOneWidget);
    });
  });

  group('Le compte à rebours des 72 h', () {
    testWidgets('il s’affiche sur une demande acceptée, en toutes lettres', (
      tester,
    ) async {
      await ouvre(tester, <Reservation>[
        reservation(
          etat: EtatReservation.acceptee,
          telephone: '0770 11 22 33',
          expire: DateTime.now().add(
            const Duration(hours: 71, minutes: 12, seconds: 30),
          ),
        ),
      ]);

      expect(find.text('71 h 12 min'), findsOneWidget);
    });

    // Qu'il DESCENDE tout seul se vérifie sur le widget lui-même, dans
    // compte_a_rebours_test.dart : un test d'écran avance l'horloge des
    // minuteries, pas celle de DateTime.now(). Ici on vérifie seulement qu'il
    // est là, et là où il faut.

    testWidgets('il ne s’affiche pas sur une demande en attente', (
      tester,
    ) async {
      await ouvre(tester, <Reservation>[
        reservation(etat: EtatReservation.enAttente),
      ]);

      expect(find.textContaining('La date vous est réservée'), findsNothing);
    });
  });

  group('Ce que l’écran écrit', () {
    testWidgets('les sept états s’écrivent en français, jamais en code', (
      tester,
    ) async {
      await ouvre(
        tester,
        EtatReservation.values
            .map((e) => reservation(etat: e))
            .toList(growable: false),
      );

      for (final etat in EtatReservation.values) {
        expect(find.text(etat.libelle), findsOneWidget, reason: etat.code);
        expect(find.text(etat.code), findsNothing, reason: etat.code);
      }
    });

    // Un cas par test : deux `ouvre` dans un même `testWidgets` ne changeraient
    // rien à l'écran. L'override d'un Notifier est posé à la construction du
    // ProviderScope, et un second `pumpWidget` met à jour le scope existant
    // sans rejouer son `build()` — la première liste resterait.
    testWidgets('avant la réponse, le montant est une « Estimation »', (
      tester,
    ) async {
      await ouvre(tester, <Reservation>[
        reservation(etat: EtatReservation.enAttente),
      ]);

      expect(find.text('Estimation'), findsOneWidget);
      expect(find.text('Montant convenu'), findsNothing);
    });

    testWidgets('après, c’est un « Montant convenu »', (tester) async {
      await ouvre(tester, <Reservation>[
        reservation(
          etat: EtatReservation.confirmee,
          telephone: '0770 11 22 33',
          acompte: 59500,
        ),
      ]);

      expect(find.text('Montant convenu'), findsOneWidget);
      expect(find.text('Estimation'), findsNothing);
    });
  });

  group('L’annulation', () {
    testWidgets('elle est proposée sur une demande en attente', (tester) async {
      await ouvre(tester, <Reservation>[
        reservation(etat: EtatReservation.enAttente),
      ]);

      expect(find.text('Annuler la demande'), findsOneWidget);
    });

    testWidgets('elle ne l’est plus une fois la date confirmée', (
      tester,
    ) async {
      // cancel_booking() l'accepterait encore, mais il y a un acompte en jeu et
      // le barème du §5.3 s'applique : ce n'est plus un bouton de liste.
      await ouvre(tester, <Reservation>[
        reservation(etat: EtatReservation.confirmee),
      ]);

      expect(find.text('Annuler la demande'), findsNothing);
    });

    testWidgets('elle demande confirmation, et non au premier tap', (
      tester,
    ) async {
      await ouvre(tester, <Reservation>[
        reservation(etat: EtatReservation.enAttente),
      ]);

      await tester.tap(find.text('Annuler la demande'));
      await tester.pumpAndSettle();

      expect(find.text('Annuler cette demande ?'), findsOneWidget);
      expect(find.text('Non, la garder'), findsOneWidget);
      expect(find.text('Oui, annuler'), findsOneWidget);
    });

    testWidgets('« Non, la garder » referme sans rien faire', (tester) async {
      await ouvre(tester, <Reservation>[
        reservation(etat: EtatReservation.enAttente),
      ]);

      await tester.tap(find.text('Annuler la demande'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Non, la garder'));
      await tester.pumpAndSettle();

      expect(find.text('Annuler cette demande ?'), findsNothing);
      expect(find.text('En attente de réponse'), findsOneWidget);
    });
  });

  group('L’écran vide', () {
    testWidgets('il dit quoi faire, et donne le bouton pour le faire', (
      tester,
    ) async {
      await ouvre(tester, const <Reservation>[]);

      expect(find.text('Vous n’avez pas encore de demande'), findsOneWidget);
      expect(find.text('Chercher une salle'), findsOneWidget);
    });
  });

  testWidgets('l’écran se rend aussi en thème sombre', (tester) async {
    await ouvre(tester, <Reservation>[
      reservation(
        etat: EtatReservation.acceptee,
        telephone: '0770 11 22 33',
        acompte: 59500,
        expire: DateTime.now().add(const Duration(hours: 12)),
      ),
    ], theme: FerhaTheme.dark());

    expect(find.text('Acceptée — acompte à verser'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// Rend la liste qu'on lui donne, sans réseau ni abonnement.
class _MesReservationsDeTest extends MesReservations {
  _MesReservationsDeTest(this._liste);

  final List<Reservation> _liste;

  @override
  Future<List<Reservation>> build() async => _liste;
}
