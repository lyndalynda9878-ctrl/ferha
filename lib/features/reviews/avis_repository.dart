import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_providers.dart';
import 'avis.dart';

/// Les deux lectures et les trois gestes des avis (§5.4, CLI-08, OWN-06).
///
/// UNE INTERFACE PLUTÔT QUE DES FONCTIONS LIBRES, pour la même raison que
/// `OwnerRepository` : les tests la remplacent en bloc. Les écrans de ce dossier
/// se montent alors sans réseau, sans session et sans base.
///
/// LES GARDE-FOUS SONT EN BASE, PAS ICI. `deposer_avis()` refuse d'elle-même une
/// réservation qui n'est pas la vôtre, une réservation non honorée, une fenêtre
/// fermée et un avis figé ; `repondre_a_un_avis()` refuse la salle d'un autre et
/// une seconde réponse. Ce que les écrans cachent, ils le cachent pour ne pas
/// proposer un geste qui échouerait — jamais pour empêcher qu'il réussisse.
abstract interface class AvisRepository {
  /// Les avis d'une salle, le plus récent en tête — l'écran 7.
  ///
  /// Ouverte aux visiteurs : un avis sert d'abord à celui qui n'a pas encore
  /// réservé (§3, étape 2).
  Future<AvisDeLaSalle> deLaSalle(String venueId);

  /// Ce qu'il faut à l'écran de dépôt, avis déjà déposé compris.
  Future<AvisADeposer> aDeposer(String bookingId);

  /// Dépose l'avis, ou le corrige si le client en avait déjà écrit un.
  ///
  /// UN SEUL APPEL POUR LES DEUX : c'est un seul geste vu du client, et c'est
  /// `deposer_avis()` (026) qui sait lequel des deux elle fait.
  Future<void> deposer({
    required String bookingId,
    required int note,
    Map<SousNote, int> sousNotes = const <SousNote, int>{},
    String? commentaire,
  });

  /// Répond à un avis, une seule fois (§4.3, OWN-06).
  Future<void> repondre(String avisId, String reponse);
}

/// Celui qui appelle vraiment les fonctions de 026.
class AvisRepositorySupabase implements AvisRepository {
  /// Crée le dépôt autour d'un client Supabase.
  const AvisRepositorySupabase(this._client);

  final SupabaseClient _client;

  @override
  Future<AvisDeLaSalle> deLaSalle(String venueId) async {
    // `avis_de_la_salle()` rend un seul jsonb — la salle, ses moyennes et ses
    // avis — et non une table : l'écran 7 tient en un objet, et le découper en
    // deux appels ferait deux allers-retours sur une 4G algérienne (§7.3).
    final json = await _client.rpc<Map<String, dynamic>>(
      'avis_de_la_salle',
      params: <String, dynamic>{'p_venue_id': venueId},
    );

    return AvisDeLaSalle.depuisJson(json);
  }

  @override
  Future<AvisADeposer> aDeposer(String bookingId) async {
    final lignes = await _client.rpc<List<dynamic>>(
      'avis_a_deposer',
      params: <String, dynamic>{'p_booking_id': bookingId},
    );

    if (lignes.isEmpty) {
      // La fonction lève sur tous ses refus ; une liste vide voudrait dire
      // qu'elle a changé de forme. Se taire afficherait un écran vide.
      throw StateError('Aucun avis à déposer pour la réservation $bookingId.');
    }

    return AvisADeposer.depuisJson(
      (lignes.first as Map).cast<String, dynamic>(),
    );
  }

  /// LES QUATRE SOUS-NOTES PARTENT TOUJOURS, `null` COMPRIS. Une sous-note
  /// retirée par le client doit s'effacer en base, et une clé absente laisserait
  /// l'ancienne valeur : `deposer_avis()` écrit les cinq colonnes à chaque
  /// correction, elle ne les fusionne pas.
  @override
  Future<void> deposer({
    required String bookingId,
    required int note,
    Map<SousNote, int> sousNotes = const <SousNote, int>{},
    String? commentaire,
  }) async {
    await _client.rpc<dynamic>(
      'deposer_avis',
      params: <String, dynamic>{
        'p_booking_id': bookingId,
        'p_rating': note,
        'p_rating_cleanliness': sousNotes[SousNote.proprete],
        'p_rating_service': sousNotes[SousNote.service],
        'p_rating_value': sousNotes[SousNote.rapportQualitePrix],
        'p_rating_accuracy': sousNotes[SousNote.conformite],
        'p_body': commentaire,
      },
    );
  }

  @override
  Future<void> repondre(String avisId, String reponse) async {
    await _client.rpc<dynamic>(
      'repondre_a_un_avis',
      params: <String, dynamic>{'p_review_id': avisId, 'p_reply': reponse},
    );
  }
}

/// Le dépôt des avis.
final avisRepositoryProvider = Provider<AvisRepository>(
  (ref) => AvisRepositorySupabase(ref.watch(supabaseClientProvider)),
);
