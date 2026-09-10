import 'package:flutter/material.dart';

import '../../../core/theme/ferha_colors.dart';
import '../../../core/theme/ferha_radii.dart';
import '../nouvelle_salle.dart';

/// « Étape 4 sur 5 », et une barre qui se remplit (écran 10 des maquettes).
///
/// Le chiffre ET la barre, pas l'un ou l'autre : la barre dit d'un coup d'œil
/// combien il reste, le chiffre dit exactement où l'on est. C'est ce que fait
/// l'écran 10, qui écrit « Étape 4 sur 5 » en toutes lettres.
///
/// PARTAGÉE ENTRE DEUX ÉCRANS, ET C'EST POUR CELA QU'ELLE A DÉMÉNAGÉ ICI. Le
/// formulaire porte les quatre premières étapes, l'écran des photos la
/// cinquième ; deux exemplaires de cette barre finiraient par ne plus compter
/// pareil, et le propriétaire verrait « étape 5 sur 4 » un jour de refonte.
class ProgressionPublication extends StatelessWidget {
  /// Crée la barre de progression.
  const ProgressionPublication({required this.rang, super.key});

  /// Le rang de l'étape en cours, à partir de un.
  final int rang;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Étape $rang sur ${EtapePublication.total}',
            style: text.labelSmall?.copyWith(
              color: colors.inkTertiary,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: FerhaRadii.chipBorder,
            child: LinearProgressIndicator(
              value: rang / EtapePublication.total,
              minHeight: 6,
              backgroundColor: colors.surfaceSecondary,
              color: colors.primary,
            ),
          ),
        ],
      ),
    );
  }
}
