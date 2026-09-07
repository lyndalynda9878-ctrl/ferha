import 'package:flutter/material.dart';

/// Rayons d'arrondi de l'identité visuelle (cahier des charges §10.1).
///
/// 10 px pour les images, 12 px pour les cartes et les boutons, 20 px pour les
/// puces. Aucun autre rayon ne doit apparaître dans un écran.
abstract final class FerhaRadii {
  /// Images et vignettes.
  static const double image = 10;

  /// Cartes, boutons, champs de saisie, feuilles modales.
  static const double card = 12;

  /// Puces (chips) et pastilles.
  static const double chip = 20;

  /// [BorderRadius] des images.
  static const BorderRadius imageBorder = BorderRadius.all(
    Radius.circular(image),
  );

  /// [BorderRadius] des cartes et des boutons.
  static const BorderRadius cardBorder = BorderRadius.all(
    Radius.circular(card),
  );

  /// [BorderRadius] des puces.
  static const BorderRadius chipBorder = BorderRadius.all(
    Radius.circular(chip),
  );
}
