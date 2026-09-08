import 'package:flutter/foundation.dart';

/// Une salle telle que la renvoie `search_venues()`.
///
/// Aucun calcul ici : le prix arrive déjà fait pour la date demandée, la note
/// déjà pondérée. Ce type ne fait que nommer les colonnes.
@immutable
class VenueSummary {
  /// Crée un résumé de salle.
  const VenueSummary({
    required this.id,
    required this.nom,
    required this.wilayaCode,
    required this.commune,
    required this.capacite,
    required this.prix,
    required this.creneauPrix,
    this.placesParking,
    this.photoCouverture,
    this.equipements = const <String>[],
    this.note,
    this.nombreAvis = 0,
  });

  /// Construit depuis une ligne de la fonction RPC.
  factory VenueSummary.depuisLigne(Map<String, dynamic> l) {
    return VenueSummary(
      id: l['venue_id'] as String,
      nom: l['name'] as String,
      wilayaCode: l['wilaya_code'] as String,
      commune: l['commune'] as String,
      capacite: (l['capacity_seated'] as num).toInt(),
      placesParking: (l['parking_spaces'] as num?)?.toInt(),
      photoCouverture: l['cover_photo'] as String?,
      equipements:
          (l['amenity_codes'] as List<dynamic>?)?.cast<String>() ??
          const <String>[],
      prix: l['price'] as num,
      creneauPrix: l['price_slot'] as String,
      // NULL en base quand la salle n'a aucun avis, et NULL ici : c'est ce qui
      // permet à l'écran de n'afficher aucune étoile plutôt que « 0,0 (0) ».
      note: l['rating'] as num?,
      nombreAvis: (l['review_count'] as num?)?.toInt() ?? 0,
    );
  }

  /// Identifiant de la salle.
  final String id;

  /// Nom commercial.
  final String nom;

  /// Code de wilaya sur deux chiffres.
  final String wilayaCode;

  /// Commune.
  final String commune;

  /// Capacité assise, en couverts.
  final int capacite;

  /// Places de parking. `null` = non renseigné, `0` = pas de parking : les deux
  /// ne se disent pas de la même façon.
  final int? placesParking;

  /// Chemin ou URL de la photo de couverture.
  final String? photoCouverture;

  /// Codes d'équipements. Les libellés viennent du référentiel, pas d'ici.
  final List<String> equipements;

  /// Prix pour la date et le créneau demandés, majorations comprises.
  final num prix;

  /// Créneau auquel ce prix correspond.
  final String creneauPrix;

  /// Note bayésienne (§5.4), ou `null` si la salle n'a aucun avis.
  final num? note;

  /// Nombre d'avis.
  final int nombreAvis;

  /// Vrai seulement si la salle a réellement été notée.
  ///
  /// Une salle sans avis n'affiche pas d'étoiles — pas « 0,0 (0) », qui la
  /// ferait passer pour mal notée alors qu'elle est simplement neuve.
  bool get estNotee => note != null && nombreAvis > 0;
}
