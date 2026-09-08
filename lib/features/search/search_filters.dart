import 'package:flutter/foundation.dart';

/// Les créneaux vendables (§5.1).
enum Creneau {
  /// 11 h – 17 h.
  midi('midi', 'Midi'),

  /// 18 h – 01 h.
  soir('soir', 'Soir'),

  /// Les deux, vendus ensemble.
  journee('journee', 'Journée');

  const Creneau(this.code, this.libelle);

  /// Valeur envoyée à la base.
  final String code;

  /// Libellé affiché.
  final String libelle;

  /// Retrouve un créneau depuis son code, `soir` par défaut.
  static Creneau depuisCode(String? code) => Creneau.values.firstWhere(
    (c) => c.code == code,
    orElse: () => Creneau.soir,
  );
}

/// Les types d'événement proposés à la recherche.
///
/// ATTENTION — cette liste n'a PAS de référentiel en base. Le §4.2 (CLI-01)
/// cite « type d'événement » parmi les filtres et les maquettes en montrent les
/// puces, mais aucune table du §6 ne dit quels événements une salle accueille.
///
/// Le critère voyage donc jusqu'à `search_venues()`, qui l'accepte et ne s'en
/// sert pas encore — filtrer sur une donnée qui n'existe pas ne renverrait
/// aucune salle, ce qui serait pire que ne pas filtrer. Le jour où le modèle
/// portera cette information, ces libellés viendront d'une table, comme ceux
/// des équipements.
const List<String> typesEvenement = <String>[
  'Mariage',
  'Fiançailles',
  'Henné',
  'Circoncision',
  'Anniversaire',
];

/// Les critères d'une recherche.
///
/// Immuable et comparable : c'est la clé du fournisseur de résultats, et deux
/// recherches identiques ne doivent pas produire deux appels réseau.
@immutable
class SearchFilters {
  /// Crée un jeu de critères.
  const SearchFilters({
    this.texte,
    this.wilayaCode,
    this.commune,
    this.date,
    this.creneau = Creneau.soir,
    this.invites,
    this.budgetMax,
    this.typeEvenement,
    this.equipements = const <String>[],
  });

  /// Champ libre : wilaya, commune ou nom de salle.
  final String? texte;

  /// Code de wilaya sur deux chiffres.
  final String? wilayaCode;

  /// Commune exacte.
  final String? commune;

  /// Date de l'événement. `null` = peu importe : aucune salle n'est alors
  /// écartée pour cause de date prise.
  final DateTime? date;

  /// Créneau demandé.
  final Creneau creneau;

  /// Nombre d'invités. Sert deux fois : il écarte les salles trop petites, et
  /// il entre dans le calcul du prix.
  final int? invites;

  /// Budget maximum, en dinars, comparé au prix réel de la date.
  final num? budgetMax;

  /// Type d'événement. Voir [typesEvenement] : non filtrant pour l'instant.
  final String? typeEvenement;

  /// Codes d'équipements exigés — tous, pas l'un d'eux.
  final List<String> equipements;

  /// Copie modifiée. `null` conserve la valeur ; passer `effacer` la retire.
  SearchFilters copyWith({
    String? texte,
    String? wilayaCode,
    String? commune,
    DateTime? date,
    Creneau? creneau,
    int? invites,
    num? budgetMax,
    String? typeEvenement,
    List<String>? equipements,
    Set<String> effacer = const <String>{},
  }) {
    return SearchFilters(
      texte: effacer.contains('texte') ? null : (texte ?? this.texte),
      wilayaCode: effacer.contains('wilaya')
          ? null
          : (wilayaCode ?? this.wilayaCode),
      commune: effacer.contains('commune') ? null : (commune ?? this.commune),
      date: effacer.contains('date') ? null : (date ?? this.date),
      creneau: creneau ?? this.creneau,
      invites: effacer.contains('invites') ? null : (invites ?? this.invites),
      budgetMax: effacer.contains('budget')
          ? null
          : (budgetMax ?? this.budgetMax),
      typeEvenement: effacer.contains('type')
          ? null
          : (typeEvenement ?? this.typeEvenement),
      equipements: equipements ?? this.equipements,
    );
  }

  /// Vrai si au moins un critère est posé.
  bool get aDesCriteres =>
      texte != null ||
      wilayaCode != null ||
      commune != null ||
      date != null ||
      invites != null ||
      budgetMax != null ||
      typeEvenement != null ||
      equipements.isNotEmpty;

  // ---------------------------------------------------------------------------
  // Aller-retour avec l'URL
  //
  // Les critères passent par des paramètres de requête et non par `extra` de
  // go_router : sur le web, une recherche doit pouvoir se copier, se partager
  // et survivre à un rechargement de page.
  // ---------------------------------------------------------------------------

  /// Les critères sous forme de paramètres d'URL, sans les valeurs vides.
  Map<String, String> versParametres() => <String, String>{
    if (texte != null && texte!.isNotEmpty) 'q': texte!,
    if (wilayaCode != null) 'wilaya': wilayaCode!,
    if (commune != null) 'commune': commune!,
    if (date != null) 'date': _versIso(date!),
    'creneau': creneau.code,
    if (invites != null) 'invites': '$invites',
    if (budgetMax != null) 'budget': '$budgetMax',
    if (typeEvenement != null) 'type': typeEvenement!,
    if (equipements.isNotEmpty) 'equip': equipements.join(','),
  };

  /// Relit des critères depuis des paramètres d'URL.
  static SearchFilters depuisParametres(Map<String, String> p) {
    final equip = p['equip'];
    return SearchFilters(
      texte: _nonVide(p['q']),
      wilayaCode: _nonVide(p['wilaya']),
      commune: _nonVide(p['commune']),
      date: DateTime.tryParse(p['date'] ?? ''),
      creneau: Creneau.depuisCode(p['creneau']),
      invites: int.tryParse(p['invites'] ?? ''),
      budgetMax: num.tryParse(p['budget'] ?? ''),
      typeEvenement: _nonVide(p['type']),
      equipements: (equip == null || equip.isEmpty)
          ? const <String>[]
          : equip.split(','),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SearchFilters &&
      other.texte == texte &&
      other.wilayaCode == wilayaCode &&
      other.commune == commune &&
      other.date == date &&
      other.creneau == creneau &&
      other.invites == invites &&
      other.budgetMax == budgetMax &&
      other.typeEvenement == typeEvenement &&
      listEquals(other.equipements, equipements);

  @override
  int get hashCode => Object.hash(
    texte,
    wilayaCode,
    commune,
    date,
    creneau,
    invites,
    budgetMax,
    typeEvenement,
    Object.hashAll(equipements),
  );
}

String? _nonVide(String? v) => (v == null || v.isEmpty) ? null : v;

/// `2027-08-14`, le format qu'attend PostgreSQL.
String _versIso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Format ISO d'une date, pour l'envoi en base.
String dateVersIso(DateTime d) => _versIso(d);

/// Les mois en français.
///
/// Écrits ici plutôt que tirés d'`intl` : le paquet n'est qu'une dépendance
/// transitive, et douze mots ne valent pas une dépendance de plus.
const List<String> _mois = <String>[
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];

/// « 14 août 2027 ».
String dateEnFrancais(DateTime d) => '${d.day} ${_mois[d.month - 1]} ${d.year}';

/// « 14 août », sans l'année — pour les puces, où la place manque.
String dateCourteEnFrancais(DateTime d) => '${d.day} ${_mois[d.month - 1]}';

/// « 180 000 » — séparateur d'espace fine insécable, comme en typographie
/// française. Les prix sont en dinars et toujours entiers à l'affichage.
String montantEnDinars(num montant) {
  final entier = montant.round().toString();
  final tampon = StringBuffer();
  for (var i = 0; i < entier.length; i++) {
    if (i > 0 && (entier.length - i) % 3 == 0) tampon.write(' ');
    tampon.write(entier[i]);
  }
  return tampon.toString();
}
