import 'package:flutter/material.dart';

import 'display_font.dart';
import 'ferha_colors.dart';
import 'ferha_radii.dart';

/// Construit les deux thèmes Material 3 de Ferha à partir de la palette
/// « Ambre & ivoire » (cahier des charges §10.1).
///
/// Les deux thèmes sont livrés dès le premier jour : les rattraper après coup
/// demanderait de rouvrir tous les écrans.
abstract final class FerhaTheme {
  /// Thème clair — fond ivoire.
  static ThemeData light() => _build(Brightness.light, FerhaColors.light);

  /// Thème sombre.
  static ThemeData dark() => _build(Brightness.dark, FerhaColors.dark);

  static ThemeData _build(Brightness brightness, FerhaColors colors) {
    final scheme = _colorScheme(brightness, colors);
    final base = ThemeData(
      brightness: brightness,
      colorScheme: scheme,
      useMaterial3: true,
    );

    return base.copyWith(
      extensions: <ThemeExtension<dynamic>>[colors],
      scaffoldBackgroundColor: colors.background,
      canvasColor: colors.background,
      dividerColor: colors.rule,
      textTheme: _textTheme(base.textTheme, colors),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.background,
        foregroundColor: colors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: bricolageGrotesque(
          TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
            color: colors.ink,
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: FerhaRadii.cardBorder,
          side: BorderSide(color: colors.rule),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colors.rule,
        space: 1,
        thickness: 1,
      ),
      // Size(0, 48) ET SURTOUT PAS Size.fromHeight(48).
      //
      // Les deux posent la meme hauteur minimale, mais `Size.fromHeight`
      // vaut `Size(double.infinity, 48)` : elle impose aussi une largeur
      // MINIMALE INFINIE. Dans une Column la largeur est bornee par le
      // parent, le bouton la prend toute, et tout va bien - c'est ce qui
      // rendait le piege invisible. Dans une Row, une Wrap ou les actions
      // d'un AlertDialog, l'enfant recoit une largeur non bornee : le
      // ConstrainedBox du bouton exige alors l'infini, et le rendu echoue
      // sur « BoxConstraints forces an infinite width » - ecran blanc.
      //
      // La hauteur se pose donc ici, et la pleine largeur s'ecrit la ou on
      // la veut, dans un SizedBox. Une largeur ne se decide pas depuis un
      // theme : elle depend du parent, que le theme ne connait pas.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: 20,
            vertical: 12,
          ),
          shape: const RoundedRectangleBorder(
            borderRadius: FerhaRadii.cardBorder,
          ),
          textStyle: bricolageGrotesque(
            const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.primaryDeep,
          // Meme raison qu'au-dessus.
          minimumSize: const Size(0, 48),
          side: BorderSide(color: colors.rule),
          shape: const RoundedRectangleBorder(
            borderRadius: FerhaRadii.cardBorder,
          ),
          textStyle: bricolageGrotesque(
            const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.primaryDeep,
          shape: const RoundedRectangleBorder(
            borderRadius: FerhaRadii.cardBorder,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colors.surfaceSecondary,
        selectedColor: colors.primarySoft,
        disabledColor: colors.surfaceSecondary,
        labelStyle: TextStyle(color: colors.inkSecondary, fontSize: 13),
        secondaryLabelStyle: TextStyle(color: colors.primaryDeep, fontSize: 13),
        side: BorderSide(color: colors.rule),
        shape: const RoundedRectangleBorder(
          borderRadius: FerhaRadii.chipBorder,
        ),
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: 10,
          vertical: 6,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceSecondary,
        hintStyle: TextStyle(color: colors.inkTertiary),
        contentPadding: const EdgeInsetsDirectional.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: FerhaRadii.cardBorder,
          borderSide: BorderSide(color: colors.rule),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: FerhaRadii.cardBorder,
          borderSide: BorderSide(color: colors.rule),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: FerhaRadii.cardBorder,
          borderSide: BorderSide(color: colors.primary, width: 1.5),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: colors.primarySoft,
        indicatorShape: const RoundedRectangleBorder(
          borderRadius: FerhaRadii.chipBorder,
        ),
        elevation: 0,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected)
                ? colors.primaryDeep
                : colors.inkTertiary,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w400,
            color: states.contains(WidgetState.selected)
                ? colors.primaryDeep
                : colors.inkTertiary,
          ),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadiusDirectional.vertical(
            top: Radius.circular(FerhaRadii.card),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: FerhaRadii.cardBorder,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.ink,
        contentTextStyle: TextStyle(color: colors.background),
        shape: const RoundedRectangleBorder(
          borderRadius: FerhaRadii.cardBorder,
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static ColorScheme _colorScheme(Brightness brightness, FerhaColors colors) {
    return ColorScheme(
      brightness: brightness,
      primary: colors.primary,
      onPrimary: colors.onPrimary,
      primaryContainer: colors.primarySoft,
      onPrimaryContainer: colors.primaryDeep,
      secondary: colors.rose,
      onSecondary: colors.onPrimary,
      secondaryContainer: colors.roseSoft,
      onSecondaryContainer: colors.roseInk,
      tertiary: colors.gold,
      onTertiary: colors.onPrimary,
      tertiaryContainer: colors.goldSoft,
      onTertiaryContainer: colors.primaryDeep,
      // Le terracotta porte déjà le sens « négatif » de la palette ; Material
      // exige une couleur d'erreur, on lui donne celle-là plutôt qu'un rouge
      // hors charte.
      error: colors.slotBooked,
      onError: colors.onPrimary,
      errorContainer: colors.slotBookedSoft,
      onErrorContainer: colors.slotBooked,
      surface: colors.surface,
      onSurface: colors.ink,
      surfaceContainerLowest: colors.surface,
      surfaceContainerLow: colors.background,
      surfaceContainer: colors.background,
      surfaceContainerHigh: colors.surfaceSecondary,
      surfaceContainerHighest: colors.surfaceSecondary,
      onSurfaceVariant: colors.inkSecondary,
      outline: colors.rule,
      outlineVariant: colors.ruleSoft,
      shadow: colors.ink,
      scrim: colors.ink,
      inverseSurface: colors.ink,
      onInverseSurface: colors.background,
      inversePrimary: colors.primarySoft,
    );
  }

  /// Bricolage Grotesque pour les titres et les chiffres, police système pour
  /// le corps de texte.
  static TextTheme _textTheme(TextTheme base, FerhaColors colors) {
    TextStyle display(TextStyle? style, double size, FontWeight weight) {
      return bricolageGrotesque(
        (style ?? const TextStyle()).copyWith(
          fontSize: size,
          fontWeight: weight,
          letterSpacing: -0.2,
          color: colors.ink,
        ),
      );
    }

    TextStyle body(TextStyle? style, double size, Color color) {
      return (style ?? const TextStyle()).copyWith(
        fontSize: size,
        height: 1.45,
        color: color,
      );
    }

    return base.copyWith(
      displayLarge: display(base.displayLarge, 40, FontWeight.w800),
      displayMedium: display(base.displayMedium, 34, FontWeight.w800),
      displaySmall: display(base.displaySmall, 28, FontWeight.w700),
      headlineLarge: display(base.headlineLarge, 26, FontWeight.w700),
      headlineMedium: display(base.headlineMedium, 22, FontWeight.w700),
      headlineSmall: display(base.headlineSmall, 20, FontWeight.w700),
      titleLarge: display(base.titleLarge, 18, FontWeight.w700),
      titleMedium: display(base.titleMedium, 16, FontWeight.w600),
      titleSmall: display(base.titleSmall, 14, FontWeight.w600),
      bodyLarge: body(base.bodyLarge, 16, colors.ink),
      bodyMedium: body(base.bodyMedium, 14, colors.ink),
      bodySmall: body(base.bodySmall, 12, colors.inkSecondary),
      labelLarge: body(base.labelLarge, 14, colors.ink),
      labelMedium: body(base.labelMedium, 12, colors.inkSecondary),
      labelSmall: body(base.labelSmall, 11, colors.inkTertiary),
    );
  }
}
