import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/ferha_colors.dart';
import '../../core/theme/ferha_radii.dart';
import '../search/search_filters.dart';
import '../search/widgets/etats.dart';
import 'demande_en_attente.dart';
import 'indicateurs_salle.dart';
import 'owner_providers.dart';
import 'salle_du_proprietaire.dart';

/// Écran 9 — le tableau de bord du propriétaire (§4.3, OWN-07 et OWN-08).
///
/// L'ÉCRAN EST FAIT POUR KARIM, 45 ans, peu à l'aise avec l'informatique, et le
/// chapeau du flux D des maquettes dit comment : « chaque écran tient en une
/// action principale ». Ici, l'action est de répondre aux demandes.
///
/// C'EST POURQUOI LES DEMANDES PASSENT DEVANT LES CHIFFRES dès qu'il y en a
/// une. La légende de l'écran 9 le dit en toutes lettres — « les demandes en
/// attente sont l'action à faire aujourd'hui ; elles passent devant les
/// statistiques dès qu'il y en a une » — alors que le dessin, lui, montre les
/// quatre indicateurs en haut. Un dessin ne peut montrer qu'une branche d'une
/// règle conditionnelle ; la légende énonce la règle. On suit la règle, et le
/// tableau des chiffres descend d'un cran les jours où il y a du travail.
///
/// AUCUN CHIFFRE N'EST CALCULÉ ICI. Taux d'occupation, prévisionnel, part
/// acceptée et variations arrivent faits d'`owner_dashboard()` (014), qui est
/// le seul endroit où ces quatre mots ont une définition. Cet écran met un
/// signe et une couleur devant une variation — il ne fait pas la soustraction.
///
/// IL NE CHANGE RIEN NON PLUS. Accepter, refuser et contre-proposer viendront
/// à l'étape suivante, par des fonctions SQL qui vérifieront qui appelle. Les
/// cartes de demande n'ont donc pas encore de boutons : mieux vaut pas de
/// bouton qu'un bouton qui ne fait rien.
///
/// PAS DE BARRE D'ONGLETS, alors que la maquette en dessine une (Tableau,
/// Agenda, Messages, Ma salle). L'agenda existe depuis le J12, ce qui en fait
/// deux sur quatre qui mèneraient quelque part — et deux onglets morts restent
/// deux onglets morts. La barre attendra donc d'avoir ses quatre destinations,
/// et l'agenda s'ouvre d'ici, par-dessus. Les deux routes sont déjà sous
/// `/proprietaire/` pour que ce jour-là ne coûte qu'un emballage.
class TableauDeBordScreen extends ConsumerWidget {
  /// Crée le tableau de bord.
  const TableauDeBordScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final espace = ref.watch(espaceProprietaireProvider);
    final salle = espace.value?.salleCourante;

    return Scaffold(
      appBar: AppBar(
        // Le nom de la salle EST le titre, comme sur la maquette : c'est la
        // première chose à savoir quand on en tient quatre. « Tableau de bord »
        // ne s'affiche que tant qu'on ignore encore de quelle salle il s'agit.
        title: salle == null
            ? const Text('Tableau de bord')
            : _TitreSalle(espace: espace.requireValue),
      ),
      body: switch (espace) {
        AsyncError(:final error) => EtatErreur(
          titre: 'Votre espace n’a pas pu être ouvert',
          erreur: error,
          onReessayer: () =>
              ref.read(espaceProprietaireProvider.notifier).reessayer(),
        ),
        AsyncData(:final value) when value.salles.isEmpty =>
          const _AucuneSalle(),
        AsyncData() when salle != null => _Contenu(salle: salle),
        _ => const _Squelette(),
      },
    );
  }
}

// =============================================================================
// Le titre, et le sélecteur de salle (OWN-08)
// =============================================================================

/// Le nom de la salle courante, et le chevron qui ouvre le choix.
///
/// LE CHEVRON N'APPARAÎT QU'À PARTIR DE DEUX SALLES. Un propriétaire qui n'en a
/// qu'une n'a rien à choisir, et lui proposer quand même un menu d'un seul
/// élément lui ferait chercher ce qu'il a manqué.
class _TitreSalle extends ConsumerWidget {
  const _TitreSalle({required this.espace});

  final EspaceProprietaire espace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salle = espace.salleCourante!;
    final titre = Text(salle.nom, overflow: TextOverflow.ellipsis);

    if (!espace.plusieursSalles) return titre;

    return InkWell(
      onTap: () => _ouvrirSelecteur(context, ref, espace),
      borderRadius: FerhaRadii.chipBorder,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 4, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Flexible(child: titre),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more, size: 22),
          ],
        ),
      ),
    );
  }
}

Future<void> _ouvrirSelecteur(
  BuildContext context,
  WidgetRef ref,
  EspaceProprietaire espace,
) async {
  final choix = await showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => _ListeDesSalles(espace: espace),
  );

  if (choix == null) return;
  await ref.read(espaceProprietaireProvider.notifier).choisir(choix);
}

class _ListeDesSalles extends StatelessWidget {
  const _ListeDesSalles({required this.espace});

  final EspaceProprietaire espace;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 0, 12),
        children: <Widget>[
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 8),
            child: Text('Vos salles', style: text.titleMedium),
          ),
          for (final salle in espace.salles)
            ListTile(
              selected: salle.id == espace.salleCouranteId,
              selectedTileColor: colors.primarySoft,
              leading: Icon(
                salle.id == espace.salleCouranteId
                    ? Icons.check_circle
                    : Icons.storefront_outlined,
                color: salle.id == espace.salleCouranteId
                    ? colors.primaryDeep
                    : colors.inkTertiary,
              ),
              title: Text(salle.nom),
              subtitle: Text(
                // Le statut n'est dit que lorsqu'il n'est pas « publiée » :
                // écrire « Publiée » sur les quatre lignes n'apprend rien et
                // noie la seule qui ne l'est pas.
                salle.statut.estAuCatalogue
                    ? salle.localisation
                    : '${salle.localisation} · ${salle.statut.libelle}',
              ),
              // Le nombre de demandes voyage avec la salle (`owner_venues()`) :
              // le sélecteur dit « 3 » sans un second appel par salle.
              trailing: salle.demandesEnAttente == 0
                  ? null
                  : _Pastille(nombre: salle.demandesEnAttente),
              onTap: () => Navigator.of(context).pop(salle.id),
            ),
        ],
      ),
    );
  }
}

class _Pastille extends StatelessWidget {
  const _Pastille({required this.nombre});

  final int nombre;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;

    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: 9,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: colors.primary,
        borderRadius: FerhaRadii.chipBorder,
      ),
      child: Text(
        '$nombre',
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: colors.onPrimary),
      ),
    );
  }
}

// =============================================================================
// Le corps de l'écran
// =============================================================================

class _Contenu extends ConsumerWidget {
  const _Contenu({required this.salle});

  final SalleDuProprietaire salle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final demandes = ref.watch(demandesEnAttenteProvider(salle.id));

    // L'ORDRE SE DÉCIDE AVANT QUE LA LISTE SOIT ARRIVÉE. `owner_venues()` a déjà
    // dit combien de demandes attendent ; s'en servir évite que l'écran se
    // réordonne sous les yeux une seconde après son ouverture. Une fois la
    // liste là, c'est elle qui fait foi.
    final aDesDemandes =
        demandes.value?.isNotEmpty ?? salle.demandesEnAttente > 0;

    final demandesSection = _Demandes(salle: salle);
    final chiffresSection = _Indicateurs(venueId: salle.id);

    return RefreshIndicator(
      onRefresh: () => _rafraichir(ref, salle.id),
      child: ListView(
        // Sans quoi on ne peut pas tirer vers le bas quand la page est courte —
        // et une salle sans demande ni chiffre est exactement le cas où l'on a
        // envie de vérifier que rien n'a bougé.
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 32),
        children: <Widget>[
          // Le bandeau reste en tête dans les deux cas : il dit pourquoi tout
          // ce qui suit est à zéro.
          if (!salle.statut.estAuCatalogue)
            _BandeauStatut(statut: salle.statut),

          // L'ENTRÉE DE L'AGENDA, ET PAS UN ONGLET. La maquette de l'écran 9
          // dessine une barre — Tableau, Agenda, Messages, Ma salle — dont deux
          // onglets sur quatre mèneraient aujourd'hui quelque part. Deux
          // onglets morts restent deux onglets morts ; l'agenda s'ouvre donc
          // par-dessus le tableau de bord, et la barre attendra d'avoir ses
          // quatre destinations. Les routes sont déjà sous `/proprietaire/`
          // pour que ce jour-là ne coûte qu'un emballage.
          const _EntreeAgenda(),
          const SizedBox(height: 16),

          // Les jours sans demande, les chiffres reprennent la tête : une file
          // vide n'est pas une action à faire, et la laisser en haut ferait
          // commencer l'écran par « rien à signaler ».
          if (aDesDemandes) ...<Widget>[demandesSection, chiffresSection],
          if (!aDesDemandes) ...<Widget>[chiffresSection, demandesSection],
        ],
      ),
    );
  }
}

/// La porte de l'agenda, sur le tableau de bord.
///
/// Une ligne pleine largeur plutôt qu'un bouton dans la barre de titre : c'est
/// la seconde chose qu'un propriétaire vient faire, après répondre à ses
/// demandes, et elle mérite d'être lisible pour Karim, 45 ans, peu à l'aise
/// avec l'informatique.
class _EntreeAgenda extends StatelessWidget {
  const _EntreeAgenda();

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: FerhaRadii.cardBorder,
        side: BorderSide(color: colors.rule),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(FerhaRoutes.proprietaireAgenda),
        child: Padding(
          padding: const EdgeInsetsDirectional.all(14),
          child: Row(
            children: <Widget>[
              Icon(Icons.calendar_month_outlined, color: colors.primaryDeep),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Agenda',
                      style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Voir le mois, fermer une date',
                      style: text.bodySmall?.copyWith(
                        color: colors.inkSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colors.inkTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _rafraichir(WidgetRef ref, String venueId) async {
  ref.invalidate(indicateursProvider(venueId));
  ref.invalidate(demandesEnAttenteProvider(venueId));

  try {
    await Future.wait<Object>(<Future<Object>>[
      ref.read(indicateursProvider(venueId).future),
      ref.read(demandesEnAttenteProvider(venueId).future),
    ]);
  } on Object catch (_) {
    // L'échec est déjà à l'écran, porté par la section qui l'a subi. Le laisser
    // remonter jusqu'ici ne ferait que doubler le message — et une exception
    // non rattrapée sortant d'un `RefreshIndicator` casserait l'animation.
  }
}

/// Dit qu'une salle n'est pas au catalogue, plutôt que de laisser croire à des
/// chiffres décevants.
///
/// Un brouillon n'a pas de mauvais taux d'occupation : il n'est visible de
/// personne, donc réservable par personne. Sans cette ligne, un zéro se lirait
/// comme un échec commercial.
class _BandeauStatut extends StatelessWidget {
  const _BandeauStatut({required this.statut});

  final StatutSalle statut;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsetsDirectional.only(bottom: 16),
      padding: const EdgeInsetsDirectional.all(12),
      decoration: BoxDecoration(
        color: colors.roseSoft,
        borderRadius: FerhaRadii.cardBorder,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.visibility_off_outlined, size: 18, color: colors.roseInk),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${statut.libelle} — cette salle n’apparaît pas dans les '
              'recherches, et ne peut donc recevoir aucune demande.',
              style: text.bodySmall?.copyWith(color: colors.roseInk),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Les demandes en attente
// =============================================================================

class _Demandes extends ConsumerWidget {
  const _Demandes({required this.salle});

  final SalleDuProprietaire salle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final demandes = ref.watch(demandesEnAttenteProvider(salle.id));

    return switch (demandes) {
      AsyncError(:final error) => Padding(
        padding: const EdgeInsetsDirectional.only(bottom: 24),
        child: _EchecDeSection(
          titre: 'Les demandes n’ont pas pu être lues',
          erreur: error,
          onReessayer: () =>
              ref.invalidate(demandesEnAttenteProvider(salle.id)),
        ),
      ),
      AsyncData(:final value) when value.isEmpty => const _FileVide(),
      AsyncData(:final value) => _ListeDesDemandes(demandes: value),
      _ => const _SqueletteDemandes(),
    };
  }
}

class _ListeDesDemandes extends StatelessWidget {
  const _ListeDesDemandes({required this.demandes});

  final List<DemandeEnAttente> demandes;

  @override
  Widget build(BuildContext context) {
    // Une seule horloge pour toute la liste : deux cartes voisines ne doivent
    // pas dire « il y a 2 h » et « il y a 1 h » de la même minute.
    final maintenant = DateTime.now();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _TitreDeSection(
          libelle: 'Demandes en attente',
          compte: demandes.length,
        ),
        for (final demande in demandes)
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: 12),
            child: _CarteDemande(demande: demande, maintenant: maintenant),
          ),
        const SizedBox(height: 12),
      ],
    );
  }
}

/// Une demande, de haut en bas : qui, quand, combien.
///
/// LE NOM EST DÉJÀ RACCOURCI QUAND IL ARRIVE — « Amina K. » vient de
/// `short_name()` (014), pas d'une troncature faite ici. Il n'y a rien à
/// couper, et rien à révéler.
///
/// LA CARTE ENTIÈRE OUVRE LA DEMANDE, ET ELLE NE PORTE AUCUN BOUTON DE RÉPONSE.
/// La maquette de l'écran 9 en dessine deux — « Accepter » et
/// « Contre-proposer » — à même la carte. On ne les met pas là, et pas parce
/// qu'ils seraient difficiles : accepter un mariage engage une salle pour une
/// soirée et pose une option de 72 h (§5.1), sur la foi d'une carte qui ne
/// montre ni le message du client, ni les options qu'il a cochées, ni son nom
/// entier. La décision se prend sur l'écran de détail, où tout cela est écrit.
/// La contre-proposition, elle, demande une saisie : elle attend son étape.
class _CarteDemande extends StatelessWidget {
  const _CarteDemande({required this.demande, required this.maintenant});

  final DemandeEnAttente demande;
  final DateTime maintenant;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () =>
            context.push(FerhaRoutes.proprietaireDemandeDe(demande.bookingId)),
        child: Padding(
          padding: const EdgeInsetsDirectional.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        Text(demande.client, style: text.titleSmall),
                        if (demande.estNouvelle(maintenant)) const _Nouveau(),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    demande.attendDepuis(maintenant),
                    style: text.bodySmall?.copyWith(color: colors.inkTertiary),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                <String>[
                  dateEnFrancais(demande.date),
                  demande.creneau.libelle.toLowerCase(),
                  '${demande.invites} invités',
                  if (demande.typeEvenement != null) demande.typeEvenement!,
                ].join(' · '),
                style: text.bodySmall?.copyWith(color: colors.inkSecondary),
              ),
              const SizedBox(height: 10),
              Divider(height: 1, color: colors.ruleSoft),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Text(
                    'Estimation',
                    style: text.bodyMedium?.copyWith(
                      color: colors.inkSecondary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    // Le devis d'`estimate_price()`, tel quel. Aucune seconde
                    // formule, ici pas plus qu'ailleurs.
                    '${montantEnDinars(demande.montant)} DA',
                    style: text.titleSmall?.copyWith(color: colors.primaryDeep),
                  ),
                  const SizedBox(width: 6),
                  // La flèche dit que la carte s'ouvre. Sans elle, une carte
                  // cliquable ne se distingue pas d'une carte inerte.
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: colors.inkTertiary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Nouveau extends StatelessWidget {
  const _Nouveau();

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;

    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: 8,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: colors.primarySoft,
        borderRadius: FerhaRadii.chipBorder,
      ),
      child: Text(
        'Nouveau',
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: colors.primaryDeep),
      ),
    );
  }
}

/// Aucune demande à traiter — dit calmement, et sans loupe barrée.
class _FileVide extends StatelessWidget {
  const _FileVide();

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsetsDirectional.symmetric(vertical: 16),
      padding: const EdgeInsetsDirectional.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceSecondary,
        borderRadius: FerhaRadii.cardBorder,
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.inbox_outlined, size: 18, color: colors.inkTertiary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Aucune demande en attente.',
              style: text.bodyMedium?.copyWith(color: colors.inkSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Les quatre indicateurs
// =============================================================================

class _Indicateurs extends ConsumerWidget {
  const _Indicateurs({required this.venueId});

  final String venueId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final indicateurs = ref.watch(indicateursProvider(venueId));

    return switch (indicateurs) {
      AsyncError(:final error) => _EchecDeSection(
        titre: 'Les chiffres n’ont pas pu être lus',
        erreur: error,
        onReessayer: () => ref.invalidate(indicateursProvider(venueId)),
      ),
      AsyncData(:final value) => _GrilleIndicateurs(indicateurs: value),
      _ => const _SqueletteIndicateurs(),
    };
  }
}

class _GrilleIndicateurs extends StatelessWidget {
  const _GrilleIndicateurs({required this.indicateurs});

  final IndicateursSalle indicateurs;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;
    final i = indicateurs;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _TitreDeSection(libelle: 'Ce mois-ci'),
        _Rangee(
          gauche: _CarteIndicateur(
            libelle: 'Taux d’occupation',
            valeur: _pourcent(i.tauxOccupation),
            detail: _Variation(points: i.variationOccupation),
            // Une salle entièrement bloquée n'a pas un mauvais taux : elle
            // n'avait rien à vendre. Le dire évite de lire « — » comme une
            // panne.
            explication: i.tauxOccupation == null
                ? 'Aucun créneau à vendre'
                : null,
          ),
          droite: _CarteIndicateur(
            libelle: 'Prévisionnel ${moisEnFrancais(i.mois)}',
            valeur: _montantCompact(i.revenu),
            detail: _Variation(fraction: i.variationRevenu),
            explication:
                '${i.datesVendues} date${i.datesVendues > 1 ? 's' : ''}',
          ),
        ),
        const SizedBox(height: 12),
        _Rangee(
          gauche: _CarteIndicateur(
            libelle: 'Note moyenne',
            // Pas de variation, et ce n'est pas un oubli : une moyenne
            // bayésienne cumulée depuis toujours ne bouge que de quelques
            // centièmes d'un mois à l'autre.
            valeur: i.note == null
                ? '—'
                : i.note!.toStringAsFixed(1).replaceAll('.', ','),
            explication: i.nombreAvis == 0
                ? 'Aucun avis'
                : '${i.nombreAvis} avis',
          ),
          droite: _CarteIndicateur(
            libelle: 'Demandes acceptées',
            valeur: _pourcent(i.tauxAcceptation),
            detail: _Variation(points: i.variationAcceptation),
            explication: i.demandesTranchees == 0
                ? 'Aucune demande tranchée'
                : null,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          // Dit une fois sous la grille plutôt que répété sur trois cartes, où
          // il ne tiendrait de toute façon pas.
          'Variations comparées au mois précédent.',
          style: text.bodySmall?.copyWith(color: colors.inkTertiary),
        ),
      ],
    );
  }
}

/// Deux cartes de même hauteur, quoi qu'elles contiennent.
///
/// `IntrinsicHeight` plutôt qu'une hauteur écrite en dur : « Aucune demande
/// tranchée » prend deux lignes là où « ▲ 9 pts » en prend une, et une hauteur
/// fixe finirait par rogner l'une des deux.
class _Rangee extends StatelessWidget {
  const _Rangee({required this.gauche, required this.droite});

  final Widget gauche;
  final Widget droite;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(child: gauche),
          const SizedBox(width: 12),
          Expanded(child: droite),
        ],
      ),
    );
  }
}

class _CarteIndicateur extends StatelessWidget {
  const _CarteIndicateur({
    required this.libelle,
    required this.valeur,
    this.detail,
    this.explication,
  });

  final String libelle;
  final String valeur;

  /// La variation, quand l'indicateur en a une.
  final Widget? detail;

  /// Ce qui remplace ou complète la variation — « 12 dates », « Aucun avis ».
  final String? explication;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsetsDirectional.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: FerhaRadii.cardBorder,
        border: Border.all(color: colors.ruleSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            libelle,
            style: text.bodySmall?.copyWith(color: colors.inkSecondary),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              valeur,
              style: text.headlineSmall?.copyWith(color: colors.ink),
            ),
          ),
          const SizedBox(height: 4),
          if (detail != null) detail!,
          if (explication != null)
            Text(
              explication!,
              style: text.bodySmall?.copyWith(color: colors.inkTertiary),
            ),
        ],
      ),
    );
  }
}

/// Une variation, avec sa flèche et sa couleur.
///
/// LA FLÈCHE PORTE LE SENS, PAS LA COULEUR. Ambre pour une hausse, rouge du
/// thème pour une baisse : sage et terracotta, qui seraient la lecture
/// habituelle, sont réservés au calendrier et aux états de réservation par la
/// charte (§10.1), et on ne leur invente pas un troisième emploi ici.
/// Quiconque ne distingue pas les deux teintes lit quand même ▲ et ▼.
///
/// UNE VARIATION ABSENTE S'ÉCRIT « — », JAMAIS « ▲ 0 % ». La base rend `null`
/// quand la comparaison n'a pas de sens : un mois précédent sans réservation,
/// sans revenu, sans demande tranchée. Afficher zéro y répondrait par un
/// chiffre là où il n'y a pas de réponse.
class _Variation extends StatelessWidget {
  const _Variation({this.points, this.fraction});

  /// Un écart en POINTS, déjà multiplié par la base — « ▲ 9 pts ».
  final double? points;

  /// Un écart en PART DE 1 — « ▲ 14 % ».
  final double? fraction;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    final valeur = points ?? (fraction == null ? null : fraction! * 100);
    if (valeur == null || valeur == 0) {
      return Text(
        '—',
        style: text.bodySmall?.copyWith(color: colors.inkTertiary),
      );
    }

    final hausse = valeur > 0;
    final couleur = hausse
        ? colors.primaryDeep
        : Theme.of(context).colorScheme.error;
    final unite = points == null ? '%' : 'pts';

    return Row(
      children: <Widget>[
        Icon(
          hausse ? Icons.arrow_drop_up : Icons.arrow_drop_down,
          size: 18,
          color: couleur,
        ),
        Flexible(
          child: Text(
            '${valeur.abs().round()} $unite',
            style: text.bodySmall?.copyWith(color: couleur),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Ce qui reste
// =============================================================================

class _TitreDeSection extends StatelessWidget {
  const _TitreDeSection({required this.libelle, this.compte});

  final String libelle;
  final int? compte;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;

    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 10),
      child: Text(
        compte == null ? libelle : '$libelle · $compte',
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(color: colors.inkSecondary),
      ),
    );
  }
}

/// L'échec d'UNE section, sans emporter le reste de l'écran.
///
/// Les chiffres et les demandes viennent de deux appels ; que l'un rate ne rend
/// pas l'autre faux. Un `EtatErreur` plein écran effacerait des demandes qui
/// sont arrivées, et qui attendent toujours une réponse.
class _EchecDeSection extends StatelessWidget {
  const _EchecDeSection({
    required this.titre,
    required this.erreur,
    required this.onReessayer,
  });

  final String titre;
  final Object erreur;
  final VoidCallback onReessayer;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsetsDirectional.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceSecondary,
        borderRadius: FerhaRadii.cardBorder,
        border: Border.all(color: colors.ruleSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.cloud_off_outlined,
                size: 18,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(titre, style: text.titleSmall)),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: onReessayer,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Réessayer'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Un compte propriétaire sans aucune salle.
///
/// Le cas existe dès l'inscription : on se déclare propriétaire avant d'avoir
/// publié quoi que ce soit. L'écran ne peut rien afficher, mais il peut dire
/// pourquoi — et il ne propose pas encore d'en créer une, puisque cet écran-là
/// n'existe pas.
class _AucuneSalle extends StatelessWidget {
  const _AucuneSalle();

  @override
  Widget build(BuildContext context) {
    return const EtatVide(
      icone: Icons.storefront_outlined,
      titre: 'Aucune salle pour l’instant',
      explication:
          'Votre tableau de bord s’ouvrira dès qu’une salle sera inscrite à '
          'votre compte. L’inscription d’une salle se fait pour le moment avec '
          'l’équipe Ferha.',
    );
  }
}

// =============================================================================
// Les squelettes
//
// Des blocs à la forme de ce qui arrive, plutôt qu'une roue centrée : l'écran
// ne saute pas quand les chiffres se posent.
// =============================================================================

class _Squelette extends StatelessWidget {
  const _Squelette();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 32),
      children: const <Widget>[_SqueletteDemandes(), _SqueletteIndicateurs()],
    );
  }
}

class _SqueletteIndicateurs extends StatelessWidget {
  const _SqueletteIndicateurs();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: <Widget>[
        _Rangee(gauche: _Bloc(hauteur: 92), droite: _Bloc(hauteur: 92)),
        SizedBox(height: 12),
        _Rangee(gauche: _Bloc(hauteur: 92), droite: _Bloc(hauteur: 92)),
      ],
    );
  }
}

class _SqueletteDemandes extends StatelessWidget {
  const _SqueletteDemandes();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsetsDirectional.only(bottom: 24),
      child: Column(
        children: <Widget>[
          _Bloc(hauteur: 108),
          SizedBox(height: 12),
          _Bloc(hauteur: 108),
        ],
      ),
    );
  }
}

class _Bloc extends StatelessWidget {
  const _Bloc({required this.hauteur});

  final double hauteur;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;

    return Container(
      height: hauteur,
      decoration: BoxDecoration(
        color: colors.surfaceSecondary,
        borderRadius: FerhaRadii.cardBorder,
      ),
    );
  }
}

// =============================================================================
// Mises en forme
// =============================================================================

/// « 68 % », ou « — » quand la base n'a pas de taux à donner.
///
/// L'espace fine insécable avant le signe, comme partout ailleurs dans le
/// projet : c'est la typographie française, et elle évite qu'un « % » se
/// retrouve seul au début d'une ligne.
String _pourcent(double? part) =>
    part == null ? '—' : '${(part * 100).round()} %';

/// « 1,84 M DA » au-delà du million, « 640 000 DA » en deçà.
///
/// Un prévisionnel s'écrit à sept chiffres, et sept chiffres ne tiennent pas
/// dans une carte de moitié d'écran sur un téléphone de 390 px. On ne rogne pas
/// pour autant la précision où elle compte : sous le million, le montant est
/// écrit en entier.
String _montantCompact(num montant) {
  if (montant < 1000000) return '${montantEnDinars(montant)} DA';

  var millions = (montant / 1000000).toStringAsFixed(2);
  // « 12,00 M » n'apporte rien de plus que « 12 M ».
  while (millions.endsWith('0')) {
    millions = millions.substring(0, millions.length - 1);
  }
  if (millions.endsWith('.')) {
    millions = millions.substring(0, millions.length - 1);
  }
  return '${millions.replaceAll('.', ',')} M DA';
}
