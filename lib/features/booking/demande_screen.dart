import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/exiger_connexion.dart';
import '../../core/router/routes.dart';
import '../../core/theme/ferha_colors.dart';
import '../../core/theme/ferha_radii.dart';
import '../search/search_filters.dart';
import '../search/widgets/etats.dart';
import '../venue/venue_detail.dart';
import '../venue/venue_providers.dart';
import 'booking_messages.dart';
import 'booking_providers.dart';
import 'devis_reservation.dart';

/// Écran 5 des maquettes — la demande de réservation (§3 étape 3, CLI-05).
///
/// AUCUN MONTANT N'EST CALCULÉ ICI. Pas un total, pas un sous-total, pas
/// l'acompte, pas même une addition de deux prix d'options. Chaque changement
/// — type d'événement, invité de plus, case cochée — rappelle
/// `booking_quote()`, qui appelle `estimate_price()` (§5.2). Si vous voyez un
/// `+` entre deux montants dans ce fichier, c'est un bug.
///
/// LA CONNEXION EST DEMANDÉE ICI, ET NULLE PART AVANT. Chercher, ouvrir une
/// fiche, lire un calendrier et composer cette demande se font sans compte :
/// c'est le parcours du §3. Le compte n'est réclamé qu'à l'instant d'envoyer,
/// par `exigerConnexion` — et comme l'écran de connexion s'ouvre PAR-DESSUS
/// celui-ci puis se referme dessus, l'état de la page survit : le type
/// d'événement, le nombre d'invités et les options cochées sont toujours là
/// quand le client revient. Le renvoyer à l'accueil lui ferait tout
/// recommencer.
class DemandeScreen extends ConsumerStatefulWidget {
  /// Crée l'écran de demande.
  const DemandeScreen({
    required this.venueId,
    required this.date,
    required this.creneau,
    this.invites,
    super.key,
  });

  /// La salle.
  final String venueId;

  /// La date choisie au calendrier.
  final DateTime date;

  /// Le créneau choisi au calendrier.
  final Creneau creneau;

  /// Le nombre d'invités venu de la recherche, s'il y en avait un.
  final int? invites;

  @override
  ConsumerState<DemandeScreen> createState() => _DemandeScreenState();
}

class _DemandeScreenState extends ConsumerState<DemandeScreen> {
  /// Le nombre d'invités affiché, qui suit le doigt.
  int? _invites;

  /// Le nombre d'invités sur lequel porte le devis.
  ///
  /// SÉPARÉ DU PRÉCÉDENT, ET C'EST TOUT L'INTÉRÊT. Le pas du sélecteur est de
  /// dix : passer de 300 à 450 fait quinze appuis, et un devis par appui ferait
  /// quinze allers-retours sur une 4G algérienne (§7.3). Celui-ci ne bouge
  /// qu'une fois le doigt reposé — [_delaiDevis] plus tard.
  int? _invitesDevis;

  Timer? _minuterie;

  /// Le temps qu'on laisse au doigt avant de redemander un devis.
  static const Duration _delaiDevis = Duration(milliseconds: 400);

  /// Le pas du sélecteur d'invités. Une salle se remplit par dizaines.
  static const int _pasInvites = 10;

  TypeEvenement? _type;
  final Set<String> _optionsCochees = <String>{};

  final _invitesCtrl = TextEditingController();

  /// Le dernier devis reçu, gardé pendant qu'un autre se charge.
  ///
  /// Même raison qu'au calendrier : remplacer le récapitulatif par un squelette
  /// à chaque case cochée ferait sauter la page sous le doigt. Les montants
  /// précédents restent affichés, en attente, et changent quand la réponse
  /// arrive.
  DevisReservation? _dernierDevis;

  bool _envoiEnCours = false;
  String? _erreurEnvoi;

  @override
  void dispose() {
    _minuterie?.cancel();
    _invitesCtrl.dispose();
    super.dispose();
  }

  /// Pose le nombre d'invités initial dès que la fiche arrive.
  ///
  /// Par défaut, les couverts compris dans le prix de base : c'est le point de
  /// départ honnête — celui où le client ne paie aucun supplément — et il vient
  /// de la grille tarifaire, jamais d'un chiffre inventé ici.
  void _initialiseInvites(VenueDetail salle) {
    if (_invites != null) return;

    final tarif = salle.tarifPour(widget.creneau.code);
    final depart = widget.invites ?? tarif?.couvertsInclus ?? salle.capacite;

    _invites = _borne(depart, salle);
    _invitesDevis = _invites;
    _invitesCtrl.text = '$_invites';
  }

  /// Entre 1 et la capacité assise de la salle.
  ///
  /// Ce n'est pas une règle de prix : c'est la capacité déclarée par le
  /// propriétaire, et la recherche écarte déjà les salles trop petites. On ne
  /// laisse donc pas demander 600 couverts à une salle qui en tient 450.
  int _borne(int valeur, VenueDetail salle) =>
      valeur.clamp(1, salle.capacite).toInt();

  void _changeInvites(int valeur, VenueDetail salle) {
    final borne = _borne(valeur, salle);
    setState(() => _invites = borne);
    _programmeDevis(borne);
  }

  void _programmeDevis(int invites) {
    _minuterie?.cancel();
    _minuterie = Timer(_delaiDevis, () {
      if (!mounted) return;
      setState(() => _invitesDevis = invites);
    });
  }

  /// Cocher ou décocher une option : le devis repart aussitôt.
  ///
  /// Pas de temporisation ici, contrairement aux invités : une case se coche
  /// une fois, et le client attend de voir le montant bouger.
  void _basculeOption(OptionSalle option) {
    setState(() {
      if (!_optionsCochees.remove(option.id)) _optionsCochees.add(option.id);
    });
  }

  Future<void> _envoyer(VenueDetail salle, DevisReservation devis) async {
    // LA CONNEXION, ICI. Si le visiteur renonce, on ne fait rien de plus : ses
    // choix restent à l'écran, l'écran de connexion s'étant simplement refermé
    // par-dessus.
    if (!await exigerConnexion(context, ref)) return;
    if (!mounted) return;

    setState(() {
      _envoiEnCours = true;
      _erreurEnvoi = null;
    });

    try {
      final envoyee = await ref
          .read(bookingServiceProvider)
          .envoyer(
            salle: salle,
            date: widget.date,
            creneau: widget.creneau,
            invites: devis.invites,
            // Les options que la BASE a facturées, pas les cases cochées : si
            // l'une d'elles a disparu du catalogue entre-temps, le
            // récapitulatif de confirmation ne doit pas la citer.
            options: devis.options,
            typeEvenement: _type,
          );
      if (!mounted) return;

      // pushReplacement : la confirmation prend la place du formulaire. Le
      // bouton retour ramène au calendrier, et non sur une demande déjà
      // envoyée qu'on renverrait d'un doigt distrait.
      context.pushReplacement(
        Uri(
          path: FerhaRoutes.demandeEnvoyee,
          queryParameters: <String, String>{'ref': envoyee.groupId},
        ).toString(),
        extra: envoyee,
      );
    } on Object catch (erreur) {
      if (!mounted) return;
      setState(() => _erreurEnvoi = messageErreurDemande(erreur));
    } finally {
      if (mounted) setState(() => _envoiEnCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fiche = ref.watch(
      ficheProvider(
        DemandeFiche(
          venueId: widget.venueId,
          date: widget.date,
          invites: widget.invites,
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Votre demande')),
      body: switch (fiche) {
        AsyncError(:final error) => EtatErreur(
          erreur: error,
          onReessayer: () => ref.invalidate(ficheProvider),
        ),
        AsyncData(:final value) => _corps(value),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _corps(VenueDetail salle) {
    _initialiseInvites(salle);

    final devis = ref.watch(
      devisProvider(
        DemandeDevis(
          venueId: salle.id,
          date: widget.date,
          creneau: widget.creneau,
          invites: _invitesDevis!,
          optionIds: _optionsCochees,
        ),
      ),
    );

    final recu = devis.value;
    if (recu != null) _dernierDevis = recu;

    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 32),
      children: <Widget>[
        _EnTete(salle: salle, date: widget.date, creneau: widget.creneau),
        const SizedBox(height: 24),

        if (salle.typesEvenement.isNotEmpty) ...<Widget>[
          const _Intitule('Événement'),
          const SizedBox(height: 10),
          _ChoixType(
            types: salle.typesEvenement,
            choisi: _type,
            onChange: (t) => setState(() => _type = t),
          ),
          const SizedBox(height: 20),
        ],

        const _Intitule('Nombre d’invités'),
        const SizedBox(height: 10),
        _ChoixInvites(
          valeur: _invites!,
          capacite: salle.capacite,
          controleur: _invitesCtrl,
          pas: _pasInvites,
          onChange: (v) => _changeInvites(v, salle),
        ),

        if (salle.options.isNotEmpty) ...<Widget>[
          const SizedBox(height: 20),
          const _Intitule('Options'),
          const SizedBox(height: 10),
          for (final option in salle.options)
            _LigneOption(
              option: option,
              cochee: _optionsCochees.contains(option.id),
              onChange: () => _basculeOption(option),
            ),
        ],

        const SizedBox(height: 24),
        _Recapitulatif(
          devis: _dernierDevis,
          creneau: widget.creneau,
          date: widget.date,
          erreur: devis.error,
          enAttente: devis.isLoading,
          onReessayer: () => ref.invalidate(devisProvider),
        ),

        if (_erreurEnvoi != null) ...<Widget>[
          const SizedBox(height: 16),
          _Refus(message: _erreurEnvoi!),
        ],

        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            // Rien à envoyer tant qu'aucun devis n'est arrivé : on ne demande
            // pas une réservation dont on n'a pas montré le prix.
            onPressed: (_dernierDevis == null || _envoiEnCours)
                ? null
                : () => _envoyer(salle, _dernierDevis!),
            style: FilledButton.styleFrom(
              padding: const EdgeInsetsDirectional.symmetric(vertical: 16),
            ),
            child: _envoiEnCours
                ? const _Patiente()
                : const Text('Envoyer la demande'),
          ),
        ),
        const SizedBox(height: 12),

        // La phrase de la maquette, mot pour mot : « La mention "aucun paiement
        // à cette étape" lève le principal frein à l'envoi. »
        Text(
          'Aucun paiement à cette étape. Le propriétaire répond sous 48 h.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: context.ferhaColors.inkTertiary,
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Les morceaux de l'écran
// -----------------------------------------------------------------------------

/// De quoi savoir ce qu'on demande : la salle, la date, le créneau.
///
/// Absent de la maquette, qui n'a que la barre de titre « Votre demande ».
/// Mais on arrive ici depuis un calendrier de dix-huit mois, et la date choisie
/// est la seule chose que le client ne peut plus vérifier une fois qu'il a
/// quitté la grille. Elle vaut trois lignes.
class _EnTete extends StatelessWidget {
  const _EnTete({
    required this.salle,
    required this.date,
    required this.creneau,
  });

  final VenueDetail salle;
  final DateTime date;
  final Creneau creneau;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceSecondary,
        borderRadius: FerhaRadii.cardBorder,
        border: Border.all(color: colors.ruleSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            salle.nom,
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            salle.localisation,
            style: text.bodySmall?.copyWith(color: colors.inkSecondary),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Icon(Icons.event_outlined, size: 16, color: colors.inkSecondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${dateEnFrancais(date)} · ${libelleCreneau(creneau)}',
                  style: text.bodyMedium?.copyWith(color: colors.ink),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Les puces de type d'événement.
class _ChoixType extends StatelessWidget {
  const _ChoixType({
    required this.types,
    required this.choisi,
    required this.onChange,
  });

  final List<TypeEvenement> types;
  final TypeEvenement? choisi;
  final ValueChanged<TypeEvenement?> onChange;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final type in types)
          ChoiceChip(
            label: Text(type.libelle),
            selected: choisi?.code == type.code,
            // Retirer son choix reste possible : le type d'événement n'est pas
            // obligatoire, `bookings.event_type` est nullable.
            onSelected: (pris) => onChange(pris ? type : null),
          ),
      ],
    );
  }
}

/// Le sélecteur d'invités : − , un nombre qu'on peut aussi taper, + .
///
/// Le nombre est saisissable parce que le pas est de dix : aller de 120 à 380
/// ferait vingt-six appuis. Il reste borné à la capacité de la salle, et la
/// borne s'affiche plutôt que d'agir en silence.
///
/// LE TEXTE AFFICHÉ NE PEUT PAS MENTIR SUR LE DEVIS. Quelqu'un qui tape 900
/// dans une salle de 450 voit sa valeur ramenée à 450 dans l'état — c'est elle
/// qui part au devis — mais le champ, lui, montrerait encore 900 s'il ne se
/// recalait jamais. Le champ se recale donc dès qu'il perd le focus, et le
/// nombre lu à l'écran est toujours celui qui a été chiffré.
class _ChoixInvites extends StatefulWidget {
  const _ChoixInvites({
    required this.valeur,
    required this.capacite,
    required this.controleur,
    required this.pas,
    required this.onChange,
  });

  final int valeur;
  final int capacite;
  final TextEditingController controleur;
  final int pas;
  final ValueChanged<int> onChange;

  @override
  State<_ChoixInvites> createState() => _ChoixInvitesState();
}

class _ChoixInvitesState extends State<_ChoixInvites> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_auDepartDuFocus);
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_auDepartDuFocus)
      ..dispose();
    super.dispose();
  }

  /// Le champ quitté se recale sur la valeur réellement prise en compte.
  void _auDepartDuFocus() {
    if (!_focus.hasFocus) _pose(widget.valeur);
  }

  void _pose(int nouvelle) {
    final borne = nouvelle.clamp(1, widget.capacite).toInt();
    if (widget.controleur.text != '$borne') {
      widget.controleur.text = '$borne';
      widget.controleur.selection = TextSelection.collapsed(
        offset: widget.controleur.text.length,
      );
    }
    widget.onChange(borne);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 4, 4),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: FerhaRadii.cardBorder,
            border: Border.all(color: colors.rule),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: widget.controleur,
                  focusNode: _focus,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsetsDirectional.zero,
                    suffixText: 'invités',
                  ),
                  onChanged: (saisie) {
                    final n = int.tryParse(saisie);
                    // Un champ vidé pour être retapé ne doit pas sauter à 1
                    // sous les doigts : on attend un nombre.
                    if (n != null && n >= 1) {
                      widget.onChange(n.clamp(1, widget.capacite));
                    }
                  },
                  onEditingComplete: () => _pose(widget.valeur),
                ),
              ),
              IconButton(
                onPressed: widget.valeur > 1
                    ? () => _pose(widget.valeur - widget.pas)
                    : null,
                icon: const Icon(Icons.remove),
                tooltip: '${widget.pas} invités de moins',
              ),
              IconButton(
                onPressed: widget.valeur < widget.capacite
                    ? () => _pose(widget.valeur + widget.pas)
                    : null,
                icon: const Icon(Icons.add),
                tooltip: '${widget.pas} invités de plus',
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Capacité de la salle : ${widget.capacite} couverts.',
          style: text.bodySmall?.copyWith(color: colors.inkTertiary),
        ),
      ],
    );
  }
}

/// Une option cochable, avec son prix — ou « Incluse ».
class _LigneOption extends StatelessWidget {
  const _LigneOption({
    required this.option,
    required this.cochee,
    required this.onChange,
  });

  final OptionSalle option;
  final bool cochee;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    return InkWell(
      onTap: onChange,
      borderRadius: FerhaRadii.cardBorder,
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(vertical: 2),
        child: Row(
          children: <Widget>[
            Checkbox(value: cochee, onChanged: (_) => onChange()),
            Expanded(child: Text(option.libelle, style: text.bodyMedium)),
            const SizedBox(width: 8),
            Text(
              // Un forfait à zéro dinar n'est pas « 0 DA » : c'est une option
              // que la salle comprend dans son prix, et elle le dit ainsi.
              option.incluse ? 'Incluse' : '${montantEnDinars(option.prix)} DA',
              style: text.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: option.incluse ? colors.slotFree : colors.ink,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Le récapitulatif — celui qui se recalcule à chaque geste.
///
/// TOUS SES MONTANTS VIENNENT DE [devis], donc de `booking_quote()`, donc
/// d'`estimate_price()`. Ce widget les met en page ; il n'en fabrique aucun.
class _Recapitulatif extends StatelessWidget {
  const _Recapitulatif({
    required this.devis,
    required this.creneau,
    required this.date,
    required this.erreur,
    required this.enAttente,
    required this.onReessayer,
  });

  final DevisReservation? devis;
  final Creneau creneau;
  final DateTime date;
  final Object? erreur;
  final bool enAttente;
  final VoidCallback onReessayer;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;

    // L'erreur passe devant les montants gardés : afficher l'ancien total sous
    // des options qui ont changé annoncerait un prix que personne ne pratique.
    if (erreur != null) {
      return _DevisImpossible(erreur: erreur!, onReessayer: onReessayer);
    }

    final d = devis;
    if (d == null) return const _RecapEnAttente();

    return Container(
      padding: const EdgeInsetsDirectional.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: FerhaRadii.cardBorder,
        border: Border.all(color: colors.rule),
      ),
      // Le voile de l'attente, comme au calendrier : il dit « ces montants ne
      // sont pas encore les bons » sans rien déplacer.
      child: AnimatedOpacity(
        opacity: enAttente ? 0.5 : 1,
        duration: const Duration(milliseconds: 150),
        child: Column(
          children: <Widget>[
            // Le prix du créneau, avec ce qui l'a majoré — « Soirée samedi
            // (haute saison) » dans la maquette.
            _Ligne(libelle: _libelleCreneauMajore(d), montant: d.prixCreneau),

            if (d.couvertsSup > 0)
              _Ligne(
                libelle:
                    '${d.couvertsSup} couvert${d.couvertsSup > 1 ? 's' : ''} '
                    'au-delà de ${d.couvertsInclus}',
                montant: d.montantCouvertsSup,
              ),

            for (final option in d.options)
              if (!option.incluse)
                _Ligne(libelle: option.libelle, montant: option.prix),

            Padding(
              padding: const EdgeInsetsDirectional.symmetric(vertical: 10),
              child: Divider(height: 1, color: colors.rule),
            ),

            _Ligne(
              libelle: 'Estimation totale',
              montant: d.total,
              enAvant: true,
            ),
            const SizedBox(height: 6),
            _Ligne(
              libelle: 'Acompte à verser (${d.pourcentageAcompte} %)',
              montant: d.montantAcompte,
            ),
          ],
        ),
      ),
    );
  }

  /// « Soirée samedi (haute saison) », comme sur la maquette.
  ///
  /// Les majorations se nomment, elles ne se devinent pas : un client qui voit
  /// 343 200 DA là où la fiche annonçait 220 000 doit lire pourquoi sur la même
  /// ligne. Ce sont les coefficients renvoyés par la base qui décident — pas
  /// une règle de calendrier réécrite ici.
  String _libelleCreneauMajore(DevisReservation d) {
    final raisons = <String>[
      if (d.jourMajore) _nomDuJour(date),
      if (d.saisonMajoree) 'haute saison',
    ];
    final base = libelleCreneau(creneau);
    return raisons.isEmpty ? base : '$base (${raisons.join(', ')})';
  }
}

/// Une ligne « libellé … montant » du récapitulatif.
class _Ligne extends StatelessWidget {
  const _Ligne({
    required this.libelle,
    required this.montant,
    this.enAvant = false,
  });

  final String libelle;
  final num montant;

  /// Vrai pour la ligne du total, la seule qui soit en gras.
  final bool enAvant;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    final style = enAvant
        ? text.titleMedium?.copyWith(fontWeight: FontWeight.w700)
        : text.bodyMedium?.copyWith(color: colors.inkSecondary);

    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(child: Text(libelle, style: style)),
          const SizedBox(width: 12),
          Text(
            '${montantEnDinars(montant)} DA',
            style: (enAvant ? style : text.bodyMedium)?.copyWith(
              fontWeight: FontWeight.w700,
              color: enAvant ? colors.primaryDeep : colors.ink,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Le récapitulatif tant que le premier devis n'est pas arrivé.
class _RecapEnAttente extends StatelessWidget {
  const _RecapEnAttente();

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;

    return Container(
      padding: const EdgeInsetsDirectional.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: FerhaRadii.cardBorder,
        border: Border.all(color: colors.rule),
      ),
      child: Column(
        spacing: 12,
        children: <Widget>[
          for (final largeur in <double>[0.55, 0.4, 0.7])
            Row(
              children: <Widget>[
                Expanded(
                  flex: (largeur * 100).round(),
                  child: Container(
                    height: 12,
                    decoration: BoxDecoration(
                      color: colors.surfaceSecondary,
                      borderRadius: FerhaRadii.chipBorder,
                    ),
                  ),
                ),
                Expanded(
                  flex: 100 - (largeur * 100).round(),
                  child: const SizedBox(),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Ce qu'on montre quand le devis n'a pas abouti.
class _DevisImpossible extends StatelessWidget {
  const _DevisImpossible({required this.erreur, required this.onReessayer});

  final Object erreur;
  final VoidCallback onReessayer;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;
    final rouge = Theme.of(context).colorScheme.error;

    return Container(
      padding: const EdgeInsetsDirectional.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: FerhaRadii.cardBorder,
        border: Border.all(color: rouge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Le devis n’a pas pu être calculé',
            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            messageErreurDemande(erreur),
            style: text.bodySmall?.copyWith(color: colors.inkSecondary),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: onReessayer,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Réessayer'),
          ),
        ],
      ),
    );
  }
}

/// Le refus de l'envoi, en toutes lettres et à côté du bouton qui l'a produit.
class _Refus extends StatelessWidget {
  const _Refus({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final rouge = Theme.of(context).colorScheme.error;

    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: FerhaRadii.cardBorder,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.error_outline, size: 18, color: rouge),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: text.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Petit intitulé de section, comme sur la fiche salle.
class _Intitule extends StatelessWidget {
  const _Intitule(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Text(
      texte,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: context.ferhaColors.inkSecondary,
        letterSpacing: 0.5,
      ),
    );
  }
}

/// Indicateur d'attente à l'intérieur du bouton d'envoi.
class _Patiente extends StatelessWidget {
  const _Patiente();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 18,
      width: 18,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: Theme.of(context).colorScheme.onPrimary,
      ),
    );
  }
}

/// « Soirée », « Midi », « Journée entière ».
///
/// Le libellé du créneau tel qu'il se lit dans une phrase, là où
/// [Creneau.libelle] donne celui des puces.
String libelleCreneau(Creneau creneau) => switch (creneau) {
  Creneau.midi => 'Midi',
  Creneau.soir => 'Soirée',
  Creneau.journee => 'Journée entière',
};

/// « samedi » — le nom du jour, pour dire quelle majoration s'applique.
String _nomDuJour(DateTime date) => _jours[date.weekday - 1];

const List<String> _jours = <String>[
  'lundi',
  'mardi',
  'mercredi',
  'jeudi',
  'vendredi',
  'samedi',
  'dimanche',
];
