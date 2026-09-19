import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ferha/core/l10n/generated/app_localizations.dart';
import 'package:ferha/core/l10n/locale_controller.dart';
import 'package:ferha/core/router/routes.dart';
import 'package:ferha/core/theme/ferha_theme.dart';
import 'package:ferha/features/auth/auth_providers.dart';
import 'package:ferha/features/favorites/favoris_providers.dart';
import 'package:ferha/features/favorites/favoris_repository.dart';
import 'package:ferha/features/favorites/favoris_screen.dart';
import 'package:ferha/features/favorites/widgets/coeur_favori.dart';
import 'package:ferha/features/search/search_providers.dart';
import 'package:ferha/features/search/venue_summary.dart';

import 'textes_traduits.dart';

/// LES FAVORIS, CÔTÉ ÉCRAN — quatre choses qu'on ne peut pas prouver en SQL.
///
/// La base a ses propres bancs d'essai (`supabase/tests/020`) : la clé primaire
/// composite qui refuse le doublon, et la RLS qui empêche B de voir les favoris
/// de A. Ils prouvent ce que la base garantit. Ce fichier-ci prouve les quatre
/// promesses que seul le Dart tient :
///
///   1. LE CŒUR BASCULE DANS LES DEUX SENS — il allume, et il éteint ;
///   2. IL SE RÉÉTEINT QUAND LA BASE REFUSE, et il dit pourquoi. C'est le test
///      qui compte le plus : un cœur allumé sur un favori qui n'existe pas est
///      le même mensonge qu'un prix qui change entre la liste et la fiche ;
///   3. L'ÉTAT VIDE PORTE SON BOUTON — la règle du projet est qu'un état vide
///      nomme ce qui manque et donne une sortie, jamais « aucun favori » seul ;
///   4. L'ONGLET NON CONNECTÉ NE REDIRIGE PAS. Le routeur n'a aucune
///      redirection globale vers la connexion, et cet onglet n'en gagne pas une.
///
/// LE DÉPÔT EST REMPLACÉ, PAS LE CLIENT SUPABASE. `FavorisRepository` existe
/// pour cela : sans cette couture, la règle n° 2 ne serait vérifiable qu'avec
/// une vraie base en face — donc jamais vérifiée.
void main() {
  const salle = '5a11e000-0000-4000-a000-000000000001';
  const autreSalle = '5a11e000-0000-4000-a000-000000000004';
  const amina = 'd0000000-0000-4000-a000-000000000010';

  // ===========================================================================
  // LES DOUBLURES
  // ===========================================================================

  /// Une session valide, sans réseau ni GoTrue derrière.
  Session sessionDe(String utilisateur) => Session(
    accessToken: 'jeton-de-test',
    tokenType: 'bearer',
    user: User(
      id: utilisateur,
      appMetadata: const <String, dynamic>{},
      userMetadata: const <String, dynamic>{},
      aud: 'authenticated',
      createdAt: DateTime(2026).toIso8601String(),
    ),
  );

  ProviderContainer conteneur({Session? session, _DepotDeTest? depot}) {
    final c = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        sessionProvider.overrideWith(() => _SessionDeTest(session)),
        favorisRepositoryProvider.overrideWithValue(depot ?? _DepotDeTest()),
        // La carte traduit les codes d'équipement ; sans cette doublure elle
        // irait les chercher dans une base qu'aucun test n'a ouverte.
        equipementsProvider.overrideWith(
          (ref) async => const <String, String>{},
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  /// Monte un widget sous l'application, dans la langue et le thème demandés.
  Future<void> monte(
    WidgetTester tester,
    ProviderContainer c,
    Widget enfant, {
    Locale locale = const Locale('fr'),
    bool sombre = false,
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: ferhaSupportedLocales,
          theme: sombre ? FerhaTheme.dark() : FerhaTheme.light(),
          home: Scaffold(body: Center(child: enfant)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Vrai quand le cœur affiché est plein.
  bool coeurAllume(WidgetTester tester) =>
      find.byIcon(Icons.favorite).evaluate().isNotEmpty;

  // ===========================================================================
  // 1. LE CŒUR BASCULE DANS LES DEUX SENS
  // ===========================================================================

  group('Le cœur bascule', () {
    testWidgets('un appui allume, un second éteint', (tester) async {
      final depot = _DepotDeTest();
      final c = conteneur(session: sessionDe(amina), depot: depot);

      await monte(tester, c, const CoeurFavori(venueId: salle));

      // Au départ : rien d'aimé, donc un cœur vide.
      expect(coeurAllume(tester), isFalse);
      expect(find.byIcon(Icons.favorite_outline), findsOneWidget);

      await tester.tap(find.byType(CoeurFavori));
      await tester.pumpAndSettle();

      // ALLUMÉ À L'ÉCRAN, ET ÉCRIT EN BASE. Les deux, sans quoi le test
      // passerait sur un cœur purement décoratif.
      expect(coeurAllume(tester), isTrue);
      expect(depot.ajoutes, <String>[salle]);
      expect(c.read(favorisIdsProvider).value, <String>{salle});

      await tester.tap(find.byType(CoeurFavori));
      await tester.pumpAndSettle();

      expect(coeurAllume(tester), isFalse);
      expect(depot.retires, <String>[salle]);
      expect(c.read(favorisIdsProvider).value, isEmpty);
    });

    testWidgets('il part de ce que la base porte déjà', (tester) async {
      // Un favori posé la semaine dernière : le cœur doit être allumé dès la
      // première image, sans qu'on ait à y toucher.
      final depot = _DepotDeTest(identifiants: <String>{salle});
      final c = conteneur(session: sessionDe(amina), depot: depot);

      await monte(tester, c, const CoeurFavori(venueId: salle));

      expect(coeurAllume(tester), isTrue);
      expect(depot.ajoutes, isEmpty);
    });

    testWidgets('deux cœurs voisins ne se marchent pas dessus', (tester) async {
      // UNE SEULE REQUÊTE POUR TOUT L'ÉCRAN : les deux cœurs lisent le même
      // ensemble. Allumer l'un ne doit pas allumer l'autre.
      final depot = _DepotDeTest();
      final c = conteneur(session: sessionDe(amina), depot: depot);

      await monte(
        tester,
        c,
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CoeurFavori(venueId: salle),
            CoeurFavori(venueId: autreSalle),
          ],
        ),
      );

      await tester.tap(find.byType(CoeurFavori).first);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.favorite), findsOneWidget);
      expect(find.byIcon(Icons.favorite_outline), findsOneWidget);
      expect(c.read(favorisIdsProvider).value, <String>{salle});
    });

    testWidgets('les deux étiquettes existent, et elles diffèrent', (
      tester,
    ) async {
      // DEUX LIBELLÉS ET NON UN SEUL : le bouton annonce ce qu'un appui fera,
      // jamais l'état courant — la règle de la bascule de thème.
      final c = conteneur(session: sessionDe(amina));
      await monte(tester, c, const CoeurFavori(venueId: salle));

      expect(
        tester.widget<Tooltip>(find.byType(Tooltip)).message,
        textesFr.favoriAjouter,
      );
      expect(
        tester.widget<Icon>(find.byType(Icon)).semanticLabel,
        textesFr.favoriAjouter,
      );

      await tester.tap(find.byType(CoeurFavori));
      await tester.pumpAndSettle();

      expect(
        tester.widget<Tooltip>(find.byType(Tooltip)).message,
        textesFr.favoriRetirer,
      );
      expect(textesFr.favoriAjouter, isNot(textesFr.favoriRetirer));
    });
  });

  // ===========================================================================
  // 2. IL SE RÉÉTEINT QUAND LA BASE REFUSE
  // ===========================================================================

  group('Quand la base refuse', () {
    testWidgets('le cœur s’allume, puis se rééteint, et il le dit', (
      tester,
    ) async {
      // LE REFUS ARRIVE EN DEUX TEMPS, et c'est tout l'intérêt : on regarde
      // l'écran PENDANT que la requête est en vol. Un dépôt qui échouerait
      // instantanément ne montrerait jamais le cœur allumé, et le test ne
      // prouverait pas que l'allumage précède la base.
      final enVol = Completer<void>();
      final depot = _DepotDeTest(ajoutEnAttente: enVol);
      final c = conteneur(session: sessionDe(amina), depot: depot);

      await monte(tester, c, const CoeurFavori(venueId: salle));
      expect(coeurAllume(tester), isFalse);

      await tester.tap(find.byType(CoeurFavori));
      await tester.pump();

      // LE DOIGT A VU TOUT DE SUITE, la base n'a pas encore répondu.
      expect(coeurAllume(tester), isTrue);
      expect(enVol.isCompleted, isFalse);

      enVol.completeError(
        const PostgrestException(message: 'refus du serveur', code: '42501'),
      );
      await tester.pumpAndSettle();

      // IL S'EST RÉÉTEINT.
      expect(coeurAllume(tester), isFalse);
      expect(find.byIcon(Icons.favorite_outline), findsOneWidget);
      expect(c.read(favorisIdsProvider).value, isEmpty);

      // ET IL DIT POURQUOI. Un cœur qui se rééteint en silence laisserait
      // croire à un doigt mal posé.
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining(textesFr.favoriNonEnregistre), findsOneWidget);
    });

    testWidgets('un retrait refusé rallume le cœur', (tester) async {
      // L'AUTRE SENS, et il n'est pas symétrique par construction : le
      // fournisseur remet l'ensemble D'AVANT, il ne prend pas le contraire de
      // ce qu'il vient d'écrire.
      final depot = _DepotDeTest(
        identifiants: <String>{salle},
        erreurDeRetrait: const PostgrestException(message: 'refus'),
      );
      final c = conteneur(session: sessionDe(amina), depot: depot);

      await monte(tester, c, const CoeurFavori(venueId: salle));
      expect(coeurAllume(tester), isTrue);

      await tester.tap(find.byType(CoeurFavori));
      await tester.pumpAndSettle();

      expect(coeurAllume(tester), isTrue);
      expect(c.read(favorisIdsProvider).value, <String>{salle});
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });

  // ===========================================================================
  // 3. L'ÉTAT VIDE PORTE SON BOUTON
  // ===========================================================================

  group('L’onglet, connecté', () {
    testWidgets('vide, il nomme le geste et donne une sortie', (tester) async {
      final c = conteneur(session: sessionDe(amina), depot: _DepotDeTest());

      await monte(tester, c, const FavorisScreen());

      // IL NE DIT PAS « AUCUN FAVORI ». Il nomme le geste qui manque.
      expect(find.text(textesFr.favorisVideTitre), findsOneWidget);
      expect(find.text(textesFr.favorisVideTexte), findsOneWidget);

      // ET IL DONNE UN BOUTON POUR EN SORTIR — c'est la moitié qui s'oublie.
      //
      // UN PRÉDICAT ET NON `widgetWithText`, parce que le bouton porte une
      // icône : `FilledButton.icon` construit une SOUS-CLASSE, et `byType` ne
      // reconnaît que le type exact. Un test écrit avec `byType` passerait de
      // vert à rouge le jour où quelqu'un ajoute une icône, sans qu'aucune
      // promesse n'ait été rompue.
      final bouton = find.ancestor(
        of: find.text(textesFr.favorisVideBouton),
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      );
      expect(bouton, findsOneWidget);
      expect(
        (tester.widget(bouton) as FilledButton).onPressed,
        isNotNull,
        reason:
            'Un bouton d’état vide désactivé serait pire que pas de bouton.',
      );
    });

    testWidgets('plein, il réutilise la carte de partout ailleurs', (
      tester,
    ) async {
      final depot = _DepotDeTest(
        salles: <VenueSummary>[
          const VenueSummary(
            id: salle,
            nom: 'Salle El Bahia',
            wilayaCode: '31',
            commune: 'Oran',
            capacite: 450,
            prix: 180000,
            creneauPrix: 'soir',
          ),
        ],
      );
      final c = conteneur(session: sessionDe(amina), depot: depot);

      await monte(tester, c, const FavorisScreen());

      expect(find.text('Salle El Bahia'), findsOneWidget);
      expect(find.text(textesFr.favorisVideTitre), findsNothing);
    });

    testWidgets('il se dessine aussi en thème sombre', (tester) async {
      // LA RÈGLE DU PROJET : thème clair ET sombre pour chaque nouvel écran.
      // Les trois états de l'onglet et le cœur ne posent aucune couleur à la
      // main — tout vient de `FerhaColors`, qui a ses deux jeux. Ce test le
      // tient : une couleur écrite en dur passerait ici en clair et rendrait
      // l'écran illisible en sombre sans que rien ne le signale.
      final depot = _DepotDeTest(
        salles: <VenueSummary>[
          const VenueSummary(
            id: salle,
            nom: 'Salle El Bahia',
            wilayaCode: '31',
            commune: 'Oran',
            capacite: 450,
            prix: 180000,
            creneauPrix: 'soir',
          ),
        ],
      );
      final c = conteneur(session: sessionDe(amina), depot: depot);

      await monte(tester, c, const FavorisScreen(), sombre: true);

      expect(tester.takeException(), isNull);
      expect(find.text('Salle El Bahia'), findsOneWidget);
      expect(
        Theme.of(tester.element(find.byType(FavorisScreen))).brightness,
        Brightness.dark,
      );
    });

    testWidgets('vide, il se dessine aussi en thème sombre', (tester) async {
      final c = conteneur(session: sessionDe(amina), depot: _DepotDeTest());

      await monte(tester, c, const FavorisScreen(), sombre: true);

      expect(tester.takeException(), isNull);
      expect(find.text(textesFr.favorisVideTitre), findsOneWidget);
    });

    testWidgets('en erreur, il propose Réessayer', (tester) async {
      final depot = _DepotDeTest(
        erreurDeListe: const PostgrestException(message: 'réseau coupé'),
      );
      final c = conteneur(session: sessionDe(amina), depot: depot);

      await monte(tester, c, const FavorisScreen());

      expect(find.text(textesFr.favorisErreurTitre), findsOneWidget);
    });
  });

  // ===========================================================================
  // 4. NON CONNECTÉ, IL EXPLIQUE — IL NE REDIRIGE PAS
  // ===========================================================================

  testWidgets('non connecté, l’onglet reste sur /favoris', (tester) async {
    // LE ROUTEUR N'A AUCUNE REDIRECTION GLOBALE et n'en gagne pas une
    // aujourd'hui. Ce test monte un VRAI GoRouter : si l'onglet redirigeait, la
    // route courante serait /connexion et l'explication ne serait pas à l'écran.
    final c = conteneur();

    final routeur = GoRouter(
      initialLocation: FerhaRoutes.favoris,
      routes: <RouteBase>[
        GoRoute(
          path: FerhaRoutes.favoris,
          builder: (_, _) => const FavorisScreen(),
        ),
        GoRoute(
          path: FerhaRoutes.connexion,
          builder: (_, _) =>
              const Scaffold(body: Center(child: Text('écran de connexion'))),
        ),
      ],
    );
    addTearDown(routeur.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp.router(
          locale: const Locale('fr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: ferhaSupportedLocales,
          theme: FerhaTheme.light(),
          routerConfig: routeur,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // ON EST RESTÉ SUR L'ONGLET.
    expect(
      routeur.routerDelegate.currentConfiguration.uri.path,
      FerhaRoutes.favoris,
    );
    expect(find.text('écran de connexion'), findsNothing);

    // ET IL EXPLIQUE, plutôt que de poser un formulaire devant quelqu'un qui
    // voulait seulement voir de quoi il s'agit.
    expect(find.text(textesFr.favorisNonConnecteTitre), findsOneWidget);
    expect(find.text(textesFr.favorisNonConnecteTexte), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, textesFr.authSeConnecter),
      findsOneWidget,
    );
  });

  // ===========================================================================
  // 5. LES DEUX LANGUES
  // ===========================================================================

  group('Les deux langues', () {
    test('toutes les clés des favoris existent en arabe', () {
      final paires = <String, (String, String)>{
        'favorisTitre': (textesFr.favorisTitre, textesAr.favorisTitre),
        'favoriAjouter': (textesFr.favoriAjouter, textesAr.favoriAjouter),
        'favoriRetirer': (textesFr.favoriRetirer, textesAr.favoriRetirer),
        'favoriNonEnregistre': (
          textesFr.favoriNonEnregistre,
          textesAr.favoriNonEnregistre,
        ),
        'favorisVideTitre': (
          textesFr.favorisVideTitre,
          textesAr.favorisVideTitre,
        ),
        'favorisVideTexte': (
          textesFr.favorisVideTexte,
          textesAr.favorisVideTexte,
        ),
        'favorisVideBouton': (
          textesFr.favorisVideBouton,
          textesAr.favorisVideBouton,
        ),
        'favorisNonConnecteTitre': (
          textesFr.favorisNonConnecteTitre,
          textesAr.favorisNonConnecteTitre,
        ),
        'favorisNonConnecteTexte': (
          textesFr.favorisNonConnecteTexte,
          textesAr.favorisNonConnecteTexte,
        ),
        'favorisErreurTitre': (
          textesFr.favorisErreurTitre,
          textesAr.favorisErreurTitre,
        ),
      };

      paires.forEach((cle, textes) {
        final (fr, ar) = textes;
        expect(fr.trim(), isNotEmpty, reason: cle);
        // LE PIÈGE D'UNE CLÉ AJOUTÉE DANS app_fr.arb SEULEMENT : `gen-l10n`
        // retomberait sur le modèle français sans rien dire.
        expect(ar, isNot(fr), reason: cle);
        expect(ar, matches(RegExp(r'[؀-ۿ]')), reason: cle);
      });
    });

    testWidgets('en arabe, le cœur passe de l’autre côté de la carte', (
      tester,
    ) async {
      // LA RÈGLE DE TOUT LE PROJET. Ce qui se vérifie n'est pas l'écart mais le
      // fait qu'il se lise dans le sens de la page : un `Positioned(right:)`
      // donnerait la même valeur en français et resterait à droite en arabe.
      final c = conteneur(session: sessionDe(amina));
      await monte(
        tester,
        c,
        const Directionality(
          textDirection: TextDirection.rtl,
          child: SizedBox(
            width: 200,
            height: 140,
            child: Stack(
              children: <Widget>[
                PositionedDirectional(
                  top: 4,
                  end: 4,
                  child: CoeurFavori(venueId: salle, surPhoto: true),
                ),
              ],
            ),
          ),
        ),
        locale: const Locale('ar'),
      );

      final positionne = tester.widget<Positioned>(
        find
            .ancestor(
              of: find.byType(CoeurFavori),
              matching: find.byType(Positioned),
            )
            .first,
      );

      // En RTL, `end: 4` doit tomber à GAUCHE.
      expect(positionne.left, 4);
      expect(positionne.right, isNull);
    });
  });
}

/// La session que le conteneur de test impose, sans GoTrue derrière.
class _SessionDeTest extends SessionController {
  _SessionDeTest(this._session);

  final Session? _session;

  @override
  Session? build() => _session;
}

/// Un dépôt de favoris qui garde ce qu'on lui envoie, sans réseau ni base.
///
/// IL GARDE LES GESTES, et c'est ce que regardent les tests : non pas ce que
/// l'écran affiche après coup, mais ce qui ARRIVE à la base. Un cœur peut
/// s'allumer juste tout en n'écrivant rien.
class _DepotDeTest implements FavorisRepository {
  _DepotDeTest({
    Set<String> identifiants = const <String>{},
    this.salles = const <VenueSummary>[],
    this.erreurDeRetrait,
    this.erreurDeListe,
    this.ajoutEnAttente,
  }) : _identifiants = <String>{...identifiants};

  final Set<String> _identifiants;

  /// Ce que rend `mes_favoris()`.
  final List<VenueSummary> salles;

  /// Ce que lève le retrait, s'il y a lieu.
  final Object? erreurDeRetrait;

  /// Ce que lève la liste, s'il y a lieu.
  final Object? erreurDeListe;

  /// Quand il est là, l'ajout n'aboutit qu'une fois ce jeton complété.
  ///
  /// C'est ce qui permet de regarder l'écran PENDANT que la requête est en vol
  /// — donc de prouver que le cœur s'allume avant que la base réponde. Il porte
  /// aussi le refus, par `completeError` : un ajout qui échouerait
  /// instantanément ne montrerait jamais le cœur allumé, et le test ne
  /// prouverait pas que l'allumage précède la base.
  final Completer<void>? ajoutEnAttente;

  /// Les salles ajoutées, dans l'ordre.
  final List<String> ajoutes = <String>[];

  /// Les salles retirées, dans l'ordre.
  final List<String> retires = <String>[];

  @override
  Future<Set<String>> identifiantsDe(String utilisateur) async => <String>{
    ..._identifiants,
  };

  @override
  Future<void> ajouter({
    required String utilisateur,
    required String venueId,
  }) async {
    if (ajoutEnAttente != null) await ajoutEnAttente!.future;
    ajoutes.add(venueId);
    _identifiants.add(venueId);
  }

  @override
  Future<void> retirer({
    required String utilisateur,
    required String venueId,
  }) async {
    if (erreurDeRetrait != null) throw erreurDeRetrait!;
    retires.add(venueId);
    _identifiants.remove(venueId);
  }

  @override
  Future<List<VenueSummary>> mesFavoris() async {
    if (erreurDeListe != null) throw erreurDeListe!;
    return salles;
  }
}
