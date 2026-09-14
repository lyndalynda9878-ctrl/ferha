import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/formats_ferha.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/widgets/photo_salle.dart';
import '../../../core/theme/ferha_colors.dart';
import '../../../core/theme/ferha_radii.dart';
import '../search_providers.dart';
import '../venue_summary.dart';

/// Carte de salle des maquettes (écrans 1 et 2).
///
/// Photo, nom, commune et capacité, puces d'équipements, puis le prix et la
/// note sur une même ligne de pied.
class VenueCard extends ConsumerWidget {
  /// Crée une carte de salle.
  const VenueCard({
    required this.salle,
    this.dense = false,
    this.onTap,
    super.key,
  });

  /// La salle à montrer.
  final VenueSummary salle;

  /// Version compacte, sans les puces d'équipements — c'est celle de l'écran
  /// d'accueil, où la carte n'est qu'un aperçu.
  final bool dense;

  /// Ouvre la fiche. `null` tant que la fiche n'existe pas.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;
    final textes = AppLocalizations.of(context);

    // Le libellé d'un équipement dépend de la langue, son code non : les
    // libellés viennent donc du référentiel, jamais de la carte.
    final libelles =
        ref.watch(equipementsProvider).value ?? const <String, String>{};

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            PhotoSalle(
              chemin: salle.photoCouverture,
              hauteur: dense ? 108 : 140,
            ),
            Padding(
              padding: const EdgeInsetsDirectional.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    salle.nom,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    textes.carteCommuneEtCapacite(
                      salle.commune,
                      '${salle.capacite}',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(color: colors.inkSecondary),
                  ),

                  if (!dense) ...<Widget>[
                    const SizedBox(height: 10),
                    _Equipements(salle: salle, libelles: libelles),
                  ],

                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Expanded(
                        child: _Prix(salle: salle, dense: dense),
                      ),
                      // Pas d'étoiles quand il n'y a pas d'avis. Une salle
                      // neuve n'est pas une salle mal notée.
                      if (salle.estNotee) _Note(salle: salle),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Les puces d'équipements, plus le parking.
///
/// Le parking n'est pas un équipement — il vit dans `venues.parking_spaces`,
/// qui dit aussi combien de places. C'est de là que vient la puce
/// « Parking 60 » des maquettes.
class _Equipements extends StatelessWidget {
  const _Equipements({required this.salle, required this.libelles});

  final VenueSummary salle;
  final Map<String, String> libelles;

  @override
  Widget build(BuildContext context) {
    final places = salle.placesParking;
    final textes = AppLocalizations.of(context);

    final etiquettes = <String>[
      // NULL veut dire « non renseigné », 0 veut dire « pas de parking » : on
      // n'annonce un parking que s'il y en a vraiment un.
      if (places != null && places > 0) textes.cartePuceParking('$places'),
      // Les codes inconnus du référentiel sont tus plutôt que montrés bruts.
      ...salle.equipements.map((code) => libelles[code]).whereType<String>(),
    ];

    if (etiquettes.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: etiquettes
          .take(4)
          .map((e) => _Puce(libelle: e))
          .toList(growable: false),
    );
  }
}

class _Puce extends StatelessWidget {
  const _Puce({required this.libelle});

  final String libelle;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;

    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: 10,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceSecondary,
        borderRadius: FerhaRadii.chipBorder,
        border: Border.all(color: colors.rule),
      ),
      child: Text(
        libelle,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: colors.inkSecondary),
      ),
    );
  }
}

/// Le prix, déjà calculé pour la date demandée.
class _Prix extends StatelessWidget {
  const _Prix({required this.salle, required this.dense});

  final VenueSummary salle;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;
    final textes = AppLocalizations.of(context);
    final formats = FormatsFerha(textes);

    // « DA / soirée » sur l'accueil, où aucune date n'est encore choisie ;
    // « DA » seul dans les résultats, où le prix vaut pour LA date demandée.
    //
    // LE NOMBRE ET LA DEVISE SONT DEUX MORCEAUX PARCE QU'ILS N'ONT PAS LE MÊME
    // STYLE : le montant est gras et coloré, « DA / soirée » discret. C'est la
    // seule raison pour laquelle `devise` existe à côté de `montantEnDinars`.
    final suffixe = dense
        ? ' ${textes.devise} / ${_creneauEnMots(textes, salle.creneauPrix)}'
        : ' ${textes.devise}';

    return Text.rich(
      TextSpan(
        children: <InlineSpan>[
          TextSpan(
            text: formats.nombre(salle.prix),
            style: text.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.primaryDeep,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          TextSpan(
            text: suffixe,
            style: text.bodySmall?.copyWith(color: colors.inkTertiary),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

String _creneauEnMots(AppLocalizations textes, String code) => switch (code) {
  'midi' => textes.creneauMidiMinuscule,
  'journee' => textes.creneauJourneeMinuscule,
  _ => textes.creneauSoirMinuscule,
};

/// La note, affichée seulement quand la salle en a une.
class _Note extends StatelessWidget {
  const _Note({required this.salle});

  final VenueSummary salle;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    // VIRGULE DÉCIMALE, ET DANS LES DEUX LANGUES. On écrit 4,6 en français,
    // et l'Algérie écrit 4,6 en arabe aussi — la virgule décimale y est celle
    // de l'école et des factures. Ce n'est donc pas une valeur à traduire : les
    // chiffres restent latins (§10), et leur séparateur avec eux.
    final note = salle.note!.toStringAsFixed(1).replaceAll('.', ',');

    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.star_rounded, size: 16, color: colors.gold),
          const SizedBox(width: 3),
          Text(
            note,
            style: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 3),
          Text(
            '(${salle.nombreAvis})',
            style: text.bodySmall?.copyWith(color: colors.inkTertiary),
          ),
        ],
      ),
    );
  }
}
