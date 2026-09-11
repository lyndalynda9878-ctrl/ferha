import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_providers.dart';
import '../auth/auth_providers.dart';
import 'notification_ferha.dart';
import 'notifications_repository.dart';

/// Les notifications de l'utilisateur connecté, tenues à jour par le temps réel.
///
/// IL N'EST PAS `autoDispose`, ET C'EST DÉLIBÉRÉ. La cloche vit sur l'accueil
/// et sur le tableau de bord ; l'écran des notifications, lui, s'ouvre et se
/// referme. Un fournisseur qui se refermerait avec l'écran défairait l'unique
/// abonnement Realtime chaque fois qu'on revient en arrière — et la cloche
/// repartirait de zéro. Un seul canal, ouvert tant que la session dure.
///
/// UN SEUL ABONNEMENT POUR TOUTE LA SESSION. C'est pourquoi ce n'est pas un
/// `FutureProvider` : un fournisseur qui s'invaliderait lui-même à chaque
/// événement referait aussi son abonnement, et le canal serait défait puis
/// refait à chaque notification reçue. Ici `build()` s'abonne, et [recharger]
/// ne touche qu'aux données.
///
/// ON RECHARGE, ON NE RAPIÈCE PAS. L'événement Realtime porte la ligne brute de
/// `notifications`, payload compris — on POURRAIT la coudre dans la liste. On
/// ne le fait pas : le compteur de non lues, lui, ne se déduit pas d'une ligne,
/// et il faudrait le recalculer à la main. Deux façons d'obtenir le même nombre
/// finissent toujours par en donner deux différents. On apprend donc seulement
/// que quelque chose a bougé, et on redemande la liste à `mes_notifications()`.
class Notifications extends AsyncNotifier<ListeNotifications> {
  @override
  Future<ListeNotifications> build() async {
    // Se déconnecter vide la cloche, se connecter la remplit : aucun écran n'a
    // à s'en occuper. On observe la session entière et non le seul booléen —
    // il faut l'identifiant pour filtrer l'abonnement.
    final session = ref.watch(sessionProvider);
    if (session == null) return ListeNotifications.vide;

    _ecoute(session.user.id);
    // On charge AUSSI à l'ouverture, et pas seulement sur événement. Le service
    // Realtime de Supabase démarre à froid quand le projet a dormi, et une
    // notification déposée pendant ces deux secondes-là ne serait annoncée à
    // personne. La cloche affiche donc toujours un nombre lu, pas deviné.
    return ref.read(notificationsRepositoryProvider).liste();
  }

  /// S'abonne aux notifications de CE compte.
  ///
  /// Le filtre `user_id=eq.<uid>` ne remplace pas la politique
  /// `notifications_select_own` (006) — c'est elle qui décide, et Realtime
  /// l'évalue pour chaque abonné. Il lui évite seulement d'examiner des lignes
  /// qui ne partiraient de toute façon pas.
  void _ecoute(String userId) {
    final client = ref.read(supabaseClientProvider);

    final canal = client
        .channel('notifications-$userId')
        .onPostgresChanges(
          // Les trois : une notification naît, se marque lue depuis un autre
          // appareil, et — un jour — se purge. On ne devine pas laquelle nous
          // intéresse, on recharge.
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) => recharger(),
        )
        .subscribe();

    // Fermer la session ferme le canal : un abonnement oublié continue de
    // recevoir, et de consommer, pour personne.
    ref.onDispose(() => client.removeChannel(canal));
  }

  /// Redemande la liste sans repasser par un état de chargement.
  ///
  /// La cloche ne doit pas disparaître le temps d'un aller-retour réseau parce
  /// qu'une notification vient d'arriver : le nombre affiché reste le dernier
  /// connu jusqu'à ce que le suivant soit là.
  Future<void> recharger() async {
    try {
      final liste = await ref.read(notificationsRepositoryProvider).liste();
      // Le fournisseur a pu être jeté pendant la requête — une déconnexion le
      // reconstruit. Écrire dans un état abandonné lèverait.
      if (!ref.mounted) return;
      state = AsyncData<ListeNotifications>(liste);
    } on Object catch (erreur, pile) {
      if (!ref.mounted) return;
      state = AsyncError<ListeNotifications>(erreur, pile);
    }
  }

  /// Relance depuis zéro, squelette compris — le geste du bouton « Réessayer ».
  Future<void> reessayer() async {
    state = const AsyncLoading<ListeNotifications>();
    await recharger();
  }

  /// Marque une notification lue, et le montre tout de suite.
  ///
  /// L'ÉTAT LOCAL CHANGE AVANT LA RÉPONSE DU SERVEUR. Toucher une notification
  /// ouvre un écran dans la foulée : attendre l'aller-retour pour éteindre la
  /// pastille la laisserait allumée pendant la transition, puis s'éteindre
  /// toute seule au retour — on croirait avoir mal appuyé. L'événement Realtime
  /// repassera derrière avec la vérité de la base.
  ///
  /// UN ÉCHEC NE SE DIT PAS. Le geste n'est pas celui qu'on est venu faire :
  /// on est venu ouvrir sa réservation. Une notification qui reste non lue se
  /// rattrape au prochain appui ou au « Tout marquer comme lu » ; une alerte
  /// rouge par-dessus l'écran qui s'ouvre, non.
  Future<void> marquerLue(String id) async {
    _marquerLocalement(<String>{id});
    try {
      await ref.read(notificationsRepositoryProvider).marquerLue(id);
    } on Object catch (_) {
      // Volontairement muet, voir ci-dessus.
    }
  }

  /// Marque lues toutes les notifications — le bouton de l'écran.
  ///
  /// Celui-là, on est venu le faire : un échec doit donc remonter, et l'écran
  /// le dit. On recharge ensuite plutôt que de croire l'état local, parce que
  /// « toutes » peut dépasser les cinquante lignes affichées.
  Future<void> toutMarquerLu() async {
    final actuel = state.value;
    if (actuel == null || actuel.nonLues == 0) return;

    _marquerLocalement(actuel.items.map((n) => n.id).toSet());
    await ref.read(notificationsRepositoryProvider).toutMarquerLu();
    await recharger();
  }

  /// Repose l'état avec ces notifications marquées lues, compteur ajusté.
  void _marquerLocalement(Set<String> ids) {
    final actuel = state.value;
    if (actuel == null) return;

    final maintenant = DateTime.now();
    final items = <NotificationFerha>[];
    var eteintes = 0;

    for (final n in actuel.items) {
      if (!n.lue && ids.contains(n.id)) {
        items.add(n.marqueeLue(maintenant));
        eteintes++;
      } else {
        items.add(n);
      }
    }

    if (eteintes == 0) return;

    state = AsyncData<ListeNotifications>(
      ListeNotifications(
        items: items,
        // Jamais en dessous de zéro : le compteur porte sur toute la table, la
        // liste sur cinquante lignes, et une soustraction naïve pourrait passer
        // sous la barre si les deux divergeaient.
        nonLues: (actuel.nonLues - eteintes).clamp(0, actuel.nonLues),
      ),
    );
  }
}

/// Les notifications de l'utilisateur connecté, et leur compteur.
final notificationsProvider =
    AsyncNotifierProvider<Notifications, ListeNotifications>(Notifications.new);

/// Le nombre de notifications non lues — ce que porte la pastille de la cloche.
///
/// UN FOURNISSEUR À PART, ET NON `ref.watch(notificationsProvider).value`. La
/// cloche est dans une barre d'application : elle se reconstruirait à chaque
/// rechargement de la liste, alors que seul ce nombre l'intéresse. Ici, elle ne
/// se redessine que quand il change vraiment.
///
/// Zéro pendant le chargement et sur erreur : une pastille vaut mieux absente
/// que fausse, et un point d'exclamation sur une cloche n'appellerait aucun
/// geste utile.
final notificationsNonLuesProvider = Provider<int>(
  (ref) => ref.watch(notificationsProvider).value?.nonLues ?? 0,
);
