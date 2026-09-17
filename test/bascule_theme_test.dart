import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ferha/core/l10n/generated/app_localizations.dart';
import 'package:ferha/core/l10n/locale_controller.dart';
import 'package:ferha/core/preferences/preferences_affichage.dart';
import 'package:ferha/core/theme/ferha_theme.dart';
import 'package:ferha/core/theme/theme_controller.dart';
import 'package:ferha/core/widgets/bouton_theme.dart';

import 'owner_fakes.dart';
import 'textes_traduits.dart';

/// LA BASCULE CLAIR / SOMBRE — trois états derrière, deux positions devant.
///
/// Le thème sombre existe depuis le premier jour et personne ne le voit : il
/// suivait le réglage du système, donc il restait invisible pour quiconque a sa
/// machine en clair. Ce banc vérifie les quatre choses qu'on attend du bouton
/// qui le rend atteignable.
///
/// =============================================================================
/// DEUX CONTENEURS RIVERPOD SUCCESSIFS, C'EST DEUX OUVERTURES DE L'APPLICATION
///
/// Le même dispositif que `salle_retenue_test.dart`, et pour la même raison :
/// entre les deux conteneurs, seules les préférences survivent — exactement
/// comme un `localStorage` survit à un rechargement de page. C'est la seule
/// façon de vérifier qu'on retient vraiment, sans plateforme à simuler.
void main() {
  /// Une ouverture de l'application, sur des préférences qui lui survivent.
  ProviderContainer ouverture(PreferencesEnMemoire preferences) {
    final container = ProviderContainer(
      overrides: [preferencesAffichageProvider.overrideWithValue(preferences)],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// Monte le bouton seul, sous un `MaterialApp` piloté par le fournisseur.
  ///
  /// C'EST BIEN L'APPLICATION QU'ON PILOTE, ET NON UN THÈME POSÉ À LA MAIN :
  /// `themeMode` lit `modeThemeProvider`, comme `main.dart`. Un test qui
  /// poserait `theme:` directement vérifierait que Flutter sait afficher deux
  /// palettes — ce dont personne ne doute — et non que le bouton relie l'un à
  /// l'autre.
  Future<void> monte(
    WidgetTester tester,
    ProviderContainer conteneur, {
    Brightness systeme = Brightness.light,
    Locale locale = const Locale('fr'),
  }) async {
    // LA LUMINOSITÉ DU SYSTÈME EST UNE DONNÉE D'ENTRÉE, et elle se pose SUR LE
    // DISPATCHER, pas dans un `MediaQuery` de l'arbre : c'est `MaterialApp`
    // lui-même qui résout `ThemeMode.system`, au-dessus de tout ce qu'on
    // pourrait envelopper. Un `MediaQuery` posé dans `builder:` arrive une
    // strate trop bas — le thème est déjà choisi quand il s'applique.
    tester.platformDispatcher.platformBrightnessTestValue = systeme;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: conteneur,
        child: Consumer(
          builder: (context, ref, _) => MaterialApp(
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: ferhaSupportedLocales,
            theme: FerhaTheme.light(),
            darkTheme: FerhaTheme.dark(),
            themeMode: ref.watch(modeThemeProvider),
            home: const Scaffold(body: Center(child: BoutonTheme())),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// La luminosité réellement posée sur le bouton.
  Brightness luminositeALEcran(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(BoutonTheme))).brightness;

  // ===========================================================================
  // 1. LE BOUTON CHANGE BIEN LE THÈME
  // ===========================================================================

  group('Le bouton change le thème', () {
    testWidgets('un appui fait passer du clair au sombre', (tester) async {
      final preferences = PreferencesEnMemoire();
      final conteneur = ouverture(preferences);

      await monte(tester, conteneur);

      expect(luminositeALEcran(tester), Brightness.light);
      // IL MONTRE OÙ L'ON VA : une lune sur un écran clair.
      expect(find.byIcon(Icons.dark_mode_outlined), findsOneWidget);

      await tester.tap(find.byType(BoutonTheme));
      await tester.pumpAndSettle();

      expect(luminositeALEcran(tester), Brightness.dark);
      expect(conteneur.read(modeThemeProvider), ThemeMode.dark);
      // Et l'icône a suivi : le soleil annonce maintenant le retour au clair.
      expect(find.byIcon(Icons.light_mode_outlined), findsOneWidget);
      expect(find.byIcon(Icons.dark_mode_outlined), findsNothing);
    });

    testWidgets('un second appui ramène au clair', (tester) async {
      final conteneur = ouverture(PreferencesEnMemoire());
      await monte(tester, conteneur);

      await tester.tap(find.byType(BoutonTheme));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BoutonTheme));
      await tester.pumpAndSettle();

      expect(luminositeALEcran(tester), Brightness.light);
      expect(conteneur.read(modeThemeProvider), ThemeMode.light);
    });

    testWidgets('le bouton n’écrit jamais « suivre le système »', (
      tester,
    ) async {
      // LES DEUX POSITIONS VISIBLES SONT DES CHOIX FERMES. Un bouton qui
      // repasserait par `system` en troisième appui ferait, sur un téléphone
      // clair, deux appuis de suite sans rien changer à l'écran — la meilleure
      // façon de faire croire qu'il est cassé.
      final conteneur = ouverture(PreferencesEnMemoire());
      await monte(tester, conteneur);

      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byType(BoutonTheme));
        await tester.pumpAndSettle();
        expect(conteneur.read(modeThemeProvider), isNot(ThemeMode.system));
      }
    });
  });

  // ===========================================================================
  // 2. LE CHOIX SURVIT AU RECHARGEMENT
  // ===========================================================================

  group('Le choix survit', () {
    testWidgets('le sombre choisi se retrouve à l’ouverture suivante', (
      tester,
    ) async {
      final preferences = PreferencesEnMemoire();

      final premiere = ouverture(preferences);
      await monte(tester, premiere);
      await tester.tap(find.byType(BoutonTheme));
      await tester.pumpAndSettle();

      expect(luminositeALEcran(tester), Brightness.dark);
      expect(await preferences.modeTheme(), 'dark');

      // La page se recharge. Rien ne passe d'un conteneur à l'autre — sauf le
      // fichier de préférences.
      premiere.dispose();

      final seconde = ouverture(preferences);
      await monte(tester, seconde);

      expect(seconde.read(modeThemeProvider), ThemeMode.dark);
      expect(luminositeALEcran(tester), Brightness.dark);
    });

    test(
      'c’est shared_preferences qui porte le choix, et rien d’autre',
      () async {
        // LA CLÉ EST UNE PRÉFÉRENCE D'AFFICHAGE, au même titre que la langue :
        // pas de `profiles.theme`, pas de requête, pas de session. Le contrôleur
        // n'a aucun moyen d'écrire ailleurs — il ne connaît que ce service.
        final preferences = PreferencesEnMemoire();
        final conteneur = ouverture(preferences);

        await conteneur
            .read(modeThemeProvider.notifier)
            .choisir(ThemeMode.dark);

        expect(await preferences.modeTheme(), 'dark');
        // La langue et la salle ne sont pas touchées au passage.
        expect(await preferences.langue(), isNull);
        expect(preferences.retenue, isNull);
      },
    );

    test('une valeur inconnue sur l’appareil ne fait rien tomber', () async {
      // Le fichier est en clair, et sur le web n'importe quelle extension peut
      // y écrire. On retombe sur le thème du système plutôt que de lever.
      final conteneur = ouverture(PreferencesEnMemoire(null, 'sépia'));

      expect(conteneur.read(modeThemeProvider), ThemeMode.system);
      await Future<void>.delayed(Duration.zero);
      expect(conteneur.read(modeThemeProvider), ThemeMode.system);
    });
  });

  // ===========================================================================
  // 3. LE PREMIER LANCEMENT SUIT LE SYSTÈME
  // ===========================================================================

  group('Le premier lancement suit le système', () {
    test('sans rien de retenu, l’état est « suivre le système »', () async {
      final preferences = PreferencesEnMemoire();
      final conteneur = ouverture(preferences);

      expect(conteneur.read(modeThemeProvider), ThemeMode.system);
      // La lecture de la préférence est asynchrone : on la laisse revenir les
      // mains vides, et l'état ne bouge pas.
      await Future<void>.delayed(Duration.zero);
      expect(conteneur.read(modeThemeProvider), ThemeMode.system);
      // ET RIEN N'EST ÉCRIT. Retenir « system » au démarrage effacerait la
      // différence entre « on ne m'a jamais rien demandé » et « on m'a demandé
      // de suivre le téléphone ».
      expect(await preferences.modeTheme(), isNull);
    });

    testWidgets('un téléphone en sombre ouvre en sombre', (tester) async {
      // LE CŒUR DE L'AFFAIRE : c'est pour ce cas-là que « suivre le système »
      // ne disparaît pas quand le bouton arrive.
      final conteneur = ouverture(PreferencesEnMemoire());
      await monte(tester, conteneur, systeme: Brightness.dark);

      expect(conteneur.read(modeThemeProvider), ThemeMode.system);
      expect(luminositeALEcran(tester), Brightness.dark);
      // Et le bouton propose le clair, pas le sombre : il lit la luminosité à
      // l'écran, pas le mode.
      expect(find.byIcon(Icons.light_mode_outlined), findsOneWidget);
    });

    testWidgets('sur un téléphone en sombre, le bouton mène au clair', (
      tester,
    ) async {
      final preferences = PreferencesEnMemoire();
      final conteneur = ouverture(preferences);
      await monte(tester, conteneur, systeme: Brightness.dark);

      await tester.tap(find.byType(BoutonTheme));
      await tester.pumpAndSettle();

      expect(conteneur.read(modeThemeProvider), ThemeMode.light);
      expect(luminositeALEcran(tester), Brightness.light);
      expect(await preferences.modeTheme(), 'light');
    });

    testWidgets('un choix explicite l’emporte sur le système', (tester) async {
      // Téléphone en sombre, « clair » retenu : c'est le choix qui gagne, sans
      // quoi la préférence ne servirait à rien précisément là où elle compte.
      final conteneur = ouverture(PreferencesEnMemoire(null, 'light'));
      await monte(tester, conteneur, systeme: Brightness.dark);

      expect(conteneur.read(modeThemeProvider), ThemeMode.light);
      expect(luminositeALEcran(tester), Brightness.light);
    });
  });

  // ===========================================================================
  // 4. LES DEUX LIBELLÉS EXISTENT DANS LES DEUX LANGUES
  // ===========================================================================

  group('Les deux libellés', () {
    // `textes_traduits.dart` : les deux classes générées, hors de tout arbre.
    final fr = textesFr;
    final ar = textesAr;

    test('les deux langues ont les deux', () {
      for (final (langue, textes) in <(String, AppLocalizations)>[
        ('fr', fr),
        ('ar', ar),
      ]) {
        expect(textes.themeVersSombre.trim(), isNotEmpty, reason: langue);
        expect(textes.themeVersClair.trim(), isNotEmpty, reason: langue);
        // DEUX LIBELLÉS, ET NON UN SEUL : un bouton qui dirait la même chose
        // dans les deux sens ne nommerait pas une destination.
        expect(
          textes.themeVersSombre,
          isNot(textes.themeVersClair),
          reason: langue,
        );
      }
    });

    test('l’arabe n’est pas resté en français', () {
      // Le piège d'une clé ajoutée dans `app_fr.arb` seulement : `gen-l10n`
      // retomberait sur le modèle sans rien dire.
      expect(ar.themeVersSombre, isNot(fr.themeVersSombre));
      expect(ar.themeVersClair, isNot(fr.themeVersClair));
      expect(ar.themeVersSombre, matches(RegExp(r'[؀-ۿ]')));
      expect(ar.themeVersClair, matches(RegExp(r'[؀-ۿ]')));
    });

    testWidgets('le bouton porte le libellé de la langue courante', (
      tester,
    ) async {
      final conteneur = ouverture(PreferencesEnMemoire());
      await monte(tester, conteneur, locale: const Locale('ar'));

      // L'infobulle ET l'étiquette d'accessibilité, qui sont la même phrase :
      // `Tooltip` pose un `Semantics(tooltip:)`, `Icon.semanticLabel` pose le
      // `label`. Sans le second, un lecteur d'écran annoncerait un bouton sans
      // nom.
      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltip.message, ar.themeVersSombre);

      final icone = tester.widget<Icon>(find.byType(Icon));
      expect(icone.semanticLabel, ar.themeVersSombre);
    });

    testWidgets('et il en change quand le thème change', (tester) async {
      final conteneur = ouverture(PreferencesEnMemoire());
      await monte(tester, conteneur);

      expect(
        tester.widget<Tooltip>(find.byType(Tooltip)).message,
        fr.themeVersSombre,
      );

      await tester.tap(find.byType(BoutonTheme));
      await tester.pumpAndSettle();

      expect(
        tester.widget<Tooltip>(find.byType(Tooltip)).message,
        fr.themeVersClair,
      );
    });
  });

  // ===========================================================================
  // 5. LE BOUTON SE RETOURNE AVEC LA PAGE
  // ===========================================================================

  testWidgets('en arabe, le bouton passe de l’autre côté de la barre', (
    tester,
  ) async {
    // LA RÈGLE DE TOUT LE PROJET, sur un bouton de 36 px : `start` et non
    // `left`. Ce qui se vérifie n'est pas l'écart lui-même mais le fait qu'il
    // se lise dans le sens de la page — un `EdgeInsets.only(left:)` donnerait
    // exactement la même valeur en français et resterait à gauche en arabe.
    final conteneur = ouverture(PreferencesEnMemoire());
    await monte(tester, conteneur, locale: const Locale('ar'));

    final padding = tester.widget<Padding>(
      find
          .ancestor(of: find.byType(IconButton), matching: find.byType(Padding))
          .first,
    );
    expect(padding.padding, isA<EdgeInsetsDirectional>());

    final resolu = padding.padding.resolve(TextDirection.rtl);
    expect(
      resolu.right,
      greaterThan(0),
      reason:
          'En RTL, l’écart de « start » doit tomber à DROITE. S’il est à '
          'gauche, c’est qu’un EdgeInsets non directionnel s’est glissé là.',
    );
    expect(resolu.left, 0);
  });
}
