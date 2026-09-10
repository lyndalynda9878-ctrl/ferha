import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ferha/core/preferences/preferences_affichage.dart';
import 'package:ferha/core/theme/ferha_theme.dart';
import 'package:ferha/features/auth/auth_providers.dart';
import 'package:ferha/features/booking/reservation.dart';
import 'package:ferha/features/owner/demande_detail.dart';
import 'package:ferha/features/owner/detail_demande_screen.dart';
import 'package:ferha/features/owner/indicateurs_salle.dart';
import 'package:ferha/features/owner/owner_repository.dart';
import 'package:ferha/features/owner/salle_du_proprietaire.dart';

import 'owner_fakes.dart';

/// L'écran de détail, et les deux gestes qu'il porte.
///
/// LE TEST LE PLUS IMPORTANT DE CE FICHIER EST CELUI D'« ANNULER ». Un refus
/// est définitif : la famille reçoit un « non » qu'on ne peut pas retirer. Une
/// fenêtre de confirmation qui refuserait quand même en se fermant serait pire
/// que pas de fenêtre du tout, puisqu'elle donnerait l'illusion d'un recours.
///
/// LE SECOND EST CELUI DU TÉLÉPHONE ABSENT. Il double la règle du §9, tenue en
/// base par `booking_contact()` — mais un écran qui afficherait un champ vide,
/// ou un bloc « Le contact » sans rien dedans, dirait quand même quelque chose
/// de faux.
void main() {
  const bahia = '5a11e000-0000-4000-a000-000000000001';

  Future<DepotDeTest> ouvre(
    WidgetTester tester,
    DemandeDetail demande, {
    ThemeData? theme,
    Object? erreur,
  }) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final depot = DepotDeTest(
      sallesRendues: <SalleDuProprietaire>[
        salleDeTest(id: bahia, demandesEnAttente: 1),
      ],
      indicateursRendus: <String, IndicateursSalle>{bahia: indicateursDeTest()},
      detailsRendus: <String, DemandeDetail>{demande.bookingId: demande},
      erreurDeReponse: erreur,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          estConnecteProvider.overrideWithValue(true),
          preferencesAffichageProvider.overrideWithValue(
            PreferencesEnMemoire(bahia),
          ),
          ownerRepositoryProvider.overrideWithValue(depot),
        ],
        child: MaterialApp(
          theme: theme ?? FerhaTheme.light(),
          home: DetailDemandeScreen(bookingId: demande.bookingId),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return depot;
  }

  group('Ce que l’écran montre', () {
    testWidgets('le nom entier, le message, les options, le devis', (
      tester,
    ) async {
      await ouvre(
        tester,
        detailDeTest(
          id: '1',
          venueId: bahia,
          client: 'Amina Kaddour',
          message: 'Bonjour, nous serons environ 300 personnes.',
          options: const <OptionChoisie>[
            OptionChoisie(
              code: 'decoration',
              libelle: 'Décoration',
              prix: 25000,
            ),
            OptionChoisie(code: 'chambre', libelle: 'Chambre', prix: 0),
          ],
        ),
      );

      // Le nom ENTIER, là où la file n'en donnait que l'initiale.
      expect(find.text('Amina Kaddour'), findsOneWidget);
      expect(
        find.text('Bonjour, nous serons environ 300 personnes.'),
        findsOneWidget,
      );
      expect(find.text('14 août 2027'), findsOneWidget);
      expect(find.text('Soir'), findsOneWidget);
      expect(find.text('Mariage'), findsOneWidget);

      // Une option à zéro dinar n'est pas une option absente : c'est une
      // chambre à préparer, même offerte.
      expect(find.text('Décoration'), findsOneWidget);
      expect(find.text('Chambre'), findsOneWidget);
      expect(find.text('Incluse'), findsOneWidget);
    });

    testWidgets('aucun téléphone tant que la demande est en attente (§9)', (
      tester,
    ) async {
      await ouvre(
        tester,
        detailDeTest(
          id: '1',
          venueId: bahia,
          // Ce que la base renvoie sur une demande en attente : pas de numéro,
          // et `phone_available` à false.
          telephone: null,
          telephoneDisponible: false,
        ),
      );

      expect(find.textContaining('dès que vous aurez accepté'), findsOneWidget);
      expect(find.byIcon(Icons.phone_outlined), findsNothing);
    });

    testWidgets('le téléphone paraît une fois la demande acceptée', (
      tester,
    ) async {
      await ouvre(
        tester,
        detailDeTest(
          id: '1',
          venueId: bahia,
          etat: EtatReservation.acceptee,
          acompte: 51250,
          telephone: '0555 12 34 56',
          telephoneDisponible: true,
        ),
      );

      expect(find.text('0555 12 34 56'), findsOneWidget);
      expect(find.text('51${fine}250 DA'), findsOneWidget);
    });

    testWidgets('un client sans numéro se dit autrement qu’un numéro caché', (
      tester,
    ) async {
      await ouvre(
        tester,
        detailDeTest(
          id: '1',
          venueId: bahia,
          etat: EtatReservation.acceptee,
          telephone: null,
          // La base a le droit de donner le numéro — il n'y en a simplement pas.
          telephoneDisponible: true,
        ),
      );

      expect(find.textContaining('n’a pas renseigné'), findsOneWidget);
      expect(find.textContaining('dès que vous aurez accepté'), findsNothing);
    });
  });

  group('Les deux boutons', () {
    testWidgets('ils n’apparaissent que sur une demande en attente', (
      tester,
    ) async {
      await ouvre(tester, detailDeTest(id: '1', venueId: bahia));
      expect(find.byKey(cleAccepter), findsOneWidget);
      expect(find.byKey(cleRefuser), findsOneWidget);

      // La contre-proposition du §5.2 n'est pas de cette étape. Ce test
      // échouera le jour où on l'ajoutera, ce qui est le moment de le relire.
      expect(find.text('Contre-proposer'), findsNothing);
    });

    testWidgets('une demande déjà refusée n’en porte plus, et dit pourquoi', (
      tester,
    ) async {
      await ouvre(
        tester,
        detailDeTest(
          id: '1',
          venueId: bahia,
          etat: EtatReservation.refusee,
          motif: 'Salle déjà retenue ce soir-là.',
        ),
      );

      expect(find.byKey(cleAccepter), findsNothing);
      expect(find.byKey(cleRefuser), findsNothing);
      expect(find.textContaining('Vous avez refusé'), findsOneWidget);
      expect(
        find.textContaining('Salle déjà retenue ce soir-là.'),
        findsOneWidget,
      );
    });

    testWidgets('accepter part sans confirmation, et le dit', (tester) async {
      final depot = await ouvre(tester, detailDeTest(id: '1', venueId: bahia));

      await tester.tap(find.byKey(cleAccepter));
      await tester.pumpAndSettle();

      expect(depot.acceptees, <String>['bkg-1']);
      expect(find.textContaining('72 h pour verser l’acompte'), findsOneWidget);
    });
  });

  group('Le refus demande confirmation', () {
    testWidgets('la fenêtre s’ouvre, et nomme le client', (tester) async {
      await ouvre(
        tester,
        detailDeTest(id: '1', venueId: bahia, client: 'Amina Kaddour'),
      );

      await tester.tap(find.byKey(cleRefuser));
      await tester.pumpAndSettle();

      expect(find.text('Refuser cette demande ?'), findsOneWidget);
      expect(find.textContaining('Amina Kaddour'), findsWidgets);
      expect(find.text('Motif (facultatif)'), findsOneWidget);
    });

    testWidgets('« Annuler » ne refuse rien du tout', (tester) async {
      final depot = await ouvre(tester, detailDeTest(id: '1', venueId: bahia));

      await tester.tap(find.byKey(cleRefuser));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(cleAnnulerRefus));
      await tester.pumpAndSettle();

      // LE TEST QUI COMPTE. Une confirmation qui refuserait quand même serait
      // pire que pas de confirmation : elle donnerait l'illusion d'un recours.
      expect(depot.refusees, isEmpty);
      // Et les boutons sont toujours là : rien n'a été décidé.
      expect(find.byKey(cleRefuser), findsOneWidget);
    });

    testWidgets('le motif saisi part avec le refus', (tester) async {
      final depot = await ouvre(tester, detailDeTest(id: '1', venueId: bahia));

      await tester.tap(find.byKey(cleRefuser));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(cleMotif), 'Salle en travaux');
      await tester.tap(find.byKey(cleConfirmerRefus));
      await tester.pumpAndSettle();

      expect(depot.refusees.single.motif, 'Salle en travaux');
    });

    testWidgets('un motif vide ne bloque pas le refus', (tester) async {
      final depot = await ouvre(tester, detailDeTest(id: '1', venueId: bahia));

      await tester.tap(find.byKey(cleRefuser));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(cleConfirmerRefus));
      await tester.pumpAndSettle();

      // Demandé, pas exigé : obliger à écrire quelque chose produirait des
      // « non » et des points, pas des raisons.
      expect(depot.refusees.single.motif, isNull);
    });
  });

  group('Quand la base dit non', () {
    testWidgets('FE013 devient une phrase, pas un code', (tester) async {
      await ouvre(
        tester,
        detailDeTest(id: '1', venueId: bahia),
        erreur: const PostgrestException(
          message:
              'Ce créneau a été confirmé entre-temps par une autre réservation.',
          code: 'PT409',
          hint: 'FE013',
        ),
      );

      await tester.tap(find.byKey(cleAccepter));
      await tester.pumpAndSettle();

      expect(find.textContaining('confirmé entre-temps'), findsOneWidget);
      expect(find.textContaining('FE013'), findsNothing);
      // Le propriétaire n'est pas laissé devant un mur : les boutons restent,
      // et refuser reste possible.
      expect(find.byKey(cleRefuser), findsOneWidget);
    });
  });

  testWidgets('le thème sombre s’affiche aussi', (tester) async {
    await ouvre(
      tester,
      detailDeTest(id: '1', venueId: bahia),
      theme: FerhaTheme.dark(),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Amina Kaddour'), findsOneWidget);
    expect(find.byKey(cleAccepter), findsOneWidget);
  });
}

/// L'espace fine insécable de `montantEnDinars`. Voir
/// `tableau_de_bord_ecran_test.dart` : un test qui échoue sur une espace qu'on
/// ne voit pas coûte une demi-heure.
const fine = ' ';
