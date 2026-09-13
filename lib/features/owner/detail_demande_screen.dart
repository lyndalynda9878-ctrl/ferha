import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/ferha_colors.dart';
import '../../core/theme/ferha_radii.dart';
import '../booking/reservation.dart';
import '../reviews/avis_messages.dart';
import '../search/search_filters.dart';
import '../search/widgets/etats.dart';
import 'demande_detail.dart';
import 'demande_en_attente.dart';
import 'owner_messages.dart';
import 'owner_providers.dart';

/// Le détail d'une demande, et la réponse du propriétaire (§4.3, OWN-05).
///
/// AUCUNE MAQUETTE NE DESSINE CET ÉCRAN — le flux D en montre trois, et le
/// dixième est l'ajout des photos. Sa structure est donc déduite de la carte de
/// l'écran 9, dont il est le dépliement : les mêmes informations dans le même
/// ordre, plus ce qui ne tenait pas dans une carte — le nom entier du client,
/// son message, les options retenues.
///
/// L'ORDRE SUIT LA DÉCISION À PRENDRE. On regarde d'abord QUAND et POUR QUI —
/// c'est ce qui fait dire oui ou non —, ensuite ce que le client a demandé, et
/// l'argent en dernier. Un écran qui commencerait par le montant ferait
/// arbitrer un mariage au prix, ce que le §5.2 refuse déjà en interdisant qu'un
/// prix soit saisi.
///
/// LES DEUX BOUTONS NE SONT PAS CE QUI PROTÈGE. `accepter_demande()` et
/// `refuser_demande()` (015) vérifient elles-mêmes que la salle est bien celle
/// du demandeur, et refusent une demande déjà tranchée. Les cacher quand la
/// demande n'attend plus de réponse évite de proposer un geste qui échouerait ;
/// cela n'empêche rien.
///
/// LE REFUS DEMANDE CONFIRMATION, PAS L'ACCEPTATION, et ce n'est pas une
/// distraction. Un refus est définitif pour cette demande et ne se rattrape
/// pas — la famille reçoit un « non » qu'on ne peut pas retirer. Une
/// acceptation, elle, pose une option de 72 h qui expire d'elle-même si rien ne
/// suit (§5.1) : le pire d'un geste malheureux est trois jours d'attente.
/// Le bouton « Accepter » de la barre du bas.
const Key cleAccepter = Key('demande-accepter');

/// Le bouton « Refuser » de la barre du bas — celui qui OUVRE la confirmation.
const Key cleRefuser = Key('demande-refuser');

/// Le champ de motif de la fenêtre de confirmation.
/// Le bouton « J'ai reçu l'acompte », sur une demande où le client a annoncé
/// un versement en espèces.
const Key cleEncaissementEspeces = Key('demande-especes-confirmer');

/// La fenêtre qui le confirme.
const Key cleConfirmerEspeces = Key('demande-especes-oui');

/// Le bouton « L'événement a eu lieu », sur une réservation confirmée dont la
/// date est passée.
const Key cleMarquerHonoree = Key('demande-honoree');

/// La fenêtre qui le confirme.
const Key cleConfirmerHonoree = Key('demande-honoree-oui');

const Key cleMotif = Key('demande-motif');

/// Le bouton qui refuse pour de bon, dans la fenêtre.
const Key cleConfirmerRefus = Key('demande-refuser-confirmer');

/// Le bouton qui renonce au refus.
const Key cleAnnulerRefus = Key('demande-refuser-annuler');

class DetailDemandeScreen extends ConsumerWidget {
  /// Crée l'écran de détail.
  const DetailDemandeScreen({required this.bookingId, super.key});

  /// La demande à ouvrir — la ligne représentative de son groupe.
  final String bookingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(detailDemandeProvider(bookingId));

    return Scaffold(
      appBar: AppBar(title: const Text('La demande')),
      body: switch (detail) {
        AsyncError(:final error) => EtatErreur(
          titre: 'Cette demande n’a pas pu être ouverte',
          erreur: error,
          onReessayer: () => ref.invalidate(detailDemandeProvider(bookingId)),
        ),
        AsyncData(:final value) => _Detail(demande: value),
        _ => const _Squelette(),
      },
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.demande});

  final DemandeDetail demande;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 24),
            children: <Widget>[
              _EnTete(demande: demande),
              if (!demande.attendUneReponse) ...<Widget>[
                const SizedBox(height: 16),
                _EtatDeLaDemande(demande: demande),
              ],
              const SizedBox(height: 20),
              _Evenement(demande: demande),
              if (demande.message != null && demande.message!.isNotEmpty) ...[
                const SizedBox(height: 20),
                _MessageDuClient(message: demande.message!),
              ],
              const SizedBox(height: 20),
              _Devis(demande: demande),
              const SizedBox(height: 20),
              _Contact(demande: demande),
              if (demande.especesEnAttente) ...<Widget>[
                const SizedBox(height: 20),
                _EspecesAConfirmer(demande: demande),
              ],
              if (demande.honorable) ...<Widget>[
                const SizedBox(height: 20),
                _AMarquerHonoree(demande: demande),
              ],
            ],
          ),
        ),
        // Les boutons restent visibles quelle que soit la longueur du message
        // du client : la décision ne doit pas se chercher au bas d'un
        // défilement.
        if (demande.attendUneReponse) _Actions(demande: demande),
      ],
    );
  }
}

// =============================================================================
// Le haut de l'écran : pour qui, et depuis quand
// =============================================================================

class _EnTete extends StatelessWidget {
  const _EnTete({required this.demande});

  final DemandeDetail demande;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Le nom ENTIER, là où la liste n'en donnait que l'initiale. On décide
        // d'un mariage en sachant à qui l'on répond ; on trie une file sans.
        Text(demande.client, style: text.headlineSmall),
        const SizedBox(height: 4),
        Text(
          '${demande.salle} · demande reçue '
          '${attenteEnFrancais(demande.creeLe, DateTime.now())}',
          style: text.bodySmall?.copyWith(color: colors.inkSecondary),
        ),
      ],
    );
  }
}

/// Ce que devient une demande à laquelle on a déjà répondu.
///
/// LES LIBELLÉS D'[EtatReservation] NE CONVIENNENT PAS ICI, et c'est écrit dans
/// cette énumération : ils sont rédigés DU POINT DE VUE DU CLIENT. « Acceptée —
/// acompte à verser » s'adresse à qui doit verser l'acompte, pas à qui
/// l'attend. L'état, lui, est le même des deux côtés : une seule valeur en base,
/// deux façons de la dire.
class _EtatDeLaDemande extends StatelessWidget {
  const _EtatDeLaDemande({required this.demande});

  final DemandeDetail demande;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    final (String phrase, IconData icone) = switch (demande.etat) {
      EtatReservation.acceptee => (
        'Acceptée. Le client a 72 h pour verser l’acompte ; passé ce délai, '
            'la date repart à la vente.',
        Icons.schedule,
      ),
      EtatReservation.confirmee => (
        'Confirmée. L’acompte est versé et la date est prise.',
        Icons.check_circle_outline,
      ),
      EtatReservation.terminee => (
        'Terminée. L’événement a eu lieu.',
        Icons.done_all,
      ),
      EtatReservation.refusee => (
        'Vous avez refusé cette demande.',
        Icons.block,
      ),
      EtatReservation.annulee => (
        'Cette demande a été annulée.',
        Icons.cancel_outlined,
      ),
      EtatReservation.expiree => (
        'L’option de 72 h a expiré sans acompte : la date est repartie à la '
            'vente.',
        Icons.hourglass_disabled,
      ),
      // Jamais atteint — le bandeau ne s'affiche pas sur une demande en
      // attente. Écrit quand même : une énumération se balaie en entier.
      EtatReservation.enAttente => (
        'En attente de votre réponse.',
        Icons.hourglass_empty,
      ),
    };

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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icone, size: 18, color: colors.inkSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  phrase,
                  style: text.bodyMedium?.copyWith(color: colors.ink),
                ),
              ),
            ],
          ),
          // Le motif d'un refus est écrit pour être lu par le client, sur son
          // écran de suivi. Le montrer ici rappelle au propriétaire ce qu'il a
          // dit — et à quoi le client répondra s'il rappelle.
          if (demande.motif != null && demande.motif!.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              'Motif communiqué : « ${demande.motif} »',
              style: text.bodySmall?.copyWith(color: colors.inkSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

// =============================================================================
// Ce que le client a demandé
// =============================================================================

class _Evenement extends StatelessWidget {
  const _Evenement({required this.demande});

  final DemandeDetail demande;

  @override
  Widget build(BuildContext context) {
    return _Bloc(
      titre: 'L’événement',
      enfants: <Widget>[
        _Ligne(
          icone: Icons.event_outlined,
          libelle: 'Date',
          valeur: dateEnFrancais(demande.date),
        ),
        _Ligne(
          icone: Icons.schedule_outlined,
          libelle: 'Créneau',
          valeur: demande.creneau.libelle,
        ),
        _Ligne(
          icone: Icons.groups_outlined,
          libelle: 'Invités',
          valeur: '${demande.invites}',
        ),
        if (demande.typeEvenement != null)
          _Ligne(
            icone: Icons.celebration_outlined,
            libelle: 'Type',
            valeur: demande.typeEvenement!,
          ),
      ],
    );
  }
}

class _MessageDuClient extends StatelessWidget {
  const _MessageDuClient({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    return _Bloc(
      titre: 'Son message',
      enfants: <Widget>[
        // Sélectionnable : il arrive qu'un client y glisse un numéro ou un nom
        // à recopier, et l'écran n'a pas à décider que c'est interdit.
        SelectableText(
          message,
          style: text.bodyMedium?.copyWith(color: colors.ink, height: 1.45),
        ),
      ],
    );
  }
}

// =============================================================================
// L'argent, en dernier
// =============================================================================

class _Devis extends StatelessWidget {
  const _Devis({required this.demande});

  final DemandeDetail demande;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    return _Bloc(
      titre: 'Le devis',
      enfants: <Widget>[
        if (demande.options.isNotEmpty) ...<Widget>[
          for (final option in demande.options)
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: 6),
              child: Row(
                children: <Widget>[
                  Icon(Icons.check, size: 16, color: colors.inkTertiary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      option.libelle,
                      style: text.bodyMedium?.copyWith(
                        color: colors.inkSecondary,
                      ),
                    ),
                  ),
                  Text(
                    // Une option à zéro dinar n'est pas une option absente :
                    // c'est une chambre à préparer, même offerte.
                    option.estIncluse
                        ? 'Incluse'
                        : '${montantEnDinars(option.prix)} DA',
                    style: text.bodySmall?.copyWith(color: colors.inkSecondary),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Divider(height: 1, color: colors.ruleSoft),
          const SizedBox(height: 10),
        ],
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Estimation',
                style: text.bodyMedium?.copyWith(color: colors.inkSecondary),
              ),
            ),
            Text(
              // Le devis d'estimate_price(), tel quel. Le §5.2 autorise le
              // propriétaire à proposer un autre montant en acceptant — ce
              // geste-là a besoin d'une saisie et d'un écran, et il viendra à
              // son étape. Rien ici ne recalcule ni n'ajuste.
              '${montantEnDinars(demande.montant)} DA',
              style: text.titleMedium?.copyWith(color: colors.primaryDeep),
            ),
          ],
        ),
        if (demande.acompte != null) ...<Widget>[
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Acompte demandé',
                  style: text.bodyMedium?.copyWith(color: colors.inkSecondary),
                ),
              ),
              Text(
                '${montantEnDinars(demande.acompte!)} DA',
                style: text.bodyMedium?.copyWith(color: colors.ink),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// =============================================================================
// Le contact — et la règle du §9
// =============================================================================

/// Le téléphone du client, quand la base a le droit de le donner.
///
/// CE N'EST PAS CET ÉCRAN QUI TIENT LA RÈGLE DU §9. `booking_contact()` (006)
/// renvoie un numéro vide tant que la demande n'est pas acceptée, et
/// `owner_request_detail()` recopie cette réponse sans la relire. Retirer la
/// condition ci-dessous ne ferait apparaître aucun numéro : il n'y en a pas
/// dans la charge utile.
///
/// Ce que l'écran ajoute, c'est de DIRE POURQUOI. Un champ vide laisserait
/// croire que le client n'a pas de téléphone, ce qui ferait chercher une
/// explication ailleurs.
class _Contact extends StatelessWidget {
  const _Contact({required this.demande});

  final DemandeDetail demande;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    if (!demande.telephoneDisponible) {
      return _Bloc(
        titre: 'Le contact',
        enfants: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.lock_outline, size: 18, color: colors.inkTertiary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Le téléphone du client vous sera donné dès que vous aurez '
                  'accepté la demande.',
                  style: text.bodyMedium?.copyWith(color: colors.inkSecondary),
                ),
              ),
            ],
          ),
        ],
      );
    }

    final numero = demande.telephone;
    if (numero == null || numero.isEmpty) {
      return _Bloc(
        titre: 'Le contact',
        enfants: <Widget>[
          Text(
            'Ce client n’a pas renseigné de numéro de téléphone.',
            style: text.bodyMedium?.copyWith(color: colors.inkSecondary),
          ),
        ],
      );
    }

    return _Bloc(
      titre: 'Le contact',
      enfants: <Widget>[
        Row(
          children: <Widget>[
            Icon(Icons.phone_outlined, size: 18, color: colors.primaryDeep),
            const SizedBox(width: 10),
            // Écrit en clair et sélectionnable, comme côté client : un lien
            // `tel:` ne fait presque rien sur un navigateur d'ordinateur, et
            // le back-office se consulte au bureau.
            Expanded(
              child: SelectableText(
                numero,
                style: text.titleMedium?.copyWith(color: colors.ink),
              ),
            ),
            IconButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: numero));
                if (!context.mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Numéro copié.')));
              },
              icon: const Icon(Icons.copy_outlined, size: 18),
              tooltip: 'Copier le numéro',
            ),
          ],
        ),
      ],
    );
  }
}

// =============================================================================
// Les deux boutons
// =============================================================================

/// « Le client vient vous apporter l'acompte » — et le bouton qui le constate.
///
/// IL N'APPARAÎT QUE QUAND UN VERSEMENT EST ANNONCÉ (`especes_en_attente`), et
/// jamais autrement. Un bouton « J'ai reçu l'acompte » toujours visible
/// inviterait le propriétaire à prendre une date pour de l'argent que personne
/// ne lui a promis — et c'est lui qui en porterait la conséquence le jour où
/// deux familles se présenteraient.
///
/// IL DEMANDE CONFIRMATION, TOUJOURS. Ce tap prend la date : il fait passer la
/// réservation en « confirmée », exactement comme un paiement Chargily, et rien
/// ne la fera revenir en arrière. Un geste irréversible qui se déclenche au
/// premier appui, sur un écran qu'on parcourt, est un geste qu'on finit par
/// faire par erreur.
///
/// LE MONTANT AFFICHÉ EST `acompteDu`, l'entier — le même que celui que le
/// client a lu sur son écran 6. C'est ce qu'il apportera, et c'est donc ce
/// qu'il faut compter.
class _EspecesAConfirmer extends ConsumerStatefulWidget {
  const _EspecesAConfirmer({required this.demande});

  final DemandeDetail demande;

  @override
  ConsumerState<_EspecesAConfirmer> createState() => _EspecesAConfirmerState();
}

class _EspecesAConfirmerState extends ConsumerState<_EspecesAConfirmer> {
  bool _enCours = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;
    final montant = widget.demande.acompteDu;

    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.all(14),
      decoration: BoxDecoration(
        color: colors.primarySoft,
        borderRadius: FerhaRadii.cardBorder,
        border: Border.all(color: colors.primary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.payments_outlined,
                size: 18,
                color: colors.primaryDeep,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Acompte en espèces annoncé',
                  style: text.titleSmall?.copyWith(
                    color: colors.primaryDeep,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            montant == null
                ? '${widget.demande.client} vous apportera l’acompte à la '
                      'salle. Confirmez une fois que vous l’aurez reçu : la '
                      'date sera alors prise.'
                : '${widget.demande.client} vous apportera '
                      '${montantEnDinars(montant)} DA à la salle. Confirmez '
                      'une fois que vous les aurez reçus : la date sera alors '
                      'prise.',
            style: text.bodySmall?.copyWith(color: colors.inkSecondary),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: cleEncaissementEspeces,
              onPressed: _enCours ? null : _confirmer,
              icon: _enCours
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check, size: 18),
              label: const Text('J’ai reçu l’acompte'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmer() async {
    final montant = widget.demande.acompteDu;

    final confirme = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmer l’encaissement ?'),
        content: Text(
          montant == null
              ? 'La date sera prise et ne pourra plus être rendue. Ne '
                    'confirmez qu’une fois l’argent en main.'
              : 'Vous confirmez avoir reçu ${montantEnDinars(montant)} DA de '
                    '${widget.demande.client}. La date sera prise et ne pourra '
                    'plus être rendue — ne confirmez qu’une fois l’argent en '
                    'main.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Pas encore'),
          ),
          FilledButton(
            key: cleConfirmerEspeces,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Oui, j’ai reçu'),
          ),
        ],
      ),
    );

    if (confirme != true || !mounted) return;

    setState(() => _enCours = true);
    try {
      // Le service, et non le dépôt en direct : c'est lui qui sait ce que cette
      // confirmation vient de rendre faux — le détail, la file des demandes,
      // le revenu du mois. L'écran se recharge donc tout seul, l'état passe à
      // « confirmée » sous les yeux, et ce bloc disparaît : il n'y a plus rien
      // à confirmer.
      await ref
          .read(reponseADemandeServiceProvider)
          .confirmerEspeces(widget.demande);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Acompte encaissé. La date est prise.')),
      );
    } on Object catch (erreur) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(messageErreurReponse(erreur))));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }
}

/// « L'événement a eu lieu » — le geste qui débloque l'avis (§3, étape 6).
///
/// IL N'EXISTAIT PAS AVANT LE J17, et c'est ce qui rendait le §5.4 inatteignable :
/// `complete_booking()` était écrite depuis la migration 004 et aucun écran ne
/// l'appelait. Une réservation payée restait « confirmée » pour toujours, et
/// personne ne pouvait noter une salle.
///
/// IL NE S'AFFICHE QU'APRÈS LA DATE, parce qu'on ne marque pas honoré ce qui n'a
/// pas eu lieu. La base le refuse aussi (FE073) ; le cacher évite seulement de
/// proposer un geste qui échouerait.
///
/// IL DEMANDE CONFIRMATION, comme l'encaissement en espèces. Marquer honoré ne
/// se défait pas : il n'existe aucune transition qui ramène de « completed » à
/// « confirmed », et le client reçoit dans la seconde une invitation à noter la
/// salle. Un premier appui, sur un écran qu'on parcourt, est un geste qu'on
/// finit par faire par erreur.
class _AMarquerHonoree extends ConsumerStatefulWidget {
  const _AMarquerHonoree({required this.demande});

  final DemandeDetail demande;

  @override
  ConsumerState<_AMarquerHonoree> createState() => _AMarquerHonoreeState();
}

class _AMarquerHonoreeState extends ConsumerState<_AMarquerHonoree> {
  bool _enCours = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.all(14),
      decoration: BoxDecoration(
        color: colors.goldSoft,
        borderRadius: FerhaRadii.cardBorder,
        border: Border.all(color: colors.gold),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.celebration_outlined,
                size: 18,
                color: colors.primaryDeep,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'La date est passée',
                  style: text.titleSmall?.copyWith(
                    color: colors.primaryDeep,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Confirmez que l’événement a bien eu lieu. '
            '${widget.demande.client} pourra alors déposer un avis sur votre '
            'salle, pendant trente jours.',
            style: text.bodySmall?.copyWith(color: colors.inkSecondary),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: cleMarquerHonoree,
              onPressed: _enCours ? null : _marquer,
              icon: _enCours
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check, size: 18),
              label: const Text('L’événement a eu lieu'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _marquer() async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('L’événement a-t-il eu lieu ?'),
        content: Text(
          'La réservation passera en « terminée », et ${widget.demande.client} '
          'sera invitée à déposer un avis sur votre salle. Ce geste ne se '
          'défait pas.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Pas encore'),
          ),
          FilledButton(
            key: cleConfirmerHonoree,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Oui, c’est fait'),
          ),
        ],
      ),
    );

    if (confirme != true || !mounted) return;

    setState(() => _enCours = true);
    try {
      await ref
          .read(reponseADemandeServiceProvider)
          .marquerHonoree(widget.demande);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'C’est noté. Votre cliente peut maintenant vous noter.',
          ),
        ),
      );
    } on Object catch (erreur) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(messageErreurHonorer(erreur))));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }
}

class _Actions extends ConsumerStatefulWidget {
  const _Actions({required this.demande});

  final DemandeDetail demande;

  @override
  ConsumerState<_Actions> createState() => _ActionsState();
}

class _ActionsState extends ConsumerState<_Actions> {
  bool _enCours = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;

    return Material(
      color: colors.surface,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 12),
          child: Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  // Les deux boutons portent une clé, et la fenêtre de refus
                  // aussi : « Refuser » s'écrit à deux endroits dès qu'elle
                  // s'ouvre, et un test qui les confondrait vérifierait le
                  // mauvais.
                  key: cleRefuser,
                  onPressed: _enCours ? null : _refuser,
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Refuser'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsetsDirectional.symmetric(
                      vertical: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  key: cleAccepter,
                  onPressed: _enCours ? null : _accepter,
                  icon: _enCours
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check, size: 18),
                  label: const Text('Accepter'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsetsDirectional.symmetric(
                      vertical: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _accepter() async {
    await _repondre(
      (service) => service.accepter(widget.demande),
      succes: 'Demande acceptée. Le client a 72 h pour verser l’acompte.',
    );
  }

  Future<void> _refuser() async {
    final motif = await showDialog<String?>(
      context: context,
      builder: (context) => _DialogueDeRefus(client: widget.demande.client),
    );
    // `null` = la fenêtre a été fermée sans confirmer. Une chaîne vide est un
    // refus assumé sans motif : les deux ne se confondent pas.
    if (motif == null) return;

    await _repondre(
      (service) =>
          service.refuser(widget.demande, motif: motif.isEmpty ? null : motif),
      succes: 'Demande refusée. Le client en est informé.',
    );
  }

  Future<void> _repondre(
    Future<void> Function(ReponseADemandeService) geste, {
    required String succes,
  }) async {
    setState(() => _enCours = true);
    try {
      await geste(ref.read(reponseADemandeServiceProvider));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(succes)));
    } on Object catch (erreur) {
      if (!mounted) return;
      // Le refus de la base traduit en une phrase qui dit quoi faire — jamais
      // le message brut de PostgREST.
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(messageErreurReponse(erreur))));
    } finally {
      // L'écran reste ouvert et se recharge : le propriétaire voit l'option de
      // 72 h se poser et l'acompte apparaître. Le faire sortir lui cacherait
      // ce qu'il vient de décider.
      if (mounted) setState(() => _enCours = false);
    }
  }
}

/// La confirmation d'un refus, et la question du motif.
///
/// LE MOTIF EST DEMANDÉ, PAS EXIGÉ — le bouton reste actif sur un champ vide,
/// comme `refuser_demande()` accepte un motif nul. Obliger à écrire quelque
/// chose produirait des « non » et des points, pas des raisons.
class _DialogueDeRefus extends StatefulWidget {
  const _DialogueDeRefus({required this.client});

  final String client;

  @override
  State<_DialogueDeRefus> createState() => _DialogueDeRefusState();
}

class _DialogueDeRefusState extends State<_DialogueDeRefus> {
  final TextEditingController _motif = TextEditingController();

  @override
  void dispose() {
    _motif.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    return AlertDialog(
      title: const Text('Refuser cette demande ?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '${widget.client} recevra votre réponse, et la demande sera close. '
            'Vous ne pourrez pas revenir dessus.',
            style: text.bodyMedium?.copyWith(color: colors.inkSecondary),
          ),
          const SizedBox(height: 16),
          TextField(
            key: cleMotif,
            controller: _motif,
            maxLines: 3,
            maxLength: 300,
            textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(
              labelText: 'Motif (facultatif)',
              hintText: 'Salle déjà retenue, travaux, capacité insuffisante…',
              alignLabelWithHint: true,
            ),
          ),
          Text(
            'Une raison, même courte, évite au client de se demander ce qu’il '
            'a mal fait.',
            style: text.bodySmall?.copyWith(color: colors.inkTertiary),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          key: cleAnnulerRefus,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: cleConfirmerRefus,
          onPressed: () => Navigator.of(context).pop(_motif.text.trim()),
          child: const Text('Refuser'),
        ),
      ],
    );
  }
}

// =============================================================================
// Ce qui se répète
// =============================================================================

class _Bloc extends StatelessWidget {
  const _Bloc({required this.titre, required this.enfants});

  final String titre;
  final List<Widget> enfants;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsetsDirectional.only(bottom: 8),
          child: Text(
            titre,
            style: text.titleSmall?.copyWith(color: colors.inkSecondary),
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsetsDirectional.all(14),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: FerhaRadii.cardBorder,
            border: Border.all(color: colors.ruleSoft),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: enfants,
          ),
        ),
      ],
    );
  }
}

class _Ligne extends StatelessWidget {
  const _Ligne({
    required this.icone,
    required this.libelle,
    required this.valeur,
  });

  final IconData icone;
  final String libelle;
  final String valeur;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 8),
      child: Row(
        children: <Widget>[
          Icon(icone, size: 18, color: colors.inkTertiary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              libelle,
              style: text.bodyMedium?.copyWith(color: colors.inkSecondary),
            ),
          ),
          Text(valeur, style: text.bodyMedium?.copyWith(color: colors.ink)),
        ],
      ),
    );
  }
}

class _Squelette extends StatelessWidget {
  const _Squelette();

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;

    Widget bloc(double hauteur) => Container(
      height: hauteur,
      margin: const EdgeInsetsDirectional.only(bottom: 20),
      decoration: BoxDecoration(
        color: colors.surfaceSecondary,
        borderRadius: FerhaRadii.cardBorder,
      ),
    );

    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 24),
      children: <Widget>[bloc(56), bloc(140), bloc(96), bloc(120)],
    );
  }
}
