/// Le thème de l'application : clair, sombre, ou celui du téléphone.
///
/// LE JUMEAU DE `locale_controller.dart`, et délibérément. Même patron — un
/// `Notifier` dont `build()` rend une valeur tout de suite puis la corrige
/// quand l'appareil a répondu —, même fournisseur Riverpod, même `choisir()`
/// qui change l'écran d'abord et écrit ensuite. Les deux répondent à la même
/// question, « comment voulez-vous lire ? », et il n'y avait aucune raison d'y
/// répondre deux fois différemment.
///
/// =============================================================================
/// UNE SEULE DIFFÉRENCE AVEC SON JUMEAU, ET ELLE EST VOULUE
///
/// La langue s'écrit DEUX fois : sur l'appareil et dans `profiles.locale`. Le
/// thème s'écrit une fois, sur l'appareil, et nulle part ailleurs.
///
/// Ce n'est pas une simplification : `profiles.locale` existe parce que la base
/// devra un jour rédiger un courriel et une notification, et qu'il faut bien
/// qu'elle sache dans quelle langue. Aucun courriel n'a de thème. Un thème ne
/// répond pas à qui vous êtes, il répond à l'écran que vous tenez et à la
/// lumière de la pièce — deux choses qui ne suivent pas un compte d'un appareil
/// à l'autre.
///
/// D'où un contrôleur qui ne connaît ni Supabase, ni la session, ni
/// `features/` : il ne lui manque rien. Et c'est une bonne chose par ailleurs —
/// `locale_controller.dart` importe `features/auth/` depuis `core/`, ce qui
/// est un défaut noté pour le J27 ; celui-ci ne le refait pas.
///
/// =============================================================================
/// TROIS ÉTATS DANS LE MODÈLE, DEUX POSITIONS SUR LE BOUTON
///
/// `ThemeMode` en porte exactement trois — `system`, `light`, `dark` — et c'est
/// le type que `MaterialApp.themeMode` attend : rien à traduire entre l'état et
/// ce qui s'affiche, comme `Locale` n'a rien à traduire non plus.
///
/// « Suivre le système » est l'état de la PREMIÈRE VISITE, et il ne disparaît
/// pas quand le bouton existe : quelqu'un dont le téléphone est en sombre doit
/// arriver en sombre, sans rien avoir à demander. Le bouton, lui, n'écrit
/// jamais `system` — il montre vers quoi on va et pose un choix ferme. On ne
/// revient donc à « suivre le système » qu'en effaçant les données du site,
/// et c'est assumé : une troisième position sur un bouton rond de 36 px
/// coûterait plus de confusion qu'elle ne rend de service.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../preferences/preferences_affichage.dart';

/// Le mode de thème actif de l'application.
class ThemeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    // LA LECTURE EST ASYNCHRONE, L'ÉTAT DE DÉPART NE L'EST PAS — exactement
    // comme pour la langue. Mais ici la valeur d'attente est aussi la bonne
    // réponse au premier lancement : `system` affiche déjà ce que le téléphone
    // demande. Personne ne voit donc de clignotement au premier démarrage, et
    // celui qui a choisi « sombre » voit au pire une image de son thème système
    // avant le sien.
    _relireLaPreference();
    return ThemeMode.system;
  }

  Future<void> _relireLaPreference() async {
    final nom = await ref.read(preferencesAffichageProvider).modeTheme();
    final retenu = _modeDepuisNom(nom);
    // `ref.mounted` : l'application peut s'être fermée entre-temps, et un
    // fournisseur jeté n'accepte plus d'état.
    if (retenu != null && ref.mounted) state = retenu;
  }

  /// Fixe le mode actif et le retient sur l'appareil.
  ///
  /// L'ORDRE COMPTE, comme pour la langue : l'écran change d'abord, le stockage
  /// ensuite. Ce qui est long ou faillible vient après ce qui est instantané
  /// et sûr.
  Future<void> choisir(ThemeMode mode) async {
    state = mode;
    await ref.read(preferencesAffichageProvider).retenirModeTheme(mode.name);
  }
}

/// Le [ThemeMode] d'un nom retenu, ou `null` s'il n'est d'aucun des trois.
///
/// `ThemeMode.values.byName` ferait le même travail et LÈVERAIT sur une valeur
/// inconnue. Ce qu'on lit vient d'un fichier en clair sur l'appareil, que
/// n'importe quelle extension de navigateur peut écrire : on rend `null`, et
/// l'application reste sur le thème du système.
ThemeMode? _modeDepuisNom(String? nom) {
  if (nom == null) return null;
  for (final mode in ThemeMode.values) {
    if (mode.name == nom) return mode;
  }
  return null;
}

/// Le mode de thème actif de l'application.
final modeThemeProvider = NotifierProvider<ThemeController, ThemeMode>(
  ThemeController.new,
);
