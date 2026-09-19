import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/message_erreur.dart';
import '../../../core/router/exiger_connexion.dart';
import '../../../core/theme/ferha_colors.dart';
import '../favoris_providers.dart';

/// Le cœur qui met une salle de côté.
///
/// UN SEUL WIDGET POUR LES TROIS ENDROITS — la carte de l'accueil, celle des
/// résultats, et la fiche. La carte étant déjà partagée entre les deux premiers,
/// le poser dessus le fait apparaître aux deux sans rien dupliquer.
///
/// =============================================================================
/// LE GESTE INTERROMPU SE TERMINE
///
/// Un visiteur non connecté qui touche le cœur ne perd pas son geste :
/// `exigerConnexion` ouvre la connexion par-dessus l'écran, et quand elle se
/// referme sur une session valide, la bascule PART TOUTE SEULE. La personne
/// n'a pas à retrouver la salle et à retoucher le cœur — elle a déjà dit ce
/// qu'elle voulait.
///
/// C'est ce que permet `exigerConnexion` en rendant `true` : le geste continue
/// là où il s'était arrêté.
///
/// =============================================================================
/// IL S'ALLUME AU DOIGT, ET SE RÉÉTEINT SI LA BASE REFUSE
///
/// `basculer` écrit l'état à l'écran avant de partir vers la base, et le remet
/// si elle dit non — voir `favoris_providers.dart`. Ce widget fait la moitié
/// visible du travail : il attrape l'erreur relancée et la MONTRE. Un cœur qui
/// se rééteindrait en silence laisserait croire à un doigt mal posé.
///
/// =============================================================================
/// AUCUN COMPTEUR À CÔTÉ
///
/// Pas de « 12 personnes aiment cette salle ». La RLS ne rend que mes lignes,
/// donc ce chiffre n'existe pas — et sur un catalogue de démonstration il
/// serait une preuve sociale fabriquée.
class CoeurFavori extends ConsumerWidget {
  /// Crée le cœur d'une salle.
  const CoeurFavori({required this.venueId, this.surPhoto = false, super.key});

  /// La salle que ce cœur met de côté.
  final String venueId;

  /// Posé par-dessus une photo, et non sur le fond de la carte.
  ///
  /// La fiche salle le pose sur l'image d'en-tête : il lui faut alors un fond
  /// à lui pour rester lisible sur une photo claire comme sur une sombre —
  /// c'est le même problème que le dégradé sous la flèche de retour.
  final bool surPhoto;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.ferhaColors;
    final textes = AppLocalizations.of(context);

    final aime = ref.watch(
      favorisIdsProvider.select((e) => e.value?.contains(venueId) ?? false),
    );

    // DEUX ÉTIQUETTES, PAS UNE. Le bouton annonce ce qu'un appui fera, jamais
    // l'état courant — la règle de la bascule de langue et de celle du thème.
    final libelle = aime ? textes.favoriRetirer : textes.favoriAjouter;

    return IconButton(
      onPressed: () => _basculer(context, ref),
      tooltip: libelle,
      iconSize: 20,
      visualDensity: VisualDensity.compact,
      style: surPhoto
          ? IconButton.styleFrom(
              shape: const CircleBorder(),
              backgroundColor: colors.surface,
            )
          : null,
      icon: Icon(
        aime ? Icons.favorite : Icons.favorite_outline,
        // LE CŒUR PLEIN PREND LA COULEUR D'ACCENT, le vide reste discret : il
        // ne doit pas réclamer l'attention que mérite le prix juste à côté.
        color: aime ? colors.primaryDeep : colors.inkSecondary,
        // `Tooltip` pose un `Semantics(tooltip:)`, qui n'est pas un `label` :
        // sans celui-ci, un lecteur d'écran annoncerait un bouton sans nom.
        semanticLabel: libelle,
      ),
    );
  }

  Future<void> _basculer(BuildContext context, WidgetRef ref) async {
    // LA CONNEXION SE DEMANDE AU MOMENT D'AGIR, comme pour toutes les autres
    // actions : chercher une salle et ouvrir une fiche restent ouverts à tous.
    if (!await exigerConnexion(context, ref)) return;
    if (!context.mounted) return;

    // On lit le messager AVANT l'attente : après, `context` peut avoir été
    // démonté par la carte qui se reconstruit.
    final messager = ScaffoldMessenger.of(context);
    final textes = AppLocalizations.of(context);

    try {
      await ref.read(favorisIdsProvider.notifier).basculer(venueId);
    } on Object catch (erreur) {
      // Le cœur s'est déjà rééteint — le fournisseur l'a remis avant de
      // relancer. Il reste à dire pourquoi.
      messager
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              '${textes.favoriNonEnregistre} ${messageErreur(textes, erreur)}',
            ),
          ),
        );
    }
  }
}
