import 'package:flutter/material.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/message_erreur.dart';
import '../../../core/theme/ferha_colors.dart';
import '../../../core/theme/ferha_radii.dart';

/// Squelette d'une carte de salle, pendant le chargement.
///
/// Des blocs à la forme de ce qui arrive, plutôt qu'une roue centrée : l'écran
/// ne saute pas quand les données se posent, et l'attente paraît plus courte
/// parce qu'on voit déjà où regarder.
class CarteSquelette extends StatelessWidget {
  /// Crée un squelette de carte.
  const CarteSquelette({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(height: 140, color: colors.surfaceSecondary),
          Padding(
            padding: const EdgeInsetsDirectional.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: <Widget>[
                _Barre(
                  largeur: 170,
                  hauteur: 14,
                  couleur: colors.surfaceSecondary,
                ),
                _Barre(largeur: 120, hauteur: 10, couleur: colors.ruleSoft),
                Row(
                  children: <Widget>[
                    _Barre(
                      largeur: 84,
                      hauteur: 12,
                      couleur: colors.surfaceSecondary,
                    ),
                    const Spacer(),
                    _Barre(
                      largeur: 48,
                      hauteur: 12,
                      couleur: colors.surfaceSecondary,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Barre extends StatelessWidget {
  const _Barre({
    required this.largeur,
    required this.hauteur,
    required this.couleur,
  });

  final double largeur;
  final double hauteur;
  final Color couleur;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: largeur,
      height: hauteur,
      decoration: BoxDecoration(
        color: couleur,
        // Le rayon des puces plutôt qu'un calcul maison : sur une barre de
        // moins de 40 px de haut, il est de toute façon rogné à la moitié de
        // la hauteur, donc la capsule est la même — et aucun rayon n'est
        // écrit à la main dans un écran.
        borderRadius: FerhaRadii.chipBorder,
      ),
    );
  }
}

/// Ce qu'on affiche quand il n'y a rien à montrer.
///
/// Un « Aucun résultat » sec laisse le client devant un mur : il ne sait pas si
/// l'application est cassée, si sa date est mauvaise ou s'il a mis un budget
/// trop bas. [pistes] dit quoi essayer, et chaque piste est une action.
class EtatVide extends StatelessWidget {
  /// Crée l'état vide.
  const EtatVide({
    required this.titre,
    required this.explication,
    this.icone = Icons.search_off,
    this.pistes = const <Widget>[],
    super.key,
  });

  /// L'icône du vide.
  ///
  /// Une loupe barrée par défaut, parce que c'est la recherche qui a inauguré
  /// ce widget. Elle se change : « vous n'avez pas encore de demande » n'est
  /// pas une recherche infructueuse, et une loupe y ferait croire à une erreur
  /// de critères.
  final IconData icone;

  /// Ce qui s'est passé, en une ligne.
  final String titre;

  /// Pourquoi, et ce que cela veut dire.
  final String explication;

  /// Les gestes qui débloquent — boutons, pas conseils en l'air.
  final List<Widget> pistes;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icone, size: 44, color: colors.inkTertiary),
              const SizedBox(height: 16),
              Text(titre, textAlign: TextAlign.center, style: text.titleLarge),
              const SizedBox(height: 8),
              Text(
                explication,
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(color: colors.inkSecondary),
              ),
              if (pistes.isNotEmpty) ...<Widget>[
                const SizedBox(height: 24),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: pistes,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Ce qu'on affiche quand la requête a échoué.
///
/// Le message d'origine est montré, traduit quand il est connu. « Une erreur
/// est survenue » ne dit ni qu'il n'y a pas de réseau, ni que la fonction SQL
/// manque, ni que la clé est fausse — trois gestes différents.
class EtatErreur extends StatelessWidget {
  /// Crée l'état d'erreur.
  const EtatErreur({
    required this.erreur,
    required this.onReessayer,
    this.titre,
    super.key,
  });

  /// Ce qui n'a pas abouti.
  ///
  /// `null` prend « La recherche n'a pas abouti », parce que c'est la recherche
  /// qui a inauguré ce widget. Ailleurs, le dire juste évite d'annoncer une
  /// recherche à quelqu'un qui consultait ses réservations.
  ///
  /// LE DÉFAUT N'EST PLUS UNE CONSTANTE : il dépend de la langue, donc du
  /// contexte, et un paramètre par défaut se calcule à la compilation.
  final String? titre;

  /// L'erreur remontée, telle quelle.
  final Object erreur;

  /// Relance la requête.
  final VoidCallback onReessayer;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;
    final rouge = Theme.of(context).colorScheme.error;
    final textes = AppLocalizations.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.cloud_off_outlined, size: 44, color: rouge),
              const SizedBox(height: 16),
              Text(
                titre ?? textes.erreurRechercheTitre,
                textAlign: TextAlign.center,
                style: text.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                messageErreur(textes, erreur),
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(color: colors.inkSecondary),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onReessayer,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(textes.reessayer),
                ),
              ),
              const SizedBox(height: 16),
              // Le détail technique reste accessible sans encombrer : replié
              // par défaut, entier quand on le déplie.
              Theme(
                data: Theme.of(
                  context,
                ).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  title: Text(
                    textes.detailTechnique,
                    style: text.bodySmall?.copyWith(color: colors.inkTertiary),
                  ),
                  children: <Widget>[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsetsDirectional.all(12),
                      decoration: BoxDecoration(
                        color: colors.surfaceSecondary,
                        borderRadius: FerhaRadii.cardBorder,
                        border: Border.all(color: colors.ruleSoft),
                      ),
                      child: SelectableText(
                        '$erreur',
                        style: text.bodySmall?.copyWith(
                          color: colors.inkSecondary,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
