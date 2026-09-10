import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import 'owner_providers.dart';

/// Le bouton qui remplace « Réserver » quand la salle regardée est la sienne.
///
/// ON NE BLOQUE PAS UNE PORTE, ON N'EN MET PAS. Un propriétaire arrivait
/// jusqu'au bout du formulaire de sa propre salle pour s'entendre dire, au pied
/// de la page, que `request_booking()` refusait (FE005). Le refus était juste ;
/// le chemin qui y menait ne l'était pas. Là où il y avait un geste perdu
/// d'avance, il y a maintenant celui qui a du sens : rejoindre son tableau de
/// bord SUR CETTE SALLE-LÀ.
///
/// La même icône et le même mot que l'entrée du profil — `Icons.storefront`,
/// « ma salle » —, pour que ce soit reconnu comme le même endroit.
class BoutonGererMaSalle extends ConsumerWidget {
  /// Crée le bouton.
  const BoutonGererMaSalle({required this.venueId, this.style, super.key});

  /// La salle à ouvrir dans le tableau de bord.
  final String venueId;

  /// De quoi ajuster la taille selon l'endroit — une barre d'action est plus
  /// serrée qu'un état vide. Les couleurs, elles, restent celles du thème.
  final ButtonStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FilledButton.icon(
      onPressed: () => ouvrirMaSalle(context, ref, venueId),
      icon: const Icon(Icons.storefront_outlined, size: 18),
      label: const Text('Gérer ma salle'),
      style: style,
    );
  }
}

/// Ouvre le tableau de bord sur [venueId].
///
/// LA SALLE COURANTE SE POSE AVANT LA NAVIGATION, ET SANS L'ATTENDRE.
/// `choisir()` change l'état AVANT son premier `await` — l'écriture de la
/// préférence sur l'appareil vient après —, si bien que le tableau de bord se
/// construit déjà sur la bonne salle. L'attendre ferait patienter le
/// propriétaire derrière un accès disque pour rien ; une écriture ratée ne
/// coûte, elle, qu'un choix oublié à la prochaine ouverture.
///
/// `choisir()` ignore d'elle-même une salle absente de la liste : ce lien ne
/// s'affiche que sur les salles du propriétaire, mais il n'a pas à s'en
/// remettre à son appelant.
///
/// `push` et non `go`, comme depuis le profil : le retour ramène sur la fiche.
void ouvrirMaSalle(BuildContext context, WidgetRef ref, String venueId) {
  unawaited(ref.read(espaceProprietaireProvider.notifier).choisir(venueId));
  context.push(FerhaRoutes.proprietaireTableau);
}
