import 'package:flutter/material.dart';

/// Famille de la police d'affichage, telle que déclarée dans `pubspec.yaml`.
const String ferhaDisplayFontFamily = 'Bricolage Grotesque';

/// Bornes de l'axe de graisse du fichier variable.
const double _minWeight = 200;
const double _maxWeight = 800;

/// Bornes de l'axe de taille optique du fichier variable.
const double _minOpticalSize = 12;
const double _maxOpticalSize = 96;

/// Habille un style de texte avec Bricolage Grotesque.
///
/// La police est embarquée en un seul fichier variable
/// (`assets/fonts/BricolageGrotesque-Variable.ttf`, SIL OFL 1.1). Ses valeurs
/// par défaut sont en haut de plage — `wght` 800, `opsz` 96 — donc les deux
/// axes sont toujours pilotés explicitement, sinon tout s'afficherait en très
/// gras à la taille d'un titre d'affiche :
///
/// - `wght` suit le [TextStyle.fontWeight] demandé ;
/// - `opsz` suit la taille du texte, ce à quoi sert la taille optique : des
///   formes plus ouvertes en petit corps, plus serrées en grand titre.
///
/// `fontWeight` reste posé sur le style : c'est lui que lisent la synthèse de
/// graisse d'une police de secours et les outils d'accessibilité.
TextStyle bricolageGrotesque(TextStyle base) {
  final weight = base.fontWeight ?? FontWeight.w400;
  final size = base.fontSize ?? 14;

  return base.copyWith(
    fontFamily: ferhaDisplayFontFamily,
    fontVariations: <FontVariation>[
      FontVariation(
        'wght',
        weight.value.toDouble().clamp(_minWeight, _maxWeight),
      ),
      FontVariation('opsz', size.clamp(_minOpticalSize, _maxOpticalSize)),
    ],
  );
}
