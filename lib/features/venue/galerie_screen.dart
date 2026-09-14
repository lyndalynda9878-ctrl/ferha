import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/ferha_colors.dart';
import '../../core/theme/ferha_radii.dart';
import '../../core/widgets/photo_salle.dart';
import '../search/widgets/etats.dart';
import 'venue_providers.dart';

/// Galerie plein écran (§10, « Galerie plein écran »).
///
/// Fond sombre quel que soit le thème : une photo se regarde sur du noir, et
/// c'est le seul écran de l'application où le fond ivoire ne s'applique pas —
/// il tirerait les couleurs des photos vers le jaune.
///
/// ELLE RELIT SES PHOTOS, ON NE LES LUI TEND PAS.
///
/// La fiche les lui passait par `extra` de go_router, puisqu'elle les avait
/// déjà — une requête d'économisée. Elle coûtait la page : `extra` ne franchit
/// pas l'historique du navigateur, et au retour d'un rechargement la galerie
/// tombait sur un transtypage impossible. On a retiré la dépendance plutôt que
/// de rattraper le transtypage : une page qui a besoin de ce que l'écran
/// précédent lui a tendu ne se partage pas et ne se recharge pas.
class GalerieScreen extends ConsumerStatefulWidget {
  /// Crée la galerie plein écran.
  const GalerieScreen({required this.venueId, this.depart = 0, super.key});

  /// La salle.
  final String venueId;

  /// La photo affichée en premier.
  final int depart;

  @override
  ConsumerState<GalerieScreen> createState() => _GalerieScreenState();
}

class _GalerieScreenState extends ConsumerState<GalerieScreen> {
  late final PageController _controleur = PageController(
    initialPage: widget.depart,
  );
  late int _index = widget.depart;

  @override
  void dispose() {
    _controleur.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fiche = ref.watch(
      ficheProvider(DemandeFiche(venueId: widget.venueId)),
    );

    final colors = context.ferhaColors;

    return fiche.when(
      loading: () => ColoredBox(
        color: colors.galleryBackdrop,
        child: Center(
          child: CircularProgressIndicator(color: colors.onGalleryMuted),
        ),
      ),
      error: (erreur, _) => Scaffold(
        appBar: AppBar(),
        body: EtatErreur(
          erreur: erreur,
          onReessayer: () => ref.invalidate(
            ficheProvider(DemandeFiche(venueId: widget.venueId)),
          ),
        ),
      ),
      data: (salle) => _echafaudage(salle.photos),
    );
  }

  Widget _echafaudage(List<String> photos) {
    final colors = context.ferhaColors;

    if (photos.isEmpty) {
      return Scaffold(
        appBar: AppBar(),
        body: const EtatVide(
          titre: 'Aucune photo',
          explication:
              'Le propriétaire n’a pas encore ajouté de photo à cette salle.',
        ),
      );
    }

    return Scaffold(
      backgroundColor: colors.galleryBackdrop,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: colors.onGallery,
        title: Text(
          '${_index + 1} / ${photos.length}',
          style: TextStyle(
            color: colors.onGallery,
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
      ),
      body: Stack(
        children: <Widget>[
          PageView.builder(
            controller: _controleur,
            itemCount: photos.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) => InteractiveViewer(
              maxScale: 4,
              child: Center(
                child: PhotoSalle(
                  chemin: photos[i],
                  fit: BoxFit.contain,
                  tailleIcone: 48,
                ),
              ),
            ),
          ),
          if (photos.length > 1)
            PositionedDirectional(
              bottom: 0,
              start: 0,
              end: 0,
              child: SafeArea(
                child: _Pastilles(nombre: photos.length, actif: _index),
              ),
            ),
        ],
      ),
    );
  }
}

/// Les pastilles de position, sous les photos.
class _Pastilles extends StatelessWidget {
  const _Pastilles({required this.nombre, required this.actif});

  final int nombre;
  final int actif;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;

    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          for (var i = 0; i < nombre; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsetsDirectional.symmetric(horizontal: 3),
              width: i == actif ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: i == actif ? colors.primary : colors.onGalleryMuted,
                // Rogné à la moitié de la hauteur sur une pastille de 6 px :
                // la capsule est la même, et aucun rayon n'est écrit à la main.
                borderRadius: FerhaRadii.chipBorder,
              ),
            ),
        ],
      ),
    );
  }
}
