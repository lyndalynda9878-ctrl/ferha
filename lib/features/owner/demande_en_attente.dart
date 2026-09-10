import 'package:flutter/foundation.dart';

import '../search/search_filters.dart';

/// Une demande qui attend une réponse, vue par le propriétaire
/// (§4.3, OWN-05 ; écran 9).
///
/// UNE LIGNE PAR DEMANDE, PAS PAR CRÉNEAU. Une journée entière occupe midi et
/// soir dans `bookings`, mais c'est un seul mariage et un seul devis :
/// `owner_pending_requests()` lit `booking_groups`, et [montant] est celui du
/// groupe entier (§6.1).
///
/// LE CLIENT N'APPARAÎT QUE PAR SON PRÉNOM ET UNE INITIALE. Ce n'est pas une
/// troncature d'affichage : `short_name()` (014) coupe le patronyme AVANT que
/// la ligne quitte la base, et l'écran ne pourrait pas l'afficher en entier
/// même s'il le voulait. Pour décider d'accepter un mariage, le nom de famille
/// n'apporte rien — il arrivera avec le détail de la demande, par
/// `booking_contact()`, quand il y aura une raison de l'avoir.
///
/// AUCUN TÉLÉPHONE ICI NON PLUS, pour la même raison et par le même chemin :
/// la règle du §9 vit dans `booking_contact()`, et une demande en attente n'en
/// sort pas.
@immutable
class DemandeEnAttente {
  /// Crée une demande en attente.
  const DemandeEnAttente({
    required this.groupId,
    required this.bookingId,
    required this.client,
    required this.date,
    required this.creneau,
    required this.invites,
    required this.montant,
    required this.creeLe,
    this.typeEvenement,
  });

  /// Construit depuis une ligne d'`owner_pending_requests()`.
  factory DemandeEnAttente.depuisJson(Map<String, dynamic> j) =>
      DemandeEnAttente(
        groupId: j['group_id'] as String,
        bookingId: j['booking_id'] as String,
        client: j['client_name'] as String,
        date: DateTime.parse(j['event_date'] as String),
        creneau: Creneau.depuisCode(j['requested_slot'] as String?),
        invites: (j['guest_count'] as num).toInt(),
        // Le libellé du référentiel quand il existe ; sinon le code brut,
        // parce que `bookings.event_type` est du texte libre et qu'une valeur
        // hors référentiel vaut mieux affichée que perdue.
        typeEvenement:
            (j['event_label'] as String?) ?? (j['event_type'] as String?),
        montant: j['quoted_amount'] as num,
        creeLe: DateTime.parse(j['created_at'] as String).toLocal(),
      );

  /// L'identifiant de la demande — un groupe, une ou deux lignes.
  final String groupId;

  /// La ligne représentative du groupe.
  ///
  /// C'est elle qu'attendent `owner_request_detail()`, `accepter_demande()` et
  /// `refuser_demande()` : toutes remontent au groupe elles-mêmes, et une
  /// journée entière se répond d'un bloc.
  final String bookingId;

  /// Le client, prénom et initiale — « Amina K. ».
  final String client;

  /// La date de l'événement.
  final DateTime date;

  /// Le créneau demandé.
  final Creneau creneau;

  /// Le nombre d'invités.
  final int invites;

  /// Le type d'événement, déjà traduit quand il vient du référentiel.
  final String? typeEvenement;

  /// L'estimation, en dinars, pour la demande entière.
  ///
  /// Elle vient d'`estimate_price()` par le trigger de 005, et de nulle part
  /// ailleurs. Rien dans cet écran ne la recalcule.
  final num montant;

  /// L'instant où la demande est arrivée.
  final DateTime creeLe;

  /// Vrai tant que la demande a moins d'un jour.
  ///
  /// LA PASTILLE « Nouveau » DE LA MAQUETTE DIT « ARRIVÉE DEPUIS VOTRE
  /// DERNIÈRE VISITE », et nous n'avons pas cette information : rien en base
  /// n'enregistre qu'un propriétaire a ouvert son tableau de bord. Vingt-quatre
  /// heures est l'approximation honnête — elle se trompe seulement pour qui
  /// regarde deux fois dans la même journée, et jamais dans le sens qui compte,
  /// puisqu'elle ne peut pas taire une demande vraiment neuve.
  ///
  /// [maintenant] est un paramètre et non un `DateTime.now()` interne : sans
  /// cela, aucun test ne pourrait vérifier la frontière.
  bool estNouvelle(DateTime maintenant) =>
      maintenant.difference(creeLe) < const Duration(days: 1);

  /// Depuis combien de temps elle attend — « il y a 2 h », « hier ».
  ///
  /// Le propriétaire ne lit pas un horodatage, il lit un retard : ce qui
  /// l'intéresse est de savoir laquelle attend depuis trop longtemps. Les 48 h
  /// de réponse du §5.1 se comptent d'ailleurs à partir d'ici.
  String attendDepuis(DateTime maintenant) =>
      attenteEnFrancais(creeLe, maintenant);
}

/// « il y a 2 h », « hier », « il y a 4 jours ».
///
/// Une fonction libre et non une méthode : l'écran de détail dit la même chose
/// de la même demande, et il travaille sur un autre modèle. Deux exemplaires
/// finiraient par diverger — l'un dirait « il y a 1 j » quand l'autre dirait
/// « hier », sur le même écran, à propos de la même chose.
///
/// [maintenant] est un paramètre et non un `DateTime.now()` interne : sans
/// cela, aucun test ne pourrait vérifier les frontières.
String attenteEnFrancais(DateTime quand, DateTime maintenant) {
  final ecart = maintenant.difference(quand);

  // Une horloge d'appareil en retard, ou une demande arrivée pendant que
  // l'écran s'affichait : « dans 3 minutes » n'aurait aucun sens.
  if (ecart.isNegative || ecart.inMinutes < 1) return 'à l’instant';
  if (ecart.inMinutes < 60) return 'il y a ${ecart.inMinutes} min';
  if (ecart.inHours < 24) return 'il y a ${ecart.inHours} h';
  if (ecart.inDays == 1) return 'hier';
  return 'il y a ${ecart.inDays} jours';
}
