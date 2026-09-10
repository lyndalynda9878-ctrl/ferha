import 'package:flutter/foundation.dart';

import '../search/search_filters.dart';

/// Ce qu'un créneau de l'agenda peut être (§4.3, OWN-06).
///
/// LES CINQ ÉTATS D'`owner_agenda()`, ET RIEN D'AUTRE. Le code vient de la base,
/// le libellé s'affiche : « ferme » ne se montre jamais tel quel, pas plus que
/// « draft » ne se montre dans le sélecteur de salle. C'est le même partage
/// qu'entre [StatutSalle] et [EtatReservation].
///
/// L'ORDRE DE LA LISTE EST CELUI DE LA LÉGENDE, du plus libre au plus fermé.
/// C'est aussi celui de la priorité que la base applique quand un créneau porte
/// plusieurs choses à la fois — mais à l'envers : là-bas, c'est le plus
/// contraignant qui gagne.
enum EtatAgenda {
  /// À vendre.
  libre('libre', 'Libre'),

  /// Une demande attend une réponse. Elle n'a bloqué aucune date (§5.1).
  demande('demande', 'Demande'),

  /// Une demande acceptée, option de 72 h en cours (§5.1).
  option('option', 'Option'),

  /// Payée ou honorée : la date est vendue.
  confirme('confirme', 'Confirmé'),

  /// Le propriétaire a fermé le créneau.
  ferme('ferme', 'Fermé');

  const EtatAgenda(this.code, this.libelle);

  /// La valeur rendue par `owner_agenda()`.
  final String code;

  /// Ce qui s'affiche, dans la légende comme dans la feuille du bas.
  final String libelle;

  /// Retrouve un état depuis son code.
  ///
  /// Un code inconnu est une erreur de programme : `owner_agenda()` n'en rend
  /// que cinq, et un sixième voudrait dire que la fonction a changé sans que
  /// cet écran le sache. Mieux vaut le dire que peindre un cercle au hasard.
  static EtatAgenda depuisCode(String code) => EtatAgenda.values.firstWhere(
    (e) => e.code == code,
    orElse: () =>
        throw ArgumentError.value(code, 'code', 'État d’agenda inconnu'),
  );

  /// Vrai quand le propriétaire peut fermer ce créneau.
  ///
  /// Seulement libre. Une option ou une confirmation appartiennent à quelqu'un
  /// d'autre — `bloquer_date()` refuse (FE022) —, et une demande en attente
  /// n'empêche rien mais mérite une réponse avant qu'on lui ferme la porte au
  /// nez : l'écran renvoie donc vers elle plutôt que de proposer les deux.
  bool get seFerme => this == libre;

  /// Vrai quand il peut le rouvrir.
  bool get seRouvre => this == ferme;

  /// Vrai quand la case mène à une demande, plutôt qu'à une fermeture.
  bool get ouvreUneDemande =>
      this == demande || this == option || this == confirme;
}

/// Un créneau de l'agenda : un jour, un créneau, un état, et ce qui va avec.
///
/// Les champs facultatifs ne le sont pas au hasard : `owner_agenda()` ne renvoie
/// le client, le devis et l'identifiant de demande que sur les créneaux qui en
/// portent un, et le motif que sur ceux qui sont fermés. Un créneau libre
/// n'a donc rien d'autre que sa date — et c'est la base qui le décide, pas cet
/// écran qui filtrerait après coup.
@immutable
class CreneauAgenda {
  /// Crée un créneau d'agenda.
  const CreneauAgenda({
    required this.jour,
    required this.creneau,
    required this.etat,
    this.bookingId,
    this.groupId,
    this.client,
    this.invites,
    this.montant,
    this.optionExpire,
    this.motif,
  });

  /// Construit depuis une ligne d'`owner_agenda()`.
  factory CreneauAgenda.depuisJson(Map<String, dynamic> j) => CreneauAgenda(
    jour: DateTime.parse(j['day'] as String),
    creneau: Creneau.depuisCode(j['slot'] as String),
    etat: EtatAgenda.depuisCode(j['state'] as String),
    bookingId: j['booking_id'] as String?,
    groupId: j['group_id'] as String?,
    client: j['client_name'] as String?,
    invites: (j['guest_count'] as num?)?.toInt(),
    montant: j['quoted_amount'] as num?,
    optionExpire: j['option_expires_at'] == null
        ? null
        : DateTime.parse(j['option_expires_at'] as String).toLocal(),
    motif: j['reason'] as String?,
  );

  /// Le jour, à minuit.
  final DateTime jour;

  /// Midi ou soir. Jamais « journée » : l'agenda travaille sur les créneaux
  /// atomiques, comme `bookings.slot` et `venue_blackouts.slot` (§6.1).
  final Creneau creneau;

  /// Où en est ce créneau.
  final EtatAgenda etat;

  /// La ligne représentative de la demande, pour l'ouvrir. `null` si le créneau
  /// n'en porte pas — ou si ce n'est pas elle qui s'affiche.
  final String? bookingId;

  /// Le groupe de la demande.
  final String? groupId;

  /// Le client, prénom et initiale — `short_name()` (014).
  final String? client;

  /// Le nombre d'invités de la demande.
  final int? invites;

  /// Le devis du groupe, calculé par `estimate_price()`.
  final num? montant;

  /// L'échéance de l'option de 72 h (§5.1), sur les créneaux en option.
  final DateTime? optionExpire;

  /// Le motif de la fermeture — la note privée du propriétaire.
  ///
  /// IL NE SORT QUE PAR ICI. `venue_availability` ne porte que venue_id, date
  /// et slot, et `venue_calendar()` que le jour et son état : le motif n'a
  /// aucun chemin vers un client. `supabase/tests/004_agenda_proprietaire.sql`
  /// le vérifie.
  final String? motif;
}

/// L'agenda d'un mois, prêt à être posé sur une grille.
///
/// LA BASE REND UNE GRILLE COMPLÈTE, ET C'EST TOUT L'INTÉRÊT. `owner_agenda()`
/// renvoie une ligne par jour ET par créneau, « libre » comprise : il n'y a
/// donc aucun trou à combler ici, et surtout aucune règle à réinventer pour les
/// jours dont la base n'aurait rien dit. Passer de midi à soir ne redemande
/// rien non plus — les deux créneaux sont déjà là.
@immutable
class AgendaDuMois {
  /// Crée l'agenda d'un mois.
  const AgendaDuMois({required this.mois, required this.parJour});

  /// Construit depuis les lignes d'`owner_agenda()`.
  factory AgendaDuMois.depuisLignes(
    DateTime mois,
    List<Map<String, dynamic>> lignes,
  ) {
    final parJour = <int, Map<String, CreneauAgenda>>{};
    for (final ligne in lignes) {
      final creneau = CreneauAgenda.depuisJson(ligne);
      (parJour[creneau.jour.day] ??=
              <String, CreneauAgenda>{})[creneau.creneau.code] =
          creneau;
    }
    return AgendaDuMois(
      mois: DateTime(mois.year, mois.month),
      parJour: parJour,
    );
  }

  /// Le premier du mois affiché.
  final DateTime mois;

  /// Les créneaux, par quantième puis par code de créneau.
  ///
  /// Indexé par le NUMÉRO du jour et non par une `DateTime` : deux `DateTime`
  /// qui désignent le même jour ne sont égales que si leurs heures le sont
  /// aussi, et une clé construite ailleurs finirait par ne plus rien trouver.
  /// Le mois est déjà connu, le quantième suffit à le compléter.
  final Map<int, Map<String, CreneauAgenda>> parJour;

  /// Le créneau d'un jour, ou `null` si ce jour n'est pas dans ce mois.
  CreneauAgenda? creneauDe(DateTime jour, Creneau creneau) {
    if (jour.year != mois.year || jour.month != mois.month) return null;
    return parJour[jour.day]?[creneau.code];
  }
}

/// Le mois demandé et la salle : la clé du fournisseur d'agenda.
///
/// Immuable et comparable, comme [SearchFilters] et [DemandeFiche] : deux fois
/// le même mois ne doivent pas produire deux appels réseau. Le jour est
/// délibérément écrasé — l'agenda d'un mois est le même qu'on le demande le 1er
/// ou le 31, et garder le quantième ferait une clé différente par jour.
@immutable
class DemandeAgenda {
  /// Crée la clé.
  DemandeAgenda({required this.venueId, required DateTime mois})
    : mois = DateTime(mois.year, mois.month);

  /// La salle.
  final String venueId;

  /// Le premier du mois.
  final DateTime mois;

  @override
  bool operator ==(Object other) =>
      other is DemandeAgenda && other.venueId == venueId && other.mois == mois;

  @override
  int get hashCode => Object.hash(venueId, mois);
}
