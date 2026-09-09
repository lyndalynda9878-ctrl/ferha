import 'package:flutter/foundation.dart';

/// Une salle, vue par celui qui la tient.
///
/// C'est la ligne du sélecteur de l'écran 9 : Karim en a quatre, et il change
/// de salle sans quitter son tableau de bord. [demandesEnAttente] voyage avec
/// elle pour que le sélecteur puisse dire « 3 demandes » sans un second appel
/// par salle.
@immutable
class SalleDuProprietaire {
  /// Crée une salle du sélecteur.
  const SalleDuProprietaire({
    required this.id,
    required this.nom,
    required this.commune,
    required this.statut,
    required this.demandesEnAttente,
    this.wilayaNom,
    this.photo,
  });

  /// Construit depuis une ligne d'`owner_venues()`.
  factory SalleDuProprietaire.depuisJson(Map<String, dynamic> j) =>
      SalleDuProprietaire(
        id: j['venue_id'] as String,
        nom: j['name'] as String,
        commune: j['commune'] as String,
        wilayaNom: j['wilaya_name'] as String?,
        photo: j['cover_photo'] as String?,
        statut: StatutSalle.depuisCode(j['status'] as String),
        demandesEnAttente: (j['pending_count'] as num).toInt(),
      );

  /// L'identifiant de la salle.
  final String id;

  /// Son nom.
  final String nom;

  /// Sa commune.
  final String commune;

  /// Sa wilaya.
  final String? wilayaNom;

  /// Sa photo de couverture.
  final String? photo;

  /// Où elle en est de sa publication.
  final StatutSalle statut;

  /// Le nombre de demandes qui attendent une réponse.
  final int demandesEnAttente;

  /// « Oran, Oran » n'apprend rien : la commune suffit quand elle répète la
  /// wilaya.
  String get localisation => (wilayaNom == null || wilayaNom == commune)
      ? commune
      : '$commune, $wilayaNom';
}

/// L'état de publication d'une salle (§4.4, ADM-01).
///
/// Comme pour les états de réservation, le code de la base d'un côté et la
/// phrase française de l'autre : « draft » ne s'affiche jamais.
enum StatutSalle {
  /// En cours d'inscription, visible de son seul propriétaire.
  brouillon('draft', 'Brouillon'),

  /// Envoyée à la validation humaine.
  enValidation('pending', 'En attente de validation'),

  /// Au catalogue.
  publiee('published', 'Publiée'),

  /// Retirée du catalogue par l'administration.
  suspendue('suspended', 'Suspendue');

  const StatutSalle(this.code, this.libelle);

  /// La valeur de `venues.status`.
  final String code;

  /// Ce qui s'affiche.
  final String libelle;

  /// Vrai quand la salle est au catalogue, donc réservable.
  bool get estAuCatalogue => this == publiee;

  /// Retrouve un statut depuis son code.
  ///
  /// Un code inconnu est une erreur de programme : la contrainte CHECK de
  /// `venues.status` interdit tout le reste.
  static StatutSalle depuisCode(String code) => StatutSalle.values.firstWhere(
    (s) => s.code == code,
    orElse: () =>
        throw ArgumentError.value(code, 'code', 'Statut de salle inconnu'),
  );
}
