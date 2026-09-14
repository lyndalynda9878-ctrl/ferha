import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ferha/core/l10n/generated/app_localizations.dart';
import 'package:ferha/core/l10n/locale_controller.dart';
import 'package:ferha/core/theme/ferha_colors.dart';
import 'package:ferha/core/theme/ferha_theme.dart';

/// Un bouton doit tenir dans un parent qui ne borne pas sa largeur.
///
/// C'est le piège qui a rendu la fiche salle blanche : le thème posait
/// `minimumSize: Size.fromHeight(48)`, autrement dit une largeur minimale
/// infinie. Dans une Column personne ne le voyait — le parent bornait la
/// largeur. Dans la Row de la barre d'action, le rendu échouait sur
/// « BoxConstraints forces an infinite width », et l'écran ne s'affichait pas.
///
/// C'est la Row qui donne une largeur NON BORNÉE à un enfant non flexible, et
/// c'est elle qui échoue — mesuré : avec l'ancien thème, ces cas-là lèvent, les
/// autres non. Wrap et OverflowBar bornent leurs enfants à leur propre largeur
/// et pardonnent donc la faute ; ils restent ici parce qu'ils sont les deux
/// autres endroits où un bouton se pose hors d'une Column, et qu'on veut le
/// savoir si cela change.
void main() {
  Widget sous(ThemeData theme, Widget parent) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: ferhaSupportedLocales,
    theme: theme,
    home: Scaffold(body: parent),
  );

  final themes = <String, ThemeData>{
    'clair': FerhaTheme.light(),
    'sombre': FerhaTheme.dark(),
  };

  final boutons = <String, Widget>{
    'FilledButton': FilledButton(onPressed: null, child: const Text('Aller')),
    'OutlinedButton': OutlinedButton(
      onPressed: null,
      child: const Text('Aller'),
    ),
    'FilledButton.icon': FilledButton.icon(
      onPressed: null,
      icon: const Icon(Icons.refresh, size: 18),
      label: const Text('Aller'),
    ),
    'OutlinedButton.icon': OutlinedButton.icon(
      onPressed: null,
      icon: const Icon(Icons.refresh, size: 18),
      label: const Text('Aller'),
    ),
  };

  final parents = <String, Widget Function(Widget)>{
    // La barre d'action de la fiche et celle du calendrier.
    'une Row': (b) => Row(children: <Widget>[const Spacer(), b]),
    // Les pistes de l'état vide.
    'une Wrap': (b) => Wrap(children: <Widget>[b]),
    // Les actions d'une boîte de dialogue.
    'un OverflowBar': (b) => OverflowBar(children: <Widget>[b]),
  };

  for (final theme in themes.entries) {
    for (final bouton in boutons.entries) {
      for (final parent in parents.entries) {
        testWidgets(
          'thème ${theme.key} : ${bouton.key} tient dans ${parent.key}',
          (tester) async {
            await tester.pumpWidget(
              sous(theme.value, parent.value(bouton.value)),
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  _eteintNeSePeintPasEnAmbre();
}

/// Un bouton éteint ne doit pas avoir l'air allumé.
///
/// C'est la troisième correction du J11, et l'enquête a innocenté le thème :
/// `FilledButton.styleFrom` n'y pose que `backgroundColor`, jamais
/// `disabledBackgroundColor`, et `ButtonStyleButton.defaultColor` rend alors
/// `null` pour l'état désactivé — la valeur retombe sur celle de Material 3,
/// `onSurface` à 12 %. Autrement dit le thème fait déjà ce qu'il faut.
///
/// Ce test est là pour que cela le reste. Le piège serait d'ajouter un jour un
/// `backgroundColor` par `WidgetStatePropertyAll` — la même couleur pour tous
/// les états, y compris désactivé —, et l'ambre resterait plein sous un bouton
/// qui n'accepte plus rien. Aucun écran ne le verrait ; celui-ci si.
void _eteintNeSePeintPasEnAmbre() {
  for (final theme in <String, ThemeData>{
    'clair': FerhaTheme.light(),
    'sombre': FerhaTheme.dark(),
  }.entries) {
    testWidgets('thème ${theme.key} : un bouton éteint n’a pas l’air actif', (
      tester,
    ) async {
      final colors = theme.value.extension<FerhaColors>()!;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: ferhaSupportedLocales,
          theme: theme.value,
          home: const Scaffold(
            body: Column(
              children: <Widget>[
                FilledButton(onPressed: null, child: Text('Envoyer')),
                FilledButton(onPressed: _rien, child: Text('Envoyer')),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Le Material que pose ButtonStyleButton porte la couleur résolue pour
      // l'état courant : c'est là que se lit ce qu'on voit vraiment.
      Material fond(int index) => tester.widget<Material>(
        find
            .descendant(
              of: find.byType(FilledButton).at(index),
              matching: find.byType(Material),
            )
            .first,
      );

      final eteint = fond(0);
      final allume = fond(1);

      expect(allume.color, colors.primary);
      expect(eteint.color, isNot(colors.primary));
      expect(eteint.textStyle?.color, isNot(colors.onPrimary));
    });
  }
}

void _rien() {}
