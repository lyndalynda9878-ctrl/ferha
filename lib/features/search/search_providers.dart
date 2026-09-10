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

/// Les 58 wilayas, sans exception.
///
/// À NE PAS CONFONDRE AVEC [wilayasProvider], qui n'en rend qu'une partie. Ce
/// dernier lit `wilayas_avec_salles` : celles où il y a déjà quelque chose à
/// montrer, parce qu'une puce de recherche qui ne mène nulle part fait perdre
/// un geste. Ici c'est l'inverse — le formulaire d'inscription d'une salle
/// (§4.3, OWN-01) doit proposer TOUTES les wilayas, y compris celles qui n'ont
/// pas encore une seule salle. Ce sont précisément les plus importantes : c'est
/// la première salle d'une wilaya qui l'ouvre au catalogue, et lui refuser
/// l'entrée fermerait la carte pour toujours.
///
/// Le référentiel entier, gardé une fois chargé : cinquante-huit lignes qui ne
/// changent jamais ne se redemandent pas.
final toutesLesWilayasProvider = FutureProvider<List<Wilaya>>((ref) async {
  final client = ref.watch(supabaseClientProvider);

  final lignes = await client
      .from('wilayas')
      .select('code, name_fr')
      .order('code');

  return lignes
      .map<Wilaya>(
        (l) => (code: l['code'] as String, nom: l['name_fr'] as String),
      )
      .toList(growable: false);
});

/// Une wilaya du référentiel : son code sur deux chiffres, et son nom.
typedef Wilaya = ({String code, String nom});

/// Un équipement du référentiel, tel qu'on le montre à cocher.
typedef Equipement = ({String code, String libelle, String categorie});

/// Le référentiel des équipements, groupés par catégorie.
///
/// À NE PAS CONFONDRE non plus avec [equipementsProvider], qui rend une simple
/// table code → libellé : elle suffit aux cartes de résultat, qui traduisent un
/// code déjà connu. Pour COCHER, il faut l'ordre et le regroupement — « confort,
/// espaces, services, logistique », les quatre catégories de la table (§6).
/// Trente cases en vrac ne se lisent pas ; quatre paquets de sept, si.
///
/// La `Map` garde l'ordre d'insertion en Dart, et la requête est triée par
/// catégorie puis par position : les paquets sortent donc dans l'ordre du
/// référentiel, jamais dans celui du hasard.
final equipementsParCategorieProvider =
    FutureProvider<Map<String, List<Equipement>>>((ref) async {
      final client = ref.watch(supabaseClientProvider);

      final lignes = await client
          .from('amenities')
          .select('code, label_fr, category, position')
          .order('category')
          .order('position');

      final parCategorie = <String, List<Equipement>>{};
      for (final l in lignes) {
        final categorie = l['category'] as String;
        (parCategorie[categorie] ??= <Equipement>[]).add((
          code: l['code'] as String,
          libelle: l['label_fr'] as String,
          categorie: categorie,
        ));
      }
      return parCategorie;
    });

/// Le nom français d'une catégorie d'équipement.
///
/// Les quatre codes viennent du `CHECK` d'`amenities.category` (001). Ils ne
/// s'affichent jamais tels quels — « logistique » passerait, « espaces » aussi,
/// mais ce sont des codes, et un code qu'on affiche finit par être traduit par
/// erreur le jour où l'arabe arrive.
String libelleCategorieEquipement(String code) => switch (code) {
  'confort' => 'Confort',
  'espaces' => 'Espaces',
  'services' => 'Services',
  'logistique' => 'Logistique',
  // Une cinquième catégorie apparaîtrait telle quelle plutôt que de disparaître
  // avec ses équipements : mieux vaut un intitulé laid qu'une case invisible.
  _ => code,
};
