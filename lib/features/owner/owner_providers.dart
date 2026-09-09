import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/preferences/preferences_affichage.dart';
import '../auth/auth_providers.dart';
import 'demande_en_attente.dart';
import 'indicateurs_salle.dart';
import 'owner_repository.dart';
import 'salle_du_proprietaire.dart';

/// Les salles d'un propriétaire, et celle qu'il regarde.
///
/// LES DEUX VONT ENSEMBLE, ET C'EST POURQUOI C'EST UN SEUL ÉTAT. Une salle
/// courante rangée à part pourrait désigner une salle absente de la liste — au
/// mieux un écran vide, au pire un appel à `owner_dashboard()` sur la salle
/// d'un autre. Ici, [salleCourante] se lit DANS [salles] : les deux ne peuvent
/// pas diverger.
@immutable
class EspaceProprietaire {
  /// Crée l'état de l'espace propriétaire.
  const EspaceProprietaire({required this.salles, this.salleCouranteId});

  /// Toutes les salles du propriétaire, brouillons compris, par nom.
  final List<SalleDuProprietaire> salles;

  /// L'identifiant de la salle affichée, ou `null` s'il n'en a aucune.
  final String? salleCouranteId;

  /// La salle affichée.
  ///
  /// `null` seulement quand la liste est vide : [EspaceProprietaireNotifier]
  /// ne retient jamais un identifiant absent de [salles].
  SalleDuProprietaire? get salleCourante {
    for (final salle in salles) {
      if (salle.id == salleCouranteId) return salle;
    }
    return null;
  }

  /// Vrai quand il y a plusieurs salles, donc un choix à offrir (OWN-08).
  bool get plusieursSalles => salles.length > 1;
}

/// Charge les salles du propriétaire et retrouve celle qu'il regardait.
///
/// POURQUOI RETENIR LA SALLE. Karim en a quatre, et il ouvre son tableau de
/// bord plusieurs fois par jour pour la même. La lui redemander à chaque fois
/// serait lui faire payer un choix qu'il a déjà fait — et lui faire croire, la
/// première seconde, que ses chiffres sont ceux d'une autre salle.
///
/// LA PRÉFÉRENCE N'EST PAS UNE AUTORISATION. L'identifiant retenu vient d'un
/// fichier en clair sur l'appareil, que n'importe qui peut réécrire ; il n'est
/// donc jamais cru sur parole. On ne garde une salle retenue que si elle est
/// dans la liste que la BASE vient de rendre — et cette liste-là ne contient
/// que les salles du propriétaire connecté, `owner_venues()` ne connaissant
/// qu'`auth.uid()`. Une préférence rescapée d'un autre compte, ou pointant une
/// salle vendue depuis, ne fait donc rien d'autre que se faire oublier.
class EspaceProprietaireNotifier extends AsyncNotifier<EspaceProprietaire> {
  @override
  Future<EspaceProprietaire> build() async {
    // Se déconnecter vide l'espace, se connecter le recharge : aucun écran n'a
    // à s'en occuper.
    //
    // On observe le BOOLÉEN et non la session elle-même. La session change
    // aussi à chaque renouvellement de jeton — toutes les heures, sans que rien
    // n'ait bougé pour le propriétaire ; la suivre ferait redemander la liste
    // des salles à chacun. Ce qui compte ici est le passage de « personne » à
    // « quelqu'un », et c'est exactement ce que ce booléen dit.
    if (!ref.watch(estConnecteProvider)) {
      return const EspaceProprietaire(salles: <SalleDuProprietaire>[]);
    }

    final salles = await ref.read(ownerRepositoryProvider).salles();
    if (salles.isEmpty) {
      return const EspaceProprietaire(salles: <SalleDuProprietaire>[]);
    }

    final preferences = ref.read(preferencesAffichageProvider);
    final retenue = await preferences.salleChoisie();
    final existe = salles.any((s) => s.id == retenue);
    final courante = existe ? retenue! : salles.first.id;

    // La préférence ne survit pas à la salle qu'elle désigne. La réécrire ici
    // évite qu'un identifiant mort reste sur l'appareil à être réexaminé à
    // chaque ouverture ; on n'écrit que si elle a bougé, parce qu'une écriture
    // par démarrage pour reposer la même valeur ne sert personne.
    if (retenue != courante) await preferences.retenirSalle(courante);

    return EspaceProprietaire(salles: salles, salleCouranteId: courante);
  }

  /// Change de salle, et le retient pour la prochaine ouverture.
  ///
  /// L'écran change AVANT que l'appareil ait fini d'écrire : le sélecteur doit
  /// se refermer sur les chiffres de la nouvelle salle, pas attendre un accès
  /// disque. Une écriture ratée ne coûte alors qu'un choix oublié au prochain
  /// démarrage — jamais un tableau de bord qui refuse de tourner.
  Future<void> choisir(String venueId) async {
    final actuel = state.value;
    if (actuel == null || actuel.salleCouranteId == venueId) return;
    if (!actuel.salles.any((s) => s.id == venueId)) return;

    state = AsyncData<EspaceProprietaire>(
      EspaceProprietaire(salles: actuel.salles, salleCouranteId: venueId),
    );
    await ref.read(preferencesAffichageProvider).retenirSalle(venueId);
  }

  /// Relit la liste des salles, squelette compris — le bouton « Réessayer ».
  Future<void> reessayer() async {
    state = const AsyncLoading<EspaceProprietaire>();
    state = await AsyncValue.guard(build);
  }
}

/// Les salles du propriétaire connecté, et celle qu'il regarde.
final espaceProprietaireProvider =
    AsyncNotifierProvider<EspaceProprietaireNotifier, EspaceProprietaire>(
      EspaceProprietaireNotifier.new,
    );

/// Les indicateurs du mois en cours pour une salle (§4.3, OWN-07).
///
/// Une famille indexée sur la salle, et non un fournisseur unique : changer de
/// salle dans le sélecteur redemande alors les chiffres tout seul, et revenir
/// à la précédente les retrouve. `autoDispose` referme ce qui n'est plus
/// regardé — Karim a quatre salles, il n'en voit qu'une à la fois.
final indicateursProvider = FutureProvider.autoDispose
    .family<IndicateursSalle, String>(
      (ref, venueId) => ref.watch(ownerRepositoryProvider).indicateurs(venueId),
    );

/// Les demandes en attente d'une salle (§4.3, OWN-05).
///
/// PAS D'ABONNEMENT TEMPS RÉEL ICI, à la différence du suivi côté client. Là-bas
/// l'écran répond à « où en est ma demande » et attend un événement qu'il ne
/// provoque pas ; ici, c'est le propriétaire lui-même qui fait bouger la liste
/// en répondant — et les gestes qui la feront bouger n'existent pas encore.
/// L'écran se retire vers le bas pour se rafraîchir, ce qui suffit tant que
/// personne d'autre n'écrit à sa place.
final demandesEnAttenteProvider = FutureProvider.autoDispose
    .family<List<DemandeEnAttente>, String>(
      (ref, venueId) =>
          ref.watch(ownerRepositoryProvider).demandesEnAttente(venueId),
    );
