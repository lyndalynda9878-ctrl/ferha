import 'package:flutter/foundation.dart';

/// Une ligne de la grille tarifaire, avec son prix pour la date demandée.
@immutable
class LigneTarif {
  /// Crée une ligne de grille tarifaire.
  const LigneTarif({
    required this.creneau,
    required this.prixBase,
    required this.couvertsInclus,
    required this.prixCouvertSup,
    required this.coefJour,
    required this.coefSaison,
    required this.couvertsSup,
    required this.montantCouvertsSup,
    required this.total,
  });

  /// Construit depuis le JSON de `venue_detail()`.
  factory LigneTarif.depuisJson(Map<String, dynamic> j) => LigneTarif(
    creneau: j['slot'] as String,
    prixBase: j['base_price'] as num,
    couvertsInclus: (j['included_seats'] as num).toInt(),
    prixCouvertSup: j['extra_seat_price'] as num,
    coefJour: j['day_coef'] as num,
    coefSaison: j['season_coef'] as num,
    couvertsSup: (j['extra_seats'] as num).toInt(),
    montantCouvertsSup: j['extra_seats_amount'] as num,
    total: j['total'] as num,
  );

  /// `midi`, `soir` ou `journee`.
  final String creneau;

  /// Prix de base, hors majorations.
  final num prixBase;

  /// Couverts compris dans le prix de base.
  final int couvertsInclus;

  /// Prix du couvert au-delà.
  final num prixCouvertSup;

  /// Coefficient du jour appliqué (§5.2). 1 hors jeudi, vendredi et samedi.
  final num coefJour;

  /// Coefficient de saison appliqué (§5.2). 1 hors juin–septembre et vacances.
  final num coefSaison;

  /// Couverts facturés en supplément.
  final int couvertsSup;

  /// Montant du supplément.
  final num montantCouvertsSup;

  /// Le prix, majorations comprises, pour la date demandée.
  final num total;

  /// Vrai si le jour choisi est majoré (jeudi, vendredi ou samedi).
  bool get jourMajore => coefJour > 1;

  /// Vrai si la date tombe en haute saison.
  bool get saisonMajoree => coefSaison > 1;
}

/// Un équipement de la salle, déjà traduit par le référentiel.
typedef EquipementSalle = ({
  String code,
  String libelle,
  String? icone,
  String categorie,
});

/// La fiche complète d'une salle, telle que la renvoie `venue_detail()`.
///
/// Ce que ce type NE PORTE PAS, et ne doit jamais porter : rien du
/// propriétaire. Ni son nom, ni son téléphone (§9). Le numéro n'est révélé
/// qu'après acceptation d'une demande, par `booking_contact()`.
@immutable
class VenueDetail {
  /// Crée une fiche salle.
  const VenueDetail({
    required this.id,
    required this.nom,
    required this.commune,
    required this.wilayaCode,
    required this.capacite,
    required this.photos,
    required this.equipements,
    required this.tarifs,
    required this.dateEstimation,
    this.wilayaNom,
    this.superficie,
    this.placesParking,
    this.description,
    this.note,
    this.nombreAvis = 0,
    this.typesEvenement = const <String>[],
    this.invites,
  });

  /// Construit depuis le JSON de `venue_detail()`.
  factory VenueDetail.depuisJson(Map<String, dynamic> j) {
    return VenueDetail(
      id: j['id'] as String,
      nom: j['name'] as String,
      commune: j['commune'] as String,
      wilayaCode: j['wilaya_code'] as String,
      wilayaNom: j['wilaya_name'] as String?,
      capacite: (j['capacity_seated'] as num).toInt(),
      superficie: (j['area_sqm'] as num?)?.toInt(),
      placesParking: (j['parking_spaces'] as num?)?.toInt(),
      description: j['description'] as String?,
      note: j['rating'] as num?,
      nombreAvis: (j['review_count'] as num?)?.toInt() ?? 0,
      photos: (j['photos'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map((p) => p['path'] as String)
          .toList(growable: false),
      equipements: (j['amenities'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map<EquipementSalle>(
            (a) => (
              code: a['code'] as String,
              libelle: a['label'] as String,
              icone: a['icon'] as String?,
              categorie: a['category'] as String,
            ),
          )
          .toList(growable: false),
      typesEvenement: (j['event_types'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map((t) => t['label'] as String)
          .toList(growable: false),
      tarifs: (j['pricing'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(LigneTarif.depuisJson)
          .toList(growable: false),
      dateEstimation: DateTime.parse(j['event_date'] as String),
      invites: (j['guest_count'] as num?)?.toInt(),
    );
  }

  /// Identifiant de la salle.
  final String id;

  /// Nom commercial.
  final String nom;

  /// Commune.
  final String commune;

  /// Code de wilaya sur deux chiffres.
  final String wilayaCode;

  /// Nom de la wilaya, depuis le référentiel.
  final String? wilayaNom;

  /// Capacité assise, en couverts.
  final int capacite;

  /// Superficie en mètres carrés. `null` = non renseignée.
  final int? superficie;

  /// Places de parking. `null` = non renseigné, `0` = pas de parking.
  final int? placesParking;

  /// Texte libre du propriétaire.
  final String? description;

  /// Note bayésienne (§5.4), ou `null` si la salle n'a aucun avis.
  final num? note;

  /// Nombre d'avis.
  final int nombreAvis;

  /// Chemins ou URL des photos, couverture en tête.
  final List<String> photos;

  /// Équipements, déjà traduits.
  final List<EquipementSalle> equipements;

  /// Types d'événement acceptés. Vide = la salle accepte tout.
  final List<String> typesEvenement;

  /// La grille tarifaire, un créneau par ligne.
  final List<LigneTarif> tarifs;

  /// La date pour laquelle les prix ont été calculés.
  final DateTime dateEstimation;

  /// Le nombre d'invités demandé, s'il y en avait un.
  final int? invites;

  /// Vrai seulement si la salle a réellement été notée.
  bool get estNotee => note != null && nombreAvis > 0;

  /// « Bir El Djir, Oran (31) », comme sur la maquette.
  String get localisation {
    final wilaya = wilayaNom ?? 'wilaya $wilayaCode';
    return '$commune, $wilaya ($wilayaCode)';
  }

  /// La ligne de tarif d'un créneau, ou `null` si la salle ne le vend pas.
  LigneTarif? tarifPour(String creneau) {
    for (final t in tarifs) {
      if (t.creneau == creneau) return t;
    }
    return null;
  }
}

/// L'état d'un jour au calendrier.
///
/// Trois états, pas quatre. « Libre » est l'absence : `venue_calendar()` ne
/// renvoie que ce qui est pris.
enum EtatJour {
  /// Rien ne l'occupe.
  libre,

  /// Une réservation confirmée occupe le créneau (§6.1).
  reserve,

  /// Le propriétaire a bloqué la date — ou elle est passée.
  indisponible,
}
