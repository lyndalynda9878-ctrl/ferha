import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Fabrique de la police d'affichage : reçoit un style de base et le rend
/// habillé de la police des titres.
typedef DisplayFont = TextStyle Function(TextStyle base);

/// Bricolage Grotesque, servie par `google_fonts`.
///
/// C'est la police d'affichage de production : titres et chiffres. Le corps de
/// texte reste sur la police système (cahier des charges §10.1).
TextStyle bricolageGrotesque(TextStyle base) {
  return GoogleFonts.bricolageGrotesque(textStyle: base);
}

/// Police d'affichage neutre : la police système, sans habillage.
///
/// `google_fonts` télécharge Bricolage Grotesque au premier lancement. Un test
/// ou une intégration continue n'ont pas de réseau : ils construisent le thème
/// avec cette fabrique-ci, ce qui laisse tout le reste du thème identique.
TextStyle systemDisplayFont(TextStyle base) => base;
