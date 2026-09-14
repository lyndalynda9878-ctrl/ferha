import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ferha/core/l10n/generated/app_localizations.dart';
import 'package:ferha/core/l10n/locale_controller.dart';
import 'package:ferha/core/preferences/preferences_affichage.dart';
import 'package:ferha/core/supabase/supabase_providers.dart';
import 'package:ferha/core/router/routes.dart';
import 'package:ferha/core/theme/ferha_theme.dart';
import 'package:ferha/features/auth/auth_providers.dart';
import 'package:ferha/features/owner/compression_photo.dart';
import 'package:ferha/features/owner/owner_repository.dart';
import 'package:ferha/features/owner/photo_de_salle.dart';
import 'package:ferha/features/owner/photos_salle_screen.dart';

import 'owner_fakes.dart';

/// L'étape des photos (§4.3, OWN-02 ; §7.3 ; écran 10).
///
/// CE QUE CE FICHIER SURVEILLE :
///
///   1. QUE « CONTINUER » RESTE ÉTEINT SOUS CINQ PHOTOS, et qu'il dise combien
///      il en manque. `envoyer_salle_en_validation()` (021) refuse en FE041 :
///      un bouton allumé ferait traverser le récapitulatif pour y essuyer ce
///      refus, sur un écran où l'on croit avoir fini.
///
///   2. QUE LA PHOTO DÉPLACÉE EN PREMIÈRE POSITION DEVIENNE LA COUVERTURE.
///      C'est la promesse de la maquette — « la première devient la
///      couverture » — et il n'y a pas d'autre geste pour la choisir. Le test
///      regarde les deux moitiés : l'ORDRE envoyé au dépôt, et la pastille
///      affichée après coup.
///
///   3. QUE LE FORMAT RÉELLEMENT PRODUIT DÉCIDE DE L'EXTENSION. C'est la règle
///      du §7.3 poussée jusqu'au bout : un repli JPEG s'appelle « .jpg », et
///      jamais « .webp ». La compression est doublée ici, mais
///      [reconnaitreFormat] est la vraie — c'est elle qui refuse le PNG.
///
///   4. QU'UNE PHOTO QUI ÉCHOUE ÉCHOUE SEULE, et se renvoie seule. Sur une 4G
///      qui coupe une fois, refaire les cinq autres est ce qui fait abandonner.
void main() {
  const venueId = '5a11e000-0000-4000-a000-0000000000ff';

  // LE PREMIER TEST DE CE DÉPÔT QUI A BESOIN D'UN CLIENT SUPABASE, et
  // `supabase_providers.dart` l'annonçait : « c'est ce qui permettra de
  // substituer un client de test le jour où il y aura des tests de données ».
  // Ce client-là ne parle à personne — `PhotoSalle` ne lui demande que
  // `getPublicUrl()`, qui colle un chemin au bout d'une URL sans rien envoyer.
  // Sans lui, chaque vignette lève au lieu de s'afficher.
  //
  // UN SEUL POUR TOUT LE FICHIER, ET SANS `dispose()`. Deux détails, et les
  // deux sont des pièges de `flutter_test`, où le temps est simulé :
  //
  //   * `autoRefreshToken: false` — GoTrue lance sinon, dès sa construction, un
  //     `Timer.periodic` de dix secondes qui ne s'éteint jamais sous le temps
  //     simulé, et chaque test échoue sur « A Timer is still pending » ;
  //   * pas de `dispose()` — il attend la fermeture du canal temps réel, qui
  //     n'arrive jamais non plus, et c'est toute la suite qui ne rend pas la
  //     main. Un client qui n'a ouvert aucune connexion n'a rien à refermer.
  final clientDeTest = SupabaseClient(
    'https://exemple.supabase.co',
    'cle-de-test-sans-valeur',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );

  /// Monte l'écran sur un dépôt et un sélecteur de test.
  ///
  /// La fenêtre est haute à dessein : l'écran empile une liste, deux boutons,
  /// un encart de conseil et une barre du bas, et un `RenderFlex overflowed`
  /// ferait échouer des tests qui ne parlent pas de mise en page.
  Future<
    ({
      DepotDeTest depot,
      SelecteurDeTest selecteur,
      CompresseurDeTest compresseur,
    })
  >
  ouvre(
    WidgetTester tester, {
    int photosExistantes = 0,
    int photosAChoisir = 1,
    FormatPhoto format = FormatPhoto.webp,
    Object? erreurDePhotos,
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = const Size(1000, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final depot = DepotDeTest()
      ..galeries[venueId] = galerieDeTest(photosExistantes)
      ..erreurDePhotos = erreurDePhotos;

    final selecteur = SelecteurDeTest(aRendre: photosAChoisir);
    final compresseur = CompresseurDeTest(format: format);

    final routeur = GoRouter(
      initialLocation: FerhaRoutes.publierPhotosDe(venueId),
      routes: <RouteBase>[
        GoRoute(
          path: FerhaRoutes.publierPhotos,
          builder: (context, state) =>
              PhotosSalleScreen(venueId: state.pathParameters['id']!),
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
          supabaseClientProvider.overrideWithValue(clientDeTest),
          ownerRepositoryProvider.overrideWithValue(depot),
          selecteurDePhotosProvider.overrideWithValue(selecteur),
          compresseurDePhotoProvider.overrideWithValue(compresseur),
        ],
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: ferhaSupportedLocales,
          theme: theme ?? FerhaTheme.light(),
          routerConfig: routeur,
        ),
      ),
    );
    await tester.pumpAndSettle();

    return (depot: depot, selecteur: selecteur, compresseur: compresseur);
  }

  /// Le bouton « Continuer » de la barre du bas.
  FilledButton continuer(WidgetTester tester) => tester.widget<FilledButton>(
    find.ancestor(
      of: find.text('Continuer'),
      matching: find.byType(FilledButton),
    ),
  );

  group('« Continuer » et le minimum de cinq photos', () {
    testWidgets('reste éteint sous cinq photos, et dit combien il en manque', (
      tester,
    ) async {
      await ouvre(tester, photosExistantes: 3);

      expect(continuer(tester).onPressed, isNull);
      expect(find.text('Encore 2 photos avant de continuer.'), findsOneWidget);
    });

    testWidgets('accorde le singulier quand il n’en manque qu’une', (
      tester,
    ) async {
      await ouvre(tester, photosExistantes: 4);

      expect(continuer(tester).onPressed, isNull);
      expect(find.text('Encore une photo avant de continuer.'), findsOneWidget);
    });

    testWidgets('s’allume à cinq photos, et annonce le compte', (tester) async {
      await ouvre(tester, photosExistantes: photosMinimum);

      expect(continuer(tester).onPressed, isNotNull);
      expect(find.text('5 photos sur $photosMaximum'), findsOneWidget);
    });

    testWidgets('s’éteint pendant un envoi, même avec cinq photos déjà là', (
      tester,
    ) async {
      // LE CAS QU'ON OUBLIE : cinq photos en base et une sixième en vol.
      // Continuer maintenant abandonnerait un envoi en cours, et le
      // propriétaire trouverait une photo de moins que ce qu'il a vu.
      final monde = await ouvre(tester, photosExistantes: photosMinimum);

      // On retient l'envoi au dépôt : sans cela, la doublure répond dans le
      // même tour de boucle et l'instant qu'on veut observer n'existe pas.
      monde.depot.envoiRetenu = Completer<void>();

      await tester.tap(find.text('Galerie'));
      // Deux `pump` : le premier laisse le sélecteur rendre ses fichiers, le
      // second laisse l'écran les enfiler et lancer l'envoi. Un `pumpAndSettle`
      // n'irait nulle part — l'envoi est retenu exprès.
      await tester.pump();
      await tester.pump();

      expect(continuer(tester).onPressed, isNull);
      expect(find.text('Attendez la fin des envois en cours.'), findsOneWidget);

      // Le réseau rend la main : le bouton se rallume tout seul.
      monde.depot.envoiRetenu!.complete();
      monde.depot.envoiRetenu = null;
      await tester.pumpAndSettle();

      expect(continuer(tester).onPressed, isNotNull);
      expect(find.text('6 photos sur $photosMaximum'), findsOneWidget);
    });

    testWidgets('mène au récapitulatif une fois allumé', (tester) async {
      await ouvre(tester, photosExistantes: photosMinimum);

      await tester.tap(find.text('Continuer'));
      await tester.pumpAndSettle();

      expect(find.text('Le récapitulatif'), findsOneWidget);
    });
  });

  group('La couverture est la première photo', () {
    testWidgets('la pastille « Couverture » est sur la première, et seule', (
      tester,
    ) async {
      await ouvre(tester, photosExistantes: 3);

      expect(find.text('Couverture'), findsOneWidget);
      expect(find.text('Photo 2'), findsOneWidget);
      expect(find.text('Photo 3'), findsOneWidget);
    });

    testWidgets(
      'la photo déplacée en première position devient la couverture',
      (tester) async {
        final monde = await ouvre(tester, photosExistantes: 3);
        final avant = await monde.depot.photos(venueId);

        // On remonte la troisième en tête, comme le ferait un glisser-déposer.
        final etat = tester.state<State<PhotosSalleScreen>>(
          find.byType(PhotosSalleScreen),
        );
        final liste = tester.widget<ReorderableListView>(
          find.byType(ReorderableListView),
        );
        liste.onReorder(2, 0);
        await tester.pumpAndSettle();

        expect(etat.mounted, isTrue);

        // LA PREMIÈRE MOITIÉ : l'ordre COMPLET est parti au dépôt, la photo
        // déplacée en tête. `reordonner_photos()` (021) refuse une liste
        // partielle (FE040) — envoyer autre chose que la galerie entière
        // échouerait en vrai sans échouer ici.
        expect(monde.depot.ordresRecus, hasLength(1));
        expect(monde.depot.ordresRecus.single, <String>[
          avant[2].id,
          avant[0].id,
          avant[1].id,
        ]);

        // LA SECONDE MOITIÉ, sans laquelle la première ne prouve rien : la
        // couverture affichée est bien celle qu'on a déplacée.
        final apres = await monde.depot.photos(venueId);
        expect(apres.first.id, avant[2].id);
        expect(apres.first.estCouverture, isTrue);
        expect(apres.where((p) => p.estCouverture), hasLength(1));

        expect(find.text('Couverture'), findsOneWidget);
      },
    );

    testWidgets('un refus du dépôt remet l’ordre précédent, et le dit', (
      tester,
    ) async {
      final monde = await ouvre(tester, photosExistantes: 3);
      final avant = await monde.depot.photos(venueId);

      monde.depot.erreurDePhotos = StateError('la base a dit non');

      final liste = tester.widget<ReorderableListView>(
        find.byType(ReorderableListView),
      );
      liste.onReorder(2, 0);
      await tester.pumpAndSettle();

      // La galerie n'a pas bougé, et l'écran ne prétend pas le contraire.
      final apres = monde.depot.galeries[venueId]!;
      expect(apres.first.id, avant.first.id);
      expect(find.textContaining('la base a dit non'), findsOneWidget);
    });
  });

  group('Le format réellement produit décide de l’extension', () {
    testWidgets('du WebP donne un chemin en .webp', (tester) async {
      final monde = await ouvre(tester, photosAChoisir: 1);

      await tester.tap(find.text('Galerie'));
      await tester.pumpAndSettle();

      expect(monde.depot.envoyeesPhotos.single.format, FormatPhoto.webp);
      final photos = await monde.depot.photos(venueId);
      expect(photos.single.chemin, startsWith('$venueId/'));
      expect(photos.single.chemin, endsWith('.webp'));
    });

    testWidgets('un repli JPEG donne un chemin en .jpg, et jamais en .webp', (
      tester,
    ) async {
      // LE CAS DU §7.3 : un navigateur qui ne sait pas encoder du WebP. Le
      // fichier doit s'appeler comme ce qu'il EST.
      final monde = await ouvre(
        tester,
        photosAChoisir: 1,
        format: FormatPhoto.jpeg,
      );

      await tester.tap(find.text('Galerie'));
      await tester.pumpAndSettle();

      expect(monde.depot.envoyeesPhotos.single.format, FormatPhoto.jpeg);
      final photos = await monde.depot.photos(venueId);
      expect(photos.single.chemin, endsWith('.jpg'));
      expect(photos.single.chemin, isNot(endsWith('.webp')));
    });

    test('reconnaitreFormat lit les octets, et refuse le PNG', () {
      // C'EST LE TEST QUI TIENT LA PROMESSE « JAMAIS UN PNG DÉGUISÉ EN .WEBP ».
      // Sur le web, `canvas.toDataURL('image/webp')` retombe silencieusement
      // sur du PNG et le paquet jette le préfixe qui l'aurait dit : seule une
      // lecture des octets peut encore le voir.
      final webp = Uint8List.fromList(<int>[
        0x52, 0x49, 0x46, 0x46, // RIFF
        0x24, 0x00, 0x00, 0x00, // la taille, sans importance ici
        0x57, 0x45, 0x42, 0x50, // WEBP
      ]);
      final jpeg = Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xE0, 0x00]);
      final png = Uint8List.fromList(<int>[
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
      ]);

      expect(reconnaitreFormat(webp), FormatPhoto.webp);
      expect(reconnaitreFormat(jpeg), FormatPhoto.jpeg);
      expect(reconnaitreFormat(png), isNull);

      // Un RIFF qui n'est pas du WebP — un WAV, par exemple — ne doit pas
      // passer sur ses quatre premiers octets.
      final riffAutre = Uint8List.fromList(<int>[
        0x52, 0x49, 0x46, 0x46,
        0x24, 0x00, 0x00, 0x00,
        0x57, 0x41, 0x56, 0x45, // WAVE
      ]);
      expect(reconnaitreFormat(riffAutre), isNull);

      // Et rien qui soit trop court pour être lu ne doit faire lever.
      expect(reconnaitreFormat(Uint8List(0)), isNull);
      expect(reconnaitreFormat(Uint8List.fromList(<int>[0xFF, 0xD8])), isNull);
    });
  });

  group('Une photo qui échoue échoue seule', () {
    testWidgets('elle se renvoie sans refaire les autres', (tester) async {
      final monde = await ouvre(tester, photosAChoisir: 3);
      monde.depot.erreurDePhotos = StateError('la 4G a coupé');

      await tester.tap(find.text('Galerie'));
      await tester.pumpAndSettle();

      // Les trois ont échoué, chacune avec son bouton.
      expect(find.text('Cette photo n’est pas partie'), findsNWidgets(3));
      expect(find.text('Renvoyer'), findsNWidgets(3));
      expect(monde.compresseur.appels, 3);

      // Le réseau revient. On n'en renvoie qu'une.
      monde.depot.erreurDePhotos = null;
      await tester.tap(find.text('Renvoyer').first);
      await tester.pumpAndSettle();

      final photos = await monde.depot.photos(venueId);
      expect(photos, hasLength(1));
      expect(find.text('Cette photo n’est pas partie'), findsNWidgets(2));

      // LA LIGNE QUI COMPTE : une seule compression de plus, pas quatre. Les
      // deux autres n'ont pas été refaites.
      expect(monde.compresseur.appels, 4);
    });

    testWidgets('« Retirer » l’enlève de la file sans rien envoyer', (
      tester,
    ) async {
      final monde = await ouvre(tester, photosAChoisir: 1);
      monde.depot.erreurDePhotos = StateError('non');

      await tester.tap(find.text('Galerie'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Retirer'));
      await tester.pumpAndSettle();

      expect(find.text('Cette photo n’est pas partie'), findsNothing);
      // On regarde la galerie du dépôt en direct, et non par `photos()` : le
      // dépôt lève encore, et c'est ce qu'on veut — la question est de savoir si
      // « Retirer » a écrit quelque part, pas si la lecture remarche.
      expect(monde.depot.galeries[venueId], isEmpty);
      expect(monde.depot.envoyeesPhotos, isEmpty);
    });
  });

  group('La borne de vingt photos', () {
    testWidgets('le sélecteur ne se voit proposer que les places restantes', (
      tester,
    ) async {
      final monde = await ouvre(tester, photosExistantes: 18);

      await tester.tap(find.text('Galerie'));
      await tester.pumpAndSettle();

      expect(monde.selecteur.dernierMaximum, photosMaximum - 18);
    });

    testWidgets(
      'à vingt photos, les deux boutons cèdent la place à une phrase',
      (tester) async {
        await ouvre(tester, photosExistantes: photosMaximum);

        expect(find.text('Galerie'), findsNothing);
        expect(find.text('Appareil photo'), findsNothing);
        expect(
          find.textContaining('vous avez atteint', skipOffstage: false),
          findsNothing,
        );
        expect(
          find.textContaining('$photosMaximum photos, le maximum'),
          findsOneWidget,
        );
      },
    );
  });

  group('Ce que l’écran n’affiche pas', () {
    testWidgets('ni la statistique inventée, ni le conseil automatique', (
      tester,
    ) async {
      // La maquette porte « trois fois plus de demandes » et « il manque une
      // photo du parking ». Aucune donnée du projet ne soutient le premier, et
      // le second demanderait de reconnaître ce qu'il y a sur les images. À
      // leur place, une phrase fixe et vraie.
      await ouvre(tester, photosExistantes: 3);

      expect(find.textContaining('trois fois plus'), findsNothing);
      expect(find.textContaining('il manque une photo'), findsNothing);
      expect(find.text('Pensez à l’extérieur et au parking.'), findsOneWidget);
    });
  });

  group('Clair et sombre', () {
    testWidgets('l’écran se construit dans les deux thèmes', (tester) async {
      await ouvre(tester, photosExistantes: 3, theme: FerhaTheme.dark());
      expect(tester.takeException(), isNull);
      expect(find.text('Couverture'), findsOneWidget);
    });
  });
}
