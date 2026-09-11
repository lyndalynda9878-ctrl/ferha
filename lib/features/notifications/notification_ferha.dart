import 'package:flutter/foundation.dart';

import '../../core/router/routes.dart';
import '../search/search_filters.dart';

/// À qui la notification s'adresse — et donc où elle mène.
///
/// UNE MÊME NOTIFICATION PART PARFOIS AUX DEUX PARTIES. « Réservation
/// confirmée » est déposée au client et au propriétaire, avec le même type et
/// le même identifiant de demande ; seul l'écran d'arrivée diffère. Sans cette
/// clé, l'application devrait comparer l'identifiant de session au client de la
/// réservation — c'est-à-dire refaire en Dart un travail que la base a déjà
/// fait, et le refaire avec moins d'informations.
///
/// Elle est donc écrite dans le payload par `notify_user()` (022), là où
/// `client_id` et `owner_id` sont sous la main.
enum RoleNotification {
  /// La personne qui a demandé la salle.
  client('client'),

  /// La personne qui la loue.
  proprietaire('owner');

  const RoleNotification(this.code);

  /// La valeur écrite dans `payload->>'role'`.
  final String code;

  /// Retrouve un rôle depuis le payload. Client par défaut.
  ///
  /// UN PAYLOAD SANS RÔLE EXISTE : les notifications déposées avant la
  /// migration 022 n'en portent pas. Les envoyer sur « Mes réservations » est
  /// le repli le moins coûteux — l'écran est ouvert à tout le monde, alors que
  /// le détail d'une demande refuse une salle qui n'est pas la vôtre.
  static RoleNotification depuisCode(String? code) =>
      code == proprietaire.code ? proprietaire : client;
}

/// Les événements notifiés (§4.1, CORE-04).
///
/// LE CODE DE LA BASE D'UN CÔTÉ, LA PHRASE FRANÇAISE DE L'AUTRE, comme pour
/// `EtatReservation`. `booking_answered` n'a rien à faire sous les yeux de
/// quelqu'un qui attend une réponse pour son mariage.
///
/// CERTAINS TITRES DÉPENDENT DU PAYLOAD, et c'est pourquoi ils ne sont pas
/// écrits ici : une réponse du propriétaire se dit « acceptée » ou « refusée »
/// selon `status`. [NotificationFerha.titre] fait cette lecture, à un seul
/// endroit.
enum TypeNotification {
  /// Une famille vient de demander une date. Côté propriétaire.
  nouvelleDemande('booking_requested'),

  /// Le propriétaire a répondu — oui, non, ou un autre montant (§5.2).
  reponse('booking_answered'),

  /// L'acompte est encaissé : la date est prise (§3, étape 5).
  confirmee('booking_confirmed'),

  /// Quelqu'un a annulé (§5.3).
  annulee('booking_cancelled'),

  /// L'option de 72 h est passée sans acompte (§5.1).
  expiree('booking_expired'),

  /// La carte a été refusée, ou le paiement abandonné. Côté client.
  ///
  /// L'OPTION N'EST PAS PERDUE POUR AUTANT, et le titre doit le laisser
  /// entendre : une carte refusée ne retire pas les 72 h. Le client peut
  /// réessayer, ou porter l'acompte en espèces.
  paiementEchoue('payment_failed'),

  /// L'argent est arrivé, et la date n'est pas prise (025).
  ///
  /// Les trois façons d'en arriver là — option expirée, créneau pris par un
  /// autre, réservation déjà payée — se disent de la même façon au client :
  /// son versement va lui être rendu. Le détail est dans `payments.anomalie`,
  /// et il regarde l'administration, pas lui.
  paiementARembourser('payment_to_refund'),

  /// Un paiement qu'un humain doit regarder. Côté administration (§4.4).
  paiementAExaminer('payment_anomaly'),

  /// Le client a annoncé un versement en espèces. Côté propriétaire.
  especesAnnoncees('cash_pending'),

  /// Rappel à sept jours. Pas encore émis — voir « Ce qui manque encore ».
  rappelJ7('reminder_j7'),

  /// Rappel à un jour. Pas encore émis non plus.
  rappelJ1('reminder_j1'),

  /// L'événement a eu lieu : l'avis se débloque (§5.4).
  invitationAvis('review_invitation');

  const TypeNotification(this.code);

  /// La valeur de `notifications.type`. Elle ne s'affiche jamais.
  final String code;

  /// Retrouve un type depuis le code de la base.
  ///
  /// UN CODE INCONNU NE FAIT PAS TOMBER L'ÉCRAN, contrairement à
  /// `EtatReservation.depuisCode`. La différence n'est pas un caprice : une
  /// réservation dont l'état est illisible ne peut rien afficher de juste,
  /// alors qu'une notification inconnue n'est qu'une ligne de plus dans une
  /// liste. Le jour où la base apprendra un type que cette version de
  /// l'application ignore — un rappel, un message —, la cloche continuera de
  /// compter juste et l'écran de s'ouvrir.
  static TypeNotification? depuisCode(String code) {
    for (final type in TypeNotification.values) {
      if (type.code == code) return type;
    }
    return null;
  }
}

/// Une notification, telle que la renvoie `mes_notifications()`.
///
/// TOUT CE QU'ELLE AFFICHE VIENT DE SON PAYLOAD, et le payload est rempli par
/// la base au moment où la notification naît (022). L'écran ne va donc chercher
/// ni le nom de la salle ni la date : il n'y a pas une requête par ligne, et
/// surtout pas de texte de salle écrit en dur.
///
/// ET LE PAYLOAD EST FIGÉ. Une salle renommée demain ne réécrit pas l'annonce
/// d'hier — c'est la différence entre une notification et une vue.
@immutable
class NotificationFerha {
  /// Crée une notification.
  const NotificationFerha({
    required this.id,
    required this.type,
    required this.role,
    required this.creeLe,
    this.lueLe,
    this.bookingId,
    this.salle,
    this.commune,
    this.date,
    this.creneau,
    this.invites,
    this.statut,
  });

  /// Construit depuis une ligne de `mes_notifications()`.
  factory NotificationFerha.depuisJson(Map<String, dynamic> j) {
    final payload = (j['payload'] as Map<String, dynamic>?) ?? const {};
    final date = payload['event_date'] as String?;

    return NotificationFerha(
      id: j['id'] as String,
      type: TypeNotification.depuisCode(j['type'] as String),
      role: RoleNotification.depuisCode(payload['role'] as String?),
      salle: payload['venue_name'] as String?,
      commune: payload['commune'] as String?,
      bookingId: payload['booking_id'] as String?,
      date: date == null ? null : DateTime.parse(date),
      // `requested_slot` et non `slots` : c'est ce que la famille a demandé —
      // « journée entière » —, et non les deux lignes que la base en a faites.
      creneau: payload['requested_slot'] == null
          ? null
          : Creneau.depuisCode(payload['requested_slot'] as String),
      invites: (payload['guest_count'] as num?)?.toInt(),
      statut: payload['status'] as String?,
      lueLe: j['read_at'] == null
          ? null
          : DateTime.parse(j['read_at'] as String).toLocal(),
      creeLe: DateTime.parse(j['created_at'] as String).toLocal(),
    );
  }

  /// L'identifiant de la notification — celui qu'on marque lu.
  final String id;

  /// L'événement. `null` quand la base connaît un type que cette version
  /// ignore : la ligne s'affiche quand même, sobrement.
  final TypeNotification? type;

  /// De quel côté se tient le destinataire — et donc où mène [destination].
  final RoleNotification role;

  /// La ligne représentative de la réservation concernée.
  final String? bookingId;

  /// Le nom de la salle, tel qu'il était au moment de l'événement.
  final String? salle;

  /// Sa commune.
  final String? commune;

  /// La date de l'événement.
  final DateTime? date;

  /// Le créneau demandé : midi, soir, ou la journée entière.
  final Creneau? creneau;

  /// Le nombre d'invités.
  final int? invites;

  /// Pour une réponse du propriétaire : « accepted » ou « refused ».
  final String? statut;

  /// Quand la notification a été lue. `null` tant qu'elle ne l'est pas.
  final DateTime? lueLe;

  /// Quand elle est arrivée.
  final DateTime creeLe;

  /// Vrai quand elle a déjà été ouverte.
  bool get lue => lueLe != null;

  /// La même notification, marquée lue à [quand].
  ///
  /// ELLE EST ICI ET NON DANS LE FOURNISSEUR, parce que c'est la notification
  /// qui sait de quoi elle est faite : une copie écrite ailleurs oublierait un
  /// champ le jour où on en ajoute un, et l'oublierait en silence.
  NotificationFerha marqueeLue(DateTime quand) => NotificationFerha(
    id: id,
    type: type,
    role: role,
    creeLe: creeLe,
    lueLe: quand,
    bookingId: bookingId,
    salle: salle,
    commune: commune,
    date: date,
    creneau: creneau,
    invites: invites,
    statut: statut,
  );

  /// Le titre, en français, du point de vue du destinataire.
  ///
  /// LE POINT DE VUE COMPTE AUTANT QUE LA TRADUCTION. « accepted » ne se dit
  /// pas « acceptée » et rien de plus : pour la famille, c'est surtout un
  /// acompte à verser sous 72 h.
  String get titre => switch (type) {
    TypeNotification.nouvelleDemande => 'Nouvelle demande de réservation',
    TypeNotification.reponse => switch (statut) {
      'accepted' => 'Demande acceptée — acompte à verser',
      'refused' => 'Demande refusée',
      _ => 'Réponse du propriétaire',
    },
    TypeNotification.confirmee =>
      role == RoleNotification.proprietaire
          ? 'Acompte reçu, la date est prise'
          : 'Réservation confirmée',
    TypeNotification.annulee => 'Réservation annulée',
    // On ne dit pas « annulée » : personne n'a rien fait, et c'est justement
    // le problème. La date est repartie à la vente toute seule.
    TypeNotification.expiree =>
      role == RoleNotification.proprietaire
          ? 'Option expirée, la date se relibère'
          : 'Option expirée, la date est repartie',
    // On ne dit pas « échec » tout court : l'option court toujours, et c'est la
    // seule chose que le client ait besoin de savoir à cet instant.
    TypeNotification.paiementEchoue =>
      'Paiement non abouti, votre option court',
    TypeNotification.paiementARembourser =>
      role == RoleNotification.proprietaire
          ? 'Un paiement reçu n’a pas pu être confirmé'
          : 'Votre paiement va vous être remboursé',
    TypeNotification.paiementAExaminer => 'Paiement à examiner',
    TypeNotification.especesAnnoncees => 'Acompte en espèces annoncé',
    TypeNotification.rappelJ7 => 'Votre événement dans une semaine',
    TypeNotification.rappelJ1 => 'Votre événement, c’est demain',
    TypeNotification.invitationAvis => 'Racontez votre soirée',
    null => 'Nouvelle notification',
  };

  /// La ligne de détail : la salle, la date, le créneau.
  ///
  /// Elle se construit de ce qui est là et saute ce qui manque — une
  /// notification sans réservation rattachée n'affiche pas de virgules vides.
  String get details {
    final morceaux = <String>[
      if (salle != null) salle!,
      if (date != null)
        creneau == null
            ? dateEnFrancais(date!)
            : '${dateEnFrancais(date!)}, ${creneau!.libelle.toLowerCase()}',
      if (invites != null) '$invites invités',
    ];
    return morceaux.join(' · ');
  }

  /// L'écran qu'ouvre un appui.
  ///
  /// LE RÔLE DÉCIDE, PAS LE TYPE. Le propriétaire va au détail de la demande —
  /// c'est là qu'il accepte ou refuse ; la famille va à son suivi. `bookingId`
  /// manquant ramène au suivi plutôt que nulle part : un écran ouvert vaut
  /// mieux qu'un appui sans effet.
  String get destination =>
      role == RoleNotification.proprietaire && bookingId != null
      ? FerhaRoutes.proprietaireDemandeDe(bookingId!)
      : FerhaRoutes.mesReservations;
}
