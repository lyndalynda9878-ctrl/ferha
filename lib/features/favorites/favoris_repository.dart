import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_providers.dart';
import '../search/venue_summary.dart';

/// Les quatre gestes des favoris — lire, ajouter, retirer, et la liste entiere.
///
/// UNE INTERFACE PLUTOT QUE DES APPELS EN DIRECT, pour la meme raison que
/// [AvisRepository] et [OwnerRepository] : les tests la remplacent en bloc. Sans
/// elle, la regle qui compte le plus de ce dossier — LE CŒUR SE REETEINT QUAND
/// LA BASE REFUSE — ne serait verifiable qu'avec une vraie base en face, donc
/// jamais verifiee.
///
/// LES GARDE-FOUS SONT EN BASE, PAS ICI. La cle primaire composite refuse le
/// doublon, `favorites_insert_self` refuse d'aimer au nom d'un autre ou une
/// salle qu'on n'a pas le droit de voir, et `mes_favoris()` ne rend que les
/// lignes de qui appelle. Rien de tout cela n'est reverifie dans ce fichier :
/// le client ne fait qu'appeler, et croire le refus quand il vient.
abstract interface class FavorisRepository {
  /// Les identifiants des salles que [utilisateur] a mises de cote.
  ///
  /// Un ensemble et non une liste : la seule question qu'on lui pose est
  /// « cette salle-la en fait-elle partie ? », et un cœur par carte la pose
  /// autant de fois qu'il y a de cartes a l'ecran.
  Future<Set<String>> identifiantsDe(String utilisateur);

  /// Ajoute la salle aux favoris de [utilisateur].
  Future<void> ajouter({required String utilisateur, required String venueId});

  /// Retire la salle des favoris de [utilisateur].
  Future<void> retirer({required String utilisateur, required String venueId});

  /// Les salles mises de cote, dans la forme exacte d'une carte.
  ///
  /// Aucun parametre : `mes_favoris()` lit `auth.uid()` elle-meme. Passer un
  /// identifiant ici laisserait croire qu'on peut demander ceux d'un autre.
  Future<List<VenueSummary>> mesFavoris();
}

/// Celui qui parle vraiment a la table et a la fonction de 039.
class FavorisRepositorySupabase implements FavorisRepository {
  /// Cree le depot autour d'un client Supabase.
  const FavorisRepositorySupabase(this._client);

  final SupabaseClient _client;

  @override
  Future<Set<String>> identifiantsDe(String utilisateur) async {
    // ON NE DEMANDE QUE LA COLONNE QU'ON LIT. La politique RLS borne deja les
    // lignes a celles de la personne connectee — le `eq` ne la remplace pas, il
    // evite seulement de faire examiner des lignes qui ne sortiraient pas.
    final lignes = await _client
        .from('favorites')
        .select('venue_id')
        .eq('user_id', utilisateur);

    return <String>{for (final ligne in lignes) ligne['venue_id'] as String};
  }

  @override
  Future<void> ajouter({
    required String utilisateur,
    required String venueId,
  }) async {
    await _client.from('favorites').insert(<String, dynamic>{
      'user_id': utilisateur,
      'venue_id': venueId,
    });
  }

  @override
  Future<void> retirer({
    required String utilisateur,
    required String venueId,
  }) async {
    await _client
        .from('favorites')
        .delete()
        .eq('user_id', utilisateur)
        .eq('venue_id', venueId);
  }

  @override
  Future<List<VenueSummary>> mesFavoris() async {
    final lignes = await _client.rpc<List<dynamic>>('mes_favoris');

    return <VenueSummary>[
      for (final ligne in lignes)
        VenueSummary.depuisLigne((ligne as Map).cast<String, dynamic>()),
    ];
  }
}

/// Le depot des favoris de l'application.
final favorisRepositoryProvider = Provider<FavorisRepository>(
  (ref) => FavorisRepositorySupabase(ref.watch(supabaseClientProvider)),
);
