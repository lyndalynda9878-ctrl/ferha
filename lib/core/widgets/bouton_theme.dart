import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/ferha_colors.dart';
import '../theme/theme_controller.dart';

/// Le petit bouton rond qui bascule entre le clair et le sombre.
///
/// IL MONTRE OÙ L'ON VA, PAS OÙ L'ON EST — la règle de la bascule de langue,
/// appliquée à un glyphe plutôt qu'à un mot. Une lune sur un écran clair veut
/// dire « appuyez pour passer en sombre » ; un soleil sur un écran sombre dit
/// l'inverse. Un bouton qui afficherait l'état courant ne dirait pas s'il
/// change quoi que ce soit, et c'est exactement ce qu'on lui demande.
///
/// =============================================================================
/// TROIS ÉTATS DERRIÈRE, DEUX POSITIONS DEVANT
///
/// `modeThemeProvider` en porte trois — voir `theme_controller.dart` —, et ce
/// bouton n'en montre que deux. Il n'y a pas de contradiction : le troisième,
/// « suivre le système », n'est pas une destination qu'on choisit, c'est
/// l'endroit d'où l'on part.
///
/// C'est pourquoi la question posée ici n'est pas « quel mode ? » mais « quelle
/// LUMINOSITÉ est à l'écran ? ». `Theme.of(context).brightness` la donne, et la
/// donne pour les trois modes d'un coup : en `system`, c'est déjà Flutter qui a
/// résolu le thème du téléphone. Relire `platformBrightness` nous-mêmes serait
/// refaire ce calcul à côté, avec le droit de se tromper.
class BoutonTheme extends ConsumerWidget {
  /// Crée le bouton de bascule de thème.
  const BoutonTheme({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.ferhaColors;
    final textes = AppLocalizations.of(context);

    final versSombre = Theme.of(context).brightness == Brightness.light;
    final libelle = versSombre ? textes.themeVersSombre : textes.themeVersClair;

    return Padding(
      // EdgeInsetsDirectional, comme partout : en arabe la barre se retourne,
      // et cet écart doit rester du côté de la cloche.
      padding: const EdgeInsetsDirectional.only(start: 4),
      child: IconButton(
        onPressed: () => ref
            .read(modeThemeProvider.notifier)
            .choisir(versSombre ? ThemeMode.dark : ThemeMode.light),
        // L'INFOBULLE ET L'ÉTIQUETTE D'ACCESSIBILITÉ SONT LA MÊME PHRASE, et
        // il en faut bien deux : `Tooltip` pose un `Semantics(tooltip:)`, qui
        // n'est pas un `label`. Un lecteur d'écran annoncerait donc un bouton
        // sans nom. `Icon.semanticLabel` donne le nom, l'infobulle donne
        // l'explication à la souris.
        tooltip: libelle,
        iconSize: 18,
        padding: EdgeInsetsDirectional.zero,
        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          // ROND, ET SANS RAYON ÉCRIT À LA MAIN : `CircleBorder` ne nomme
          // aucune valeur. FerhaRadii donne les arrondis des rectangles — un
          // cercle n'en est pas un, et lui en imposer un serait le déformer.
          shape: const CircleBorder(),
          backgroundColor: colors.surfaceSecondary,
          foregroundColor: colors.inkSecondary,
        ),
        icon: Icon(
          versSombre ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
          semanticLabel: libelle,
        ),
      ),
    );
  }
}
