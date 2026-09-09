import 'package:flutter/foundation.dart';

/// Les quatre indicateurs d'une salle pour un mois, tels que les renvoie
/// `owner_dashboard()` (§4.3, OWN-07 ; écran 9).
///
/// AUCUN CHIFFRE N'EST CALCULÉ ICI, ET C'EST TOUT L'INTÉRÊT DE LA CLASSE. Le
/// taux d'occupation, le prévisionnel, la part acceptée et leurs variations
/// sortent de la base déjà faits. Ajouter une soustraction dans ce fichier —
/// même une seule, même évidente — créerait une seconde définition de
/// « occupé » à côté de celle de 014, et deux définitions finissent toujours
/// par diverger. Ce modèle transporte, il ne compte pas.
///
/// LES `null` SONT DES RÉPONSES, PAS DES TROUS. Une salle sans avis n'a pas
/// une note de 0,0 — elle n'a pas de note ; un mois précédent sans réservation
/// ne donne pas une variation de 0 % — il ne donne pas de variation. La base
/// distingue les deux, l'écran doit écrire « — » là où elle n'a rien dit.
@immutable
class IndicateursSalle {
  /// Crée un jeu d'indicateurs.
  const IndicateursSalle({
    required this.mois,
    required this.revenu,
    required this.datesVendues,
    required this.nombreAvis,
    required this.demandesTranchees,
    required this.demandesEnAttente,
    this.tauxOccupation,
    this.variationOccupation,
    this.variationRevenu,
    this.note,
    this.tauxAcceptation,
    this.variationAcceptation,
  });

  /// Construit depuis la ligne unique d'`owner_dashboard()`.
  factory IndicateursSalle.depuisJson(Map<String, dynamic> j) =>
      IndicateursSalle(
        mois: DateTime.parse(j['month'] as String),
        tauxOccupation: (j['occupancy_rate'] as num?)?.toDouble(),
        variationOccupation: (j['occupancy_delta'] as num?)?.toDouble(),
        revenu: (j['revenue'] as num?) ?? 0,
        datesVendues: ((j['revenue_dates'] as num?) ?? 0).toInt(),
        variationRevenu: (j['revenue_delta'] as num?)?.toDouble(),
        note: (j['rating'] as num?)?.toDouble(),
        nombreAvis: ((j['review_count'] as num?) ?? 0).toInt(),
        tauxAcceptation: (j['acceptance_rate'] as num?)?.toDouble(),
        variationAcceptation: (j['acceptance_delta'] as num?)?.toDouble(),
        demandesTranchees: ((j['decided_count'] as num?) ?? 0).toInt(),
        demandesEnAttente: ((j['pending_count'] as num?) ?? 0).toInt(),
      );

  /// Le premier jour du mois observé.
  final DateTime mois;

  /// Part des créneaux vendables réellement pris, entre 0 et 1.
  ///
  /// `null` quand la salle n'avait aucun créneau à vendre ce mois-là — tout
  /// bloqué. Diviser par zéro ne veut rien dire, et « 0 % » se lirait comme un
  /// échec commercial alors que rien n'était en vente.
  final double? tauxOccupation;

  /// L'écart d'occupation avec le mois précédent, EN POINTS déjà multipliés.
  ///
  /// Des points et non un rapport : passer de 60 % à 68 %, c'est « ▲ 8 pts »
  /// et non « ▲ 13 % ». La base l'a déjà tranché, l'écran met un signe.
  final double? variationOccupation;

  /// Le revenu prévisionnel du mois, en dinars.
  final num revenu;

  /// Le nombre de dates vendues qui composent ce revenu.
  final int datesVendues;

  /// L'écart de revenu avec le mois précédent, EN PART DE 1.
  ///
  /// Une fraction ici, des points pour l'occupation : ce n'est pas une
  /// inconséquence. Un revenu qui double est « ▲ 100 % », ce qui se comprend ;
  /// un taux qui passe de 30 % à 60 % n'est pas « ▲ 100 % » mais « ▲ 30 pts ».
  final double? variationRevenu;

  /// La note moyenne bayésienne (§5.4), ou `null` faute d'avis.
  final double? note;

  /// Le nombre d'avis qui la composent.
  final int nombreAvis;

  /// Part des demandes tranchées qui ont été acceptées, entre 0 et 1.
  final double? tauxAcceptation;

  /// L'écart de part acceptée avec le mois précédent, EN POINTS.
  final double? variationAcceptation;

  /// Le nombre de demandes tranchées ce mois-ci — dénominateur de
  /// [tauxAcceptation].
  final int demandesTranchees;

  /// Le nombre de demandes qui attendent une réponse, TOUTES DATES CONFONDUES.
  ///
  /// Ce n'est pas une statistique du mois mais une file de travail : une
  /// demande pour août reçue en juin attend une réponse en juin.
  final int demandesEnAttente;
}
