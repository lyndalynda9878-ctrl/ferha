import 'package:flutter/material.dart';

/// Palette « Ambre & ivoire » (cahier des charges §10.1).
///
/// C'est le **seul** endroit du projet où une valeur hexadécimale est écrite.
/// Les écrans lisent les couleurs via `Theme.of(context).extension<FerhaColors>()`
/// — ou, plus court, via `context.ferhaColors`.
///
/// Règle la plus importante de la palette : rien n'est jamais posé sur du blanc
/// pur. C'est le fond ivoire qui donne le calme.
@immutable
class FerhaColors extends ThemeExtension<FerhaColors> {
  const FerhaColors({
    required this.primary,
    required this.primaryDeep,
    required this.primarySoft,
    required this.onPrimary,
    required this.background,
    required this.surface,
    required this.surfaceSecondary,
    required this.rose,
    required this.roseSoft,
    required this.roseInk,
    required this.gold,
    required this.goldSoft,
    required this.ink,
    required this.inkSecondary,
    required this.inkTertiary,
    required this.rule,
    required this.ruleSoft,
    required this.slotFree,
    required this.slotFreeSoft,
    required this.slotBooked,
    required this.slotBookedSoft,
    required this.slotUnavailable,
    required this.slotUnavailableSoft,
  });

  /// Ambre. Boutons, onglet actif, en-têtes.
  final Color primary;

  /// Ambre foncé. Prix, liens, titres d'accent.
  final Color primaryDeep;

  /// Ambre doux. Fonds d'encart, puce sélectionnée.
  final Color primarySoft;

  /// Encre posée sur [primary].
  final Color onPrimary;

  /// Ivoire. Fond de toutes les pages. Jamais du blanc pur.
  final Color background;

  /// Cartes, feuilles modales.
  final Color surface;

  /// Champs de saisie, puces neutres.
  final Color surfaceSecondary;

  /// Rose poudré. Puces d'équipement, encarts de conseil.
  final Color rose;

  /// Fond des encarts rose poudré.
  final Color roseSoft;

  /// Encre posée sur [roseSoft].
  final Color roseInk;

  /// Or. Étoiles de notation, et rien d'autre.
  final Color gold;

  /// Fond des encarts « or ».
  final Color goldSoft;

  /// Encre principale, brun chaud plutôt que noir.
  final Color ink;

  /// Descriptions, légendes.
  final Color inkSecondary;

  /// Méta-informations discrètes.
  final Color inkTertiary;

  /// Bordures de cartes, séparateurs.
  final Color rule;

  /// Séparateurs internes, plus discrets que [rule].
  final Color ruleSoft;

  /// Sauge — créneau libre. Calendrier et états de réservation uniquement.
  final Color slotFree;

  /// Fond du créneau libre.
  final Color slotFreeSoft;

  /// Terracotta — créneau réservé. Calendrier et états de réservation
  /// uniquement.
  final Color slotBooked;

  /// Fond du créneau réservé.
  final Color slotBookedSoft;

  /// Créneau indisponible. Calendrier et états de réservation uniquement.
  final Color slotUnavailable;

  /// Fond du créneau indisponible.
  final Color slotUnavailableSoft;

  /// Palette du thème clair.
  static const FerhaColors light = FerhaColors(
    primary: Color(0xFFA06B22),
    primaryDeep: Color(0xFF7A5015),
    primarySoft: Color(0xFFF6E6CE),
    onPrimary: Color(0xFFFFFFFF),
    background: Color(0xFFFAF5EC),
    surface: Color(0xFFFFFCF6),
    surfaceSecondary: Color(0xFFF8EDDD),
    rose: Color(0xFFC98F92),
    roseSoft: Color(0xFFF7E9E7),
    roseInk: Color(0xFF8A4552),
    gold: Color(0xFFB8862B),
    goldSoft: Color(0xFFF6E6CE),
    ink: Color(0xFF2A2118),
    inkSecondary: Color(0xFF5C5044),
    inkTertiary: Color(0xFF968878),
    rule: Color(0xFFEFE1CB),
    ruleSoft: Color(0xFFF5EADA),
    slotFree: Color(0xFF5C7F5A),
    slotFreeSoft: Color(0xFFE7EFE3),
    slotBooked: Color(0xFFB4574B),
    slotBookedSoft: Color(0xFFF8E5E0),
    slotUnavailable: Color(0xFF968878),
    slotUnavailableSoft: Color(0xFFF8EDDD),
  );

  /// Palette du thème sombre.
  static const FerhaColors dark = FerhaColors(
    primary: Color(0xFFE0A94E),
    primaryDeep: Color(0xFFF0C782),
    primarySoft: Color(0xFF33280F),
    onPrimary: Color(0xFF17130F),
    background: Color(0xFF17130F),
    surface: Color(0xFF211B17),
    surfaceSecondary: Color(0xFF2A231C),
    rose: Color(0xFFD79AA2),
    roseSoft: Color(0xFF2E1F21),
    roseInk: Color(0xFFF0C0C4),
    gold: Color(0xFFE0A94E),
    goldSoft: Color(0xFF33280F),
    ink: Color(0xFFF2EBE4),
    inkSecondary: Color(0xFFBDB0A6),
    inkTertiary: Color(0xFF8F827C),
    rule: Color(0xFF332A24),
    ruleSoft: Color(0xFF2A231C),
    slotFree: Color(0xFF7FA97C),
    slotFreeSoft: Color(0xFF1E2A1C),
    slotBooked: Color(0xFFDE8A7C),
    slotBookedSoft: Color(0xFF2E1D1A),
    slotUnavailable: Color(0xFF8F827C),
    slotUnavailableSoft: Color(0xFF2A231C),
  );

  @override
  FerhaColors copyWith({
    Color? primary,
    Color? primaryDeep,
    Color? primarySoft,
    Color? onPrimary,
    Color? background,
    Color? surface,
    Color? surfaceSecondary,
    Color? rose,
    Color? roseSoft,
    Color? roseInk,
    Color? gold,
    Color? goldSoft,
    Color? ink,
    Color? inkSecondary,
    Color? inkTertiary,
    Color? rule,
    Color? ruleSoft,
    Color? slotFree,
    Color? slotFreeSoft,
    Color? slotBooked,
    Color? slotBookedSoft,
    Color? slotUnavailable,
    Color? slotUnavailableSoft,
  }) {
    return FerhaColors(
      primary: primary ?? this.primary,
      primaryDeep: primaryDeep ?? this.primaryDeep,
      primarySoft: primarySoft ?? this.primarySoft,
      onPrimary: onPrimary ?? this.onPrimary,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceSecondary: surfaceSecondary ?? this.surfaceSecondary,
      rose: rose ?? this.rose,
      roseSoft: roseSoft ?? this.roseSoft,
      roseInk: roseInk ?? this.roseInk,
      gold: gold ?? this.gold,
      goldSoft: goldSoft ?? this.goldSoft,
      ink: ink ?? this.ink,
      inkSecondary: inkSecondary ?? this.inkSecondary,
      inkTertiary: inkTertiary ?? this.inkTertiary,
      rule: rule ?? this.rule,
      ruleSoft: ruleSoft ?? this.ruleSoft,
      slotFree: slotFree ?? this.slotFree,
      slotFreeSoft: slotFreeSoft ?? this.slotFreeSoft,
      slotBooked: slotBooked ?? this.slotBooked,
      slotBookedSoft: slotBookedSoft ?? this.slotBookedSoft,
      slotUnavailable: slotUnavailable ?? this.slotUnavailable,
      slotUnavailableSoft: slotUnavailableSoft ?? this.slotUnavailableSoft,
    );
  }

  @override
  FerhaColors lerp(covariant FerhaColors? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return FerhaColors(
      primary: mix(primary, other.primary),
      primaryDeep: mix(primaryDeep, other.primaryDeep),
      primarySoft: mix(primarySoft, other.primarySoft),
      onPrimary: mix(onPrimary, other.onPrimary),
      background: mix(background, other.background),
      surface: mix(surface, other.surface),
      surfaceSecondary: mix(surfaceSecondary, other.surfaceSecondary),
      rose: mix(rose, other.rose),
      roseSoft: mix(roseSoft, other.roseSoft),
      roseInk: mix(roseInk, other.roseInk),
      gold: mix(gold, other.gold),
      goldSoft: mix(goldSoft, other.goldSoft),
      ink: mix(ink, other.ink),
      inkSecondary: mix(inkSecondary, other.inkSecondary),
      inkTertiary: mix(inkTertiary, other.inkTertiary),
      rule: mix(rule, other.rule),
      ruleSoft: mix(ruleSoft, other.ruleSoft),
      slotFree: mix(slotFree, other.slotFree),
      slotFreeSoft: mix(slotFreeSoft, other.slotFreeSoft),
      slotBooked: mix(slotBooked, other.slotBooked),
      slotBookedSoft: mix(slotBookedSoft, other.slotBookedSoft),
      slotUnavailable: mix(slotUnavailable, other.slotUnavailable),
      slotUnavailableSoft: mix(slotUnavailableSoft, other.slotUnavailableSoft),
    );
  }
}

/// Raccourci de lecture de la palette depuis un écran.
extension FerhaColorsContext on BuildContext {
  /// La palette « Ambre & ivoire » du thème courant.
  FerhaColors get ferhaColors => Theme.of(this).extension<FerhaColors>()!;
}
