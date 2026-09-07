import 'package:ferha/core/theme/display_font.dart';
import 'package:ferha/core/theme/ferha_colors.dart';
import 'package:ferha/core/theme/ferha_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Thème clair sans appel réseau (voir [systemDisplayFont]).
ThemeData _light() => FerhaTheme.light(displayFont: systemDisplayFont);

/// Thème sombre sans appel réseau (voir [systemDisplayFont]).
ThemeData _dark() => FerhaTheme.dark(displayFont: systemDisplayFont);

void main() {
  group('FerhaTheme', () {
    test('le thème clair se construit et porte la palette Ambre & ivoire', () {
      final theme = _light();
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
      final theme = _dark();
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

      for (final theme in <ThemeData>[_light(), _dark()]) {
        final colors = theme.extension<FerhaColors>()!;
        expect(colors.background, isNot(white));
        expect(theme.scaffoldBackgroundColor, isNot(white));
        expect(theme.colorScheme.surface, isNot(white));
      }
    });

    test('les rayons de la charte sont appliqués', () {
      for (final theme in <ThemeData>[_light(), _dark()]) {
        final card = theme.cardTheme.shape! as RoundedRectangleBorder;
        final chip = theme.chipTheme.shape! as RoundedRectangleBorder;

        expect(card.borderRadius, BorderRadius.circular(12));
        expect(chip.borderRadius, BorderRadius.circular(20));
      }
    });

    testWidgets('les deux thèmes s’appliquent sans erreur', (tester) async {
      for (final theme in <ThemeData>[_light(), _dark()]) {
        await tester.pumpWidget(
          MaterialApp(
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
