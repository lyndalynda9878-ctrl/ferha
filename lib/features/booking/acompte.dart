import 'package:flutter/foundation.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../search/search_filters.dart';

/// Les moyens de paiement de l'écran 6.
///
/// TROIS, COMME LA MAQUETTE — et le troisième n'est pas une politesse. Sa
/// légende dit pourquoi il compte : « l'option espèces sur place est offerte
/// dès le MVP : elle sauve les utilisateurs réticents au paiement en ligne ».
/// Il est resté absent tant qu'il ne menait nulle part ; il mène maintenant à
/// `payer_en_especes()` (025), et le propriétaire confirme l'encaissement
/// depuis son espace.
///
/// [especes] N'OUVRE AUCUNE CAISSE, et c'est ce qui le distingue des deux
/// autres. Les cartes partent chez Chargily ; les espèces ne font qu'annoncer
/// une intention — la réservation reste « acceptée », l'option de 72 h continue
/// de courir, et l'argent changera de mains dans la salle. C'est pour cela que
/// le bouton ne dit pas « Payer » quand il est choisi.
///
/// LES CODES SONT CEUX DE `payments.method` (004). Ils ne s'affichent jamais :
/// c'est [libelle] qui va à l'écran, et [code] qui part vers la base.
enum MoyenDePaiement {
  /// La carte interbancaire, SATIM.
  cib('cib', 'Carte CIB', 'La carte de votre banque'),

  /// La carte d'Algérie Poste.
  edahabia('edahabia', 'Carte Edahabia', 'La carte d’Algérie Poste'),

  /// L'acompte en main propre, dans les 72 h.
  especes(
    'cash',
    'Espèces sur place',
    'Vous portez l’acompte à la salle, sous 72 h',
  );

  const MoyenDePaiement(this.code, this.libelle, this.explication);

  /// La valeur attendue par `payments.method`, et par Chargily pour les cartes.
  final String code;

  /// Le nom du moyen, tel qu'il s'affiche.
  final String libelle;

  /// Ce que cela veut dire concrètement, en une ligne.
  final String explication;

  /// Vrai quand ce moyen passe par une page de paiement Chargily.
  ///
  /// C'est la seule question que l'écran ait à poser : les deux cartes ouvrent
  /// une caisse et quittent l'application, les espèces posent une intention et
  /// restent sur place.
  bool get passeParChargily => this != especes;
}

/// Le moyen de paiement, dit dans la langue de l'application.
///
/// [MoyenDePaiement.libelle] et [MoyenDePaiement.explication] restent en
/// français dans l'énumération : ils servent aux journaux et aux tests, où une
/// langue qui change rendrait une trace illisible d'un jour à l'autre. Ce qui
/// va à l'écran passe par ici.
extension MoyenDePaiementTraduit on MoyenDePaiement {
  /// Le nom du moyen, tel qu'il s'affiche.
  String nomTraduit(AppLocalizations textes) => switch (this) {
    MoyenDePaiement.cib => textes.moyenCib,
    MoyenDePaiement.edahabia => textes.moyenEdahabia,
    MoyenDePaiement.especes => textes.moyenEspeces,
  };

  /// Ce que cela veut dire concrètement, en une ligne.
  String explicationTraduite(AppLocalizations textes) => switch (this) {
    MoyenDePaiement.cib => textes.moyenCibExplication,
    MoyenDePaiement.edahabia => textes.moyenEdahabiaExplication,
    MoyenDePaiement.especes => textes.moyenEspecesExplication,
  };
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
    required this.especesEnAttente,
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
    especesEnAttente: j['especes_en_attente'] as bool? ?? false,
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

  /// Vrai quand un versement en espèces est annoncé et attend le propriétaire.
  ///
  /// Elle ne veut pas dire « payé » non plus : elle veut dire que le client a
  /// dit qu'il apporterait les billets, et que personne ne les a encore comptés.
  /// La réservation reste « acceptée », et l'option de 72 h court toujours —
  /// c'est le compte à rebours en haut de l'écran qui le rappelle.
  final bool especesEnAttente;

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
