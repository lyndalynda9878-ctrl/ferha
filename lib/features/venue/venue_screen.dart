import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/formats_ferha.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/router/routes.dart';
import '../../core/theme/ferha_colors.dart';
import '../../core/theme/ferha_radii.dart';
import '../../core/widgets/photo_salle.dart';
import '../owner/gerer_ma_salle.dart';
import '../owner/owner_providers.dart';
import '../reviews/widgets/etoiles.dart';
import '../search/search_filters.dart';
import '../search/widgets/etats.dart';
import 'venue_detail.dart';
import 'venue_providers.dart';

/// Écran 3 des maquettes — la fiche salle (§4.2, CLI-03).
///
/// « La question "combien ça me coûte" ne doit jamais demander de scroller. »
/// D'où la barre d'action collée en bas : elle porte l'estimation pour les
/// critères de recherche et le bouton « Disponibilité », et reste visible quoi
/// qu'il arrive au défilement.
///
/// LE TÉLÉPHONE DU PROPRIÉTAIRE N'APPARAÎT NULLE PART, ni son nom. C'est la
/// règle du §9 : il n'est révélé qu'après acceptation d'une demande — « sinon
/// la plateforme se fait contourner dès la première recherche ». Le modèle
/// `VenueDetail` ne porte d'ailleurs aucun champ de propriétaire, et la
/// fonction SQL n'en renvoie aucun : ce n'est pas un oubli d'affichage, c'est
/// une absence de bout en bout.
///
/// Consultable sans compte : c'est l'étape 2 du parcours du §3.
class VenueScreen extends ConsumerWidget {
  /// Crée la fiche salle.
  const VenueScreen({
    required this.venueId,
    this.date,
    this.invites,
    this.creneau = Creneau.soir,
    super.key,
  });

  /// La salle à afficher.
  final String venueId;

  /// La date cherchée, reprise de la recherche.
  final DateTime? date;

  /// Le nombre d'invités cherché.
  final int? invites;

  /// Le créneau cherché — celui dont le prix s'affiche en bas.
  final Creneau creneau;

  DemandeFiche get _demande =>
      DemandeFiche(venueId: venueId, date: date, invites: invites);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fiche = ref.watch(ficheProvider(_demande));

    return Scaffold(
      body: fiche.when(
        loading: () => const _Chargement(),
        error: (erreur, _) => Scaffold(
          appBar: AppBar(),
          body: EtatErreur(
            erreur: erreur,
            onReessayer: () => ref.invalidate(ficheProvider(_demande)),
          ),
        ),
        data: (salle) => _Contenu(salle: salle, creneau: creneau),
      ),
      bottomNavigationBar: fiche.maybeWhen(
        data: (salle) => _BarreAction(
          salle: salle,
          creneau: creneau,
          date: date,
          invites: invites,
        ),
        orElse: () => null,
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Le corps défilant
// -----------------------------------------------------------------------------

class _Contenu extends StatelessWidget {
  const _Contenu({required this.salle, required this.creneau});

  final VenueDetail salle;
  final Creneau creneau;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;
    final textes = AppLocalizations.of(context);

    return CustomScrollView(
      slivers: <Widget>[
        _GalerieEnTete(salle: salle),
        SliverPadding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 20, 20, 24),
          sliver: SliverList(
            delegate: SliverChildListDelegate(<Widget>[
              Text(
                salle.nom,
                style: text.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                salle.localisation,
                style: text.bodyMedium?.copyWith(color: colors.inkSecondary),
              ),

              // Pas d'étoiles quand il n'y a pas d'avis (§5.4). Une salle neuve
              // n'est pas une salle mal notée, et « 0,0 (0) » le laisserait
              // croire.
              if (salle.estNotee) ...<Widget>[
                const SizedBox(height: 12),
                _Note(salle: salle),
              ],

              const SizedBox(height: 20),
              _TroisChiffres(salle: salle),

              if (salle.description != null &&
                  salle.description!.trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 24),
                Text(
                  salle.description!,
                  style: text.bodyMedium?.copyWith(height: 1.5),
                ),
              ],

              if (salle.equipements.isNotEmpty) ...<Widget>[
                const SizedBox(height: 24),
                _Intitule(textes.ficheEquipements),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: salle.equipements
                      .map((e) => _PuceEquipement(equipement: e))
                      .toList(growable: false),
                ),
              ],

              if (salle.typesEvenement.isNotEmpty) ...<Widget>[
                const SizedBox(height: 24),
                _Intitule(textes.ficheEvenementsAccueillis),
                const SizedBox(height: 10),
                Text(
                  salle.typesEvenement.map((t) => t.libelle).join(' · '),
                  style: text.bodyMedium?.copyWith(color: colors.inkSecondary),
                ),
              ],

              const SizedBox(height: 24),
              _Intitule(textes.ficheTarifs),
              const SizedBox(height: 10),
              _GrilleTarifaire(salle: salle, creneauMisEnAvant: creneau),
            ]),
          ),
        ),
      ],
    );
  }
}

/// La galerie en tête, repliable au défilement.
class _GalerieEnTete extends StatelessWidget {
  const _GalerieEnTete({required this.salle});

  final VenueDetail salle;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;

    return SliverAppBar(
      expandedHeight: 260,
      pinned: true,
      backgroundColor: colors.surface,
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            PhotoSalle(
              chemin: salle.photos.isEmpty ? null : salle.photos.first,
              tailleIcone: 40,
            ),
            // Un dégradé sous la barre : la flèche de retour doit rester
            // lisible quelle que soit la photo.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: AlignmentDirectional.topCenter,
                  end: AlignmentDirectional.center,
                  colors: <Color>[colors.scrim, Colors.transparent],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        if (salle.photos.length > 1)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: ActionChip(
              avatar: const Icon(Icons.photo_library_outlined, size: 16),
              label: Text(
                AppLocalizations.of(
                  context,
                ).fichePhotos('${salle.photos.length}'),
              ),
              onPressed: () => context.push(
                FerhaRoutes.galerieDe(salle.id),
                extra: salle.photos,
              ),
            ),
          ),
      ],
    );
  }
}

/// Capacité, superficie, parking — les trois chiffres de la maquette.
class _TroisChiffres extends StatelessWidget {
  const _TroisChiffres({required this.salle});

  final VenueDetail salle;

  @override
  Widget build(BuildContext context) {
    final textes = AppLocalizations.of(context);

    return Row(
      children: <Widget>[
        Expanded(
          child: _Chiffre(
            intitule: textes.ficheCapacite,
            valeur: '${salle.capacite}',
            unite: textes.uniteCouverts,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _Chiffre(
            intitule: textes.ficheSuperficie,
            // Non renseignée : on l'écrit, on n'invente pas un zéro.
            valeur: salle.superficie == null ? '—' : '${salle.superficie}',
            unite: salle.superficie == null
                ? textes.superficieNonRenseignee
                : textes.uniteMetresCarres,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _Chiffre(
            intitule: textes.ficheParking,
            // NULL et 0 ne se disent pas pareil : « non renseigné » n'est pas
            // « pas de parking ».
            valeur: salle.placesParking == null
                ? '—'
                : '${salle.placesParking}',
            unite: switch (salle.placesParking) {
              null => textes.parkingNonRenseigne,
              0 => textes.parkingAucunePlace,
              _ => textes.unitePlaces,
            },
          ),
        ),
      ],
    );
  }
}

class _Chiffre extends StatelessWidget {
  const _Chiffre({
    required this.intitule,
    required this.valeur,
    required this.unite,
  });

  final String intitule;
  final String valeur;
  final String unite;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: 10,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceSecondary,
        borderRadius: FerhaRadii.cardBorder,
        border: Border.all(color: colors.ruleSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            intitule.toUpperCase(),
            style: text.labelSmall?.copyWith(
              color: colors.inkTertiary,
              // Zéro en arabe : ses lettres se lient, les écarter casse le mot.
              letterSpacing: context.espacementDesCapitales(1),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            valeur,
            style: text.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          Text(
            unite,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.bodySmall?.copyWith(color: colors.inkTertiary),
          ),
        ],
      ),
    );
  }
}

/// La grille tarifaire, un créneau par ligne, chaque prix déjà calculé.
class _GrilleTarifaire extends StatelessWidget {
  const _GrilleTarifaire({
    required this.salle,
    required this.creneauMisEnAvant,
  });

  final VenueDetail salle;
  final Creneau creneauMisEnAvant;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;
    final textes = AppLocalizations.of(context);
    final formats = FormatsFerha(textes);

    if (salle.tarifs.isEmpty) {
      return Text(
        textes.ficheTarifsAbsents,
        style: text.bodyMedium?.copyWith(color: colors.inkSecondary),
      );
    }

    return Column(
      children: <Widget>[
        for (final tarif in salle.tarifs)
          _LigneTarifaire(
            salle: salle,
            tarif: tarif,
            enAvant: tarif.creneau == creneauMisEnAvant.code,
          ),
        const SizedBox(height: 10),
        Text(
          salle.invites == null
              ? textes.ficheTarifsNote(formats.date(salle.dateEstimation))
              : textes.ficheTarifsNoteInvites(
                  formats.date(salle.dateEstimation),
                  '${salle.invites}',
                ),
          style: text.bodySmall?.copyWith(color: colors.inkTertiary),
        ),
      ],
    );
  }
}

class _LigneTarifaire extends StatelessWidget {
  const _LigneTarifaire({
    required this.salle,
    required this.tarif,
    required this.enAvant,
  });

  final VenueDetail salle;
  final LigneTarif tarif;
  final bool enAvant;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;
    final textes = AppLocalizations.of(context);
    final formats = FormatsFerha(textes);

    // « Soirée · samedi, haute saison » — d'où vient la majoration, plutôt
    // qu'un montant sans explication.
    final contexte = <String>[
      if (tarif.jourMajore) textes.majorationJour,
      if (tarif.saisonMajoree) textes.majorationSaison,
    ];

    return Container(
      margin: const EdgeInsetsDirectional.only(bottom: 8),
      padding: const EdgeInsetsDirectional.all(14),
      decoration: BoxDecoration(
        color: enAvant ? colors.primarySoft : colors.surfaceSecondary,
        borderRadius: FerhaRadii.cardBorder,
        border: Border.all(color: enAvant ? colors.primary : colors.ruleSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      _nomCreneau(textes, tarif.creneau),
                      style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (contexte.isNotEmpty)
                      Text(
                        contexte.join(textes.separateurListe),
                        style: text.bodySmall?.copyWith(
                          color: colors.inkTertiary,
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                formats.montant(tarif.total),
                style: text.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.primaryDeep,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _detailDesCouverts(textes, formats, tarif),
            style: text.bodySmall?.copyWith(color: colors.inkSecondary),
          ),
        ],
      ),
    );
  }
}

String _nomCreneau(AppLocalizations textes, String code) => switch (code) {
  'midi' => textes.creneauMidiPhrase,
  'journee' => textes.creneauJourneePhrase,
  _ => textes.creneauSoirPhrase,
};

/// « 300 couverts compris · au-delà, 1 200 DA le couvert (50 en supplément… ) ».
///
/// En deux clés plutôt qu'une phrase à trous : la partie entre parenthèses
/// n'apparaît que si des couverts dépassent le forfait, et une langue peut
/// vouloir la placer ailleurs dans la phrase.
String _detailDesCouverts(
  AppLocalizations textes,
  FormatsFerha formats,
  LigneTarif tarif,
) {
  final base = textes.tarifCouvertsCompris(
    '${tarif.couvertsInclus}',
    formats.montant(tarif.prixCouvertSup),
  );
  if (tarif.couvertsSup <= 0) return base;
  return textes.tarifCouvertsSupplement(
    base,
    '${tarif.couvertsSup}',
    formats.montant(tarif.montantCouvertsSup),
  );
}

// -----------------------------------------------------------------------------
// La barre d'action
// -----------------------------------------------------------------------------

/// La taille des deux boutons de la barre d'action.
///
/// La même pour « Disponibilité » et pour « Gérer ma salle » : la barre ne doit
/// pas changer de hauteur selon qui regarde la fiche. Elle ne pose qu'une
/// dimension — les couleurs restent celles du thème, seul endroit où elles
/// s'écrivent.
final ButtonStyle _styleBouton = FilledButton.styleFrom(
  padding: const EdgeInsetsDirectional.symmetric(horizontal: 20, vertical: 16),
);

/// Collée en bas, toujours visible.
///
/// « La question "combien ça me coûte" ne doit jamais demander de scroller. »
/// Elle porte le prix du créneau cherché et le bouton « Disponibilité ».
///
/// LE BOUTON NE DEMANDE PAS DE COMPTE. Consulter un calendrier fait partie de
/// la consultation, pas de l'action : la connexion se demandera au moment
/// d'envoyer une demande, et pas avant.
///
/// SAUF CHEZ SOI, OÙ CE N'EST PLUS LA MÊME PORTE. Un propriétaire qui ouvre la
/// fiche de sa propre salle n'a rien à y réserver — `request_booking()` le
/// refuserait (FE005), et le lui apprendre au bas d'un formulaire rempli serait
/// lui avoir fait perdre son temps. Le bouton devient donc « Gérer ma salle ».
/// L'estimation, elle, reste : c'est son tarif, il a le droit de le lire comme
/// ses clients le lisent.
class _BarreAction extends ConsumerWidget {
  const _BarreAction({
    required this.salle,
    required this.creneau,
    required this.date,
    required this.invites,
  });

  final VenueDetail salle;
  final Creneau creneau;
  final DateTime? date;
  final int? invites;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;
    final textes = AppLocalizations.of(context);
    final formats = FormatsFerha(textes);
    final tarif = salle.tarifPour(creneau.code);
    final maSalle = ref.watch(estMaSalleProvider(salle.id));

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 20, 12),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(top: BorderSide(color: colors.rule)),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    invites == null
                        ? textes.ficheEstimationCreneau(
                            creneau.auMilieuDUnePhrase(textes),
                          )
                        : textes.ficheEstimationInvites('$invites'),
                    style: text.labelSmall?.copyWith(
                      color: colors.inkTertiary,
                      letterSpacing: context.espacementDesCapitales(1),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    // Une salle qui ne vend pas ce créneau le dit, plutôt que
                    // d'afficher un prix qui n'existe pas.
                    tarif == null
                        ? textes.creneauNonPropose
                        : formats.montant(tarif.total),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: tarif == null
                          ? colors.inkTertiary
                          : colors.primaryDeep,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (maSalle)
              BoutonGererMaSalle(venueId: salle.id, style: _styleBouton)
            else
              FilledButton(
                onPressed: () => context.push(
                  Uri(
                    path: FerhaRoutes.calendrierDe(salle.id),
                    queryParameters: <String, String>{
                      'creneau': creneau.code,
                      if (date != null) 'date': dateVersIso(date!),
                      if (invites != null) 'invites': '$invites',
                    },
                  ).toString(),
                ),
                style: _styleBouton,
                child: Text(textes.ficheDisponibilite),
              ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Pièces communes
// -----------------------------------------------------------------------------

/// La note de la fiche, et la porte de l'écran 7.
///
/// ELLE EST DEVENUE CLIQUABLE AU J17, et c'est tout ce qui a changé : une note
/// affichée sans moyen de lire ce qu'elle résume est une affirmation sans
/// preuve. Le chevron le dit, parce qu'une ligne de texte ne se devine pas
/// cliquable.
///
/// LES ÉTOILES VIENNENT DE [RangeeEtoiles], partagée avec l'écran 7 : le même
/// dessin, à trois échelles, écrit une fois.
class _Note extends StatelessWidget {
  const _Note({required this.salle});

  final VenueDetail salle;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;
    final textes = AppLocalizations.of(context);
    final note = salle.note!.toDouble();

    return InkWell(
      onTap: () => context.push(FerhaRoutes.salleAvisDe(salle.id)),
      borderRadius: FerhaRadii.cardBorder,
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(vertical: 4),
        child: Row(
          children: <Widget>[
            RangeeEtoiles(note: note),
            const SizedBox(width: 8),
            Text(
              note.toStringAsFixed(1).replaceAll('.', ','),
              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 8),
            Text(
              textes.ficheAvisVerifies(salle.nombreAvis),
              style: text.bodySmall?.copyWith(color: colors.inkTertiary),
            ),
            Icon(Icons.chevron_right, size: 18, color: colors.inkTertiary),
          ],
        ),
      ),
    );
  }
}

class _PuceEquipement extends StatelessWidget {
  const _PuceEquipement({required this.equipement});

  final EquipementSalle equipement;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;

    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: 12,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: colors.roseSoft,
        borderRadius: FerhaRadii.chipBorder,
      ),
      child: Text(
        equipement.libelle,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: colors.roseInk),
      ),
    );
  }
}

class _Intitule extends StatelessWidget {
  const _Intitule(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    return Text(
      texte.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: colors.inkTertiary,
        letterSpacing: context.espacementDesCapitales(),
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// Squelette de la fiche, pendant le chargement.
class _Chargement extends StatelessWidget {
  const _Chargement();

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;

    return CustomScrollView(
      slivers: <Widget>[
        SliverAppBar(
          expandedHeight: 260,
          pinned: true,
          backgroundColor: colors.surface,
          flexibleSpace: ColoredBox(color: colors.surfaceSecondary),
        ),
        SliverPadding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 24, 20, 24),
          sliver: SliverList(
            delegate: SliverChildListDelegate(<Widget>[
              _Bloc(
                largeur: 220,
                hauteur: 22,
                couleur: colors.surfaceSecondary,
              ),
              const SizedBox(height: 10),
              _Bloc(largeur: 150, hauteur: 14, couleur: colors.ruleSoft),
              const SizedBox(height: 24),
              Row(
                children: <Widget>[
                  for (var i = 0; i < 3; i++) ...<Widget>[
                    Expanded(
                      child: _Bloc(
                        hauteur: 74,
                        couleur: colors.surfaceSecondary,
                      ),
                    ),
                    if (i < 2) const SizedBox(width: 10),
                  ],
                ],
              ),
              const SizedBox(height: 24),
              _Bloc(hauteur: 76, couleur: colors.surfaceSecondary),
              const SizedBox(height: 8),
              _Bloc(hauteur: 76, couleur: colors.surfaceSecondary),
            ]),
          ),
        ),
      ],
    );
  }
}

class _Bloc extends StatelessWidget {
  const _Bloc({required this.hauteur, required this.couleur, this.largeur});

  final double? largeur;
  final double hauteur;
  final Color couleur;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: largeur,
      height: hauteur,
      decoration: BoxDecoration(
        color: couleur,
        borderRadius: FerhaRadii.cardBorder,
      ),
    );
  }
}
