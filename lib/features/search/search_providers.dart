import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase/supabase_providers.dart';
import 'search_filters.dart';
import 'venue_summary.dart';

/// Le résultat d'une recherche : les salles de la page, et le total.
typedef ResultatRecherche = ({List<VenueSummary> salles, int total});

/// Lance `search_venues()` en RPC.
///
/// Tout le filtrage, tout le tri et tout le calcul de prix se font en base
/// (008_search.sql). Cette fonction ne fait que porter des critères et relire
/// des lignes — s'il devient tentant d'écarter une salle ici, c'est que la
/// fonction SQL est incomplète.
Future<ResultatRecherche> chercherSalles(
  Ref ref,
  SearchFilters filtres, {
  String ordre = 'note',
  int limite = 50,
}) async {
  final client = ref.watch(supabaseClientProvider);

  final lignes = await client.rpc<List<dynamic>>(
    'search_venues',
    params: <String, dynamic>{
      'p_query': filtres.texte,
      'p_wilaya_code': filtres.wilayaCode,
      'p_commune': filtres.commune,
      'p_event_date': filtres.date == null ? null : dateVersIso(filtres.date!),
      'p_slot': filtres.creneau.code,
      'p_guest_count': filtres.invites,
      'p_max_budget': filtres.budgetMax,
      'p_event_type': filtres.typeEvenement,
      'p_amenities': filtres.equipements.isEmpty ? null : filtres.equipements,
      'p_order': ordre,
      'p_limit': limite,
      'p_offset': 0,
    },
  );

  final salles = lignes
      .cast<Map<String, dynamic>>()
      .map(VenueSummary.depuisLigne)
      .toList(growable: false);

  // total_count est identique sur toutes les lignes : c'est un `count(*) over ()`.
  // Sans ligne, il n'y a rien à compter.
  final total = lignes.isEmpty
      ? 0
      : ((lignes.first as Map<String, dynamic>)['total_count'] as num).toInt();

  return (salles: salles, total: total);
}

/// Les résultats d'une recherche complète — écran 2.
final resultatsProvider = FutureProvider.autoDispose
    .family<ResultatRecherche, SearchFilters>((ref, filtres) {
      return chercherSalles(ref, filtres, ordre: 'note');
    });

/// « Les mieux notées » de l'écran d'accueil.
///
/// Même fonction SQL, même prix calculé : une salle ne peut pas afficher un
/// montant sur l'accueil et un autre dans les résultats.
final mieuxNoteesProvider = FutureProvider.autoDispose
    .family<ResultatRecherche, SearchFilters>((ref, filtres) {
      return chercherSalles(ref, filtres, ordre: 'note', limite: 6);
    });

/// Une wilaya qui a des salles à montrer.
typedef WilayaAvecSalles = ({String code, String nom, int nombreSalles});

/// Les wilayas où il y a au moins une salle publiée.
///
/// Cinquante-huit puces ne se lisent pas : l'écran n'affiche que celles qui ont
/// quelque chose derrière. La liste vient de la base, jamais d'une constante
/// Dart — sinon elle mentirait le jour où une wilaya s'ouvre.
final wilayasProvider = FutureProvider<List<WilayaAvecSalles>>((ref) async {
  final client = ref.watch(supabaseClientProvider);

  final lignes = await client
      .from('wilayas_avec_salles')
      .select('code, name_fr, venue_count')
      .order('name_fr');

  return lignes
      .map<WilayaAvecSalles>(
        (l) => (
          code: l['code'] as String,
          nom: l['name_fr'] as String,
          nombreSalles: (l['venue_count'] as num).toInt(),
        ),
      )
      .toList(growable: false);
});

/// Le référentiel des équipements, code → libellé français.
///
/// Chargé une fois et gardé : les cartes de résultat en ont besoin à chaque
/// ligne, et le libellé dépend de la langue tandis que le code n'en dépend pas.
final equipementsProvider = FutureProvider<Map<String, String>>((ref) async {
  final client = ref.watch(supabaseClientProvider);

  final lignes = await client
      .from('amenities')
      .select('code, label_fr')
      .order('position');

  return <String, String>{
    for (final l in lignes) l['code'] as String: l['label_fr'] as String,
  };
});

/// Un type d'événement du référentiel.
typedef TypeEvenement = ({String code, String libelle});

/// Le référentiel des types d'événement (§4.2, CLI-01).
///
/// Les puces de l'écran d'accueil viennent d'ici, et le filtre envoie le
/// `code` — jamais le libellé, qui dépend de la langue. C'est la même
/// séparation que pour les équipements et les wilayas : le code est stable, le
/// libellé se traduit.
final typesEvenementProvider = FutureProvider<List<TypeEvenement>>((ref) async {
  final client = ref.watch(supabaseClientProvider);

  final lignes = await client
      .from('event_types')
      .select('code, label_fr')
      .order('position');

  return lignes
      .map<TypeEvenement>(
        (l) => (code: l['code'] as String, libelle: l['label_fr'] as String),
      )
      .toList(growable: false);
});
