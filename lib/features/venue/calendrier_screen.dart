import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/ferha_colors.dart';
import '../../core/theme/ferha_radii.dart';
import '../../core/widgets/grille_calendrier.dart';
import '../owner/gerer_ma_salle.dart';
import '../owner/owner_providers.dart';
import '../search/search_filters.dart';
import '../search/widgets/etats.dart';
import 'venue_detail.dart';
import 'venue_providers.dart';

/// Écran 4 des maquettes — le calendrier de disponibilité (§4.2, CLI-04).
///
/// Dix-huit mois, EN LECTURE SEULE. On ne réserve pas depuis ici : on regarde.
///
/// TROIS ÉTATS, ET LE CRÉNEAU SE CHOISIT AVANT LE JOUR. C'est la remarque des
/// maquettes, et elle commande toute la structure de l'écran : « un 14 août
/// libre le midi et pris le soir doit se lire d'un coup d'œil ». Un calendrier
/// qui mélangerait les créneaux ne saurait pas colorer ce jour-là, et devrait
/// inventer un quatrième état — « partiellement pris » — que personne ne sait
/// interpréter. Les puces de créneau sont donc au-dessus de la grille, et
/// changer de créneau relit le calendrier.
///
/// LE MOTIF D'UN BLOCAGE N'APPARAÎT NULLE PART. `venue_calendar()` ne le
/// renvoie pas : « fête de famille » ou « travaux » sont des notes internes du
/// propriétaire (§9). L'écran ne peut donc pas les afficher, même par erreur.
///
/// Consultable sans compte, comme la fiche.
class CalendrierScreen extends ConsumerStatefulWidget {
  /// Crée le calendrier.
  const CalendrierScreen({
    required this.venueId,
    this.creneau = Creneau.soir,
    this.date,
    this.invites,
    super.key,
  });

  /// La salle.
  final String venueId;

  /// Le créneau regardé au départ.
  final Creneau creneau;

  /// La date cherchée, mise en évidence si elle est visible.
  final DateTime? date;

  /// Le nombre d'invités, repris pour l'estimation.
  final int? invites;

  @override
  ConsumerState<CalendrierScreen> createState() => _CalendrierScreenState();
}

class _CalendrierScreenState extends ConsumerState<CalendrierScreen> {
  late Creneau _creneau = widget.creneau;
  late DateTime? _selection = widget.date;

  /// Dix-huit mois à partir du mois courant (§4.2, CLI-04).
  static const int _nombreDeMois = 18;

  /// Les derniers états reçus, gardés le temps qu'un autre créneau arrive.
  ///
  /// CHANGER DE CRÉNEAU NE REPEINT QUE LES JOURS, IL NE REFAIT PAS LA LISTE.
  /// Chaque créneau a son propre provider dans la famille : passer de midi à
  /// soir en vise un autre, qui commence forcément par `AsyncLoading` sans
  /// valeur précédente. Rendre le squelette à ce moment-là DÉMONTE le
  /// `ListView` des mois, et un `ListView` démonté emporte sa position de
  /// défilement — celui qui prend sa place repart du premier mois. Quelqu'un
  /// qui regardait mars 2027 se retrouvait en haut de la liste à chaque puce
  /// touchée, et devait redescendre dix-huit mois.
  ///
  /// On garde donc la même grille à l'écran d'un bout à l'autre, avec les états
  /// qu'on avait, et seules les couleurs changent quand la réponse arrive. Le
  /// squelette ne sert plus qu'à la toute première ouverture, quand il n'y a
  /// encore rien à garder.
  Map<DateTime, EtatJour>? _etats;

  @override
  Widget build(BuildContext context) {
    final demande = DemandeCalendrier(
      venueId: widget.venueId,
      creneau: _creneau,
    );
    final calendrier = ref.watch(calendrierProvider(demande));

    // Riverpod 3 a renommé `valueOrNull` en `value` : elle ne lève pas, et vaut
    // null tant que CE créneau-ci n'a rien renvoyé.
    final recus = calendrier.value;
    if (recus != null) _etats = recus;
    final fiche = ref.watch(
      ficheProvider(
        DemandeFiche(
          venueId: widget.venueId,
          date: _selection,
          invites: widget.invites,
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Disponibilité')),
      body: Column(
        children: <Widget>[
          _ChoixCreneau(
            creneau: _creneau,
            onChange: (c) => setState(() => _creneau = c),
          ),
          Expanded(child: _corps(calendrier, demande)),
          // Sous la grille, comme sur la maquette : on lit d'abord le mois,
          // la légende ne sert qu'au moment où une couleur intrigue.
          const _Legende(),
        ],
      ),
      bottomNavigationBar: _selection == null
          ? null
          : _Resume(
              venueId: widget.venueId,
              jour: _selection!,
              creneau: _creneau,
              tarif: fiche.value?.tarifPour(_creneau.code),
              invites: widget.invites,
            ),
    );
  }

  /// La grille dès qu'on a des états, le squelette tant qu'on n'en a aucun.
  ///
  /// La grille est le MÊME widget dans les deux cas — chargement compris — pour
  /// que son élément soit mis à jour et non recréé : c'est ce qui garde la
  /// position de défilement d'un créneau à l'autre.
  Widget _corps(
    AsyncValue<Map<DateTime, EtatJour>> calendrier,
    DemandeCalendrier demande,
  ) {
    // L'erreur passe devant les états gardés : montrer la grille du créneau
    // précédent sous une puce qui en annonce un autre raconterait des
    // disponibilités fausses. On perd le défilement, mais on ne ment pas.
    if (calendrier case AsyncError(:final error)) {
      return EtatErreur(
        erreur: error,
        onReessayer: () => ref.invalidate(calendrierProvider(demande)),
      );
    }

    final etats = _etats;
    if (etats == null) return const _CalendrierEnAttente();

    return _Grille(
      occupes: etats,
      // Le temps de la réponse, les cercles sont encore ceux du créneau d'avant.
      enAttente: calendrier.isLoading,
      nombreDeMois: _nombreDeMois,
      selection: _selection,
      onJour: (jour, etat) =>
          setState(() => _selection = etat == EtatJour.libre ? jour : null),
    );
  }
}

/// Les trois puces de créneau, au-dessus de la grille.
class _ChoixCreneau extends StatelessWidget {
  const _ChoixCreneau({required this.creneau, required this.onChange});

  final Creneau creneau;
  final ValueChanged<Creneau> onChange;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 20, 12),
      child: SegmentedButton<Creneau>(
        segments: Creneau.values
            .map(
              (c) => ButtonSegment<Creneau>(
                value: c,
                label: Text(
                  c == Creneau.journee ? 'Journée entière' : c.libelle,
                ),
              ),
            )
            .toList(growable: false),
        selected: <Creneau>{creneau},
        onSelectionChanged: (choix) => onChange(choix.first),
        showSelectedIcon: false,
      ),
    );
  }
}

/// La légende des trois états.
class _Legende extends StatelessWidget {
  const _Legende();

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 20, 12),
      child: Row(
        children: <Widget>[
          _Pastille(couleur: colors.slotFreeSoft, libelle: 'Libre'),
          const SizedBox(width: 16),
          _Pastille(couleur: colors.slotBookedSoft, libelle: 'Réservé'),
          const SizedBox(width: 16),
          _Pastille(
            couleur: colors.slotUnavailableSoft,
            libelle: 'Indisponible',
          ),
        ],
      ),
    );
  }
}

class _Pastille extends StatelessWidget {
  const _Pastille({required this.couleur, required this.libelle});

  final Color couleur;
  final String libelle;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: couleur,
            // Ronde, comme les cases qu'elle explique.
            shape: BoxShape.circle,
            border: Border.all(color: colors.ruleSoft),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          libelle,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.inkSecondary),
        ),
      ],
    );
  }
}

/// Les dix-huit mois, à la file.
///
/// Cette liste reste montée du début à la fin de l'écran : elle est le seul
/// endroit qui connaisse la position de défilement, et on ne la remplace ni
/// pendant qu'un créneau se charge, ni au moment où ses états changent.
class _Grille extends StatelessWidget {
  const _Grille({
    required this.occupes,
    required this.enAttente,
    required this.nombreDeMois,
    required this.selection,
    required this.onJour,
  });

  final Map<DateTime, EtatJour> occupes;

  /// Vrai pendant qu'un autre créneau se charge : les états affichés sont
  /// encore ceux du créneau précédent.
  final bool enAttente;

  final int nombreDeMois;
  final DateTime? selection;
  final void Function(DateTime jour, EtatJour etat) onJour;

  @override
  Widget build(BuildContext context) {
    final maintenant = DateTime.now();
    final premierMois = DateTime(maintenant.year, maintenant.month);

    // Le voile de l'attente. Il dit « ces couleurs ne sont pas encore les
    // bonnes » sans rien déplacer — un squelette, lui, remettrait la liste en
    // haut. Ce n'est pas une couleur, donc rien à prendre dans la palette ; et
    // à 1 le rendu se contente de peindre l'enfant, sans couche ni coût.
    return AnimatedOpacity(
      opacity: enAttente ? 0.4 : 1,
      duration: const Duration(milliseconds: 150),
      child: ListView.builder(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 32),
        itemCount: nombreDeMois,
        itemBuilder: (context, i) => _Mois(
          mois: DateTime(premierMois.year, premierMois.month + i),
          occupes: occupes,
          selection: selection,
          onJour: onJour,
        ),
      ),
    );
  }
}

class _Mois extends StatelessWidget {
  const _Mois({
    required this.mois,
    required this.occupes,
    required this.selection,
    required this.onJour,
  });

  final DateTime mois;
  final Map<DateTime, EtatJour> occupes;
  final DateTime? selection;
  final void Function(DateTime jour, EtatJour etat) onJour;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 28),
      // La grille vient de core/widgets : sept colonnes, dimanche en tête, des
      // cases carrées. Cet écran ne s'occupe que de ce qu'on met dedans.
      child: MoisCalendrier(
        mois: mois,
        caseDuJour: (jour) {
          final etat = _etat(jour);
          return _Jour(
            jour: jour,
            etat: etat,
            passe: _estPasse(jour),
            selectionne: selection != null && memeJour(selection!, jour),
            onTap: () => onJour(jour, etat),
          );
        },
      ),
    );
  }

  /// L'état d'un jour.
  ///
  /// Le passé compte comme indisponible : on ne réserve pas une date passée —
  /// `request_booking()` le refuse — et cela reste dans les trois états annoncés
  /// plutôt que d'en inventer un quatrième.
  EtatJour _etat(DateTime jour) {
    if (_estPasse(jour)) return EtatJour.indisponible;
    return occupes[jour] ?? EtatJour.libre;
  }

  /// Une date passée ne se réserve pas — `request_booking()` la refuse.
  ///
  /// Elle compte donc comme indisponible, ce qui la garde dans les trois états
  /// annoncés plutôt que d'en inventer un quatrième. Mais elle ne se DESSINE
  /// pas comme un blocage : un cercle beige sur tout le mois écoulé ferait
  /// croire que le propriétaire a fermé sa salle. Elle s'efface, sans cercle.
  bool _estPasse(DateTime jour) {
    final maintenant = DateTime.now();
    final aujourdhui = DateTime(
      maintenant.year,
      maintenant.month,
      maintenant.day,
    );
    return jour.isBefore(aujourdhui);
  }
}

/// Un jour du calendrier : un cercle plein, et son numéro au centre.
///
/// LA COULEUR NE PORTE JAMAIS L'INFORMATION SEULE. Un daltonien distingue mal
/// la sauge de la terracotta ; le numéro d'un jour réservé est donc BARRÉ, et
/// c'est cette barre qui dit « pris », la couleur ne faisant que la confirmer.
/// Chaque case porte en plus son état en toutes lettres pour les lecteurs
/// d'écran.
///
/// Le fond du cercle est la variante douce du jeton, son numéro la variante
/// franche : c'est exactement le découpage de la charte, qui donne à « Libre —
/// sauge #5C7F5A » un « Fond : #E7EFE3 ». Le contraste reste donc lisible, et
/// le jour sélectionné — seul cercle en aplat vif — se détache de tous.
///
/// Un jour passé n'a pas de cercle du tout : il s'efface.
class _Jour extends StatelessWidget {
  const _Jour({
    required this.jour,
    required this.etat,
    required this.passe,
    required this.selectionne,
    required this.onTap,
  });

  final DateTime jour;
  final EtatJour etat;

  /// Vrai si la date est derrière nous.
  final bool passe;

  final bool selectionne;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    final numero = Text(
      '${jour.day}',
      style: text.bodyMedium?.copyWith(
        color: colors.inkTertiary,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      ),
    );

    // Le passé : pas de cercle, pas de geste, très effacé.
    if (passe) {
      return Semantics(
        label: '${jour.day} ${nomMois(jour.month)}, date passée',
        child: Opacity(opacity: 0.4, child: Center(child: numero)),
      );
    }

    // Les couleurs de créneau du thème existent exactement pour cet écran :
    // leur documentation dit « calendrier et états de réservation uniquement ».
    final (Color fond, Color encre) = selectionne
        ? (colors.primary, colors.onPrimary)
        : switch (etat) {
            EtatJour.libre => (colors.slotFreeSoft, colors.slotFree),
            EtatJour.reserve => (colors.slotBookedSoft, colors.slotBooked),
            EtatJour.indisponible => (
              colors.slotUnavailableSoft,
              colors.slotUnavailable,
            ),
          };

    return Semantics(
      label:
          '${jour.day} ${nomMois(jour.month)}, ${_libelle(etat)}'
          '${selectionne ? ', sélectionné' : ''}',
      button: etat == EtatJour.libre,
      selected: selectionne,
      child: Material(
        color: fond,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          // Un jour pris ne se sélectionne pas : le calendrier est en lecture
          // seule, et proposer de cliquer sur une date indisponible ne mènerait
          // nulle part.
          onTap: etat == EtatJour.libre ? onTap : null,
          customBorder: const CircleBorder(),
          child: Center(
            child: Text(
              '${jour.day}',
              style: text.bodyMedium?.copyWith(
                color: encre,
                fontWeight: selectionne ? FontWeight.w700 : FontWeight.w500,
                // La barre qui dit « pris » sans passer par la couleur.
                decoration: etat == EtatJour.reserve
                    ? TextDecoration.lineThrough
                    : null,
                decorationColor: encre,
                decorationThickness: 2,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _libelle(EtatJour etat) => switch (etat) {
  EtatJour.libre => 'libre',
  EtatJour.reserve => 'réservé',
  EtatJour.indisponible => 'indisponible',
};

/// Le bandeau du bas quand un jour libre est choisi.
///
/// Il reprend le prix de ce jour-là, majorations comprises — c'est la remarque
/// de la maquette : « Samedi 14 août — soirée. Haute saison, majoration +30 %
/// appliquée. »
/// La taille du bouton du résumé, la même pour les deux qui s'y relaient.
final ButtonStyle _styleContinuer = FilledButton.styleFrom(
  padding: const EdgeInsetsDirectional.symmetric(horizontal: 20, vertical: 16),
);

class _Resume extends ConsumerWidget {
  const _Resume({
    required this.venueId,
    required this.jour,
    required this.creneau,
    required this.tarif,
    required this.invites,
  });

  /// La salle, pour le lien vers la demande.
  final String venueId;

  final DateTime jour;
  final Creneau creneau;
  final LigneTarif? tarif;

  /// Le nombre d'invités venu de la recherche, transmis à la demande.
  final int? invites;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;
    final maSalle = ref.watch(estMaSalleProvider(venueId));

    final majorations = <String>[
      if (tarif?.jourMajore ?? false) 'jour majoré',
      if (tarif?.saisonMajoree ?? false) 'haute saison',
    ];

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
                    '${dateEnFrancais(jour)} · '
                    '${creneau == Creneau.journee ? 'journée entière' : creneau.libelle.toLowerCase()}',
                    style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tarif == null
                        ? 'Créneau non proposé par cette salle'
                        : '${montantEnDinars(tarif!.total)} DA'
                              '${majorations.isEmpty ? '' : ' · ${majorations.join(', ')}'}',
                    maxLines: 2,
                    style: text.bodySmall?.copyWith(color: colors.inkSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Vers l'écran de demande (§3, étape 3). Le bouton reste éteint
            // quand la salle ne vend pas ce créneau : il n'y aurait aucun prix
            // à composer, et estimate_price() refuserait de tarifer.
            //
            // AUCUNE CONNEXION N'EST DEMANDÉE ICI. C'est l'écran suivant qui
            // la réclamera, au moment d'envoyer — et lui seul.
            //
            // CHEZ LUI, LE PROPRIÉTAIRE NE CONTINUE PAS : il regarde son propre
            // agenda, et le formulaire de demande n'a rien à lui offrir. Même
            // règle qu'à la fiche, un pas plus loin — on lui donne la porte de
            // son tableau de bord plutôt qu'une porte murée.
            if (maSalle)
              BoutonGererMaSalle(venueId: venueId, style: _styleContinuer)
            else
              FilledButton(
                onPressed: tarif == null
                    ? null
                    : () => context.push(
                        Uri(
                          path: FerhaRoutes.demandeDe(venueId),
                          queryParameters: <String, String>{
                            'creneau': creneau.code,
                            'date': dateVersIso(jour),
                            if (invites != null) 'invites': '$invites',
                          },
                        ).toString(),
                      ),
                style: _styleContinuer,
                child: const Text('Continuer'),
              ),
          ],
        ),
      ),
    );
  }
}

/// Squelette du calendrier, pendant le chargement.
class _CalendrierEnAttente extends StatelessWidget {
  const _CalendrierEnAttente();

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;

    return ListView.builder(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 32),
      itemCount: 2,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsetsDirectional.only(bottom: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 130,
              height: 18,
              decoration: BoxDecoration(
                color: colors.surfaceSecondary,
                borderRadius: FerhaRadii.chipBorder,
              ),
            ),
            const SizedBox(height: 16),
            SemainesCalendrier(
              cases: <Widget>[
                for (var i = 0; i < 35; i++)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surfaceSecondary,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
