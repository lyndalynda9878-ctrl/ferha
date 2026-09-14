import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/ferha_colors.dart';
import '../../core/widgets/grille_calendrier.dart';
import '../search/search_filters.dart';
import '../search/widgets/etats.dart';
import 'creneau_agenda.dart';
import 'feuille_creneau.dart';
import 'owner_providers.dart';
import 'salle_du_proprietaire.dart';

/// Le nom FRANÇAIS d'un mois, de 1 à 12.
///
/// Il vivait dans `grille_calendrier.dart`, partagé avec le calendrier client ;
/// il est descendu ici au J22, quand ce calendrier-là est passé à l'arabe. Cet
/// écran n'est pas traduit — il le sera avec le reste de l'espace propriétaire —
/// et d'ici là ses mois s'écrivent en toutes lettres, en français.
String nomMois(int mois) => _moisFr[mois - 1];

const List<String> _moisFr = <String>[
  'Janvier',
  'Février',
  'Mars',
  'Avril',
  'Mai',
  'Juin',
  'Juillet',
  'Août',
  'Septembre',
  'Octobre',
  'Novembre',
  'Décembre',
];

/// L'agenda du propriétaire — écran 9, onglet « Agenda » (§4.3, OWN-06).
///
/// LA MÊME GRILLE QUE L'ÉCRAN 4, ET C'EST DÉLIBÉRÉ. Elle vient de
/// `core/widgets/grille_calendrier.dart`, extraite du calendrier client plutôt
/// que refaite : sept `Expanded` autour d'`AspectRatio`, aucun `GridView`. Le
/// bug de la molette captée par une grille imbriquée a déjà été payé une fois,
/// et un second calendrier écrit à côté aurait fini par le repayer.
///
/// UN MOIS À LA FOIS, ET LES DEUX CRÉNEAUX DEDANS. `owner_agenda()` (016) rend
/// la grille complète du mois — 31 jours × 2 créneaux, « libre » comprise — en
/// un seul appel. Basculer de midi à soir ne touche donc pas au réseau : c'est
/// la différence avec le calendrier client, dont la fonction SQL ne rend qu'un
/// créneau et qui redemande à chaque puce. Sur une 4G algérienne (§7.3), c'est
/// la moitié des allers-retours d'un agenda qu'on feuillette.
///
/// TROIS GESTES, SELON CE QUE PORTE LE JOUR :
///
///   libre    → on propose de le fermer, avec le motif
///   fermé    → on propose de le rouvrir, et on rappelle le motif
///   réservé  → on ouvre la demande. Pas de fermeture possible : `bloquer_date()`
///              refuse (FE022), et le lui proposer serait promettre un geste
///              qui échouerait.
///
/// LE MOTIF NE SORT QUE PAR ICI. C'est la note privée du propriétaire, et
/// `venue_availability` — la seule lecture publique de `venue_blackouts` — ne
/// porte que venue_id, date et slot. Rien à filtrer dans cet écran : il n'y a
/// aucun chemin par lequel le motif atteindrait un client.
class AgendaScreen extends ConsumerStatefulWidget {
  /// Crée l'agenda.
  const AgendaScreen({super.key});

  @override
  ConsumerState<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends ConsumerState<AgendaScreen> {
  /// Le mois affiché, toujours ramené au premier.
  late DateTime _mois = _premierDuMoisCourant();

  /// Le créneau affiché.
  ///
  /// Midi ou soir, jamais « journée » : une case d'agenda est un créneau
  /// atomique, celui de `bookings.slot` et de `venue_blackouts.slot` (§6.1). La
  /// journée entière existe au moment de FERMER — c'est un geste, pas un état.
  Creneau _creneau = Creneau.soir;

  static DateTime _premierDuMoisCourant() {
    final maintenant = DateTime.now();
    return DateTime(maintenant.year, maintenant.month);
  }

  /// On ne feuillette pas en arrière au-delà du mois courant.
  ///
  /// Un agenda sert à décider de ce qui vient. Le passé n'a rien à y faire —
  /// aucune de ses cases n'est cliquable, et `bloquer_date()` sur une date
  /// écoulée ne changerait rien pour personne.
  bool get _peutReculer => _mois.isAfter(_premierDuMoisCourant());

  /// Dix-huit mois devant, comme le calendrier client (§4.2, CLI-04). On ne
  /// montre pas plus loin que ce qu'on sait dire.
  bool get _peutAvancer {
    final limite = _premierDuMoisCourant();
    return _mois.isBefore(DateTime(limite.year, limite.month + 17));
  }

  void _decale(int mois) =>
      setState(() => _mois = DateTime(_mois.year, _mois.month + mois));

  @override
  Widget build(BuildContext context) {
    final espace = ref.watch(espaceProprietaireProvider);
    final salle = espace.value?.salleCourante;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Agenda'),
        // Le nom de la salle en second : le titre dit où l'on est, la salle de
        // quoi l'on parle. Karim en a quatre.
        bottom: salle == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(24),
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 8),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      salle.nom,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: context.ferhaColors.inkSecondary,
                      ),
                    ),
                  ),
                ),
              ),
      ),
      body: switch (espace) {
        AsyncError(:final error) => EtatErreur(
          titre: 'Votre espace n’a pas pu être ouvert',
          erreur: error,
          onReessayer: () =>
              ref.read(espaceProprietaireProvider.notifier).reessayer(),
        ),
        AsyncData(:final value) when value.salles.isEmpty => const EtatVide(
          icone: Icons.storefront_outlined,
          titre: 'Aucune salle',
          explication:
              'Votre agenda s’ouvrira quand vous aurez inscrit une salle.',
        ),
        AsyncData() when salle != null => _Contenu(
          salle: salle,
          mois: _mois,
          creneau: _creneau,
          peutReculer: _peutReculer,
          peutAvancer: _peutAvancer,
          onMois: _decale,
          onCreneau: (c) => setState(() => _creneau = c),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

// =============================================================================
// Le corps : la navigation de mois, les puces de créneau, la grille, la légende
// =============================================================================

class _Contenu extends ConsumerWidget {
  const _Contenu({
    required this.salle,
    required this.mois,
    required this.creneau,
    required this.peutReculer,
    required this.peutAvancer,
    required this.onMois,
    required this.onCreneau,
  });

  final SalleDuProprietaire salle;
  final DateTime mois;
  final Creneau creneau;
  final bool peutReculer;
  final bool peutAvancer;
  final void Function(int mois) onMois;
  final ValueChanged<Creneau> onCreneau;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final demande = DemandeAgenda(venueId: salle.id, mois: mois);
    final agenda = ref.watch(agendaProvider(demande));

    return Column(
      children: <Widget>[
        _BarreDeMois(
          mois: mois,
          peutReculer: peutReculer,
          peutAvancer: peutAvancer,
          onMois: onMois,
        ),
        _ChoixCreneau(creneau: creneau, onChange: onCreneau),
        Expanded(
          child: switch (agenda) {
            AsyncError(:final error) => EtatErreur(
              titre: 'L’agenda n’a pas pu être chargé',
              erreur: error,
              onReessayer: () => ref.invalidate(agendaProvider(demande)),
            ),
            AsyncData(:final value) => _Grille(
              salle: salle,
              agenda: value,
              creneau: creneau,
            ),
            _ => const Center(child: CircularProgressIndicator()),
          },
        ),
        const _Legende(),
      ],
    );
  }
}

/// « ‹ Août 2027 › » — un mois à la fois.
class _BarreDeMois extends StatelessWidget {
  const _BarreDeMois({
    required this.mois,
    required this.peutReculer,
    required this.peutAvancer,
    required this.onMois,
  });

  final DateTime mois;
  final bool peutReculer;
  final bool peutAvancer;
  final void Function(int mois) onMois;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 8, 0),
      child: Row(
        children: <Widget>[
          IconButton(
            // EN ARABE, TOUT CECI SE RETOURNE, ET SANS RIEN ÉCRIRE DE PLUS. La
            // `Row` inverse ses enfants avec la direction du texte — le bouton
            // « mois précédent » passe donc à droite —, et les deux chevrons de
            // Material portent `matchTextDirection: true` dans leur `IconData`
            // (vérifié dans icons.dart) : leur glyphe se miroite tout seul. Ne
            // pas les remplacer par une variante `_rounded` ou `_sharp`, qui
            // ne le porte pas.
            icon: const Icon(Icons.chevron_left),
            onPressed: peutReculer ? () => onMois(-1) : null,
            tooltip: 'Mois précédent',
          ),
          Expanded(
            child: Text(
              '${nomMois(mois.month)} ${mois.year}',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: peutAvancer ? () => onMois(1) : null,
            tooltip: 'Mois suivant',
          ),
        ],
      ),
    );
  }
}

/// Midi ou soir. Pas de « journée entière » ici.
///
/// Une case d'agenda est un créneau réel : la journée entière n'est pas un
/// troisième état de la salle, c'est une manière de vendre — ou de fermer — les
/// deux autres d'un coup. Elle réapparaît donc dans la feuille de fermeture,
/// où elle est un geste.
class _ChoixCreneau extends StatelessWidget {
  const _ChoixCreneau({required this.creneau, required this.onChange});

  final Creneau creneau;
  final ValueChanged<Creneau> onChange;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 20, 12),
      child: SegmentedButton<Creneau>(
        segments: const <ButtonSegment<Creneau>>[
          ButtonSegment<Creneau>(value: Creneau.midi, label: Text('Midi')),
          ButtonSegment<Creneau>(value: Creneau.soir, label: Text('Soir')),
        ],
        selected: <Creneau>{creneau},
        onSelectionChanged: (choix) => onChange(choix.first),
        showSelectedIcon: false,
      ),
    );
  }
}

class _Grille extends StatelessWidget {
  const _Grille({
    required this.salle,
    required this.agenda,
    required this.creneau,
  });

  final SalleDuProprietaire salle;
  final AgendaDuMois agenda;
  final Creneau creneau;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 20),
      child: MoisCalendrier(
        mois: agenda.mois,
        // Le mois est déjà nommé par la barre du dessus : l'écrire deux fois
        // ferait lire deux fois la même chose.
        avecTitre: false,
        caseDuJour: (jour) => _Jour(
          salle: salle,
          jour: jour,
          creneau: agenda.creneauDe(jour, creneau),
        ),
      ),
    );
  }
}

// =============================================================================
// Une case
// =============================================================================

/// Un jour de l'agenda : un cercle plein, son numéro, et son geste.
///
/// LA COULEUR NE PORTE JAMAIS L'INFORMATION SEULE — même règle qu'à l'écran 4.
/// Un daltonien distingue mal la sauge de la terracotta : le numéro d'un
/// créneau confirmé est donc BARRÉ, celui d'une option est en aplat vif, et
/// chaque case dit son état en toutes lettres pour les lecteurs d'écran. La
/// légende, en bas, reste visible.
///
/// LES COULEURS VIENNENT DE LA CHARTE, ET IL EN FAUT CINQ POUR TROIS JETONS.
/// Le §10.1 donne trois couleurs sémantiques — sauge, terracotta, beige — pour
/// « le calendrier et les états de réservation », et l'agenda en distingue
/// cinq. Les trois vont là où elles disent d'aller : libre en sauge, confirmé
/// en terracotta (la date est vendue), fermé en beige. Les deux intermédiaires
/// prennent l'ambre de l'application, comme le suivi client le fait déjà pour
/// « acceptée » — l'ocre y marque ce qui attend un geste. Elles se distinguent
/// l'une de l'autre par l'aplat : la demande est en ambre DOUX, l'option en
/// ambre PLEIN. La progression se lit alors dans le sens de la vente : plus
/// c'est vif, plus la date est engagée.
///
/// Aucune valeur hexadécimale ici, évidemment : tout passe par [FerhaColors].
class _Jour extends ConsumerWidget {
  const _Jour({required this.salle, required this.jour, required this.creneau});

  final SalleDuProprietaire salle;
  final DateTime jour;

  /// Le créneau de ce jour, ou `null` si l'agenda ne l'a pas — ce qui ne
  /// devrait pas arriver, `owner_agenda()` rendant la grille complète.
  final CreneauAgenda? creneau;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    // Le passé : pas de cercle, pas de geste, très effacé. Comme à l'écran 4 —
    // un cercle beige sur tout le mois écoulé ferait croire à une fermeture.
    if (_estPasse(jour)) {
      return Semantics(
        label: '${jour.day} ${nomMois(jour.month)}, date passée',
        child: Opacity(
          opacity: 0.4,
          child: Center(
            child: Text(
              '${jour.day}',
              style: text.bodyMedium?.copyWith(
                color: colors.inkTertiary,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      );
    }

    final etat = creneau?.etat ?? EtatAgenda.libre;
    final (Color fond, Color encre) = couleursDeLEtat(etat, colors);

    return Semantics(
      label:
          '${jour.day} ${nomMois(jour.month)}, ${etat.libelle.toLowerCase()}',
      button: true,
      child: Material(
        color: fond,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          // TOUTES LES CASES SONT CLIQUABLES, et c'est la différence avec le
          // calendrier client. Là-bas, un jour pris ne mène nulle part ; ici,
          // il mène à la demande qui l'occupe. Un agenda sert à agir.
          onTap: () => _ouvrir(context, ref),
          customBorder: const CircleBorder(),
          child: Center(
            child: Text(
              '${jour.day}',
              style: text.bodyMedium?.copyWith(
                color: encre,
                fontWeight: etat == EtatAgenda.libre
                    ? FontWeight.w500
                    : FontWeight.w700,
                // La barre qui dit « vendu » sans passer par la couleur.
                decoration: etat == EtatAgenda.confirme
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

  void _ouvrir(BuildContext context, WidgetRef ref) {
    final c = creneau;
    if (c == null) return;

    // LA FEUILLE N'EST PROPOSÉE QUE SUR CE QUI SE FERME OU SE ROUVRE, et la
    // condition est écrite dans ce sens-là plutôt qu'en négatif. L'inverse —
    // « si ce n'est pas une demande, ouvre la feuille » — laissait passer un
    // créneau confirmé arrivé sans identifiant : il retombait sur la feuille,
    // qui lui proposait « Fermer la date ». `bloquer_date()` aurait refusé
    // (FE022), mais le geste n'aurait jamais dû être offert.
    if (c.etat.seFerme || c.etat.seRouvre) {
      ouvrirFeuilleDeCreneau(context, salle: salle, creneau: c);
      return;
    }

    // Réservé : on ouvre SA demande. Sans identifiant — ce qu'`owner_agenda()`
    // ne fait pas —, on ne fait rien plutôt que d'ouvrir n'importe quoi.
    if (c.bookingId != null) {
      context.push(FerhaRoutes.proprietaireDemandeDe(c.bookingId!));
    }
  }

  static bool _estPasse(DateTime jour) {
    final maintenant = DateTime.now();
    return jour.isBefore(
      DateTime(maintenant.year, maintenant.month, maintenant.day),
    );
  }
}

/// Le fond et l'encre d'un état, tels que la charte les donne.
///
/// Publique parce que la légende s'en sert aussi : deux tables de couleurs pour
/// la même chose finiraient par diverger, et c'est exactement le genre d'écart
/// que personne ne remarque avant qu'un utilisateur le signale.
@visibleForTesting
(Color, Color) couleursDeLEtat(EtatAgenda etat, FerhaColors colors) =>
    switch (etat) {
      EtatAgenda.libre => (colors.slotFreeSoft, colors.slotFree),
      EtatAgenda.demande => (colors.primarySoft, colors.primaryDeep),
      EtatAgenda.option => (colors.primary, colors.onPrimary),
      EtatAgenda.confirme => (colors.slotBookedSoft, colors.slotBooked),
      EtatAgenda.ferme => (colors.slotUnavailableSoft, colors.slotUnavailable),
    };

/// Les cinq états, sous la grille.
///
/// VISIBLE, PAS REPLIABLE. Cinq couleurs ne se retiennent pas d'un coup d'œil,
/// et un propriétaire qui ouvre son agenda une fois par semaine ne se souvient
/// pas de ce que veut dire l'ambre. Elle défile horizontalement plutôt que de
/// passer à la ligne : sur un téléphone étroit, deux rangées de légende
/// mangeraient une semaine de calendrier.
class _Legende extends StatelessWidget {
  const _Legende();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsetsDirectional.fromSTEB(20, 10, 20, 10),
        child: Row(
          spacing: 14,
          children: <Widget>[
            for (final etat in EtatAgenda.values) _Pastille(etat: etat),
          ],
        ),
      ),
    );
  }
}

class _Pastille extends StatelessWidget {
  const _Pastille({required this.etat});

  final EtatAgenda etat;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final (fond, _) = couleursDeLEtat(etat, colors);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: fond,
            // Ronde, comme les cases qu'elle explique.
            shape: BoxShape.circle,
            border: Border.all(color: colors.ruleSoft),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          etat.libelle,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.inkSecondary),
        ),
      ],
    );
  }
}
