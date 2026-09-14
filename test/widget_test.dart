import 'package:ferha/core/l10n/generated/app_localizations.dart';
import 'package:ferha/core/l10n/locale_controller.dart';
import 'package:ferha/core/theme/display_font.dart';
import 'package:ferha/core/theme/ferha_colors.dart';
import 'package:ferha/core/theme/ferha_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FerhaTheme', () {
    test('le thème clair se construit et porte la palette Ambre & ivoire', () {
      final theme = FerhaTheme.light();
      final colors = theme.extension<FerhaColors>();

      expect(theme.brightness, Brightness.light);
      expect(theme.useMaterial3, isTrue);
      expect(colors, same(FerhaColors.light));
      expect(colors!.primary, const Color(0xFFA06B22));
      expect(colors.background, const Color(0xFFFAF5EC));
      expect(colors.rose, const Color(0xFFC98F92));
      expect(colors.slotFree, const Color(0xFF5C7F5A));
      expect(colors.slotBooked, const Color(0xFFB4574B));
      expect(theme.scaffoldBackgroundColor, colors.background);
      expect(theme.colorScheme.primary, colors.primary);
    });

    test('le thème sombre se construit et porte la palette sombre', () {
      final theme = FerhaTheme.dark();
      final colors = theme.extension<FerhaColors>();

      expect(theme.brightness, Brightness.dark);
      expect(theme.useMaterial3, isTrue);
      expect(colors, same(FerhaColors.dark));
      expect(colors!.primary, const Color(0xFFE0A94E));
      expect(colors.background, const Color(0xFF17130F));
      expect(theme.scaffoldBackgroundColor, colors.background);
      expect(theme.colorScheme.primary, colors.primary);
    });

    test('aucun fond n’est du blanc pur', () {
      const white = Color(0xFFFFFFFF);

      for (final theme in <ThemeData>[FerhaTheme.light(), FerhaTheme.dark()]) {
        final colors = theme.extension<FerhaColors>()!;
        expect(colors.background, isNot(white));
        expect(theme.scaffoldBackgroundColor, isNot(white));
        expect(theme.colorScheme.surface, isNot(white));
      }
    });

    test('les rayons de la charte sont appliqués', () {
      for (final theme in <ThemeData>[FerhaTheme.light(), FerhaTheme.dark()]) {
        final card = theme.cardTheme.shape! as RoundedRectangleBorder;
        final chip = theme.chipTheme.shape! as RoundedRectangleBorder;

        expect(card.borderRadius, BorderRadius.circular(12));
        expect(chip.borderRadius, BorderRadius.circular(20));
      }
    });

    test(
      'les titres portent Bricolage Grotesque, le corps la police système',
      () {
        final text = FerhaTheme.light().textTheme;

        for (final style in <TextStyle?>[
          text.displayLarge,
          text.headlineMedium,
          text.titleLarge,
        ]) {
          expect(style!.fontFamily, ferhaDisplayFontFamily);
          // Les deux axes du fichier variable sont pilotés : sans eux la police
          // s'afficherait à ses valeurs par défaut, wght 800 et opsz 96.
          expect(
            style.fontVariations?.map((v) => v.axis),
            containsAll(<String>['wght', 'opsz']),
          );
        }

        for (final style in <TextStyle?>[text.bodyLarge, text.bodyMedium]) {
          expect(style!.fontFamily, isNot(ferhaDisplayFontFamily));
        }
      },
    );

    test('la graisse demandée se retrouve sur l’axe wght', () {
      final title = FerhaTheme.light().textTheme.titleMedium!;
      final wght = title.fontVariations!.firstWhere((v) => v.axis == 'wght');

      expect(title.fontWeight, FontWeight.w600);
      expect(wght.value, 600);
    });

    testWidgets('les deux thèmes s’appliquent sans erreur', (tester) async {
      for (final theme in <ThemeData>[FerhaTheme.light(), FerhaTheme.dark()]) {
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: ferhaSupportedLocales,
            theme: theme,
            home: Scaffold(
              appBar: AppBar(title: const Text('Ferha')),
              body: Column(
                children: <Widget>[
                  const Text('Socle'),
                  FilledButton(onPressed: () {}, child: const Text('Réserver')),
                  const Chip(label: Text('Puce')),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Socle'), findsOneWidget);

        final context = tester.element(find.text('Socle'));
        expect(Theme.of(context).extension<FerhaColors>(), isNotNull);
        expect(
          Theme.of(context).scaffoldBackgroundColor,
          theme.extension<FerhaColors>()!.background,
        );
      }
    });
  });
}
