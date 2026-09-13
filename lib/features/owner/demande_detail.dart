import 'package:flutter/foundation.dart';

import '../booking/reservation.dart';
import '../search/search_filters.dart';

/// Une option payante retenue par le client.
///
/// Le libellé et le prix viennent d'`owner_request_detail()`, qui les lit dans
/// `venue_options` : `bookings.option_ids` ne porte que des identifiants, et
/// une liste de uuid n'apprend rien à personne.
@immutable
class OptionChoisie {
  /// Crée une option.
  const OptionChoisie({
    required this.code,
    required this.libelle,
    required this.prix,
  });

  /// Construit depuis un élément du tableau `options`.
  factory OptionChoisie.depuisJson(Map<String, dynamic> j) => OptionChoisie(
    code: j['code'] as String,
    libelle: j['label'] as String,
    prix: (j['price'] as num?) ?? 0,
  );

  /// Le code de l'option dans le catalogue de la salle.
  final String code;

  /// Ce qui s'affiche.
  final String libelle;

  /// Son prix, en dinars. Zéro pour une option incluse.
  final num prix;

  /// Vrai quand l'option est comprise dans le forfait.
  ///
  /// Une option à zéro dinar n'est pas une option absente : la maquette de
  /// l'écran 5 l'affiche « Incluse », et le propriétaire doit la voir aussi —
  /// c'est une chambre à préparer, même gratuite.
  bool get estIncluse => prix == 0;
}

/// Une demande, vue en entier par le propriétaire qui doit y répondre
/// (§4.3, OWN-05).
///
/// CE QUE CET ÉCRAN A DE PLUS QUE LA CARTE DU TABLEAU DE BORD : le nom entier
/// du client, son message, les options retenues, et — une fois la demande
/// acceptée — son téléphone. Rien de tout cela n'aide à trier une file ; tout
/// sert à décider d'un mariage.
///
/// LE TÉLÉPHONE ARRIVE VIDE TANT QUE LA DEMANDE EST EN ATTENTE, et ce n'est pas
/// une règle d'affichage. `owner_request_detail()` appelle `booking_contact()`
/// (006) et recopie sa réponse sans la relire : la règle du §9 n'a pas de
/// second exemplaire. Un écran qui voudrait montrer le numéro plus tôt n'aurait
/// rien à montrer — et [telephoneDisponible] dit pourquoi, plutôt que de
/// laisser un champ vide sans explication.
@immutable
class DemandeDetail {
  /// Crée le détail d'une demande.
  const DemandeDetail({
    required this.groupId,
    required this.bookingId,
    required this.venueId,
    required this.salle,
    required this.client,
    required this.date,
    required this.creneau,
    required this.invites,
    required this.options,
    required this.montant,
    required this.etat,
    required this.creeLe,
    required this.telephoneDisponible,
    this.typeEvenement,
    this.message,
    this.telephone,
    this.acompte,
    this.acompteDu,
    this.especesEnAttente = false,
    this.motif,
  });

  /// Construit depuis la ligne d'`owner_request_detail()`.
  factory DemandeDetail.depuisJson(Map<String, dynamic> j) => DemandeDetail(
    groupId: j['group_id'] as String,
    bookingId: j['booking_id'] as String,
    venueId: j['venue_id'] as String,
    salle: j['venue_name'] as String,
    client: j['client_name'] as String,
    telephone: j['client_phone'] as String?,
    telephoneDisponible: (j['phone_available'] as bool?) ?? false,
    date: DateTime.parse(j['event_date'] as String),
    creneau: Creneau.depuisCode(j['requested_slot'] as String?),
    invites: (j['guest_count'] as num).toInt(),
    typeEvenement:
        (j['event_label'] as String?) ?? (j['event_type'] as String?),
    message: j['client_message'] as String?,
    options: ((j['options'] as List<dynamic>?) ?? const <dynamic>[])
        .cast<Map<String, dynamic>>()
        .map(OptionChoisie.depuisJson)
        .toList(growable: false),
    montant: j['quoted_amount'] as num,
    acompte: j['deposit_amount'] as num?,
    // L'entier encaissable (024) : le propriétaire compte ses billets d'après
    // le MÊME nombre que celui affiché à sa cliente.
    acompteDu: (j['acompte_du'] as num?)?.toInt(),
    especesEnAttente: (j['especes_en_attente'] as bool?) ?? false,
    // La MÊME énumération que côté client, et c'est voulu : « accepted » est un
    // seul état de la base, pas deux. Ses libellés sont écrits du point de vue
    // du client — l'écran du propriétaire ne les affiche donc pas tels quels,
    // il s'en sert pour savoir où l'on en est.
    etat: EtatReservation.depuisCode(j['status'] as String),
    motif: j['status_reason'] as String?,
    creeLe: DateTime.parse(j['created_at'] as String).toLocal(),
  );

  /// L'acompte en dinars entiers, tel que le client le voit.
  ///
  /// C'est celui qu'il faut compter. `acompte` porte les centimes du montant
  /// convenu ; celui-ci est ce que la caisse encaisse, et ce que le client
  /// apportera s'il vient en espèces.
  final int? acompteDu;

  /// Vrai quand le client a annoncé un versement en main propre, et que
  /// personne ne l'a encore confirmé.
  ///
  /// C'est ce qui fait apparaître le bouton « J'ai reçu l'acompte » : tant
  /// qu'il est faux, il n'y a rien à confirmer, et le montrer inviterait le
  /// propriétaire à prendre une date pour de l'argent qu'on ne lui a pas promis.
  final bool especesEnAttente;

  /// L'identifiant de la demande — un groupe, une ou deux lignes.
  final String groupId;

  /// La ligne représentative, celle qu'attendent `accepter_demande()` et
  /// `refuser_demande()`.
  final String bookingId;

  /// La salle concernée.
  final String venueId;

  /// Son nom.
  final String salle;

  /// Le client, nom entier.
  final String client;

  /// Son téléphone — présent UNIQUEMENT à partir de « acceptée » (§9).
  final String? telephone;

  /// Vrai quand la base a le droit de donner le numéro.
  ///
  /// Distinct de `telephone != null` : un client peut ne pas avoir renseigné de
  /// numéro du tout. « Pas encore » et « pas de numéro » sont deux phrases
  /// différentes, et l'écran doit pouvoir les dire toutes les deux.
  final bool telephoneDisponible;

  /// La date de l'événement.
  final DateTime date;

  /// Le créneau demandé.
  final Creneau creneau;

  /// Le nombre d'invités.
  final int invites;

  /// Le type d'événement, déjà traduit quand il vient du référentiel.
  final String? typeEvenement;

  /// Le mot du client, s'il en a laissé un.
  final String? message;

  /// Les options retenues, dans l'ordre du catalogue de la salle.
  final List<OptionChoisie> options;

  /// Le devis du groupe entier, en dinars.
  ///
  /// Il vient d'`estimate_price()` par le trigger de 005. Rien dans cet écran
  /// ne le recalcule, et rien ne l'ajuste : la contre-proposition du §5.2 est
  /// un geste à part, qui viendra à son étape.
  final num montant;

  /// L'acompte, fixé à l'acceptation. Null tant que la demande est en attente.
  final num? acompte;

  /// Où en est la demande.
  final EtatReservation etat;

  /// Le motif d'un refus ou d'une annulation, s'il y en a un.
  final String? motif;

  /// L'instant où la demande est arrivée.
  final DateTime creeLe;

  /// Vrai quand la demande attend encore une réponse.
  ///
  /// C'est la seule condition qui ouvre les deux boutons. Elle ne remplace pas
  /// le garde-fou de la base — `accepter_demande()` refuse elle-même une
  /// demande déjà tranchée, code FE012 — elle évite seulement de proposer un
  /// geste qui échouerait.
  bool get attendUneReponse => etat == EtatReservation.enAttente;

  /// Vrai quand la soirée peut être marquée comme honorée (§3, étape 6).
  ///
  /// DEUX CONDITIONS, ET LA SECONDE SE COMPARE ICI : la réservation est
  /// confirmée, et l'événement n'est plus à venir. Comparer une date en Dart
  /// n'est pas recalculer une règle métier — c'est le même geste que
  /// `optionEnCours` côté client, et pour le même usage : ne pas PROPOSER un
  /// bouton qui échouerait. `complete_booking()` (026) refuse elle-même un
  /// événement à venir, avec le code FE073, et c'est ce refus-là qui protège.
  ///
  /// LE JOUR MÊME COMPTE, comme en base : un mariage du 14 août se marque
  /// honoré le 14 au soir, pas le 15.
  bool get honorable {
    if (etat != EtatReservation.confirmee) return false;
    final aujourdHui = DateTime.now();
    return !DateTime(
      date.year,
      date.month,
      date.day,
    ).isAfter(DateTime(aujourdHui.year, aujourdHui.month, aujourdHui.day));
  }

  /// La somme des options payantes, pour la ligne de détail du devis.
  ///
  /// CE N'EST PAS UN PRIX : c'est le rappel de ce que le client a coché, et il
  /// ne sert jamais à recomposer [montant], qui vient d'`estimate_price()` et
  /// de nulle part ailleurs.
  num get totalOptions =>
      options.fold<num>(0, (somme, option) => somme + option.prix);
}
