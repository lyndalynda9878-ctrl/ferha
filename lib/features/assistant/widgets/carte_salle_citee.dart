import 'package:flutter/material.dart';

import '../../../core/theme/ferha_colors.dart';
import '../../../core/theme/ferha_radii.dart';
import '../../../core/widgets/photo_salle.dart';
import '../../search/search_filters.dart';
import '../message_assistant.dart';

/// La clé de la carte d'une salle citée — les tests s'en servent pour taper
/// dessus et vérifier quelle fiche s'ouvre.
Key cleCarteSalleCitee(String venueId) => Key('assistant-salle-$venueId');

/// La vignette d'une salle citée par l'assistant (maquettes, écran 8).
///
/// PHOTO, NOM, COMMUNE, PRIX — et rien d'autre. C'est la maquette, et c'est
/// aussi ce qui tient dans 120 pixels de large sans devenir illisible. Les
/// équipements et la note sont sur la FICHE, à un appui de là.
///
/// LE PRIX VIENT DE LA RÉPONSE DE LA FONCTION. Rien n'est calculé ici — pas de
/// coefficient, pas d'arrondi, pas de conversion. Il a été calculé une fois par
/// `estimate_price()`, et c'est ce nombre-là qui s'affiche. Un prix recalculé
/// en Dart serait une seconde source de vérité, et l'écart se verrait à la
/// première salle ouverte.
///
/// UNE SALLE SANS PRIX N'AFFICHE PAS « 0 ». Elle n'affiche rien : la base ne lui
/// connaît pas de tarif pour ce créneau, et un zéro serait une affirmation
/// fausse — la pire sorte, puisqu'elle donne envie de cliquer.
class CarteSalleCitee extends StatelessWidget {
  /// Crée la vignette.
  const CarteSalleCitee({required this.salle, required this.onTap, super.key});

  /// La salle citée, telle que la fonction l'a rendue.
  final SalleCitee salle;

  /// Ouvre sa fiche.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    return SizedBox(
      width: 150,
      child: Material(
        color: colors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: FerhaRadii.cardBorder,
          side: BorderSide(color: colors.ruleSoft),
        ),
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              PhotoSalle(chemin: salle.photo, hauteur: 66, tailleIcone: 20),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(9, 7, 9, 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    // LE NOM S'ÉCRIT COMME LA BASE LE PORTE, en écriture latine,
                    // même quand la réponse au-dessus est en arabe. C'est la
                    // règle 9 du prompt de l'agent, et elle a d'abord une raison
                    // d'usage : c'est ce nom-là qui est écrit sur l'enseigne, et
                    // celui qu'on retrouvera dans la recherche.
                    Text(
                      salle.nom,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      salle.sousTitre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(
                        color: colors.inkTertiary,
                      ),
                    ),
                    if (salle.prix != null) ...<Widget>[
                      const SizedBox(height: 5),
                      Text(
                        '${montantEnDinars(salle.prix!)} DA',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colors.primaryDeep,
                          fontFeatures: const <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
