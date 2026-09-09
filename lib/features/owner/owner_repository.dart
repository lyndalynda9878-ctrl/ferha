import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/preferences/preferences_affichage.dart';
import '../../core/supabase/supabase_providers.dart';
import 'demande_en_attente.dart';
import 'indicateurs_salle.dart';
import 'salle_du_proprietaire.dart';

/// Les trois lectures de l'espace propriétaire (§4.3 ; écran 9).
///
/// UNE INTERFACE PLUTÔT QUE TROIS FONCTIONS LIBRES, pour une seule raison : les
/// tests la remplacent en bloc, comme ils remplacent [PreferencesAffichage]. Un
/// écran monté sur un faux dépôt n'a besoin ni de réseau, ni de session, ni de
/// base — les tests de ce dossier ne simulent pas Supabase, ils ne le
/// rencontrent jamais.
///
/// AUCUNE DE CES TROIS MÉTHODES NE CHANGE QUOI QUE CE SOIT, et c'est l'état de
/// l'étape J10. Accepter, refuser et contre-proposer viendront par des
/// fonctions `SECURITY DEFINER` qui vérifieront qui appelle ; tant qu'elles
/// n'existent pas, ce dépôt n'offre aucun moyen de répondre à une demande.
///
/// LES GARDE-FOUS SONT EN BASE, PAS ICI. `owner_venues()` ne connaît que
/// `auth.uid()`, et les deux autres fonctions refusent une salle qui n'est pas
/// la vôtre. Vérifier une seconde fois en Dart ferait un deuxième gardien pour
/// la même règle — et celui-là, un client modifié pourrait le contourner.
abstract interface class OwnerRepository {
  /// Les salles du propriétaire connecté, dans l'ordre du sélecteur.
  Future<List<SalleDuProprietaire>> salles();

  /// Les indicateurs d'une salle pour un mois — le mois en cours par défaut.
  Future<IndicateursSalle> indicateurs(String venueId, {DateTime? mois});

  /// Les demandes en attente d'une salle, la plus récente en tête.
  Future<List<DemandeEnAttente>> demandesEnAttente(String venueId);
}

/// Celui qui appelle vraiment les fonctions de 014.
class OwnerRepositorySupabase implements OwnerRepository {
  /// Crée le dépôt autour d'un client Supabase.
  const OwnerRepositorySupabase(this._client);

  final SupabaseClient _client;

  @override
  Future<List<SalleDuProprietaire>> salles() async {
    final lignes = await _client.rpc<List<dynamic>>('owner_venues');

    return lignes
        .cast<Map<String, dynamic>>()
        .map(SalleDuProprietaire.depuisJson)
        .toList(growable: false);
  }

  /// [mois] n'est pas passé par l'écran 9, qui ne montre qu'aujourd'hui. Le
  /// paramètre existe parce que la fonction SQL l'accepte, et qu'un sélecteur
  /// de mois est la suite naturelle de cet écran : le jour où il arrivera, il
  /// n'y aura rien à changer sous lui.
  @override
  Future<IndicateursSalle> indicateurs(String venueId, {DateTime? mois}) async {
    final lignes = await _client.rpc<List<dynamic>>(
      'owner_dashboard',
      params: <String, dynamic>{
        'p_venue_id': venueId,
        if (mois != null) 'p_month': _premierDuMois(mois),
      },
    );

    if (lignes.isEmpty) {
      // Ne devrait pas arriver : `owner_dashboard()` rend toujours une ligne,
      // ou lève. Un tableau vide voudrait dire que la fonction a changé de
      // forme — mieux vaut le dire que d'afficher un écran de zéros.
      throw StateError(
        'owner_dashboard() n’a renvoyé aucune ligne pour la salle $venueId.',
      );
    }

    return IndicateursSalle.depuisJson(lignes.first as Map<String, dynamic>);
  }

  @override
  Future<List<DemandeEnAttente>> demandesEnAttente(String venueId) async {
    final lignes = await _client.rpc<List<dynamic>>(
      'owner_pending_requests',
      params: <String, dynamic>{'p_venue_id': venueId},
    );

    return lignes
        .cast<Map<String, dynamic>>()
        .map(DemandeEnAttente.depuisJson)
        .toList(growable: false);
  }

  /// `date` en SQL n'a pas d'heure : on envoie le premier du mois, en clair.
  static String _premierDuMois(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-01';
}

/// Le dépôt de l'espace propriétaire.
final ownerRepositoryProvider = Provider<OwnerRepository>(
  (ref) => OwnerRepositorySupabase(ref.watch(supabaseClientProvider)),
);
