import 'package:flutter/material.dart';

import '../../../core/theme/ferha_colors.dart';
import '../../../core/theme/ferha_radii.dart';

/// Une note en étoiles, en lecture seule.
///
/// UNE DEMI-ÉTOILE EXISTE, et elle compte : la note affichée est une moyenne
/// bayésienne (§5.4), donc presque jamais un entier. Arrondir 4,6 à 5 étoiles
/// pleines flatterait la salle d'un dixième à chaque affichage.
///
/// [taille] EST UN PARAMÈTRE parce que le même dessin sert à trois échelles —
/// 18 px sur la fiche salle, 13 px sur une carte d'avis, 26 px en tête de
/// l'écran 7 — et qu'un second widget par échelle finirait par diverger.
class RangeeEtoiles extends StatelessWidget {
  /// Crée une rangée d'étoiles.
  const RangeeEtoiles({required this.note, this.taille = 18, super.key});

  /// La note, de 0 à 5.
  final double note;

  /// La hauteur d'une étoile, en pixels logiques.
  final double taille;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var i = 1; i <= 5; i++)
          Icon(
            note >= i
                ? Icons.star_rounded
                : (note >= i - 0.5
                      ? Icons.star_half_rounded
                      : Icons.star_outline_rounded),
            size: taille,
            color: colors.gold,
          ),
      ],
    );
  }
}

/// Cinq étoiles sur lesquelles on appuie — le geste de l'écran de dépôt.
///
/// RAPPUYER SUR LA MÊME ÉTOILE EFFACE, quand [effacable] le permet. Les quatre
/// sous-notes du §4.2 sont facultatives : quelqu'un qui en allume une par erreur
/// doit pouvoir revenir à « je ne me prononce pas », et il n'y a pas de place
/// pour une croix à côté de chacune. La note globale, elle, est obligatoire :
/// l'éteindre ne mènerait qu'à un bouton « Publier » qui s'éteint aussi.
///
/// CHAQUE ÉTOILE PORTE UNE CLÉ ET UN LIBELLÉ D'ACCESSIBILITÉ. Sans eux, cinq
/// icônes identiques ne se distinguent ni pour un lecteur d'écran, ni pour un
/// test — et « appuyer sur la quatrième étoile » est précisément ce que les deux
/// ont besoin de faire.
class ChoixEtoiles extends StatelessWidget {
  /// Crée un sélecteur d'étoiles.
  const ChoixEtoiles({
    required this.cle,
    required this.libelleSemantique,
    required this.note,
    required this.onChoisir,
    this.effacable = false,
    this.taille = 32,
    super.key,
  });

  /// Le préfixe des clés de chaque étoile — « globale », « proprete »…
  final String cle;

  /// Ce que dit un lecteur d'écran : « Propreté, 4 étoiles sur 5 ».
  final String libelleSemantique;

  /// La note choisie, ou `null` quand rien n'est allumé.
  final int? note;

  /// Appelée avec la nouvelle note, ou `null` quand on efface.
  final ValueChanged<int?> onChoisir;

  /// Vrai quand rappuyer sur l'étoile allumée éteint tout.
  final bool effacable;

  /// La hauteur d'une étoile.
  final double taille;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;

    return Semantics(
      label: note == null
          ? '$libelleSemantique, aucune note'
          : '$libelleSemantique, $note étoile${note! > 1 ? 's' : ''} sur 5',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var i = 1; i <= 5; i++)
            IconButton(
              key: Key('etoile-$cle-$i'),
              onPressed: () => onChoisir(effacable && note == i ? null : i),
              // La zone tactile reste à la taille recommandée même quand
              // l'étoile est petite : on vise mal une icône de 32 px avec un
              // pouce, et se tromper d'étoile ici change une note publiée.
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              tooltip: '$i sur 5',
              icon: Icon(
                (note ?? 0) >= i
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                size: taille,
                color: (note ?? 0) >= i ? colors.gold : colors.inkTertiary,
              ),
            ),
        ],
      ),
    );
  }
}

/// Une sous-note moyenne, en barre — « Propreté ▓▓▓▓▓░ 4,8 ».
///
/// C'est la `.rbar` de la maquette de l'écran 7 : le libellé, la barre, la
/// valeur. La largeur du remplissage est la note sur cinq, et rien d'autre — la
/// moyenne vient de `venue_ratings` et ne se recalcule pas ici.
class BarreSousNote extends StatelessWidget {
  /// Crée une barre de sous-note.
  const BarreSousNote({required this.libelle, required this.note, super.key});

  /// « Propreté », « Rapport q/p »…
  final String libelle;

  /// La moyenne, de 0 à 5.
  final double note;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    return Semantics(
      label: '$libelle, ${note.toStringAsFixed(1)} sur 5',
      excludeSemantics: true,
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 88,
            child: Text(
              libelle,
              style: text.bodySmall?.copyWith(color: colors.inkSecondary),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: FerhaRadii.chipBorder,
              child: LinearProgressIndicator(
                value: (note / 5).clamp(0, 1),
                minHeight: 5,
                backgroundColor: colors.surfaceSecondary,
                valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 26,
            child: Text(
              note.toStringAsFixed(1).replaceAll('.', ','),
              textAlign: TextAlign.end,
              style: text.bodySmall?.copyWith(
                color: colors.inkTertiary,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
