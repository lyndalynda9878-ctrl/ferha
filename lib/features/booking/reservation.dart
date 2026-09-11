import 'package:flutter/foundation.dart';

import '../search/search_filters.dart';

/// L'état d'une réservation, du point de vue du CLIENT.
///
/// LE MOT « pending » NE DOIT JAMAIS ATTEINDRE L'ÉCRAN, ni aucun de ses six
/// frères. Ce sont des valeurs de colonne, écrites pour une contrainte CHECK et
/// pour des fonctions SQL ; les montrer à une famille qui attend une réponse
/// pour son mariage, ce serait lui faire lire le schéma de la base.
///
/// D'où cette énumération : le code de la base d'un côté, la phrase française
/// de l'autre, et un seul endroit où les deux se rencontrent.
///
/// LE POINT DE VUE COMPTE AUTANT QUE LA TRADUCTION. « accepted » ne se dit pas
/// « acceptée » et rien de plus : pour le client, c'est surtout un acompte à
/// verser sous 72 h. Le libellé porte donc ce qu'il y a à faire, pas seulement
/// ce qui s'est passé.
enum EtatReservation {
  /// La demande est posée. Elle ne bloque rien (§5.1).
  enAttente(
    'pending',
    'En attente de réponse',
    'Le propriétaire a 48 h pour répondre. D’ici là, la date reste ouverte '
        'à d’autres demandes.',
  ),

  /// Le propriétaire a dit oui : option de 72 h (§5.1).
  acceptee(
    'accepted',
    'Acceptée — acompte à verser',
    'La date vous est gardée le temps de verser l’acompte.',
  ),

  /// L'acompte est réglé, la date est prise (§3, étape 5).
  confirmee(
    'confirmed',
    'Confirmée',
    'La date est à vous. Le solde se règle le jour J.',
  ),

  /// L'événement a eu lieu (§3, étape 6).
  terminee('completed', 'Terminée', 'Vous pouvez maintenant déposer un avis.'),

  /// Le propriétaire a dit non.
  refusee(
    'refused',
    'Refusée',
    'Le propriétaire n’a pas retenu votre demande. Vous pouvez en envoyer '
        'une autre, ailleurs ou à une autre date.',
  ),

  /// Annulation par l'une ou l'autre partie (§5.3).
  annulee('cancelled', 'Annulée', 'Cette demande a été annulée.'),

  /// Option de 72 h échue sans acompte (§5.1).
  expiree(
    'expired',
    'Expirée',
    'L’acompte n’a pas été versé dans les 72 h, et la date est repartie à '
        'la vente.',
  );

  const EtatReservation(this.code, this.libelle, this.explication);

  /// La valeur de `bookings.status`. Elle ne s'affiche jamais.
  final String code;

  /// Le titre de l'état, en français, du point de vue du client.
  final String libelle;

  /// Ce que cet état veut dire concrètement, en une phrase.
  final String explication;

  /// Vrai tant que la réservation est en cours de route.
  bool get enCours =>
      this == enAttente || this == acceptee || this == confirmee;

  /// Vrai quand le client peut encore annuler lui-même.
  ///
  /// `cancel_booking()` accepte aussi « accepted » et « confirmed », mais ce
  /// sont deux gestes d'une autre nature — il y a un acompte en jeu, et le
  /// barème du §5.3 s'applique. L'écran ne propose donc l'annulation en un tap
  /// que sur une demande qui n'engage encore personne.
  bool get annulableParLeClient => this == enAttente;

  /// Retrouve un état depuis le code de la base.
  ///
  /// Un code inconnu est une erreur de programme, pas une donnée : la
  /// contrainte CHECK de `bookings.status` interdit tout le reste.
  static EtatReservation depuisCode(String code) =>
      EtatReservation.values.firstWhere(
        (e) => e.code == code,
        orElse: () => throw ArgumentError.value(
          code,
          'code',
          'État de réservation inconnu',
        ),
      );
}

/// Une réservation, telle que la renvoie `client_bookings()`.
///
/// Une LIGNE PAR RÉSERVATION, pas par créneau : une journée entière occupe
/// midi et soir dans `bookings`, mais c'est une seule demande, et [montant] est
/// celui du groupe — jamais une somme à refaire (§6.1).
@immutable
class Reservation {
  /// Crée une réservation.
  const Reservation({
    required this.groupId,
    required this.bookingId,
    required this.venueId,
    required this.salle,
    required this.commune,
    required this.date,
    required this.creneau,
    required this.invites,
    required this.montant,
    required this.etat,
    required this.creeLe,
    this.wilayaNom,
    this.photo,
    this.typeEvenement,
    this.motif,
    this.acompte,
    this.acompteDu,
    this.optionExpireLe,
    this.proprietaire,
    this.telephone,
  });

  /// Construit depuis une ligne de `client_bookings()`.
  factory Reservation.depuisJson(Map<String, dynamic> j) => Reservation(
    groupId: j['group_id'] as String,
    bookingId: j['booking_id'] as String,
    venueId: j['venue_id'] as String,
    salle: j['venue_name'] as String,
    commune: j['commune'] as String,
    wilayaNom: j['wilaya_name'] as String?,
    photo: j['cover_photo'] as String?,
    date: DateTime.parse(j['event_date'] as String),
    creneau: Creneau.depuisCode(j['requested_slot'] as String?),
    invites: (j['guest_count'] as num).toInt(),
    // Le libellé du référentiel quand il existe ; sinon le code, parce que
    // bookings.event_type est du texte libre et qu'une valeur hors référentiel
    // vaut mieux affichée que perdue.
    typeEvenement:
        (j['event_label'] as String?) ?? (j['event_type'] as String?),
    etat: EtatReservation.depuisCode(j['status'] as String),
    motif: j['status_reason'] as String?,
    montant: j['quoted_amount'] as num,
    acompte: j['deposit_amount'] as num?,
    // L'entier encaissable, arrondi une seule fois — en SQL (024).
    acompteDu: (j['acompte_du'] as num?)?.toInt(),
    optionExpireLe: j['option_expires_at'] == null
        ? null
        : DateTime.parse(j['option_expires_at'] as String).toLocal(),
    creeLe: DateTime.parse(j['created_at'] as String).toLocal(),
    proprietaire: j['owner_name'] as String?,
    // Null tant que la demande n'est pas acceptée : c'est booking_contact() qui
    // en décide, et personne d'autre (§9).
    telephone: j['owner_phone'] as String?,
  );

  /// L'identifiant de la réservation — un groupe, une ou deux lignes.
  final String groupId;

  /// Une ligne du groupe, celle qu'attendent `cancel_booking()` et
  /// `booking_contact()`.
  final String bookingId;

  /// La salle.
  final String venueId;

  /// Son nom.
  final String salle;

  /// Sa commune.
  final String commune;

  /// Sa wilaya.
  final String? wilayaNom;

  /// Sa photo de couverture, chemin de Storage ou URL.
  final String? photo;

  /// La date de l'événement.
  final DateTime date;

  /// Le créneau demandé.
  final Creneau creneau;

  /// Le nombre d'invités.
  final int invites;

  /// Le type d'événement, déjà traduit quand il vient du référentiel.
  final String? typeEvenement;

  /// L'état, en français.
  final EtatReservation etat;

  /// Le motif d'un refus ou d'une annulation, s'il y en a un.
  final String? motif;

  /// Le devis du groupe, en dinars.
  final num montant;

  /// L'acompte fixé par le propriétaire à l'acceptation. Null avant.
  ///
  /// Au centime : c'est le montant convenu entre les deux parties, celui qui a
  /// valeur d'accord. Pour un BOUTON, lire [acompteDu].
  final num? acompte;

  /// Le même acompte, en dinars entiers — ce que la caisse encaissera.
  ///
  /// IL VIENT DE LA BASE, ET C'EST TOUT L'INTÉRÊT. `montant_acompte()` (024)
  /// arrondit une seule fois, au dinar supérieur, et les trois endroits qui
  /// annoncent un montant à payer — le bouton de cette liste, l'écran 6, la Edge
  /// Function — lisent tous cette même fonction. Arrondir [acompte] ici ferait
  /// un second arrondi, au plus près plutôt qu'au supérieur : le bouton dirait
  /// « 51 333 DA » et Chargily en demanderait 51 334.
  ///
  /// Null tant que le propriétaire n'a pas répondu, comme [acompte].
  final int? acompteDu;

  /// L'échéance de l'option de 72 h. Null hors de l'état « acceptée ».
  final DateTime? optionExpireLe;

  /// La date de la demande.
  final DateTime creeLe;

  /// Le nom du propriétaire.
  final String? proprietaire;

  /// Son téléphone — présent UNIQUEMENT à partir de « acceptée » (§9).
  ///
  /// Ce n'est pas une règle d'affichage : la colonne arrive vide de la base
  /// tant que la demande n'est pas acceptée. Un écran qui voudrait la montrer
  /// plus tôt n'aurait rien à montrer.
  final String? telephone;

  /// « Oran, Oran (31) » n'a pas de sens dans une liste : la commune suffit.
  String get localisation =>
      wilayaNom == null ? commune : '$commune, $wilayaNom';

  /// Vrai quand un compte à rebours a encore un sens.
  bool get optionEnCours =>
      etat == EtatReservation.acceptee && optionExpireLe != null;
}
