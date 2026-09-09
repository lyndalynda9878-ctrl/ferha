import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/ferha_colors.dart';
import '../../core/theme/ferha_radii.dart';
import '../search/search_filters.dart';
import 'booking_providers.dart';
import 'demande_screen.dart' show libelleCreneau;

/// L'écran qui suit l'envoi d'une demande.
///
/// UN ÉCRAN, PAS UN MESSAGE QUI DISPARAÎT. Un `SnackBar` s'efface au bout de
/// quatre secondes, souvent avant qu'on ait fini de le lire, et ne laisse rien
/// à relire. Ce qui vient d'être demandé est la seule trace que le client a de
/// son engagement : elle reste à l'écran tant qu'il ne s'en va pas.
///
/// Il dit DEUX choses, et la seconde compte autant que la première :
///   * ce qui a été demandé — salle, date, créneau, invités, options, montant ;
///   * ce qui se passe ensuite. Une demande en attente n'est pas une
///     réservation : elle ne bloque pas la date (§5.1), et il faut le dire tout
///     de suite plutôt que de laisser croire que le 14 août est acquis.
///
/// On y arrive par `pushReplacement` : le bouton retour ramène au calendrier,
/// et non sur un formulaire déjà envoyé.
class DemandeEnvoyeeScreen extends StatelessWidget {
  /// Crée l'écran de confirmation.
  const DemandeEnvoyeeScreen({
    required this.demande,
    this.reference,
    super.key,
  });

  /// Le récapitulatif de ce qui vient d'être envoyé.
  ///
  /// `null` quand on entre par un lien profond — un rechargement de page sur le
  /// web, par exemple. Le détail ne se réinvente pas : l'écran se replie alors
  /// sur ce qu'il sait avec certitude.
  final DemandeEnvoyee? demande;

  /// La référence lue dans l'adresse, seul survivant d'un rechargement.
  final String? reference;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;
    final d = demande;

    return Scaffold(
      appBar: AppBar(title: const Text('Demande envoyée')),
      body: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 24, 20, 32),
        children: <Widget>[
          Center(
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: colors.slotFreeSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check, size: 34, color: colors.slotFree),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Votre demande est partie',
            textAlign: TextAlign.center,
            style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            d == null
                ? 'Le propriétaire l’a reçue et vous répond sous 48 h.'
                : '${d.salle} a reçu votre demande et vous répond sous 48 h.',
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: colors.inkSecondary),
          ),

          if (d != null) ...<Widget>[
            const SizedBox(height: 24),
            _Recapitulatif(demande: d),
          ],

          const SizedBox(height: 24),
          const _Suite(),

          const SizedBox(height: 20),
          Center(
            child: Text(
              'Référence : ${d?.reference ?? _abrege(reference)}',
              style: text.bodySmall?.copyWith(color: colors.inkTertiary),
            ),
          ),

          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              // `go` et non `pop` : la pile derrière cet écran contient le
              // calendrier et la fiche de la salle qu'on vient de demander.
              // Y redescendre marche à marche n'a plus de sens une fois la
              // demande partie.
              onPressed: () => context.go(FerhaRoutes.accueil),
              style: FilledButton.styleFrom(
                padding: const EdgeInsetsDirectional.symmetric(vertical: 16),
              ),
              child: const Text('Revenir à l’accueil'),
            ),
          ),
        ],
      ),
    );
  }

  /// Une référence lue dans l'adresse ressemble à un UUID entier : on n'en
  /// montre que la tête, comme pour celle du récapitulatif.
  static String _abrege(String? groupId) {
    if (groupId == null || groupId.isEmpty) return '—';
    final tete = groupId.length >= 8 ? groupId.substring(0, 8) : groupId;
    return tete.toUpperCase();
  }
}

/// Ce qui a été demandé.
class _Recapitulatif extends StatelessWidget {
  const _Recapitulatif({required this.demande});

  final DemandeEnvoyee demande;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsetsDirectional.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: FerhaRadii.cardBorder,
        border: Border.all(color: colors.rule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            demande.salle,
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          Text(
            demande.localisation,
            style: text.bodySmall?.copyWith(color: colors.inkSecondary),
          ),
          const SizedBox(height: 12),

          _Ligne(
            libelle: 'Date',
            valeur:
                '${dateEnFrancais(demande.date)} · '
                '${libelleCreneau(demande.creneau).toLowerCase()}',
          ),
          _Ligne(libelle: 'Invités', valeur: '${demande.invites}'),
          if (demande.typeEvenement != null)
            _Ligne(libelle: 'Événement', valeur: demande.typeEvenement!),
          if (demande.options.isNotEmpty)
            _Ligne(
              libelle: 'Options',
              valeur: demande.options.map((o) => o.libelle).join(', '),
            ),

          Padding(
            padding: const EdgeInsetsDirectional.symmetric(vertical: 12),
            child: Divider(height: 1, color: colors.rule),
          ),

          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Estimation',
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                // Le montant écrit en base par estimate_price(), et non le
                // dernier total affiché par le formulaire : c'est celui-là qui
                // engage, et il arrive de la réponse même de request_booking().
                '${montantEnDinars(demande.montant)} DA',
                style: text.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.primaryDeep,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Le propriétaire peut proposer un montant différent en acceptant '
            'la demande.',
            style: text.bodySmall?.copyWith(color: colors.inkTertiary),
          ),
        ],
      ),
    );
  }
}

class _Ligne extends StatelessWidget {
  const _Ligne({required this.libelle, required this.valeur});

  final String libelle;
  final String valeur;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 90,
            child: Text(
              libelle,
              style: text.bodySmall?.copyWith(color: colors.inkTertiary),
            ),
          ),
          Expanded(child: Text(valeur, style: text.bodyMedium)),
        ],
      ),
    );
  }
}

/// Ce qui se passe ensuite — les trois étapes du §3, dans l'ordre.
///
/// La deuxième phrase est celle qui compte : une demande en attente ne bloque
/// pas la date (§5.1). Le dire ici évite qu'une famille cesse de chercher en
/// croyant le 14 août acquis, puis découvre trois jours plus tard qu'il a été
/// vendu à quelqu'un d'autre.
class _Suite extends StatelessWidget {
  const _Suite();

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    const etapes = <(IconData, String, String)>[
      (
        Icons.mark_email_read_outlined,
        'Le propriétaire répond sous 48 h',
        'Il accepte, refuse, ou vous propose un autre montant. Tant qu’il n’a '
            'pas répondu, la date reste ouverte à d’autres demandes.',
      ),
      (
        Icons.lock_clock_outlined,
        'S’il accepte, la date vous est gardée 72 h',
        'C’est le délai pour verser l’acompte. Passé ce délai sans paiement, '
            'la date repart à la vente.',
      ),
      (
        Icons.event_available_outlined,
        'L’acompte versé, la date est à vous',
        'Par carte CIB ou Edahabia, ou en main propre si le propriétaire '
            'l’accepte. Le solde se règle le jour J.',
      ),
    ];

    return Container(
      padding: const EdgeInsetsDirectional.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceSecondary,
        borderRadius: FerhaRadii.cardBorder,
        border: Border.all(color: colors.ruleSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Ce qui se passe ensuite',
            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          for (final (icone, titre, detail) in etapes)
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(icone, size: 20, color: colors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          titre,
                          style: text.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          detail,
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
        ],
      ),
    );
  }
}
