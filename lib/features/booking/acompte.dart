import 'package:flutter/foundation.dart';

import '../search/search_filters.dart';

/// Les moyens de paiement de l'écran 6.
///
/// DEUX, ET PAS TROIS. La maquette en dessine un troisième — « Espèces sur
/// place (72 h) » — et sa légende explique pourquoi il compte : « elle sauve
/// les utilisateurs réticents au paiement en ligne ». Il arrivera, avec le
/// parcours qui va avec : une confirmation par le propriétaire, et une ligne
/// `payments` de méthode « cash » sans checkout. L'afficher aujourd'hui, éteint
/// ou sans suite, promettrait au client une porte qui ne s'ouvre pas — et c'est
/// exactement celui qui hésite à payer en ligne qui la pousserait.
///
/// LES CODES SONT CEUX DE `payments.method` (004). Ils ne s'affichent jamais :
/// c'est [libelle] qui va à l'écran, et [code] qui part vers la Edge Function.
enum MoyenDePaiement {
  /// La carte interbancaire, SATIM.
  cib('cib', 'Carte CIB', 'La carte de votre banque'),

  /// La carte d'Algérie Poste.
  edahabia('edahabia', 'Carte Edahabia', 'La carte d’Algérie Poste');

  const MoyenDePaiement(this.code, this.libelle, this.explication);

  /// La valeur attendue par `payments.method` et par Chargily.
  final String code;

  /// Le nom de la carte, tel qu'il s'affiche.
  final String libelle;

  /// De quelle carte on parle, pour qui ne reconnaît pas le nom.
  final String explication;
}

/// L'acompte à verser, tel que le rend `acompte_a_verser()` (024).
///
/// LE MONTANT NE SE CALCULE PAS ICI, ET C'EST LA RÈGLE DU PROJET. [acompte] est
/// un entier qui vient de `montant_acompte()`, en SQL : c'est lui que le bouton
/// affiche, et c'est lui que Chargily encaissera. Écrire `montantConvenu * 0.25`
/// quelque part dans cette classe ferait une seconde formule de prix — le
/// cahier des charges n'en veut qu'une, et elle est en base.
///
/// [solde] est ce qui restera à régler sur place le jour J. Il arrive de la base
/// lui aussi, complément exact de l'acompte arrondi : l'additionner à [acompte]
/// redonne [montantConvenu], au centime.
@immutable
class AcompteAVerser {
  /// Crée un acompte à verser.
  const AcompteAVerser({
    required this.groupId,
    required this.bookingId,
    required this.venueId,
    required this.salle,
    required this.commune,
    required this.date,
    required this.creneau,
    required this.invites,
    required this.montantConvenu,
    required this.acompte,
    required this.solde,
    required this.optionExpireLe,
    required this.paiementEnCours,
    this.wilayaNom,
    this.typeEvenement,
    this.proprietaire,
  });

  /// Construit depuis une ligne d'`acompte_a_verser()`.
  factory AcompteAVerser.depuisJson(Map<String, dynamic> j) => AcompteAVerser(
    groupId: j['group_id'] as String,
    bookingId: j['booking_id'] as String,
    venueId: j['venue_id'] as String,
    salle: j['venue_name'] as String,
    commune: j['commune'] as String,
    wilayaNom: j['wilaya_name'] as String?,
    date: DateTime.parse(j['event_date'] as String),
    creneau: Creneau.depuisCode(j['requested_slot'] as String?),
    invites: (j['guest_count'] as num).toInt(),
    // Le libellé du référentiel quand il existe ; sinon le code, parce que
    // bookings.event_type est du texte libre — même règle qu'en 013.
    typeEvenement:
        (j['event_label'] as String?) ?? (j['event_type'] as String?),
    proprietaire: j['owner_name'] as String?,
    montantConvenu: j['montant_convenu'] as num,
    // Entier : la base a déjà arrondi, une seule fois.
    acompte: (j['acompte'] as num).toInt(),
    solde: j['solde'] as num,
    optionExpireLe: DateTime.parse(j['option_expires_at'] as String).toLocal(),
    paiementEnCours: j['paiement_en_cours'] as bool? ?? false,
  );

  /// La réservation — un groupe, une ou deux lignes de `bookings`.
  final String groupId;

  /// La ligne représentative du groupe, celle qu'attendent les fonctions.
  final String bookingId;

  /// La salle.
  final String venueId;

  /// Son nom.
  final String salle;

  /// Sa commune.
  final String commune;

  /// Sa wilaya.
  final String? wilayaNom;

  /// La date de l'événement.
  final DateTime date;

  /// Le créneau demandé.
  final Creneau creneau;

  /// Le nombre d'invités.
  final int invites;

  /// Le type d'événement, déjà traduit quand il vient du référentiel.
  final String? typeEvenement;

  /// Le nom du propriétaire — « Karim a confirmé… », comme dans la maquette.
  final String? proprietaire;

  /// Le montant convenu pour la réservation entière, au centime.
  final num montantConvenu;

  /// L'acompte, en dinars ENTIERS. Le nombre du bouton, et celui de Chargily.
  final int acompte;

  /// Ce qui restera à régler sur place le jour J.
  final num solde;

  /// L'échéance de l'option de 72 h (§5.1).
  final DateTime optionExpireLe;

  /// Vrai quand une page de paiement a déjà été ouverte et n'a pas encore été
  /// tranchée.
  ///
  /// Elle ne veut PAS dire « payé » : seul le webhook Chargily confirme un
  /// paiement, et il n'existe pas encore. Elle veut dire « quelqu'un est passé
  /// par la caisse, on ne sait pas encore avec quel résultat » — et c'est
  /// exactement ce que l'écran doit dire au retour de Chargily.
  final bool paiementEnCours;

  /// « Oran, Oran (31) » n'a pas de sens : la commune suffit quand la wilaya
  /// porte le même nom.
  String get localisation => wilayaNom == null || wilayaNom == commune
      ? commune
      : '$commune, $wilayaNom';

  /// La part du montant convenu que représente l'acompte, en pourcentage entier.
  ///
  /// CALCULÉE, ET NON ÉCRITE. La maquette affiche « Acompte (25 %) », et 25 %
  /// est bien le taux que la plateforme propose (`deposit_rate()`, §5.3) — mais
  /// le §5.3 laisse le propriétaire le fixer entre 20 et 30 %, et
  /// `accept_booking()` accepte ce qu'il fixe. Écrire « 25 % » en dur mentirait
  /// le jour où il en choisit un autre. On lit donc la part des deux montants
  /// qui sont en base, et elle est juste par construction.
  ///
  /// Null quand le montant convenu est nul : il n'y a alors pas de part à dire.
  int? get partEnPourcent {
    if (montantConvenu <= 0) return null;
    return (acompte / montantConvenu * 100).round();
  }
}

/// Ce que la Edge Function `create-checkout` rend quand elle a fait son travail.
///
/// [url] EST NULLE QUAND [dejaPaye] EST VRAI, et c'est le seul cas. Chargily a
/// déjà encaissé cette page : rouvrir une caisse serait proposer de payer deux
/// fois. La réservation reste pourtant « acceptée » tant que le webhook du J16
/// n'a pas parlé — d'où [dejaPaye], qui dit à l'écran d'afficher « paiement en
/// cours de vérification » plutôt que d'ouvrir quoi que ce soit.
@immutable
class PageDePaiement {
  /// Crée le résultat d'une ouverture de page.
  const PageDePaiement({
    required this.url,
    required this.montant,
    required this.dejaPaye,
    required this.reutilisee,
  });

  /// Construit depuis la réponse JSON de la fonction.
  factory PageDePaiement.depuisJson(Map<String, dynamic> j) => PageDePaiement(
    url: j['url'] as String?,
    montant: (j['montant'] as num).toInt(),
    dejaPaye: j['deja_paye'] as bool? ?? false,
    reutilisee: j['reutilise'] as bool? ?? false,
  );

  /// L'adresse de la page Chargily. Nulle si [dejaPaye].
  final String? url;

  /// Le montant que cette page encaisse, en dinars entiers.
  final int montant;

  /// Vrai quand cette page a déjà été payée.
  final bool dejaPaye;

  /// Vrai quand c'est la page déjà ouverte qu'on rouvre, et non une neuve.
  ///
  /// Rien n'en dépend à l'écran : une page rouverte se présente exactement comme
  /// une neuve, et le client n'a pas à savoir laquelle il voit. Le champ existe
  /// pour les tests et les journaux, où la différence est justement le sujet.
  final bool reutilisee;
}

/// Levée quand il n'y a pas d'adresse de retour à donner à Chargily.
///
/// C'EST LE CAS HORS DU WEB AUJOURD'HUI. Chargily renvoie le client sur une
/// adresse http(s) après la caisse ; sur Android il faudrait un lien
/// d'application déclaré, et il ne l'est pas encore. Ouvrir quand même la page
/// de paiement enverrait quelqu'un payer sans retour possible vers
/// l'application — un refus qui dit pourquoi vaut mieux.
class PaiementHorsDuWebException implements Exception {
  /// Crée l'exception.
  const PaiementHorsDuWebException();

  @override
  String toString() =>
      'Le paiement en ligne n’est disponible que depuis un navigateur.';
}
