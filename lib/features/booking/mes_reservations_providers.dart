import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_providers.dart';
import '../auth/auth_providers.dart';
import 'reservation.dart';

/// Les réservations du client connecté, tenues à jour par le temps réel.
///
/// PAS DE MINUTERIE DE RAFRAÎCHISSEMENT, ET C'EST LE POINT. Redemander la liste
/// toutes les trente secondes coûterait du réseau en permanence pour
/// n'apprendre presque jamais rien — sur une 4G algérienne (§7.3), c'est
/// exactement la dépense qu'on refuse partout ailleurs dans ce projet. On
/// s'abonne une fois, et la base prévient.
///
/// UN SEUL ABONNEMENT POUR TOUTE LA VIE DE L'ÉCRAN. C'est pourquoi ce n'est pas
/// un `FutureProvider` : un fournisseur qui s'invaliderait lui-même à chaque
/// événement referait aussi son abonnement, et le canal serait défait puis
/// refait à chaque acceptation. Ici `build()` s'abonne, et [recharger] ne
/// touche qu'aux données.
///
/// ON RECHARGE, ON NE RAPIÈCE PAS. L'événement Realtime porte la ligne brute de
/// `bookings` : ni le nom de la salle, ni sa photo, et surtout PAS le téléphone
/// du propriétaire — Realtime ne passe pas par `booking_contact()`. Recomposer
/// une ligne d'écran à partir de cette charge utile obligerait à réécrire ici
/// la règle du §9, c'est-à-dire à en avoir deux exemplaires. On se contente
/// donc d'apprendre que quelque chose a bougé, et on redemande la liste à
/// `client_bookings()`.
class MesReservations extends AsyncNotifier<List<Reservation>> {
  RealtimeChannel? _canal;

  @override
  Future<List<Reservation>> build() async {
    // Se déconnecter vide la liste, se connecter la recharge : aucun écran n'a
    // à s'en occuper.
    final session = ref.watch(sessionProvider);
    if (session == null) return const <Reservation>[];

    _ecoute(session.user.id);
    // On charge AUSSI à l'ouverture, et pas seulement sur événement. C'est ce
    // qui rend l'écran juste même quand l'abonnement rate quelque chose — le
    // service Realtime de Supabase démarre à froid quand le projet a dormi, et
    // un changement survenu pendant ces deux secondes-là ne serait annoncé à
    // personne. L'écran ouvert affiche donc toujours l'état lu, pas l'état
    // deviné.
    return _charger();
  }

  /// S'abonne aux changements des réservations de CE client.
  ///
  /// Le filtre `client_id=eq.<uid>` ne remplace pas la politique RLS de
  /// `bookings` — c'est elle qui décide, et Realtime l'évalue pour chaque
  /// abonné. Il lui évite seulement d'examiner des lignes qui ne partiraient
  /// de toute façon pas.
  void _ecoute(String clientId) {
    final client = ref.read(supabaseClientProvider);

    final canal = client
        .channel('mes-reservations-$clientId')
        .onPostgresChanges(
          // Les trois : une demande naît, change d'état, et — un jour — se
          // purge. On ne devine pas laquelle nous intéresse, on recharge.
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'bookings',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'client_id',
            value: clientId,
          ),
          callback: (_) => recharger(),
        )
        .subscribe();

    _canal = canal;
    // Quitter l'écran ferme le canal : un abonnement oublié continue de
    // recevoir, et de consommer, pour personne.
    ref.onDispose(() {
      _canal = null;
      client.removeChannel(canal);
    });
  }

  /// Redemande la liste sans repasser par un état de chargement.
  ///
  /// L'écran ne doit pas clignoter parce que le propriétaire vient de répondre :
  /// les cartes restent en place, et seule celle qui a changé change.
  Future<void> recharger() async {
    try {
      final reservations = await _charger();
      // Le canal a pu être fermé pendant la requête — l'écran quitté, la
      // session close. Écrire dans un état jeté lèverait.
      if (_canal == null) return;
      state = AsyncData<List<Reservation>>(reservations);
    } on Object catch (erreur, pile) {
      if (_canal == null) return;
      state = AsyncError<List<Reservation>>(erreur, pile);
    }
  }

  /// Relance depuis zéro, squelette compris — le geste du bouton « Réessayer ».
  Future<void> reessayer() async {
    state = const AsyncLoading<List<Reservation>>();
    await recharger();
  }

  Future<List<Reservation>> _charger() async {
    final lignes = await ref
        .read(supabaseClientProvider)
        .rpc<List<dynamic>>('client_bookings');

    return lignes
        .cast<Map<String, dynamic>>()
        .map(Reservation.depuisJson)
        .toList(growable: false);
  }
}

/// Les réservations du client connecté.
final mesReservationsProvider =
    AsyncNotifierProvider.autoDispose<MesReservations, List<Reservation>>(
      MesReservations.new,
    );

/// L'annulation d'une demande par le client (§5.3).
///
/// `cancel_booking()` travaille sur le GROUPE entier à partir de n'importe
/// laquelle de ses lignes : une journée entière s'annule d'un coup, jamais à
/// moitié.
///
/// Rien à recharger après coup — la mise à jour de `bookings` revient par
/// Realtime, et c'est le même chemin que si le propriétaire avait annulé de son
/// côté. Un rechargement manuel ferait doublon avec lui.
class AnnulationService {
  /// Crée le service autour d'un client Supabase.
  const AnnulationService(this._client);

  final SupabaseClient _client;

  /// Annule la demande à laquelle appartient [bookingId].
  Future<void> annuler(String bookingId) async {
    await _client.rpc<List<dynamic>>(
      'cancel_booking',
      params: <String, dynamic>{'p_booking_id': bookingId},
    );
  }
}

/// Le service d'annulation.
final annulationServiceProvider = Provider<AnnulationService>(
  (ref) => AnnulationService(ref.watch(supabaseClientProvider)),
);
