import 'package:flutter/foundation.dart';

import '../search/search_filters.dart';

/// Les quatre sous-notes du §4.2 (CLI-08), et leur libellé d'écran.
///
/// LE CODE DE LA BASE D'UN CÔTÉ, LE LIBELLÉ DE L'AUTRE, comme partout dans ce
/// projet. `rating_cleanliness` est un nom de colonne ; « Propreté » est ce que
/// lit quelqu'un qui raconte sa soirée.
///
/// L'ORDRE EST CELUI DE LA MAQUETTE — propreté, service, rapport qualité/prix,
/// conformité. Il n'est pas alphabétique et ne doit pas le devenir : c'est
/// l'ordre dans lequel on se souvient d'une salle.
enum SousNote {
  /// La salle était-elle propre.
  proprete('rating_cleanliness', 'Propreté'),

  /// Le personnel a-t-il fait son travail.
  service('rating_service', 'Service'),

  /// Le prix valait-il la soirée.
  rapportQualitePrix('rating_value', 'Rapport q/p'),

  /// La salle ressemblait-elle à ses photos.
  conformite('rating_accuracy', 'Conformité');

  const SousNote(this.cle, this.libelle);

  /// La clé du JSON, et le nom de la colonne.
  final String cle;

  /// Ce qui s'affiche, à côté de la barre.
  final String libelle;
}

/// Un avis publié, tel que le rend `avis_de_la_salle()` (026).
///
/// CE QU'IL NE PORTE PAS, ET NE DOIT JAMAIS PORTER : le nom entier de son
/// auteur, son e-mail, son téléphone. [auteur] arrive déjà raccourci par
/// `nom_abrege()` — « Amina H. » —, et c'est la seule forme dans laquelle un
/// nom de client traverse la base (§9). Un écran qui voudrait en montrer plus
/// n'aurait rien à montrer.
@immutable
class AvisPublie {
  /// Crée un avis publié.
  const AvisPublie({
    required this.id,
    required this.auteur,
    required this.note,
    required this.publieLe,
    this.commentaire,
    this.sousNotes = const <SousNote, int>{},
    this.reponse,
    this.reponduLe,
  });

  /// Construit depuis un élément du tableau `reviews`.
  factory AvisPublie.depuisJson(Map<String, dynamic> j) => AvisPublie(
    id: j['id'] as String,
    auteur: (j['author'] as String?) ?? 'Client',
    note: (j['rating'] as num).toInt(),
    sousNotes: <SousNote, int>{
      for (final sousNote in SousNote.values)
        if (j[sousNote.cle] != null) sousNote: (j[sousNote.cle] as num).toInt(),
    },
    commentaire: j['body'] as String?,
    publieLe: DateTime.parse(j['created_at'] as String).toLocal(),
    reponse: j['owner_reply'] as String?,
    reponduLe: j['owner_replied_at'] == null
        ? null
        : DateTime.parse(j['owner_replied_at'] as String).toLocal(),
  );

  /// L'identifiant de l'avis — celui auquel le propriétaire répond.
  final String id;

  /// Le prénom et l'initiale, tels que la base les a rendus.
  final String auteur;

  /// La note globale, de 1 à 5.
  final int note;

  /// Les sous-notes renseignées. Vide quand l'auteur n'en a donné aucune.
  final Map<SousNote, int> sousNotes;

  /// Le texte libre, s'il y en a un.
  final String? commentaire;

  /// Quand l'avis a été déposé.
  final DateTime publieLe;

  /// La réponse du propriétaire (§4.3, OWN-06), s'il a répondu.
  final String? reponse;

  /// Quand il a répondu.
  final DateTime? reponduLe;

  /// Vrai quand le propriétaire a déjà répondu — et donc que l'avis est figé.
  bool get aUneReponse => reponse != null;

  /// « août 2026 », comme sur la maquette : le mois suffit à situer une soirée,
  /// et le quantième dirait à quelle noce l'avis appartient.
  String get moisDePublication =>
      '${moisEnFrancais(publieLe)} ${publieLe.year}';

  /// Les initiales de la pastille — « Amina H. » donne « AH ».
  ///
  /// Calculées depuis [auteur] et non depuis un nom entier : il n'y a pas de
  /// nom entier de ce côté-ci, et c'est le but.
  String get initiales {
    final mots = auteur
        .split(RegExp(r'\s+'))
        .where((m) => m.isNotEmpty)
        .toList(growable: false);
    if (mots.isEmpty) return '?';
    if (mots.length == 1) return _premiereLettre(mots.first);
    return '${_premiereLettre(mots.first)}${_premiereLettre(mots.last)}';
  }
}

/// La première lettre d'un mot, en capitale. Rend vide sur une chaîne vide.
String _premiereLettre(String mot) =>
    mot.isEmpty ? '' : mot.substring(0, 1).toUpperCase();

/// La synthèse des avis d'une salle (§8.2) — le bloc « ✦ » de l'écran 7.
///
/// ELLE EST PRÉ-CALCULÉE LA NUIT, par l'Edge Function « summarize-reviews », et
/// rien ici ne la fabrique. Elle vient de la base comme la note et les avis, et
/// pour la même raison : un texte produit à l'affichage changerait à chaque
/// ouverture de l'écran, et coûterait un appel au modèle à chaque lecteur.
///
/// [nombre] N'EST PAS LE NOMBRE D'AVIS D'AUJOURD'HUI. C'est celui dont vient ce
/// texte-là. Les deux se séparent dès qu'un avis est déposé après la dernière
/// nuit — et annoncer « la synthèse des 40 avis » sous un résumé qui en a lu 34
/// promettrait six avis qu'il n'a jamais vus.
@immutable
class SyntheseDesAvis {
  /// Crée la synthèse.
  const SyntheseDesAvis({
    required this.texte,
    required this.nombre,
    required this.misAJourLe,
  });

  /// Lit la synthèse dans le JSON d'`avis_de_la_salle()`, ou rend `null`.
  ///
  /// LES TROIS CHAMPS VONT ENSEMBLE OU PAS DU TOUT. Une synthèse sans sa date
  /// ne se présenterait pas honnêtement — le lecteur ne saurait pas de quand
  /// elle date —, et la base les écrit d'un seul bloc. On préfère donc ne rien
  /// afficher à afficher la moitié.
  static SyntheseDesAvis? depuisJson(Map<String, dynamic> j) {
    final texte = (j['summary'] as String?)?.trim();
    final nombre = (j['summary_count'] as num?)?.toInt();
    final date = j['summary_updated_at'] as String?;

    if (texte == null || texte.isEmpty || nombre == null || date == null) {
      return null;
    }

    return SyntheseDesAvis(
      texte: texte,
      nombre: nombre,
      misAJourLe: DateTime.parse(date).toLocal(),
    );
  }

  /// Le texte, dans la langue des avis qu'il résume — pas forcément celle de
  /// l'application. L'écran l'affiche dans le sens d'écriture de sa langue.
  final String texte;

  /// Le nombre d'avis dont vient ce texte.
  final int nombre;

  /// Quand elle a été rédigée.
  final DateTime misAJourLe;

  /// « août 2026 » — le mois suffit, comme pour la date d'un avis.
  String get moisDeMiseAJour =>
      '${moisEnFrancais(misAJourLe)} ${misAJourLe.year}';
}

/// Les avis d'une salle, tels que les rend `avis_de_la_salle()` — l'écran 7.
///
/// LA NOTE VIENT DE `venue_ratings`, ET DE NULLE PART AILLEURS. C'est la moyenne
/// bayésienne du §5.4, calculée en base. Rien dans ce fichier ne fait une
/// moyenne, et rien ne doit en faire : une salle avec un seul 5/5 ne dépasse pas
/// une salle à quarante 4,6, et c'est la vue qui le décide.
///
/// LA SYNTHÈSE EST FACULTATIVE, ET C'EST TOUT CE QU'IL Y A À SAVOIR D'ELLE ICI.
/// Elle manque tant que « summarize-reviews » n'est pas passée, et elle manque
/// pour toujours sous trois avis porteurs de texte — on ne résume pas deux
/// phrases (§8.2). L'écran ne dessine alors aucun cadre : un encart vide dirait
/// au visiteur que l'application est inachevée, plus fort que son absence.
@immutable
class AvisDeLaSalle {
  /// Crée la page d'avis d'une salle.
  const AvisDeLaSalle({
    required this.venueId,
    required this.salle,
    required this.nombre,
    required this.avis,
    this.note,
    this.moyennes = const <SousNote, double>{},
    this.synthese,
  });

  /// Construit depuis le JSON d'`avis_de_la_salle()`.
  factory AvisDeLaSalle.depuisJson(Map<String, dynamic> j) => AvisDeLaSalle(
    venueId: j['venue_id'] as String,
    salle: j['venue_name'] as String,
    note: (j['rating'] as num?)?.toDouble(),
    nombre: ((j['review_count'] as num?) ?? 0).toInt(),
    synthese: SyntheseDesAvis.depuisJson(j),
    moyennes: <SousNote, double>{
      for (final sousNote in SousNote.values)
        if (j[sousNote.cle] != null)
          sousNote: (j[sousNote.cle] as num).toDouble(),
    },
    avis: ((j['reviews'] as List<dynamic>?) ?? const <dynamic>[])
        .cast<Map<String, dynamic>>()
        .map(AvisPublie.depuisJson)
        .toList(growable: false),
  );

  /// La salle concernée.
  final String venueId;

  /// Son nom — le titre de l'écran.
  final String salle;

  /// La note bayésienne affichée (§5.4). `null` quand la salle n'a aucun avis.
  final double? note;

  /// Le nombre d'avis.
  final int nombre;

  /// La moyenne de chaque sous-note renseignée.
  ///
  /// UNE SOUS-NOTE ABSENTE N'EST PAS UN ZÉRO : elle est facultative, et
  /// personne ne l'a peut-être remplie. L'écran n'affiche alors pas sa barre,
  /// plutôt qu'une barre vide qui se lirait « 0 sur 5 ».
  final Map<SousNote, double> moyennes;

  /// Les avis, le plus récent en tête.
  final List<AvisPublie> avis;

  /// La synthèse pré-calculée, quand il y en a une.
  final SyntheseDesAvis? synthese;

  /// Vrai seulement si la salle a réellement été notée.
  ///
  /// Une salle neuve n'est pas une salle mal notée : « 0,0 (0) » le laisserait
  /// croire, et c'est la même règle que sur la fiche.
  bool get estNotee => note != null && nombre > 0;
}

/// Ce qu'il faut à l'écran de dépôt, tel que le rend `avis_a_deposer()` (026).
///
/// IL PORTE AUSSI L'AVIS DÉJÀ DÉPOSÉ. C'est ce qui fait de cet écran un écran de
/// CORRECTION autant que de dépôt (§5.4) : les étoiles reviennent allumées et le
/// texte revient dans son champ.
///
/// [modifiable] VIENT DE LA BASE, ET NE SE RECALCULE PAS ICI. Il réunit deux
/// règles — la fenêtre de J+1 à J+30, et l'avis figé par la réponse du
/// propriétaire —, et les deux vivent en SQL. Les refaire en Dart créerait une
/// seconde définition de « on peut encore écrire ».
@immutable
class AvisADeposer {
  /// Crée l'état de l'écran de dépôt.
  const AvisADeposer({
    required this.groupId,
    required this.bookingId,
    required this.venueId,
    required this.salle,
    required this.commune,
    required this.date,
    required this.creneau,
    required this.invites,
    required this.ouvreLe,
    required this.fermeLe,
    required this.fenetreOuverte,
    required this.modifiable,
    this.wilayaNom,
    this.photo,
    this.typeEvenement,
    this.avisId,
    this.note,
    this.sousNotes = const <SousNote, int>{},
    this.commentaire,
    this.reponse,
    this.reponduLe,
  });

  /// Construit depuis la ligne d'`avis_a_deposer()`.
  factory AvisADeposer.depuisJson(Map<String, dynamic> j) => AvisADeposer(
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
    typeEvenement: j['event_label'] as String?,
    ouvreLe: DateTime.parse(j['ouvre_le'] as String),
    fermeLe: DateTime.parse(j['ferme_le'] as String),
    fenetreOuverte: (j['fenetre_ouverte'] as bool?) ?? false,
    modifiable: (j['modifiable'] as bool?) ?? false,
    avisId: j['avis_id'] as String?,
    note: (j['rating'] as num?)?.toInt(),
    sousNotes: <SousNote, int>{
      for (final sousNote in SousNote.values)
        if (j[sousNote.cle] != null) sousNote: (j[sousNote.cle] as num).toInt(),
    },
    commentaire: j['body'] as String?,
    reponse: j['owner_reply'] as String?,
    reponduLe: j['owner_replied_at'] == null
        ? null
        : DateTime.parse(j['owner_replied_at'] as String).toLocal(),
  );

  /// L'identifiant de la réservation — un groupe, une ou deux lignes.
  final String groupId;

  /// La ligne représentative, celle qu'attend `deposer_avis()`.
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

  /// Le créneau.
  final Creneau creneau;

  /// Le nombre d'invités.
  final int invites;

  /// Le type d'événement, déjà traduit.
  final String? typeEvenement;

  /// Le premier jour où l'avis s'écrit — J+1 (§5.4).
  final DateTime ouvreLe;

  /// Le dernier — J+30.
  final DateTime fermeLe;

  /// Vrai quand on est entre les deux, aujourd'hui.
  final bool fenetreOuverte;

  /// Vrai quand « Publier » aboutira : la fenêtre court ET personne n'a répondu.
  final bool modifiable;

  /// L'avis déjà déposé, s'il existe.
  final String? avisId;

  /// Sa note globale.
  final int? note;

  /// Ses sous-notes renseignées.
  final Map<SousNote, int> sousNotes;

  /// Son commentaire.
  final String? commentaire;

  /// La réponse du propriétaire, s'il a répondu.
  final String? reponse;

  /// Quand il a répondu.
  final DateTime? reponduLe;

  /// Vrai quand un avis existe déjà — l'écran dit alors « Modifier ».
  bool get dejaDepose => avisId != null;

  /// Vrai quand l'avis est figé par la réponse du propriétaire (§5.4).
  ///
  /// Distinct de `!modifiable` : une fenêtre fermée fige aussi l'avis, mais pas
  /// pour la même raison, et l'écran ne dit pas la même phrase.
  bool get figeParLaReponse => reponse != null;

  /// « Oran, Oran » n'a pas de sens : la commune suffit.
  String get localisation => wilayaNom == null || wilayaNom == commune
      ? commune
      : '$commune, $wilayaNom';
}
