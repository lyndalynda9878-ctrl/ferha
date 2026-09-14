import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../core/router/routes.dart';
import '../../core/theme/ferha_colors.dart';
import '../../core/theme/ferha_radii.dart';
import '../../core/widgets/photo_salle.dart';
import '../search/search_filters.dart';
import '../search/widgets/etats.dart';
import 'booking_messages.dart';
import 'mes_reservations_providers.dart';
import 'reservation.dart';
import 'widgets/compte_a_rebours.dart';

/// Écran « Mes réservations » (§3 étapes 3 à 6, §4.2 CLI-06).
///
/// Ce que le client vient y chercher tient en une question : « où en est ma
/// demande ». L'écran y répond en toutes lettres — jamais « pending », jamais
/// un code — et il y répond SANS QU'ON AIT À REVENIR : l'abonnement Realtime
/// fait changer l'état sous les yeux quand le propriétaire répond.
///
/// LE TÉLÉPHONE DU PROPRIÉTAIRE N'APPARAÎT QU'À PARTIR DE « acceptée », et
/// c'est ici que la règle du §9 prend son sens : « sinon la plateforme se fait
/// contourner dès la première recherche ». Ce n'est pas cet écran qui la tient
/// — il ne le pourrait pas. `booking_contact()` (006) renvoie un numéro vide
/// tant que la demande n'est pas acceptée, et `client_bookings()` (013) recopie
/// cette réponse sans la relire. Retirer la condition d'affichage ci-dessous ne
/// ferait donc apparaître aucun numéro : il n'y en a pas dans la charge utile.
class MesReservationsScreen extends ConsumerWidget {
  /// Crée l'écran.
  const MesReservationsScreen({this.retourDePaiement, super.key});

  /// Ce que Chargily vient de faire, quand on arrive de sa page.
  ///
  /// C'est le paramètre `paiement` de l'adresse, et il vaut
  /// [FerhaRoutes.paiementEnVerification] ou [FerhaRoutes.paiementEchoue]. NI
  /// L'UN NI L'AUTRE NE CONFIRME QUOI QUE CE SOIT : le premier dit qu'un
  /// paiement est parti, pas qu'il est passé — seul le webhook Chargily le
  /// dira, et la réservation reste « acceptée » jusque-là.
  final String? retourDePaiement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reservations = ref.watch(mesReservationsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Mes réservations')),
      body: switch (reservations) {
        AsyncError(:final error) => EtatErreur(
          titre: 'Vos réservations n’ont pas pu être lues',
          erreur: error,
          onReessayer: () =>
              ref.read(mesReservationsProvider.notifier).reessayer(),
        ),
        AsyncData(:final value) when value.isEmpty => const _AucuneDemande(),
        AsyncData(:final value) => _Liste(
          reservations: value,
          retourDePaiement: retourDePaiement,
        ),
        _ => const _EnAttente(),
      },
    );
  }
}

class _Liste extends StatelessWidget {
  const _Liste({required this.reservations, this.retourDePaiement});

  final List<Reservation> reservations;
  final String? retourDePaiement;

  @override
  Widget build(BuildContext context) {
    final bandeau = _bandeauDeRetour(retourDePaiement);

    return ListView.separated(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 32),
      // Le bandeau de retour occupe la première place de la liste quand il y en
      // a un : il parle du geste qui vient d'être fait, et c'est la première
      // chose qu'on cherche en revenant.
      itemCount: reservations.length + (bandeau == null ? 0 : 1),
      separatorBuilder: (_, _) => const SizedBox(height: 14),
      itemBuilder: (context, i) {
        if (bandeau != null) {
          if (i == 0) return bandeau;
          i -= 1;
        }
        return _CarteReservation(
          reservation: reservations[i],
          // La clé porte le groupe : quand le temps réel remplace la liste, la
          // carte d'une réservation retrouve son élément — et le compte à
          // rebours qu'elle contient ne repart pas de zéro.
          key: ValueKey<String>(reservations[i].groupId),
        );
      },
    );
  }
}

/// Le mot qu'on lit en revenant de Chargily — et celui qu'on ne lit pas.
///
/// « PAIEMENT REÇU » N'EST PAS ÉCRIT ICI, ET NE DOIT PAS L'ÊTRE. Revenir sur
/// `success_url` veut seulement dire que le client a quitté la page de paiement
/// par la bonne porte : ni la banque ni Chargily ne nous ont encore rien dit.
/// C'est le webhook, signé et idempotent, qui fera passer la réservation en
/// « confirmée » — et tant qu'il n'a pas parlé, la carte juste au-dessous
/// affiche toujours « Acceptée — acompte à verser ». Un bandeau qui annoncerait
/// le contraire se contredirait lui-même, à trois centimètres d'écart.
Widget? _bandeauDeRetour(String? retour) => switch (retour) {
  FerhaRoutes.paiementEnVerification => const _BandeauRetour(
    icone: Icons.schedule_outlined,
    titre: 'Paiement en cours de vérification',
    texte:
        'Votre versement a bien été transmis. La réservation sera confirmée '
        'dès que la banque aura répondu — cela prend en général quelques '
        'minutes.',
    alerte: false,
  ),
  FerhaRoutes.paiementEchoue => const _BandeauRetour(
    icone: Icons.info_outline,
    titre: 'Paiement non abouti',
    texte:
        'Rien n’a été débité, et rien n’est perdu : votre option court '
        'toujours. Vous pouvez reprendre le versement ci-dessous.',
    alerte: true,
  ),
  _ => null,
};

class _BandeauRetour extends StatelessWidget {
  const _BandeauRetour({
    required this.icone,
    required this.titre,
    required this.texte,
    required this.alerte,
  });

  final IconData icone;
  final String titre;
  final String texte;
  final bool alerte;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;
    final (Color fond, Color encre) = alerte
        ? (colors.slotUnavailableSoft, colors.slotUnavailable)
        : (colors.primarySoft, colors.primaryDeep);

    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.all(14),
      decoration: BoxDecoration(
        color: fond,
        borderRadius: FerhaRadii.cardBorder,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icone, size: 20, color: encre),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  titre,
                  style: text.titleSmall?.copyWith(
                    color: encre,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  texte,
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

/// Une réservation, du haut : la salle, puis l'état, puis l'argent.
///
/// L'ORDRE N'EST PAS DÉCORATIF. On reconnaît d'abord de quel mariage il s'agit
/// — la photo et la date — et seulement ensuite où en est la demande. Un écran
/// qui commencerait par l'état obligerait à lire trois lignes pour savoir de
/// quelle salle on parle.
class _CarteReservation extends ConsumerWidget {
  const _CarteReservation({required this.reservation, super.key});

  final Reservation reservation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.ferhaColors;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsetsDirectional.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _EnTete(reservation: reservation),

            const SizedBox(height: 14),
            Divider(height: 1, color: colors.ruleSoft),
            const SizedBox(height: 12),

            _Etat(reservation: reservation),

            const SizedBox(height: 12),
            Divider(height: 1, color: colors.ruleSoft),
            const SizedBox(height: 10),

            _Montants(reservation: reservation),

            // Le contact, seulement une fois la demande acceptée (§9).
            if (reservation.telephone != null) ...<Widget>[
              const SizedBox(height: 12),
              _Contact(
                nom: reservation.proprietaire,
                telephone: reservation.telephone!,
              ),
            ],

            // VERSER L'ACOMPTE — le geste de l'écran 6, et l'unique porte qui y
            // mène. On ne l'offre que sur une option qui court encore : une
            // option échue attend le cron `expire_options`, qui passe au quart
            // d'heure, et proposer « Payer » pendant ces quelques minutes
            // mènerait à un écran qui refuse (FE053). `optionEnCours` compare à
            // l'instant présent, comme `tient_la_date()` en base — les deux
            // disent la même chose, à la minute.
            if (reservation.optionEnCours &&
                !reservation.optionExpireLe!.isBefore(DateTime.now()) &&
                reservation.acompteDu != null) ...<Widget>[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: FilledButton.icon(
                  onPressed: () => context.push(
                    FerhaRoutes.acompteDe(reservation.bookingId),
                  ),
                  icon: const Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 18,
                  ),
                  // acompteDu, et surtout pas acompte : c'est l'entier que la
                  // caisse encaissera, arrondi une seule fois en base. Ce bouton
                  // et l'écran 6 disent donc le même nombre, toujours.
                  label: Text(
                    'Verser l’acompte — '
                    '${montantEnDinars(reservation.acompteDu!)} DA',
                  ),
                ),
              ),
            ],

            // RACONTER SA SOIRÉE — le geste du §5.4, et la seconde porte vers
            // l'écran de dépôt ; la première est la notification que
            // `complete_booking()` dépose.
            //
            // `avisPossible` VIENT DE LA BASE et réunit les trois conditions :
            // réservation honorée, fenêtre de J+1 à J+30 ouverte, et aucune
            // réponse du propriétaire. On ne les recompose pas ici — ce serait
            // une seconde définition de la fenêtre, à côté de celle de 026.
            if (reservation.avisPossible) ...<Widget>[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                // PLEIN LA PREMIÈRE FOIS, CONTOURÉ ENSUITE. Déposer son avis est
                // ce qu'on attend de la cliente ; le corriger est une porte de
                // sortie, pas une invitation. Deux boutons plutôt qu'un bouton
                // paramétré : les deux styles ne partagent pas de type commun,
                // et un ternaire sur le constructeur ne compilerait pas.
                child: reservation.avisDepose
                    ? OutlinedButton.icon(
                        onPressed: () => context.push(
                          FerhaRoutes.deposerAvisDe(reservation.bookingId),
                        ),
                        icon: const Icon(Icons.rate_review_outlined, size: 18),
                        label: const Text('Modifier mon avis'),
                      )
                    : FilledButton.icon(
                        onPressed: () => context.push(
                          FerhaRoutes.deposerAvisDe(reservation.bookingId),
                        ),
                        icon: const Icon(Icons.rate_review_outlined, size: 18),
                        label: const Text('Déposer un avis'),
                      ),
              ),
            ]
            // L'avis est là et ne bouge plus : le propriétaire a répondu, ou
            // les trente jours sont passés. On ne propose donc aucun geste, mais
            // on ne fait pas non plus disparaître le sujet — sans cette ligne,
            // une cliente qui a écrit un avis ne verrait plus nulle part qu'elle
            // l'a fait.
            else if (reservation.avisDepose) ...<Widget>[
              const SizedBox(height: 12),
              _AvisPublie(bookingId: reservation.bookingId),
            ],

            if (reservation.etat.annulableParLeClient) ...<Widget>[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _demanderAnnulation(context, ref),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Annuler la demande'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Annuler demande une confirmation. Toujours.
  ///
  /// Une demande envoyée est le résultat de quatre écrans et d'un choix de
  /// date ; la refaire coûte plus qu'un tap. Et `cancel_booking()` ne se
  /// dédit pas : une réservation annulée ne revient pas en arrière.
  Future<void> _demanderAnnulation(BuildContext context, WidgetRef ref) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Annuler cette demande ?'),
        content: Text(
          '${reservation.salle}, le ${dateEnFrancais(reservation.date)}. '
          'Le propriétaire en sera informé, et vous devrez refaire une '
          'demande si vous changez d’avis.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Non, la garder'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Oui, annuler'),
          ),
        ],
      ),
    );

    if (confirme != true || !context.mounted) return;

    // Les textes avant l'await : le contexte peut avoir disparu ensuite.
    final textes = AppLocalizations.of(context);
    try {
      await ref.read(annulationServiceProvider).annuler(reservation.bookingId);
      // Rien à recharger : la mise à jour de bookings revient par Realtime,
      // par le même chemin que si le propriétaire avait annulé de son côté.
    } on Object catch (erreur) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(messageErreurDemande(textes, erreur))),
      );
    }
  }
}

/// « Votre avis est publié » — une ligne, pas un bouton.
///
/// ELLE REMPLACE LE BOUTON QUAND IL N'Y A PLUS RIEN À FAIRE : le propriétaire a
/// répondu, ou les trente jours du §5.4 sont passés. On pourrait ne rien
/// afficher du tout — mais une cliente qui a pris le temps d'écrire doit
/// retrouver la trace de son geste, sans quoi elle se demandera s'il est parti.
///
/// LE LIEN RESTE OUVERT. L'écran de dépôt sait s'afficher en lecture seule et
/// dire POURQUOI il l'est ; c'est mieux qu'un cul-de-sac, et c'est là qu'elle
/// lira la réponse du propriétaire.
class _AvisPublie extends StatelessWidget {
  const _AvisPublie({required this.bookingId});

  final String bookingId;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;

    return InkWell(
      onTap: () => context.push(FerhaRoutes.deposerAvisDe(bookingId)),
      borderRadius: FerhaRadii.cardBorder,
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(vertical: 6),
        child: Row(
          children: <Widget>[
            Icon(Icons.check_circle_outline, size: 16, color: colors.slotFree),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Votre avis est publié',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.inkSecondary),
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: colors.inkTertiary),
          ],
        ),
      ),
    );
  }
}

/// La salle, sa photo, la date, le créneau, les invités.
class _EnTete extends StatelessWidget {
  const _EnTete({required this.reservation});

  final Reservation reservation;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;
    final r = reservation;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ClipRRect(
          borderRadius: FerhaRadii.imageBorder,
          child: SizedBox(
            width: 78,
            height: 78,
            child: PhotoSalle(chemin: r.photo, tailleIcone: 22),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                r.salle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                r.localisation,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(color: colors.inkTertiary),
              ),
              const SizedBox(height: 6),
              Text(
                '${dateEnFrancais(r.date)} · '
                '${r.creneau.auMilieuDUnePhrase(AppLocalizations.of(context))}',
                style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              Text(
                <String>[
                  '${r.invites} invités',
                  if (r.typeEvenement != null) r.typeEvenement!,
                ].join(' · '),
                style: text.bodySmall?.copyWith(color: colors.inkSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// L'état, en français, avec sa pastille et son explication.
class _Etat extends StatelessWidget {
  const _Etat({required this.reservation});

  final Reservation reservation;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;
    final r = reservation;
    final (Color fond, Color encre) = _couleurs(r.etat, colors);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            // Une pastille de couleur ne dit rien à elle seule : le libellé est
            // à l'intérieur, et c'est lui qui porte l'information.
            Flexible(
              child: Container(
                padding: const EdgeInsetsDirectional.fromSTEB(10, 5, 10, 5),
                decoration: BoxDecoration(
                  color: fond,
                  borderRadius: FerhaRadii.chipBorder,
                ),
                child: Text(
                  r.etat.libelle,
                  style: text.labelLarge?.copyWith(
                    color: encre,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          r.etat.explication,
          style: text.bodySmall?.copyWith(color: colors.inkSecondary),
        ),

        // Le motif d'un refus ou d'une annulation, quand il y en a un : « sans
        // raison » laisse imaginer le pire.
        if (r.motif != null && r.motif!.trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            '« ${r.motif!.trim()} »',
            style: text.bodySmall?.copyWith(
              color: colors.inkSecondary,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],

        // Le compte à rebours des 72 h, en toutes lettres (maquettes, écran 6).
        if (r.optionEnCours) ...<Widget>[
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Icon(
                Icons.hourglass_bottom_outlined,
                size: 18,
                color: colors.primaryDeep,
              ),
              const SizedBox(width: 8),
              Text(
                'La date vous est réservée pendant ',
                style: text.bodyMedium?.copyWith(color: colors.inkSecondary),
              ),
              CompteARebours(
                echeance: r.optionExpireLe!,
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
      ],
    );
  }

  /// Les couleurs d'un état.
  ///
  /// Les trois jetons de créneau sont faits pour ça — leur documentation dit
  /// « calendrier et états de réservation uniquement » — et il en faut un
  /// quatrième usage : l'ocre de l'application pour l'état qui attend un geste
  /// DU CLIENT. « Acceptée » n'est pas une bonne nouvelle à contempler, c'est
  /// un acompte à verser, et elle doit se distinguer de « confirmée », qui ne
  /// demande plus rien.
  (Color, Color) _couleurs(EtatReservation etat, FerhaColors colors) =>
      switch (etat) {
        // Rien n'est acquis, rien n'est perdu.
        EtatReservation.enAttente => (
          colors.slotUnavailableSoft,
          colors.slotUnavailable,
        ),
        // À vous de jouer.
        EtatReservation.acceptee => (colors.primarySoft, colors.primaryDeep),
        // La date est à vous.
        EtatReservation.confirmee => (colors.slotFreeSoft, colors.slotFree),
        // Du passé, et une bonne nouvelle : ni vert d'alerte, ni rouge.
        EtatReservation.terminee => (
          colors.surfaceSecondary,
          colors.inkSecondary,
        ),
        // La date n'est pas — ou n'est plus — la vôtre.
        EtatReservation.refusee ||
        EtatReservation.annulee ||
        EtatReservation.expiree => (colors.slotBookedSoft, colors.slotBooked),
      };
}

/// Le devis, et l'acompte quand il est fixé.
class _Montants extends StatelessWidget {
  const _Montants({required this.reservation});

  final Reservation reservation;

  @override
  Widget build(BuildContext context) {
    final r = reservation;

    return Column(
      children: <Widget>[
        _LigneMontant(
          // Avant l'acceptation, c'est une estimation ; après, c'est ce que le
          // propriétaire a retenu. Le mot change parce que la chose change.
          libelle: r.etat == EtatReservation.enAttente
              ? 'Estimation'
              : 'Montant convenu',
          montant: r.montant,
          enAvant: true,
        ),
        if (r.acompte != null)
          _LigneMontant(libelle: 'Acompte', montant: r.acompte!),
      ],
    );
  }
}

class _LigneMontant extends StatelessWidget {
  const _LigneMontant({
    required this.libelle,
    required this.montant,
    this.enAvant = false,
  });

  final String libelle;
  final num montant;
  final bool enAvant;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              libelle,
              style: text.bodyMedium?.copyWith(color: colors.inkSecondary),
            ),
          ),
          Text(
            '${montantEnDinars(montant)} DA',
            style: (enAvant ? text.titleSmall : text.bodyMedium)?.copyWith(
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

/// Le contact du propriétaire — à partir de « acceptée », et pas avant (§9).
///
/// LE NUMÉRO EST ÉCRIT EN CLAIR ET SÉLECTIONNABLE, à côté du bouton. Un lien
/// `tel:` ouvre le composeur sur un téléphone, mais ne fait presque rien sur un
/// navigateur d'ordinateur — et l'application tourne aussi là. Quelqu'un devant
/// son écran doit pouvoir lire le numéro et le recopier, sans dépendre d'un
/// bouton qui ne mène nulle part chez lui.
class _Contact extends StatelessWidget {
  const _Contact({required this.nom, required this.telephone});

  final String? nom;
  final String telephone;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (nom != null)
            Text(
              nom!,
              style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          const SizedBox(height: 2),
          SelectableText(
            telephone,
            style: text.titleMedium?.copyWith(
              color: colors.ink,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilledButton.tonalIcon(
                onPressed: () => _appeler(context),
                icon: const Icon(Icons.call_outlined, size: 18),
                label: const Text('Appeler'),
              ),
              OutlinedButton.icon(
                onPressed: () => _copier(context),
                icon: const Icon(Icons.copy_all_outlined, size: 18),
                label: const Text('Copier'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _appeler(BuildContext context) async {
    // Les espaces d'un « 0770 11 22 33 » ne passent pas dans un URI tel:.
    final numero = telephone.replaceAll(RegExp(r'[^0-9+]'), '');
    final ouvert = await launchUrl(Uri(scheme: 'tel', path: numero));

    // Aucun composeur — un ordinateur, le plus souvent. On ne laisse pas le
    // tap sans réponse : le numéro reste lisible juste au-dessus, et on le dit.
    if (!ouvert && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Aucune application d’appel sur cet appareil. Le numéro est '
            'affiché juste au-dessus.',
          ),
        ),
      );
    }
  }

  Future<void> _copier(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: telephone));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Numéro copié.')));
  }
}

/// Aucune demande — et une porte de sortie.
class _AucuneDemande extends StatelessWidget {
  const _AucuneDemande();

  @override
  Widget build(BuildContext context) {
    return EtatVide(
      icone: Icons.event_note_outlined,
      titre: 'Vous n’avez pas encore de demande',
      explication:
          'Trouvez une salle, choisissez une date, et envoyez votre demande. '
          'Vous suivrez sa réponse ici.',
      pistes: <Widget>[
        FilledButton.icon(
          onPressed: () => context.go(FerhaRoutes.accueil),
          icon: const Icon(Icons.search, size: 18),
          label: const Text('Chercher une salle'),
        ),
      ],
    );
  }
}

/// Le squelette, pendant le premier chargement.
class _EnAttente extends StatelessWidget {
  const _EnAttente();

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;

    return ListView.separated(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 32),
      itemCount: 2,
      separatorBuilder: (_, _) => const SizedBox(height: 14),
      itemBuilder: (context, i) => Card(
        child: Padding(
          padding: const EdgeInsetsDirectional.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 78,
                height: 78,
                decoration: BoxDecoration(
                  color: colors.surfaceSecondary,
                  borderRadius: FerhaRadii.imageBorder,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 8,
                  children: <Widget>[
                    _Barre(largeur: 150, couleur: colors.surfaceSecondary),
                    _Barre(largeur: 100, couleur: colors.ruleSoft),
                    _Barre(largeur: 180, couleur: colors.surfaceSecondary),
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

class _Barre extends StatelessWidget {
  const _Barre({required this.largeur, required this.couleur});

  final double largeur;
  final Color couleur;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: largeur,
      height: 12,
      decoration: BoxDecoration(
        color: couleur,
        borderRadius: FerhaRadii.chipBorder,
      ),
    );
  }
}
