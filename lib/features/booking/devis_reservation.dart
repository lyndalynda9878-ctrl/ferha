import 'package:flutter/foundation.dart';

import '../venue/venue_detail.dart';

/// Le devis d'une demande, tel que le renvoie `booking_quote()`.
///
/// TOUS LES MONTANTS DE CE TYPE VIENNENT DE LA BASE, sans exception. Il n'y a
/// pas une addition, pas une multiplication, pas un pourcentage calculé dans
/// ce fichier ni dans l'écran qui l'affiche — la règle du projet est que le
/// prix vient d'`estimate_price()` et de nulle part ailleurs (§5.2), et
/// l'acompte de `deposit_rate()`.
///
/// C'est aussi pourquoi ce type ne porte aucun `copyWith` : on ne modifie pas
/// un devis, on en redemande un. Chaque case cochée rappelle `booking_quote()`.
@immutable
class DevisReservation {
  /// Crée un devis.
  const DevisReservation({
    required this.date,
    required this.creneau,
    required this.invites,
    required this.prixBase,
    required this.coefJour,
    required this.coefSaison,
    required this.prixCreneau,
    required this.couvertsInclus,
    required this.couvertsSup,
    required this.montantCouvertsSup,
    required this.montantOptions,
    required this.total,
    required this.tauxAcompte,
    required this.montantAcompte,
    required this.options,
  });

  /// Construit depuis le JSON de `booking_quote()`.
  factory DevisReservation.depuisJson(Map<String, dynamic> j) =>
      DevisReservation(
        date: DateTime.parse(j['event_date'] as String),
        creneau: j['slot'] as String,
        invites: (j['guest_count'] as num).toInt(),
        prixBase: j['base_price'] as num,
        coefJour: j['day_coef'] as num,
        coefSaison: j['season_coef'] as num,
        prixCreneau: j['slot_price'] as num,
        couvertsInclus: (j['included_seats'] as num).toInt(),
        couvertsSup: (j['extra_seats'] as num).toInt(),
        montantCouvertsSup: j['extra_seats_amount'] as num,
        montantOptions: j['options_amount'] as num,
        total: j['total'] as num,
        tauxAcompte: j['deposit_rate'] as num,
        montantAcompte: j['deposit_amount'] as num,
        options: (j['options'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(OptionSalle.depuisJson)
            .toList(growable: false),
      );

  /// La date sur laquelle porte ce devis.
  final DateTime date;

  /// `midi`, `soir` ou `journee`.
  final String creneau;

  /// Le nombre d'invités qui a servi au calcul.
  final int invites;

  /// Prix de base du créneau, avant majorations.
  final num prixBase;

  /// Coefficient du jour appliqué (§5.2). 1 hors jeudi, vendredi et samedi.
  final num coefJour;

  /// Coefficient de saison appliqué (§5.2).
  final num coefSaison;

  /// Prix du créneau, majorations comprises.
  final num prixCreneau;

  /// Couverts compris dans le prix de base.
  final int couvertsInclus;

  /// Couverts facturés en supplément.
  final int couvertsSup;

  /// Montant du supplément de couverts.
  final num montantCouvertsSup;

  /// Somme des options retenues.
  final num montantOptions;

  /// L'estimation totale.
  final num total;

  /// La part du total demandée en acompte — `0.25` pour 25 %.
  final num tauxAcompte;

  /// Le montant de l'acompte.
  final num montantAcompte;

  /// Les options réellement facturées, nommées par la base.
  ///
  /// C'est cette liste-là, et non les cases cochées à l'écran, qui doit servir
  /// à écrire le récapitulatif : elle dit ce que la base a compté.
  final List<OptionSalle> options;

  /// Vrai si le jour choisi est majoré (jeudi, vendredi ou samedi).
  bool get jourMajore => coefJour > 1;

  /// Vrai si la date tombe en haute saison.
  bool get saisonMajoree => coefSaison > 1;

  /// « 25 » pour un taux de 0,25 — le nombre que la maquette met entre
  /// parenthèses derrière « Acompte à verser ».
  ///
  /// Ce n'est pas un calcul de prix : c'est le même nombre, écrit en pour cent
  /// au lieu d'être écrit en fraction, comme on écrit une date en toutes
  /// lettres. Aucun montant n'en sort.
  String get pourcentageAcompte {
    final pourCent = tauxAcompte * 100;
    return pourCent == pourCent.roundToDouble()
        ? '${pourCent.round()}'
        : pourCent.toStringAsFixed(1).replaceAll('.', ',');
  }
}
