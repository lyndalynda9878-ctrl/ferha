import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_providers.dart';
import 'notification_ferha.dart';

/// Ce que la cloche et l'écran lisent en un seul appel.
///
/// LE COMPTEUR N'EST PAS `liste.where((n) => !n.lue).length`, ET C'EST LE
/// POINT. La liste s'arrête aux cinquante plus récentes ; le badge, lui, compte
/// TOUTES les non lues. Les déduire l'un de l'autre donnerait un badge qui
/// rétrécit quand on remonte dans l'historique — et un propriétaire qui croit
/// avoir tout traité alors qu'il reste des demandes plus bas.
///
/// `mes_notifications()` (022) les rend ensemble, et c'est la base qui compte.
@immutable
class ListeNotifications {
  /// Crée la liste et son compteur.
  const ListeNotifications({required this.items, required this.nonLues});

  /// Une liste vide, sans rien à compter — l'état d'un visiteur non connecté.
  static const ListeNotifications vide = ListeNotifications(
    items: <NotificationFerha>[],
    nonLues: 0,
  );

  /// Les notifications, les plus récentes en tête.
  final List<NotificationFerha> items;

  /// Le nombre total de non lues, historique compris.
  final int nonLues;
}

/// La lecture des notifications, et les deux gestes qui les marquent lues.
///
/// UNE INTERFACE PLUTÔT QUE DES APPELS DIRECTS, pour la même raison que
/// `OwnerRepository` : les tests la remplacent en bloc, et un écran monté sur
/// un faux dépôt n'a besoin ni de réseau, ni de session, ni de base.
///
/// AUCUN GARDE-FOU ICI. Les trois appels visent des fonctions bornées par la
/// politique `notifications_select_own` (006) : un client modifié qui
/// demanderait les notifications d'un autre n'obtiendrait rien de plus.
abstract interface class NotificationsRepository {
  /// Les notifications de l'utilisateur connecté, et le nombre de non lues.
  Future<ListeNotifications> liste();

  /// Marque lue une notification. Sans effet si elle l'était déjà.
  Future<void> marquerLue(String id);

  /// Marque lues toutes les notifications, et rend combien ont changé d'état.
  Future<int> toutMarquerLu();
}

/// L'implémentation qui parle à Supabase.
class NotificationsRepositorySupabase implements NotificationsRepository {
  /// Crée le dépôt autour d'un client Supabase.
  const NotificationsRepositorySupabase(this._client);

  final SupabaseClient _client;

  /// Au-delà, c'est de l'archive : on ne fait pas défiler six mois de
  /// notifications sur un téléphone, et la base plafonne de son côté à 200.
  static const int _limite = 50;

  @override
  Future<ListeNotifications> liste() async {
    final lignes = await _client.rpc<List<dynamic>>(
      'mes_notifications',
      params: <String, dynamic>{'p_limite': _limite},
    );

    final items = lignes
        .cast<Map<String, dynamic>>()
        .map(NotificationFerha.depuisJson)
        .toList(growable: false);

    return ListeNotifications(
      items: items,
      // Aucune ligne, aucun compteur — et c'est juste : une liste vide n'a rien
      // à compter. La colonne est la même sur toutes les lignes.
      nonLues: lignes.isEmpty
          ? 0
          : ((lignes.first as Map<String, dynamic>)['non_lues'] as num).toInt(),
    );
  }

  @override
  Future<void> marquerLue(String id) => _client.rpc<int>(
    'marquer_notifications_lues',
    params: <String, dynamic>{'p_id': id},
  );

  @override
  Future<int> toutMarquerLu() => _client.rpc<int>('marquer_notifications_lues');
}

/// Le dépôt des notifications.
final notificationsRepositoryProvider = Provider<NotificationsRepository>(
  (ref) => NotificationsRepositorySupabase(ref.watch(supabaseClientProvider)),
);
