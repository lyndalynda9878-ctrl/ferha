import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../supabase/supabase_providers.dart';
import '../theme/ferha_colors.dart';

/// Résout un `venue_photos.storage_path` en URL affichable.
///
/// LA RÈGLE DU DÉPÔT, et son seul endroit : une valeur qui commence par `http`
/// est une URL complète et s'affiche telle quelle — c'est le cas des salles de
/// démonstration, entorse assumée au §7.3 ; sinon c'est un chemin dans le
/// bucket `venue-photos` et on le résout.
///
/// Le jour où les vraies photos arriveront, rien à changer : les nouvelles
/// lignes porteront un chemin, les anciennes disparaîtront avec le reset.
String urlPhoto(WidgetRef ref, String chemin) {
  if (chemin.startsWith('http')) return chemin;
  return ref
      .watch(supabaseClientProvider)
      .storage
      .from('venue-photos')
      .getPublicUrl(chemin);
}

/// Une photo de salle, avec son repli.
///
/// Une photo absente et une photo qui ne charge pas donnent le même bloc : la
/// carte ne doit jamais se trouer, et l'écran ne doit jamais sauter.
class PhotoSalle extends ConsumerWidget {
  /// Crée une photo de salle.
  const PhotoSalle({
    required this.chemin,
    this.hauteur,
    this.fit = BoxFit.cover,
    this.tailleIcone = 28,
    super.key,
  });

  /// Chemin ou URL. `null` affiche directement le repli.
  final String? chemin;

  /// Hauteur imposée. `null` laisse le parent décider.
  final double? hauteur;

  /// Comment l'image remplit sa boîte.
  final BoxFit fit;

  /// Taille de l'icône du repli.
  final double tailleIcone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chemin = this.chemin;
    if (chemin == null || chemin.isEmpty) return _repli(context);

    return Image.network(
      urlPhoto(ref, chemin),
      height: hauteur,
      width: double.infinity,
      fit: fit,
      errorBuilder: (_, _, _) => _repli(context),
      loadingBuilder: (context, enfant, progression) =>
          progression == null ? enfant : _repli(context),
    );
  }

  Widget _repli(BuildContext context) {
    final colors = context.ferhaColors;
    return Container(
      height: hauteur,
      width: double.infinity,
      color: colors.surfaceSecondary,
      alignment: AlignmentDirectional.center,
      child: Icon(
        Icons.image_outlined,
        size: tailleIcone,
        color: colors.inkTertiary,
      ),
    );
  }
}
