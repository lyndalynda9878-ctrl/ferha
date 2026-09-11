import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/router/routes.dart';
import '../../core/theme/ferha_colors.dart';
import '../../core/theme/ferha_radii.dart';
import '../search/search_filters.dart';
import '../search/widgets/etats.dart';
import 'acompte.dart';
import 'acompte_messages.dart';
import 'acompte_providers.dart';
import 'demande_screen.dart' show libelleCreneau;
import 'widgets/compte_a_rebours.dart';

/// Écran 6 — « Verser l'acompte » (§3 étape 5, §4.2 CLI-06).
///
/// CE QUE LE CLIENT VIENT Y FAIRE tient en un geste : payer ce qui est convenu,
/// avant que l'option de 72 h ne s'éteigne. L'écran est donc écrit de haut en
/// bas dans l'ordre où l'on décide — ce qui a été accepté et pour combien de
/// temps, ce qu'on paie exactement, avec quelle carte, puis le bouton.
///
/// LE COMPTE À REBOURS EST EN HAUT, ET EN TOUTES LETTRES. C'est le choix de la
/// maquette, et sa légende dit pourquoi : « le compte à rebours de 72 h est
/// affiché en toutes lettres ». Il est la raison d'être de cet écran ; le mettre
/// en bas ferait lire trois blocs avant d'apprendre qu'il reste deux heures.
///
/// LE MONTANT N'EST PAS CALCULÉ ICI. Ni les 25 %, ni le solde : les trois
/// nombres — montant convenu, acompte, solde — arrivent d'`acompte_a_verser()`
/// (024), et l'acompte y a été arrondi UNE fois, en SQL. Un `* 0.25` écrit dans
/// ce fichier serait une seconde formule de prix, et le bouton finirait par
/// annoncer autre chose que ce que Chargily encaisse.
///
/// L'OPTION « ESPÈCES SUR PLACE » DE LA MAQUETTE N'EST PAS LÀ. Elle viendra avec
/// le parcours qui la rend vraie (voir [MoyenDePaiement]).
class AcompteScreen extends ConsumerStatefulWidget {
  /// Crée l'écran pour la réservation [bookingId].
  const AcompteScreen({required this.bookingId, super.key});

  /// La ligne représentative du groupe — celle qu'attendent les fonctions SQL.
  final String bookingId;

  @override
  ConsumerState<AcompteScreen> createState() => _AcompteScreenState();
}

class _AcompteScreenState extends ConsumerState<AcompteScreen> {
  /// CIB en premier, comme dans la maquette : c'est la carte la plus répandue
  /// des deux. Un choix est déjà fait pour qui n'a rien à choisir, et le bouton
  /// est actif dès l'ouverture.
  MoyenDePaiement _moyen = MoyenDePaiement.cib;

  /// Vrai entre le tap sur « Payer » et l'ouverture de la page Chargily.
  bool _enRoute = false;

  /// Le refus du dernier essai, quand il y en a eu un.
  RefusAcompte? _refus;

  @override
  Widget build(BuildContext context) {
    final acompte = ref.watch(acompteProvider(widget.bookingId));

    return Scaffold(
      appBar: AppBar(title: const Text('Verser l’acompte')),
      body: switch (acompte) {
        AsyncError(:final error) => _impossible(erreur: error),
        AsyncData(:final value) => _Contenu(
          acompte: value,
          moyen: _moyen,
          enRoute: _enRoute,
          refus: _refus,
          onMoyen: (choisi) => setState(() {
            _moyen = choisi;
            // Un autre choix efface le refus du précédent : la phrase parlait
            // d'un essai qui n'existe plus.
            _refus = null;
          }),
          onAgir: _agir,
        ),
        _ => const _EnAttente(),
      },
    );
  }

  /// Le geste du bouton — et il y en a deux, selon le moyen choisi.
  ///
  /// Les cartes ouvrent une caisse chez Chargily et quittent l'application ; les
  /// espèces posent une intention et restent ici. Un seul bouton, deux gestes :
  /// c'est le moyen sélectionné qui décide, et son libellé le dit déjà.
  Future<void> _agir() async {
    if (_moyen.passeParChargily) return _payer();
    return _annoncerEspeces();
  }

  /// Annonce un versement en main propre.
  ///
  /// ON RECHARGE APRÈS, ET C'EST CE QUI FAIT L'ÉCRAN. `acompte_a_verser()` rend
  /// alors `especes_en_attente` à vrai, et le bandeau qui l'annonce apparaît de
  /// lui-même — plutôt qu'un état local qu'il faudrait tenir d'accord avec la
  /// base.
  Future<void> _annoncerEspeces() async {
    if (_enRoute) return;
    setState(() {
      _enRoute = true;
      _refus = null;
    });

    try {
      await ref.read(paiementServiceProvider).annoncerEspeces(widget.bookingId);

      if (!mounted) return;
      ref.invalidate(acompteProvider(widget.bookingId));
      setState(() => _enRoute = false);
    } on Object catch (erreur) {
      if (!mounted) return;
      setState(() {
        _enRoute = false;
        _refus = refusAcompte(erreur);
      });
    }
  }

  /// Ouvre la page de paiement, et y envoie le client.
  ///
  /// LE SECOND TAP NE CRÉE PAS UNE SECONDE PAGE. [_enRoute] éteint le bouton le
  /// temps de l'aller-retour, et la Edge Function, elle, retrouve de toute façon
  /// la page déjà ouverte : c'est la base qui garantit « une seule page active
  /// par réservation », pas ce booléen. Il n'évite qu'un double appel inutile.
  Future<void> _payer() async {
    if (_enRoute) return;
    setState(() {
      _enRoute = true;
      _refus = null;
    });

    try {
      final page = await ref
          .read(paiementServiceProvider)
          .ouvrirPage(bookingId: widget.bookingId, moyen: _moyen);

      if (!mounted) return;

      // Déjà encaissée. On n'ouvre pas une seconde caisse — et on ne dit pas
      // « confirmé » non plus : c'est le webhook qui confirmera.
      if (page.dejaPaye || page.url == null) {
        setState(() {
          _enRoute = false;
          _refus = (
            message:
                'Ce paiement a déjà été soumis. Il est en cours de '
                'vérification ; votre réservation sera confirmée dès que la '
                'banque aura répondu.',
            definitif: true,
          );
        });
        return;
      }

      final ouvert = await launchUrl(
        Uri.parse(page.url!),
        // DANS L'ONGLET COURANT, et non dans un nouveau. Une page de paiement
        // dont on revient par `success_url` n'a pas de raison d'ouvrir un
        // second onglet — et un `_blank` demandé après un `await` est bloqué
        // par les navigateurs, qui ne le rattachent plus au tap du client.
        webOnlyWindowName: '_self',
      );

      if (!mounted) return;
      setState(() {
        _enRoute = false;
        if (!ouvert) {
          _refus = (
            message:
                'La page de paiement n’a pas pu s’ouvrir. Vérifiez que votre '
                'navigateur n’a pas bloqué la redirection.',
            definitif: false,
          );
        }
      });
    } on Object catch (erreur) {
      if (!mounted) return;
      setState(() {
        _enRoute = false;
        _refus = refusAcompte(erreur);
      });
    }
  }

  /// L'écran quand la base refuse de préparer l'acompte.
  ///
  /// LES REFUS DÉFINITIFS NE PROPOSENT PAS « Réessayer ». « Le délai de 72 h est
  /// passé » ne se répare pas en rappuyant, et un bouton qui invite à un geste
  /// dont la réponse est déjà connue fait perdre deux fois : le temps du clic,
  /// et la confiance. On propose le seul geste qui reste — revenir à ses
  /// réservations, d'où une nouvelle demande peut partir.
  Widget _impossible({required Object erreur}) {
    final refus = refusAcompte(erreur);

    return EtatVide(
      icone: refus.definitif
          ? Icons.event_busy_outlined
          : Icons.cloud_off_outlined,
      titre: refus.definitif
          ? 'Il n’y a pas d’acompte à verser ici'
          : 'L’acompte n’a pas pu être lu',
      explication: refus.message,
      pistes: <Widget>[
        if (!refus.definitif)
          FilledButton.icon(
            onPressed: () => ref.invalidate(acompteProvider(widget.bookingId)),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Réessayer'),
          ),
        OutlinedButton.icon(
          onPressed: () => context.go(FerhaRoutes.mesReservations),
          icon: const Icon(Icons.event_note_outlined, size: 18),
          label: const Text('Mes réservations'),
        ),
      ],
    );
  }
}

/// Le corps de l'écran, une fois l'acompte connu.
class _Contenu extends StatelessWidget {
  const _Contenu({
    required this.acompte,
    required this.moyen,
    required this.enRoute,
    required this.refus,
    required this.onMoyen,
    required this.onAgir,
  });

  final AcompteAVerser acompte;
  final MoyenDePaiement moyen;
  final bool enRoute;
  final RefusAcompte? refus;
  final ValueChanged<MoyenDePaiement> onMoyen;
  final VoidCallback onAgir;

  /// Vrai quand le geste proposé a déjà été fait.
  bool get _annonceFaite => !moyen.passeParChargily && acompte.especesEnAttente;

  /// Ce que dit le bouton — et il ne dit pas « Payer » pour des espèces.
  ///
  /// « Payer 51 334 DA » devant un choix « espèces sur place » promettrait que
  /// l'argent part maintenant. Il ne part pas : le client annonce, et portera
  /// les billets. Le libellé doit dire le geste qu'on fait, pas celui qu'on
  /// fera.
  String get _libelleDuBouton {
    if (moyen.passeParChargily) {
      return 'Payer ${montantEnDinars(acompte.acompte)} DA';
    }
    if (acompte.especesEnAttente) return 'Versement déjà annoncé';
    return 'Annoncer un versement de '
        '${montantEnDinars(acompte.acompte)} DA';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 32),
      children: <Widget>[
        _Accepte(acompte: acompte),

        if (acompte.especesEnAttente) ...<Widget>[
          const SizedBox(height: 12),
          _EspecesAnnoncees(montant: acompte.acompte),
        ],

        if (acompte.paiementEnCours) ...<Widget>[
          const SizedBox(height: 12),
          const _EnVerification(),
        ],

        const SizedBox(height: 18),
        _Titre(texte: 'Récapitulatif'),

        const SizedBox(height: 8),
        _Ligne(libelle: acompte.salle, valeur: acompte.localisation),
        _Ligne(
          libelle:
              '${jourEnFrancais(acompte.date)} '
              '${dateEnFrancais(acompte.date)} · '
              '${libelleCreneau(acompte.creneau).toLowerCase()}',
          valeur: '${acompte.invites} inv.',
        ),
        if (acompte.typeEvenement != null)
          _Ligne(libelle: 'Événement', valeur: acompte.typeEvenement!),

        const SizedBox(height: 6),
        Divider(height: 1, color: colors.ruleSoft),
        const SizedBox(height: 6),

        _Ligne(
          libelle: 'Montant convenu',
          valeur: '${montantEnDinars(acompte.montantConvenu)} DA',
        ),
        _Ligne(
          libelle: acompte.partEnPourcent == null
              ? 'Acompte'
              : 'Acompte (${acompte.partEnPourcent} %)',
          valeur: '${montantEnDinars(acompte.acompte)} DA',
          enAvant: true,
        ),

        const SizedBox(height: 18),
        _Titre(texte: 'Moyen de paiement'),

        const SizedBox(height: 8),
        for (final choix in MoyenDePaiement.values) ...<Widget>[
          _Carte(
            moyen: choix,
            choisi: choix == moyen,
            onTap: enRoute ? null : () => onMoyen(choix),
          ),
          const SizedBox(height: 8),
        ],

        if (refus != null) ...<Widget>[
          const SizedBox(height: 4),
          _Refus(refus: refus!),
        ],

        const SizedBox(height: 12),
        SizedBox(
          height: 50,
          child: FilledButton(
            // Un refus définitif éteint le bouton : rappuyer rendrait mot pour
            // mot la même phrase. Même règle qu'à l'envoi d'une demande.
            //
            // Une intention d'espèces déjà posée l'éteint aussi quand c'est le
            // moyen choisi : la base est idempotente, mais un bouton qui reste
            // vif laisse croire que le premier appui n'a rien fait.
            onPressed: (enRoute || (refus?.definitif ?? false) || _annonceFaite)
                ? null
                : onAgir,
            child: enRoute
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    _libelleDuBouton,
                    textAlign: TextAlign.center,
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.onPrimary,
                    ),
                  ),
          ),
        ),

        const SizedBox(height: 10),
        Text(
          'Solde de ${montantEnDinars(acompte.solde)} DA réglé sur place le '
          'jour J.',
          textAlign: TextAlign.center,
          style: text.bodySmall?.copyWith(color: colors.inkTertiary),
        ),

        // Le mode test ne concerne que Chargily : un versement en main propre
        // est un vrai versement, et le dire « en mode test » serait faux.
        if (moyen.passeParChargily) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            // Dit au client plutôt que caché (v2.0, CLI-06). Il vaut mieux
            // qu'il l'apprenne ici que devant un relevé bancaire vide.
            'Paiement en mode test : aucune somme n’est réellement débitée.',
            textAlign: TextAlign.center,
            style: text.bodySmall?.copyWith(color: colors.inkTertiary),
          ),
        ],
      ],
    );
  }
}

/// Le bandeau vert de la maquette : la demande est acceptée, et le temps court.
class _Accepte extends StatelessWidget {
  const _Accepte({required this.acompte});

  final AcompteAVerser acompte;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;
    final proprietaire = acompte.proprietaire;

    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.all(14),
      decoration: BoxDecoration(
        color: colors.slotFreeSoft,
        borderRadius: FerhaRadii.cardBorder,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.check_circle_outline,
                size: 18,
                color: colors.slotFree,
              ),
              const SizedBox(width: 6),
              Text(
                'Demande acceptée',
                style: text.titleSmall?.copyWith(
                  color: colors.slotFree,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            <String>[
              if (proprietaire != null && proprietaire.trim().isNotEmpty)
                '$proprietaire a confirmé'
              else
                'Le propriétaire a confirmé',
              'le ${jourEnFrancais(acompte.date)} '
                  '${dateEnFrancais(acompte.date)}',
              'en ${libelleCreneau(acompte.creneau).toLowerCase()}.',
            ].join(' '),
            style: text.bodyMedium?.copyWith(color: colors.inkSecondary),
          ),
          const SizedBox(height: 8),
          // Le compte à rebours, en toutes lettres (maquette, écran 6). Il
          // descend tout seul : la minuterie bat à la seconde et ne redessine
          // qu'à la minute.
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              Icon(
                Icons.hourglass_bottom_outlined,
                size: 18,
                color: colors.primaryDeep,
              ),
              const SizedBox(width: 6),
              Text(
                'La date vous est réservée pendant ',
                style: text.bodyMedium?.copyWith(color: colors.inkSecondary),
              ),
              CompteARebours(
                echeance: acompte.optionExpireLe,
                style: text.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.primaryDeep,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// « Vous avez annoncé un versement en espèces » — et ce que cela veut dire.
///
/// CE BANDEAU NE DIT PAS QUE C'EST RÉGLÉ, et il porte le compte à rebours du
/// haut de l'écran comme un rappel : l'option de 72 h continue de courir, et
/// elle s'éteindra si les billets n'arrivent pas. C'est la différence avec une
/// carte — une carte payée prend la date dans la minute ; une promesse de
/// billets ne prend rien du tout tant que le propriétaire n'a pas compté.
///
/// Il dit donc le montant et le geste qui reste à faire, sans rassurer plus que
/// de raison.
class _EspecesAnnoncees extends StatelessWidget {
  const _EspecesAnnoncees({required this.montant});

  final int montant;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.all(12),
      decoration: BoxDecoration(
        color: colors.primarySoft,
        borderRadius: FerhaRadii.cardBorder,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.payments_outlined, size: 18, color: colors.primaryDeep),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Versement en espèces annoncé',
                  style: text.titleSmall?.copyWith(
                    color: colors.primaryDeep,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Le propriétaire vous attend avec '
                  '${montantEnDinars(montant)} DA. La date sera confirmée '
                  'quand il aura reçu l’acompte — et l’option court toujours '
                  'd’ici là.',
                  style: text.bodySmall?.copyWith(color: colors.inkSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// « Paiement en cours de vérification » — et pourquoi ce n'est pas « payé ».
///
/// Revenir de Chargily ne confirme RIEN : c'est le webhook, signé et idempotent,
/// qui fera passer la réservation en « confirmée ». Tant qu'il n'a pas parlé,
/// la seule phrase honnête est celle-ci. Dire « c'est réglé » ici, puis laisser
/// la réservation « acceptée » derrière, serait mentir pendant deux minutes — et
/// être cru.
class _EnVerification extends StatelessWidget {
  const _EnVerification();

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceSecondary,
        borderRadius: FerhaRadii.cardBorder,
        border: Border.all(color: colors.ruleSoft),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.schedule_outlined, size: 18, color: colors.inkSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Un paiement est en cours de vérification. Votre réservation sera '
              'confirmée dès que la banque aura répondu.',
              style: text.bodySmall?.copyWith(color: colors.inkSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Une carte à choisir.
class _Carte extends StatelessWidget {
  const _Carte({
    required this.moyen,
    required this.choisi,
    required this.onTap,
  });

  final MoyenDePaiement moyen;
  final bool choisi;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: choisi,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: FerhaRadii.cardBorder,
        child: Container(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 14, 12),
          decoration: BoxDecoration(
            color: choisi ? colors.primarySoft : colors.surface,
            borderRadius: FerhaRadii.cardBorder,
            border: Border.all(
              color: choisi ? colors.primary : colors.rule,
              width: choisi ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                choisi
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 20,
                color: choisi ? colors.primaryDeep : colors.inkTertiary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      moyen.libelle,
                      style: text.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: choisi ? colors.primaryDeep : colors.ink,
                      ),
                    ),
                    Text(
                      moyen.explication,
                      style: text.bodySmall?.copyWith(
                        color: colors.inkSecondary,
                      ),
                    ),
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

/// Le refus du dernier essai, sous les cartes et au-dessus du bouton.
class _Refus extends StatelessWidget {
  const _Refus({required this.refus});

  final RefusAcompte refus;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.all(12),
      decoration: BoxDecoration(
        color: colors.slotBookedSoft,
        borderRadius: FerhaRadii.cardBorder,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline, size: 18, color: colors.slotBooked),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              refus.message,
              style: text.bodySmall?.copyWith(color: colors.slotBooked),
            ),
          ),
        ],
      ),
    );
  }
}

/// Un intertitre — « Récapitulatif », « Moyen de paiement ».
class _Titre extends StatelessWidget {
  const _Titre({required this.texte});

  final String texte;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;

    return Text(
      texte,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: colors.inkTertiary,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

/// Une ligne du récapitulatif : le libellé à gauche, la valeur à droite.
class _Ligne extends StatelessWidget {
  const _Ligne({
    required this.libelle,
    required this.valeur,
    this.enAvant = false,
  });

  final String libelle;
  final String valeur;
  final bool enAvant;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Text(
              libelle,
              style: (enAvant ? text.bodyLarge : text.bodyMedium)?.copyWith(
                color: enAvant ? colors.ink : colors.inkSecondary,
                fontWeight: enAvant ? FontWeight.w700 : null,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            valeur,
            style: (enAvant ? text.titleMedium : text.bodyMedium)?.copyWith(
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

/// Le squelette, pendant le premier chargement.
class _EnAttente extends StatelessWidget {
  const _EnAttente();

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;

    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 32),
      children: <Widget>[
        _Bloc(hauteur: 92, couleur: colors.surfaceSecondary),
        const SizedBox(height: 18),
        _Bloc(hauteur: 120, couleur: colors.surfaceSecondary),
        const SizedBox(height: 18),
        _Bloc(hauteur: 64, couleur: colors.surfaceSecondary),
        const SizedBox(height: 8),
        _Bloc(hauteur: 64, couleur: colors.surfaceSecondary),
      ],
    );
  }
}

class _Bloc extends StatelessWidget {
  const _Bloc({required this.hauteur, required this.couleur});

  final double hauteur;
  final Color couleur;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: hauteur,
      decoration: BoxDecoration(
        color: couleur,
        borderRadius: FerhaRadii.cardBorder,
      ),
    );
  }
}
