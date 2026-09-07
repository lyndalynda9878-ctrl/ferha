import 'package:flutter/material.dart';

import '../theme/ferha_colors.dart';

/// Écran vide du socle.
///
/// Chaque onglet en affiche un en attendant sa vraie implémentation. Aucun
/// contenu métier, aucune donnée de salle.
class PlaceholderScreen extends StatelessWidget {
  /// Crée l'écran vide d'un onglet.
  const PlaceholderScreen({required this.title, required this.icon, super.key});

  /// Nom de l'onglet, affiché en titre.
  final String title;

  /// Icône de l'onglet, reprise en filigrane.
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 48, color: colors.inkTertiary),
              const SizedBox(height: 16),
              Text(title, style: text.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'Écran à construire.',
                style: text.bodyMedium?.copyWith(color: colors.inkSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
