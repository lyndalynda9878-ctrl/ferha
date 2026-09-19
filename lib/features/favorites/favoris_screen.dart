import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../core/router/routes.dart';
import '../auth/auth_providers.dart';
import '../notifications/widgets/cloche_notifications.dart';
import '../search/widgets/etats.dart';
import '../search/widgets/venue_card.dart';
import 'favoris_providers.dart';

/// L'onglet Favoris — les salles mises de côté.
///
/// LA MÊME CARTE QUE PARTOUT AILLEURS. `VenueCard` dessine déjà la salle sur
/// l'accueil et dans les résultats, et `mes_favoris()` rend exactement la ligne
/// qu'elle attend : il n'y a aucune carte à redessiner ici. Une seconde carte
/// serait une seconde vérité sur la façon d'écrire un prix.
///
/// =============================================================================
/// NON CONNECTÉ : IL EXPLIQUE, IL NE REDIRIGE PAS
///
/// Le routeur n'a AUCUNE redirection globale vers la connexion — c'est la règle
/// de navigation du projet, écrite dans `app_router.dart` — et cet onglet n'en
/// gagne pas une. Un visiteur qui touche « Favoris » sans compte n'est pas
/// éjecté vers un formulaire : il lit pourquoi un compte est nécessaire ICI,
/// alors que chercher et consulter ne le demandent pas, et décide.
///
/// =============================================================================
/// L'ÉTAT VIDE NE DIT PAS « AUCUN FAVORI »
///
/// La règle du projet est qu'un état vide NOMME LE GESTE QUI MANQUE et donne un
/// bouton pour en sortir. « Aucun favori » laisse devant un mur : on ne sait
/// pas si l'application est cassée, si on a mal cherché, ou s'il fallait faire
/// quelque chose. « Touchez le cœur sur une salle pour la retrouver ici », avec
/// un bouton qui ramène à la recherche, dit les deux.
class FavorisScreen extends ConsumerWidget {
  /// Crée l'onglet Favoris.
  const FavorisScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textes = AppLocalizations.of(context);
    final connecte = ref.watch(estConnecteProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(textes.favorisTitre),
        actions: const <Widget>[ClocheNotifications(), SizedBox(width: 4)],
      ),
      body: connecte ? const _Liste() : const _NonConnecte(),
    );
  }
}

/// Ce que voit un visiteur sans compte.
class _NonConnecte extends StatelessWidget {
  const _NonConnecte();

  @override
  Widget build(BuildContext context) {
    final textes = AppLocalizations.of(context);

    return EtatVide(
      icone: Icons.favorite_outline,
      titre: textes.favorisNonConnecteTitre,
      explication: textes.favorisNonConnecteTexte,
      pistes: <Widget>[
        FilledButton(
          // `push` et non `go` : l'écran de connexion s'ouvre PAR-DESSUS
          // l'onglet et se referme dessus. Le visiteur revient à ses favoris,
          // désormais remplis, sans avoir à retrouver l'onglet.
          onPressed: () => context.push(FerhaRoutes.connexion),
          child: Text(textes.authSeConnecter),
        ),
      ],
    );
  }
}

/// Les trois états du projet : squelettes, erreur, vide — puis la liste.
class _Liste extends ConsumerWidget {
  const _Liste();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textes = AppLocalizations.of(context);
    final favoris = ref.watch(mesFavorisProvider);

    return switch (favoris) {
      AsyncError(:final error) => EtatErreur(
        titre: textes.favorisErreurTitre,
        erreur: error,
        onReessayer: () => ref.invalidate(mesFavorisProvider),
      ),

      // DES SQUELETTES, ET NON UNE ROUE CENTRÉE : l'écran ne saute pas quand
      // les cartes se posent, et on voit déjà où regarder. Trois, parce que
      // c'est ce que tient une hauteur de téléphone.
      AsyncLoading() => ListView.separated(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 32),
        itemCount: 3,
        separatorBuilder: (_, _) => const SizedBox(height: 16),
        itemBuilder: (_, _) => const CarteSquelette(),
      ),

      AsyncData(value: final salles) when salles.isEmpty => EtatVide(
        icone: Icons.favorite_outline,
        titre: textes.favorisVideTitre,
        explication: textes.favorisVideTexte,
        pistes: <Widget>[
          FilledButton.icon(
            // `go` et non `push` : on change d'ONGLET, on n'empile pas un
            // écran par-dessus celui-ci. Un `push` laisserait une flèche de
            // retour vers un onglet Favoris vide.
            onPressed: () => context.go(FerhaRoutes.accueil),
            icon: const Icon(Icons.search, size: 18),
            label: Text(textes.favorisVideBouton),
          ),
        ],
      ),

      AsyncData(value: final salles) => RefreshIndicator(
        onRefresh: () async => ref.invalidate(mesFavorisProvider),
        child: ListView.separated(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 32),
          itemCount: salles.length,
          separatorBuilder: (_, _) => const SizedBox(height: 16),
          itemBuilder: (_, i) => VenueCard(
            salle: salles[i],
            onTap: () => context.push(FerhaRoutes.salleDe(salles[i].id)),
          ),
        ),
      ),
    };
  }
}
