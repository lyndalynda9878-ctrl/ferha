import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ferha/core/preferences/preferences_affichage.dart';
import 'package:ferha/core/router/routes.dart';
import 'package:ferha/core/theme/ferha_theme.dart';
import 'package:ferha/features/auth/auth_providers.dart';
import 'package:ferha/features/owner/nouvelle_salle.dart';
import 'package:ferha/features/owner/owner_messages.dart';
import 'package:ferha/features/owner/owner_repository.dart';
import 'package:ferha/features/owner/publier_salle_screen.dart';
import 'package:ferha/features/search/search_providers.dart';

import 'owner_fakes.dart';

/// Le formulaire d'inscription d'une salle (§4.3, OWN-01).
///
/// CE QUE CE FICHIER SURVEILLE, DANS L'ORDRE :
///
///   1. QUE « CONTINUER » RESTE ÉTEINT TANT QU'UN CHAMP OBLIGATOIRE MANQUE, ET
///      QU'IL DISE LEQUEL. Un bouton allumé sur un formulaire incomplet mène à
///      un refus FE031 de la base, c'est-à-dire à quatre étapes remplies pour
///      rien.
///
///   2. QUE REVENIR EN ARRIÈRE NE PERDE RIEN. C'est ce qui casse le plus
///      discrètement : tout reste à l'écran, tout a l'air normal, et seul
///      quelqu'un qui revient s'en aperçoit — au moment où il a le moins envie
///      de recommencer.
///
///   3. QUE LA SALLE ARRIVE À LA BASE TELLE QU'ELLE A ÉTÉ COMPOSÉE. En
///      particulier le parking : `null` veut dire « non renseigné » et `0` veut
///      dire « pas de parking » (§6), et les confondre ferait afficher
///      « 0 place » sur une salle dont on ne sait rien.
///
/// LE DÉPÔT NE SIMULE PAS SUPABASE, IL LE REMPLACE. Les garde-fous — session,
/// propriété, statut — vivent en SQL, et c'est
/// `supabase/tests/005_publier_une_salle.sql` qui les vérifie.
void main() {
  const wilayas = <Wilaya>[
    (code: '16', nom: 'Alger'),
    (code: '31', nom: 'Oran'),
  ];

  const equipements = <String, List<Equipement>>{
    'confort': <Equipement>[
      (code: 'climatisation', libelle: 'Climatisation', categorie: 'confort'),
    ],
    'espaces': <Equipement>[
      (code: 'jardin', libelle: 'Jardin', categorie: 'espaces'),
    ],
  };

  const types = <TypeEvenement>[
    (code: 'mariage', libelle: 'Mariage'),
    (code: 'henne', libelle: 'Henné'),
  ];

  // LES VALEURS DE TEST NE SONT JAMAIS CELLES DES TEXTES D'INVITE. Les champs
  // vides affichent « Salle El Bahia » et « Bir El Djir » en gris ; taper la
  // même chose dedans ferait trouver deux fois le même texte à l'écran, et un
  // `findsOneWidget` échouerait sans que rien ne soit cassé.

  /// Les identifiants de salle pour lesquels l'écran des photos a été ouvert.
  ///
  /// C'est là que mène le formulaire depuis le J13 : `creer_salle()` rend un
  /// identifiant, et c'est lui qui sert de dossier de Storage aux photos
  /// (OWN-02). Une liste vide veut donc dire « le formulaire n'a rien inscrit ».
  late List<String> etapesPhotos;

  setUp(() => etapesPhotos = <String>[]);

  Future<DepotDeTest> ouvre(
    WidgetTester tester, {
    Object? erreurDePublication,
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = const Size(500, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final depot = DepotDeTest(erreurDePublication: erreurDePublication);

    final routeur = GoRouter(
      initialLocation: FerhaRoutes.publierSalle,
      routes: <RouteBase>[
        GoRoute(
          path: FerhaRoutes.publierSalle,
          builder: (context, state) => const PublierSalleScreen(),
        ),
        // DEPUIS LE J13, LE FORMULAIRE NE MÈNE PLUS AU RÉCAPITULATIF MAIS AUX
        // PHOTOS (OWN-02) : la cinquième étape s'est glissée entre les deux.
        // Le récapitulatif reste déclaré parce que la route existe toujours ;
        // c'est l'écran des photos qui y mène maintenant.
        GoRoute(
          path: FerhaRoutes.publierPhotos,
          builder: (context, state) {
            etapesPhotos.add(state.pathParameters['id']!);
            return const Scaffold(body: Text('L’étape des photos'));
          },
        ),
        GoRoute(
          path: FerhaRoutes.publierRecapitulatif,
          builder: (context, state) =>
              const Scaffold(body: Text('Le récapitulatif')),
        ),
        GoRoute(
          path: FerhaRoutes.proprietaireTableau,
          builder: (context, state) =>
              const Scaffold(body: Text('Le tableau de bord')),
        ),
        // Là où l'on retombe quand il n'y a rien à dépiler.
        GoRoute(
          path: FerhaRoutes.profil,
          builder: (context, state) => const Scaffold(body: Text('Le profil')),
        ),
      ],
    );
    addTearDown(routeur.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          estConnecteProvider.overrideWithValue(true),
          preferencesAffichageProvider.overrideWithValue(
            PreferencesEnMemoire(),
          ),
          ownerRepositoryProvider.overrideWithValue(depot),
          toutesLesWilayasProvider.overrideWith((ref) async => wilayas),
          equipementsParCategorieProvider.overrideWith(
            (ref) async => equipements,
          ),
          typesEvenementProvider.overrideWith((ref) async => types),
        ],
        child: MaterialApp.router(
          theme: theme ?? FerhaTheme.light(),
          routerConfig: routeur,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return depot;
  }

  /// L'état du bouton du bas, quel que soit son libellé.
  bool continuerEstAllume(WidgetTester tester) {
    final bouton = tester.widget<FilledButton>(
      find.descendant(
        of: find.byType(SafeArea),
        matching: find.byType(FilledButton),
      ),
    );
    return bouton.onPressed != null;
  }

  /// Remplit l'étape courante et passe à la suivante.
  Future<void> passeEtape1(
    WidgetTester tester, {
    String nom = 'Salle Les Palmiers',
  }) async {
    await tester.enterText(find.byType(TextField).first, nom);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();
  }

  Future<void> passeEtape2(
    WidgetTester tester, {
    String adresse = 'Cité 200 logements, route de l’aéroport',
  }) async {
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('31 · Oran').last);
    await tester.pumpAndSettle();
    // Les deux champs de l'étape, dans l'ordre de lecture : commune, adresse.
    await tester.enterText(find.byType(TextField).at(0), 'Canastel');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), adresse);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();
  }

  Future<void> passeEtape3(
    WidgetTester tester, {
    String capacite = '380',
    String? parking,
  }) async {
    final champs = find.byType(TextField);
    await tester.enterText(champs.at(0), capacite);
    await tester.pumpAndSettle();
    if (parking != null) {
      await tester.enterText(champs.at(2), parking);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();
  }

  // ---------------------------------------------------------------------------
  // 1. « Continuer » éteint, et qui dit pourquoi
  // ---------------------------------------------------------------------------

  group('« Continuer » et ce qui manque', () {
    testWidgets('étape 1 : sans nom, le bouton est éteint et le dit', (
      tester,
    ) async {
      await ouvre(tester);

      expect(continuerEstAllume(tester), isFalse);
      expect(
        find.text('Donnez un nom à votre salle pour continuer.'),
        findsOneWidget,
      );

      await tester.enterText(
        find.byType(TextField).first,
        'Salle Les Palmiers',
      );
      await tester.pumpAndSettle();

      expect(continuerEstAllume(tester), isTrue);
      expect(
        find.text('Donnez un nom à votre salle pour continuer.'),
        findsNothing,
      );
    });

    testWidgets('un nom fait de blancs ne compte pas pour un nom', (
      tester,
    ) async {
      await ouvre(tester);

      await tester.enterText(find.byType(TextField).first, '    ');
      await tester.pumpAndSettle();

      expect(continuerEstAllume(tester), isFalse);
    });

    testWidgets('étape 2 : la wilaya d’abord, puis la commune', (tester) async {
      await ouvre(tester);
      await passeEtape1(tester);

      // LES DEUX MANQUENT, ON N'EN RÉCLAME QU'UN. Une phrase qui demanderait
      // « la wilaya et la commune » serait plus longue pour un geste qui reste
      // le même : remplir le premier champ vide.
      expect(continuerEstAllume(tester), isFalse);
      expect(find.text('Choisissez la wilaya de votre salle.'), findsOneWidget);
      expect(find.text('Indiquez la commune de votre salle.'), findsNothing);

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('31 · Oran').last);
      await tester.pumpAndSettle();

      // La wilaya est là ; c'est la commune qu'on réclame maintenant.
      expect(continuerEstAllume(tester), isFalse);
      expect(find.text('Indiquez la commune de votre salle.'), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(0), 'Canastel');
      await tester.pumpAndSettle();

      // ET L'ADRESSE ENSUITE, qui est le dernier champ de l'écran. Elle n'est
      // exigée par aucune contrainte de table — `venues.address` est nullable —
      // mais par ADM-01 : « aucune salle n'est visible avant contrôle humain
      // (photos réelles, adresse plausible…) ». Sans elle, `creer_salle()`
      // refuse en FE036, après quatre étapes remplies.
      expect(continuerEstAllume(tester), isFalse);
      expect(
        find.text(
          'Indiquez l’adresse de votre salle — elle est vérifiée avant '
          'publication.',
        ),
        findsOneWidget,
      );

      await tester.enterText(
        find.byType(TextField).at(1),
        'Cité 200 logements, route de l’aéroport',
      );
      await tester.pumpAndSettle();

      expect(continuerEstAllume(tester), isTrue);
    });

    testWidgets('une adresse faite de blancs ne compte pas pour une adresse', (
      tester,
    ) async {
      await ouvre(tester);
      await passeEtape1(tester);

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('31 · Oran').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'Canastel');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(1), '    ');
      await tester.pumpAndSettle();

      expect(continuerEstAllume(tester), isFalse);
    });

    testWidgets('l’adresse dit à quoi elle sert, et qu’elle ne s’affiche pas', (
      tester,
    ) async {
      // UN CHAMP OBLIGATOIRE QU'ON NE VERRA JAMAIS AFFICHÉ a l'air d'une
      // indiscrétion tant qu'on n'a pas dit à quoi il sert. La phrase est donc
      // sous le champ, pas dans une aide qu'on n'ouvre pas.
      await ouvre(tester);
      await passeEtape1(tester);

      expect(
        find.text(
          'Obligatoire, et montrée à personne : l’équipe Ferha s’en sert pour '
          'vérifier votre salle avant de la publier.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('étape 3 : une capacité de zéro n’est pas une capacité', (
      tester,
    ) async {
      await ouvre(tester);
      await passeEtape1(tester);
      await passeEtape2(tester);

      expect(continuerEstAllume(tester), isFalse);
      expect(
        find.text('Indiquez combien de couverts votre salle peut asseoir.'),
        findsOneWidget,
      );

      // `venues.capacity_seated` exige > 0 : laisser passer un zéro mènerait à
      // un refus FE031 après quatre étapes remplies.
      await tester.enterText(find.byType(TextField).at(0), '0');
      await tester.pumpAndSettle();
      expect(continuerEstAllume(tester), isFalse);

      await tester.enterText(find.byType(TextField).at(0), '380');
      await tester.pumpAndSettle();
      expect(continuerEstAllume(tester), isTrue);
    });

    testWidgets(
      'étape 4 : tout est facultatif, le bouton est allumé d’emblée',
      (tester) async {
        await ouvre(tester);
        await passeEtape1(tester);
        await passeEtape2(tester);
        await passeEtape3(tester);

        expect(continuerEstAllume(tester), isTrue);
        expect(find.text('Inscrire ma salle'), findsOneWidget);
        // Aucun reproche à faire : rien n'est obligatoire ici.
        expect(find.byIcon(Icons.info_outline), findsNothing);
      },
    );

    testWidgets('étape 4 : un service hors liste se décrit à l’étape 1', (
      tester,
    ) async {
      // PAS DE CHAMP LIBRE DANS LES ÉQUIPEMENTS, et une phrase qui dit où
      // mettre le reste. Un « autre équipement » saisi à la main produirait
      // autant d'orthographes que de propriétaires, et aucune ne sortirait
      // d'une recherche qui filtre sur des codes.
      await ouvre(tester);
      await passeEtape1(tester);
      await passeEtape2(tester);
      await passeEtape3(tester);

      expect(
        find.text(
          'Un service qui n’est pas dans la liste ? Décrivez-le à l’étape 1.',
        ),
        findsOneWidget,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // 2. Revenir en arrière ne perd rien
  // ---------------------------------------------------------------------------

  group('Revenir en arrière', () {
    testWidgets('le nom saisi est toujours là après deux retours', (
      tester,
    ) async {
      await ouvre(tester);
      await passeEtape1(tester, nom: 'Salle Les Palmiers');
      await passeEtape2(tester);

      // On est à l'étape 3. On recule deux fois.
      expect(find.text('Étape 3 sur 5'), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Étape 2 sur 5'), findsOneWidget);
      // La commune n'a pas été effacée par le passage.
      expect(find.text('Canastel'), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Étape 1 sur 5'), findsOneWidget);
      expect(find.text('Salle Les Palmiers'), findsOneWidget);

      // Et le bouton est toujours allumé : ce qui était valide le reste.
      expect(continuerEstAllume(tester), isTrue);
    });

    testWidgets('la wilaya choisie survit à un aller-retour', (tester) async {
      await ouvre(tester);
      await passeEtape1(tester);
      await passeEtape2(tester);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      // Le menu déroulant réaffiche le choix, et non son texte d'invite.
      expect(find.text('31 · Oran'), findsWidgets);
      expect(find.text('Choisissez une wilaya'), findsNothing);
      expect(continuerEstAllume(tester), isTrue);
    });

    testWidgets('les équipements cochés survivent à un aller-retour', (
      tester,
    ) async {
      await ouvre(tester);
      await passeEtape1(tester);
      await passeEtape2(tester);
      await passeEtape3(tester);

      await tester.tap(find.text('Jardin'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Étape 3 sur 5'), findsOneWidget);

      await tester.tap(find.text('Continuer'));
      await tester.pumpAndSettle();

      final puce = tester.widget<FilterChip>(
        find.ancestor(
          of: find.text('Jardin'),
          matching: find.byType(FilterChip),
        ),
      );
      expect(puce.selected, isTrue);
    });

    testWidgets('le retour de la première étape quitte, même sans pile', (
      tester,
    ) async {
      // Le retour de la barre et le retour d'étape sont le même geste : sur la
      // première étape, il n'y a plus d'étape derrière, donc on sort.
      //
      // ET ICI IL N'Y A RIEN À DÉPILER, à dessein : le formulaire est la route
      // initiale du routeur de test. C'est le cas d'un lien direct sur le web,
      // et celui du retour de la connexion — qui fait un `go(retour)` quand
      // elle n'a elle-même rien à dépiler. Un `pop()` sec lèverait alors
      // « There is nothing to pop » et casserait l'écran au lieu de le fermer.
      await ouvre(tester);

      expect(find.text('Étape 1 sur 5'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Le profil'), findsOneWidget);

      // Rien n'a été inscrit : un formulaire abandonné ne laisse aucune trace.
      expect(etapesPhotos, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // 3. Ce qui arrive à la base
  // ---------------------------------------------------------------------------

  group('Ce qui part vers la base', () {
    testWidgets('la salle arrive telle qu’elle a été composée', (tester) async {
      final depot = await ouvre(tester);

      await passeEtape1(tester, nom: '  Salle Les Palmiers  ');
      await passeEtape2(tester);
      await passeEtape3(tester, parking: '60');
      await tester.tap(find.text('Climatisation'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mariage'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inscrire ma salle'));
      await tester.pumpAndSettle();

      expect(depot.inscrites, hasLength(1));
      final salle = depot.inscrites.single;
      expect(salle.nom.trim(), 'Salle Les Palmiers');
      expect(salle.wilayaCode, '31');
      expect(salle.commune, 'Canastel');
      expect(salle.adresse, 'Cité 200 logements, route de l’aéroport');
      expect(salle.capacite, 380);
      expect(salle.parking, 60);
      expect(salle.equipements, <String>{'climatisation'});
      expect(salle.typesEvenement, <String>{'mariage'});

      // Et l'écran a poussé l'étape des photos de LA salle créée : c'est cet
      // identifiant qui sert de dossier de Storage, `{venue_id}/{uuid}.webp`.
      expect(etapesPhotos, <String>[depot.venueCree]);
      expect(find.text('L’étape des photos'), findsOneWidget);
    });

    testWidgets('un parking laissé vide reste « non renseigné », pas zéro', (
      tester,
    ) async {
      // La distinction du §6 : NULL veut dire « je ne sais pas », 0 veut dire
      // « il n'y en a pas ». La fiche salle les affiche différemment, et la
      // confondre ici ferait annoncer « aucune place » sur une salle qui a
      // peut-être un grand parking.
      final depot = await ouvre(tester);

      await passeEtape1(tester);
      await passeEtape2(tester);
      await passeEtape3(tester);
      await tester.tap(find.text('Inscrire ma salle'));
      await tester.pumpAndSettle();

      expect(depot.inscrites.single.parking, isNull);
      expect(depot.inscrites.single.superficie, isNull);
    });

    testWidgets('un parking à zéro arrive à zéro, et non à « non renseigné »', (
      tester,
    ) async {
      final depot = await ouvre(tester);

      await passeEtape1(tester);
      await passeEtape2(tester);
      await passeEtape3(tester, parking: '0');
      await tester.tap(find.text('Inscrire ma salle'));
      await tester.pumpAndSettle();

      expect(depot.inscrites.single.parking, 0);
    });

    testWidgets('un refus de la base reste à l’écran, sans rien perdre', (
      tester,
    ) async {
      await ouvre(
        tester,
        erreurDePublication: const PostgrestException(
          message: 'refus',
          code: 'PT400',
          hint: 'FE032',
        ),
      );

      await passeEtape1(tester);
      await passeEtape2(tester);
      await passeEtape3(tester);
      await tester.tap(find.text('Inscrire ma salle'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Cette wilaya n’existe pas'), findsOneWidget);
      // On n'a navigué nulle part, et le formulaire est intact.
      expect(etapesPhotos, isEmpty);
      expect(find.text('Inscrire ma salle'), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Salle Les Palmiers'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // 4. Les codes Ferha de 017
  // ---------------------------------------------------------------------------

  group('Ce que dit la base quand elle refuse', () {
    String phrase(String hint) => messageErreurPublication(
      PostgrestException(message: 'refus', code: 'PT400', hint: hint),
    );

    test('les huit codes sont traduits, aucun n’est laissé en clair', () {
      for (final code in <String>[
        'FE030',
        'FE031',
        'FE032',
        'FE033',
        'FE034',
        'FE035',
        // L'adresse (019) et le téléphone (020). Ils ne devraient jamais
        // s'afficher — les deux boutons restent éteints sans eux — mais un
        // code laissé en clair à l'écran est ce qu'on voit quand l'écran et la
        // base cessent de dire la même chose.
        'FE036',
        'FE037',
      ]) {
        expect(phrase(code), isNot(contains(code)), reason: code);
        expect(phrase(code), isNotEmpty, reason: code);
      }
    });

    test('FE035 ne gronde personne : un double appui n’est pas une faute', () {
      expect(phrase('FE035'), contains('déjà été envoyée'));
      expect(phrase('FE035'), contains('validation'));
    });

    test('un code inconnu retombe sur le message d’origine', () {
      expect(
        messageErreurPublication(
          const PostgrestException(message: 'panne inattendue', code: 'XX000'),
        ),
        contains('panne inattendue'),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // 5. Le modèle, sans écran
  // ---------------------------------------------------------------------------

  group('NouvelleSalle', () {
    test('copyWith sait effacer, et pas seulement remplacer', () {
      // Les quatre champs nullables ont besoin de la sentinelle : sans elle,
      // effacer un parking déjà saisi serait impossible, et le champ resterait
      // à sa valeur pour toujours.
      const pleine = NouvelleSalle(
        nom: 'Salle',
        wilayaCode: '31',
        capacite: 300,
        superficie: 600,
        parking: 60,
      );

      expect(pleine.copyWith(parking: null).parking, isNull);
      expect(pleine.copyWith(superficie: null).superficie, isNull);
      expect(pleine.copyWith(wilayaCode: null).wilayaCode, isNull);
      // Et ne rien passer ne touche à rien.
      expect(pleine.copyWith(nom: 'Autre').parking, 60);
      expect(pleine.copyWith(nom: 'Autre').wilayaCode, '31');
    });

    test('les cinq champs obligatoires : quatre de la table, un d’ADM-01', () {
      const vide = NouvelleSalle();
      expect(vide.estEnvoyable, isFalse);

      // Quatre viennent des `not null` de `venues` ; l'adresse vient d'ADM-01,
      // et elle est nullable en table — ce sont `creer_salle()` et cet écran
      // qui l'exigent, pour les salles neuves seulement.
      const sansAdresse = NouvelleSalle(
        nom: 'Salle',
        wilayaCode: '31',
        commune: 'Oran',
        capacite: 300,
      );
      expect(sansAdresse.estEnvoyable, isFalse);

      const complete = NouvelleSalle(
        nom: 'Salle',
        wilayaCode: '31',
        commune: 'Oran',
        adresse: 'Cité 200 logements',
        capacite: 300,
      );
      // Ni superficie, ni parking, ni description, ni équipement : la salle
      // part quand même. « Karim ne veut pas d'un formulaire de 30 champs. »
      expect(complete.estEnvoyable, isTrue);
    });

    test(
      '« étape N sur 5 » compte les écrans, pas les valeurs de l’énumération',
      () {
        // CINQ, ET L'ÉNUMÉRATION N'EN PORTE QUE QUATRE, depuis que les photos
        // existent (OWN-02). Elles ont leur propre écran et leur propre route,
        // parce qu'elles écrivent dans une salle qui existe déjà — mais le
        // propriétaire, lui, traverse bien cinq écrans, et c'est ce qu'on lui
        // annonce. Ce test est là pour que la différence reste voulue : si un
        // jour une cinquième valeur entre dans l'énumération, il tombera.
        expect(EtapePublication.total, 5);
        expect(EtapePublication.values, hasLength(4));
        expect(EtapePublication.identite.rang, 1);
        expect(EtapePublication.equipements.rang, 4);
        expect(EtapePublication.rangDesPhotos, EtapePublication.total);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // 6. Le thème sombre
  // ---------------------------------------------------------------------------

  testWidgets('le formulaire s’affiche aussi en thème sombre', (tester) async {
    await ouvre(tester, theme: FerhaTheme.dark());

    expect(tester.takeException(), isNull);
    expect(find.text('Étape 1 sur 5'), findsOneWidget);
  });
}
