import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/formats_ferha.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/router/routes.dart';
import '../../core/theme/ferha_colors.dart';
import '../../core/theme/ferha_radii.dart';
import '../search/search_filters.dart';
import 'mes_reservations_providers.dart';
import 'reservation.dart';

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
///
/// =============================================================================
/// IL NE REÇOIT QUE LA RÉFÉRENCE, ET IL RELIT LE RESTE
///
/// Le récapitulatif lui était tendu par l'écran précédent, qui l'avait déjà —
/// une requête d'économisée. Elle coûtait la page : `extra` de go_router ne
/// franchit pas l'historique du navigateur, et il ne le dit pas. Après un
/// rechargement ou un retour, l'écran s'affichait amputé et personne ne le
/// signalait, puisqu'il ne plantait pas.
///
/// Il lit donc `mesReservationsProvider` et y cherche son groupe. Trois états,
/// et aucun ne ment :
///
///   * la réservation est là — le récapitulatif entier ;
///   * elle se charge — la page sans son récapitulatif, qui arrive ensuite ;
///   * elle est introuvable ou la lecture a échoué — la page se replie sur ce
///     qu'elle sait avec certitude, sans rien inventer.
class DemandeEnvoyeeScreen extends ConsumerWidget {
  /// Crée l'écran de confirmation.
  const DemandeEnvoyeeScreen({required this.reference, super.key});

  /// La référence de la demande, portée par l'adresse.
  ///
  /// C'est `bookings.group_id` en entier ; l'écran n'en affiche que les huit
  /// premiers caractères. `null` quand on arrive sur `/demande-envoyee` sans
  /// rien — une adresse tapée à la main, par exemple.
  final String? reference;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;
    final textes = AppLocalizations.of(context);

    // LA RÉSERVATION, RELUE PAR SA RÉFÉRENCE.
    //
    // `client_bookings()` rend la liste du client ; on y prend le groupe dont
    // l'adresse porte l'identifiant. Une référence absente, une liste encore en
    // vol, une lecture qui a échoué, un groupe qui n'est pas le sien : les
    // quatre donnent `null`, et `null` mène au même repli. L'écran n'a pas à
    // distinguer une demande introuvable d'une session expirée — dans les deux
    // cas il ne sait pas, et il le dit de la même façon.
    final demandes = ref.watch(mesReservationsProvider);
    final d = reference == null
        ? null
        : demandes.value
              ?.where((r) => r.groupId == reference)
              .cast<Reservation?>()
              .firstWhere((r) => true, orElse: () => null);

    // Vrai tant qu'on ne sait pas encore : on ne montre pas un repli définitif
    // à quelqu'un dont la réservation est en train d'arriver.
    final enAttente = d == null && reference != null && demandes.isLoading;

    return Scaffold(
      appBar: AppBar(title: Text(textes.envoyeeTitre)),
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
            textes.envoyeePartie,
            textAlign: TextAlign.center,
            style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            d == null
                ? textes.envoyeeRecue
                : textes.envoyeeRecueParSalle(d.salle),
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: colors.inkSecondary),
          ),

          if (d != null) ...<Widget>[
            const SizedBox(height: 24),
            _Recapitulatif(reservation: d),
          ] else if (enAttente) ...<Widget>[
            const SizedBox(height: 24),
            const _RecapEnAttente(),
          ],

          const SizedBox(height: 24),
          const _Suite(),

          const SizedBox(height: 20),
          Center(
            child: Text(
              textes.envoyeeReference(_abrege(reference)),
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
              child: Text(textes.envoyeeRetourAccueil),
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
  const _Recapitulatif({required this.reservation});

  final Reservation reservation;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;
    final textes = AppLocalizations.of(context);
    final formats = FormatsFerha(textes);

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
            reservation.salle,
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          Text(
            reservation.localisation,
            style: text.bodySmall?.copyWith(color: colors.inkSecondary),
          ),
          const SizedBox(height: 12),

          _Ligne(
            libelle: textes.envoyeeLigneDate,
            valeur: textes.calendrierResumeJour(
              formats.date(reservation.date),
              reservation.creneau.auMilieuDUnePhrase(textes),
            ),
          ),
          _Ligne(
            libelle: textes.envoyeeLigneInvites,
            valeur: '${reservation.invites}',
          ),
          if (reservation.typeEvenement != null)
            _Ligne(
              libelle: textes.envoyeeLigneEvenement,
              valeur: reservation.typeEvenement!,
            ),
          if (reservation.options.isNotEmpty)
            _Ligne(
              libelle: textes.envoyeeLigneOptions,
              // DES LIBELLÉS, ET AUCUN PRIX — voir la migration 033. Le montant,
              // options comprises, est celui de la ligne « Estimation ».
              valeur: reservation.options.join(textes.separateurListe),
            ),

          Padding(
            padding: const EdgeInsetsDirectional.symmetric(vertical: 12),
            child: Divider(height: 1, color: colors.rule),
          ),

          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  textes.envoyeeEstimation,
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                // Le montant écrit en base par estimate_price(), et non le
                // dernier total affiché par le formulaire : c'est celui-là qui
                // engage, et il vient de `client_bookings()`.
                formats.montant(reservation.montant),
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
            textes.envoyeeMontantPeutChanger,
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
    final textes = AppLocalizations.of(context);

    final etapes = <(IconData, String, String)>[
      (
        Icons.mark_email_read_outlined,
        textes.envoyeeSuite1Titre,
        textes.envoyeeSuite1Detail,
      ),
      (
        Icons.lock_clock_outlined,
        textes.envoyeeSuite2Titre,
        textes.envoyeeSuite2Detail,
      ),
      (
        Icons.event_available_outlined,
        textes.envoyeeSuite3Titre,
        textes.envoyeeSuite3Detail,
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
            textes.envoyeeSuiteTitre,
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

/// Le récapitulatif tant que la réservation n'est pas revenue.
///
/// TROIS BARRES PLUTÔT QU'UNE ROUE, comme partout ailleurs : l'écran ne saute
/// pas quand les données se posent, et l'attente paraît plus courte parce qu'on
/// voit déjà où regarder. Elle ne dure d'ailleurs qu'un aller-retour — celui
/// qu'on a échangé contre une page qui survit à un rechargement.
class _RecapEnAttente extends StatelessWidget {
  const _RecapEnAttente();

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;

    return Container(
      padding: const EdgeInsetsDirectional.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: FerhaRadii.cardBorder,
        border: Border.all(color: colors.rule),
      ),
      child: Column(
        spacing: 12,
        children: <Widget>[
          for (final largeur in <double>[0.6, 0.45, 0.75])
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
