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

  group('L’acompte en espèces', () {
    DemandeDetail annonce({bool especes = true}) => detailDeTest(
      id: 'esp',
      venueId: bahia,
      etat: EtatReservation.acceptee,
      acompte: 51333.25,
      acompteDu: 51334,
      especesEnAttente: especes,
      telephone: '0770 11 22 33',
      telephoneDisponible: true,
    );

    testWidgets('rien à confirmer tant que rien n’est annoncé', (tester) async {
      // Un bouton « J'ai reçu l'acompte » toujours visible inviterait le
      // propriétaire à prendre une date pour de l'argent que personne ne lui a
      // promis.
      await ouvre(tester, annonce(especes: false));

      expect(find.byKey(cleEncaissementEspeces), findsNothing);
      expect(find.text('Acompte en espèces annoncé'), findsNothing);
    });

    testWidgets('annoncé, le bloc dit le montant que le client apportera', (
      tester,
    ) async {
      await ouvre(tester, annonce());

      expect(find.text('Acompte en espèces annoncé'), findsOneWidget);
      // 51 334, l'entier — le MÊME nombre que celui lu par la cliente sur
      // l'écran 6. Compter d'après 51 333,25 ferait deux comptes.
      expect(
        find.textContaining('vous apportera 51${fine}334 DA'),
        findsOneWidget,
      );
      expect(find.byKey(cleEncaissementEspeces), findsOneWidget);
    });

    testWidgets('confirmer demande confirmation : ce tap prend la date', (
      tester,
    ) async {
      final depot = await ouvre(tester, annonce());

      await tester.tap(find.byKey(cleEncaissementEspeces));
      await tester.pumpAndSettle();

      expect(find.text('Confirmer l’encaissement ?'), findsOneWidget);
      expect(find.textContaining('ne pourra plus être rendue'), findsOneWidget);
      // Rien n'est parti tant qu'on n'a pas répondu.
      expect(depot.encaissementsConfirmes, isEmpty);
    });

    testWidgets('« Pas encore » referme sans rien confirmer', (tester) async {
      final depot = await ouvre(tester, annonce());

      await tester.tap(find.byKey(cleEncaissementEspeces));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pas encore'));
      await tester.pumpAndSettle();

      expect(find.text('Confirmer l’encaissement ?'), findsNothing);
      expect(depot.encaissementsConfirmes, isEmpty);
    });

    testWidgets('« Oui, j’ai reçu » confirme, et une seule fois', (
      tester,
    ) async {
      final depot = await ouvre(tester, annonce());

      await tester.tap(find.byKey(cleEncaissementEspeces));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(cleConfirmerEspeces));
      await tester.pumpAndSettle();

      expect(depot.encaissementsConfirmes, <String>['bkg-esp']);
      expect(find.text('Acompte encaissé. La date est prise.'), findsOneWidget);
    });

    testWidgets('un refus de la base se dit en français, par son code', (
      tester,
    ) async {
      // FE063 : l'option est morte pendant qu'il comptait les billets. Le
      // propriétaire a l'argent en main et la date est repartie à la vente —
      // la phrase doit dire quoi faire de cet argent.
      await ouvre(
        tester,
        annonce(),
        erreur: PostgrestException(message: 'peu importe', hint: 'FE063'),
      );

      await tester.tap(find.byKey(cleEncaissementEspeces));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(cleConfirmerEspeces));
      await tester.pumpAndSettle();

      expect(find.textContaining('Ne gardez pas l’acompte'), findsOneWidget);
      expect(find.textContaining('FE063'), findsNothing);
    });
  });

  /// « L'événement a eu lieu » — le geste qui débloque l'avis (§3 étape 6,
  /// §5.4).
  ///
  /// IL N'EXISTAIT PAS AVANT LE J17, et c'est ce qui rendait le §5.4
  /// inatteignable : `complete_booking()` était écrite depuis la migration 004
  /// et aucun écran ne l'appelait. Une réservation payée restait « confirmée »
  /// pour toujours, et personne ne pouvait noter une salle.
  group('Marquer l’événement comme honoré', () {
    DemandeDetail confirmee({int jours = -2}) => detailDeTest(
      id: '1',
      venueId: bahia,
      etat: EtatReservation.confirmee,
      acompte: 51334,
      acompteDu: 51334,
      telephone: '0770112233',
      telephoneDisponible: true,
      date: DateTime.now().add(Duration(days: jours)),
    );

    testWidgets('le bouton n’apparaît qu’après la date', (tester) async {
      await ouvre(tester, confirmee(jours: 3));
      expect(find.byKey(cleMarquerHonoree), findsNothing);

      await ouvre(tester, confirmee(jours: -2));
      expect(find.byKey(cleMarquerHonoree), findsOneWidget);
    });

    testWidgets('ni sur une demande qui n’est pas confirmée', (tester) async {
      await ouvre(
        tester,
        detailDeTest(
          id: '1',
          venueId: bahia,
          etat: EtatReservation.acceptee,
          date: DateTime.now().subtract(const Duration(days: 2)),
        ),
      );

      // La base le refuse aussi (FE072) ; le cacher évite seulement de proposer
      // un geste qui échouerait.
      expect(find.byKey(cleMarquerHonoree), findsNothing);
    });

    testWidgets('il annonce ce que le geste déclenche', (tester) async {
      await ouvre(tester, confirmee());

      // Le propriétaire doit savoir qu'il ouvre la porte à un avis sur SA
      // salle : c'est la moitié de ce qu'il accepte en appuyant.
      expect(
        find.textContaining('pourra alors déposer un avis'),
        findsOneWidget,
      );
    });

    testWidgets('renoncer dans la fenêtre ne marque rien', (tester) async {
      final depot = await ouvre(tester, confirmee());

      await tester.tap(find.byKey(cleMarquerHonoree));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pas encore'));
      await tester.pumpAndSettle();

      // Marquer honoré ne se défait pas : aucune transition ne ramène de
      // « completed » à « confirmed ». Une fenêtre qui marquerait quand même en
      // se fermant serait pire que pas de fenêtre du tout.
      expect(depot.honorees, isEmpty);
    });

    testWidgets('confirmer envoie la demande, et une seule fois', (
      tester,
    ) async {
      final demande = confirmee();
      final depot = await ouvre(tester, demande);

      await tester.tap(find.byKey(cleMarquerHonoree));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(cleConfirmerHonoree));
      await tester.pumpAndSettle();

      expect(depot.honorees, <String>[demande.bookingId]);
      expect(
        find.textContaining('Votre cliente peut maintenant vous noter'),
        findsOneWidget,
      );
    });

    testWidgets('FE073 est traduit, et dit quand revenir', (tester) async {
      await ouvre(
        tester,
        confirmee(),
        erreur: const PostgrestException(
          message: 'L’événement n’a pas encore eu lieu.',
          code: 'PT409',
          hint: 'FE073',
        ),
      );

      await tester.tap(find.byKey(cleMarquerHonoree));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(cleConfirmerHonoree));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Vous pourrez le marquer comme honoré'),
        findsOneWidget,
      );
      expect(find.textContaining('FE073'), findsNothing);
    });

    testWidgets(
      'FE072 ne gronde personne : un double appui n’est pas une faute',
      (tester) async {
        await ouvre(
          tester,
          confirmee(),
          erreur: const PostgrestException(
            message: 'Seule une réservation confirmée peut être honorée.',
            code: 'PT409',
            hint: 'FE072',
          ),
        );

        await tester.tap(find.byKey(cleMarquerHonoree));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(cleConfirmerHonoree));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Elle a peut-être déjà été marquée'),
          findsOneWidget,
        );
      },
    );
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
