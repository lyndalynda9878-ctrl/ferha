import 'package:flutter/foundation.dart';

/// Ce que le propriétaire a rempli jusqu'ici (§4.3, OWN-01).
///
/// IMMUABLE, ET C'EST CE QUI FAIT QUE REVENIR EN ARRIÈRE NE PERD RIEN. L'écran
/// garde une seule valeur et la remplace à chaque frappe ; changer d'étape ne
/// démonte donc rien qui porte de l'information. Un formulaire dont chaque
/// étape garderait son propre état perdrait le tout au premier retour — et
/// c'est exactement ce qu'on refait quand on en a assez de tout retaper.
///
/// LES CHAMPS OBLIGATOIRES SONT CEUX SANS LESQUELS LA SALLE N'EXISTE PAS, et
/// rien de plus. Quatre viennent de la table : `venues` déclare `name`,
/// `wilaya_code`, `commune` et `capacity_seated` en `not null` (§6). Le
/// cinquième est l'ADRESSE, et il vient d'ailleurs — de l'exigence humaine
/// d'ADM-01, « aucune salle n'est visible avant contrôle humain (photos
/// réelles, adresse plausible, propriétaire joignable) ». Elle est nullable en
/// table pour les quinze salles de démonstration qui n'en ont pas, et exigée
/// par `creer_salle()` (019) pour toute salle neuve.
///
/// Superficie, parking, description, équipements et types d'événement restent
/// facultatifs, et le resteront — « Karim ne veut pas d'un formulaire de 30
/// champs pour publier sa salle ».
@immutable
class NouvelleSalle {
  /// Crée un formulaire vide, ou déjà rempli.
  const NouvelleSalle({
    this.nom = '',
    this.description = '',
    this.wilayaCode,
    this.commune = '',
    this.adresse = '',
    this.capacite,
    this.superficie,
    this.parking,
    this.equipements = const <String>{},
    this.typesEvenement = const <String>{},
  });

  /// Le nom de la salle. Obligatoire.
  final String nom;

  /// Ce qu'elle a de particulier. Facultatif.
  final String description;

  /// Le code de wilaya sur deux chiffres. Obligatoire.
  final String? wilayaCode;

  /// La commune. Obligatoire.
  final String commune;

  /// La rue et ses repères. Obligatoire.
  ///
  /// ELLE NE S'AFFICHE NULLE PART CÔTÉ CLIENT, et ce n'est pas un oubli : ni
  /// `venue_detail()`, ni `search_venues()`, ni aucune vue ne la renvoient, et
  /// la migration 019 va jusqu'à retirer le droit de lire cette colonne-là.
  /// Elle sert au contrôle humain d'ADM-01, et à lui seul — comme le
  /// téléphone, une adresse donnée trop tôt fait contourner la plateforme.
  final String adresse;

  /// La capacité assise, en couverts. Obligatoire.
  final int? capacite;

  /// La superficie en mètres carrés. Facultative — tous les propriétaires ne
  /// la connaissent pas.
  final int? superficie;

  /// Le nombre de places de parking.
  ///
  /// `null` VEUT DIRE « NON RENSEIGNÉ », ET 0 VEUT DIRE « PAS DE PARKING ».
  /// Les deux ne se disent pas pareil, et la fiche salle les affiche
  /// différemment — « — non renseigné » contre « 0 aucune place ». Ce champ ne
  /// doit donc jamais être ramené à zéro par commodité.
  final int? parking;

  /// Les codes d'équipement cochés.
  final Set<String> equipements;

  /// Les codes de type d'événement cochés.
  ///
  /// Aucun coché veut dire « la salle accepte tout » : c'est la règle de
  /// `venue_event_types` (010), où l'absence de ligne n'est pas un refus mais
  /// une question à laquelle le propriétaire n'a pas encore répondu.
  final Set<String> typesEvenement;

  /// Renvoie une copie modifiée.
  ///
  /// LES QUATRE `Object?` NE SONT PAS UNE COQUETTERIE. `wilayaCode`,
  /// `capacite`, `superficie` et `parking` peuvent valoir `null`, et un
  /// paramètre nommé `int?` ne sait pas distinguer « on ne touche pas » de
  /// « on efface ». La sentinelle [_absent], si : effacer un parking déjà saisi
  /// doit être possible, et c'est le seul moyen de revenir à
  /// « non renseigné ».
  NouvelleSalle copyWith({
    String? nom,
    String? description,
    Object? wilayaCode = _absent,
    String? commune,
    String? adresse,
    Object? capacite = _absent,
    Object? superficie = _absent,
    Object? parking = _absent,
    Set<String>? equipements,
    Set<String>? typesEvenement,
  }) {
    return NouvelleSalle(
      nom: nom ?? this.nom,
      description: description ?? this.description,
      wilayaCode: wilayaCode == _absent
          ? this.wilayaCode
          : wilayaCode as String?,
      commune: commune ?? this.commune,
      adresse: adresse ?? this.adresse,
      capacite: capacite == _absent ? this.capacite : capacite as int?,
      superficie: superficie == _absent ? this.superficie : superficie as int?,
      parking: parking == _absent ? this.parking : parking as int?,
      equipements: equipements ?? this.equipements,
      typesEvenement: typesEvenement ?? this.typesEvenement,
    );
  }

  static const Object _absent = Object();

  /// Ce qui manque à l'étape [etape] pour pouvoir continuer, ou `null`.
  ///
  /// LA PHRASE EST LE POINT DE CETTE MÉTHODE, pas le booléen. Un bouton éteint
  /// sans explication laisse chercher : « Continuer » est gris, et on relit
  /// trois champs pour comprendre lequel n'est pas rempli. On dit donc lequel,
  /// et on le dit à côté du bouton.
  ///
  /// Une seule chose à la fois, dans l'ordre de lecture de l'écran : réclamer
  /// « le nom et la commune » quand les deux manquent ferait une phrase plus
  /// longue pour un geste qui reste le même — remplir le premier champ vide.
  String? ceQuiManque(EtapePublication etape) => switch (etape) {
    EtapePublication.identite when nom.trim().isEmpty =>
      'Donnez un nom à votre salle pour continuer.',
    EtapePublication.lieu when wilayaCode == null =>
      'Choisissez la wilaya de votre salle.',
    EtapePublication.lieu when commune.trim().isEmpty =>
      'Indiquez la commune de votre salle.',
    // L'adresse en dernier de l'étape 2, parce qu'elle est le dernier champ de
    // l'écran : on réclame toujours le premier champ vide dans l'ordre de
    // lecture.
    EtapePublication.lieu when adresse.trim().isEmpty =>
      'Indiquez l’adresse de votre salle — elle est vérifiée avant publication.',
    EtapePublication.capacite when capacite == null =>
      'Indiquez combien de couverts votre salle peut asseoir.',
    _ => null,
  };

  /// Vrai quand l'étape est complète.
  bool estComplete(EtapePublication etape) => ceQuiManque(etape) == null;

  /// Vrai quand toutes les étapes sont complètes.
  ///
  /// C'est ce que `creer_salle()` exige (FE031 et FE036). L'écran ne devrait
  /// jamais laisser envoyer sans, mais la base reste le dernier mot.
  bool get estEnvoyable => EtapePublication.values.every(estComplete);
}

/// Les étapes du formulaire, dans l'ordre d'OWN-01.
///
/// « Formulaire en 5 étapes courtes : identité, localisation, capacité,
/// équipements, photos. » Les quatre premières sont ici ; les photos (OWN-02)
/// viennent avec leur propre écran et leur propre compression, et se glisseront
/// en cinquième position — avant l'envoi, après la création du brouillon.
///
/// L'ÉCRAN 10 DES MAQUETTES DIT « ÉTAPE 4 SUR 5 » POUR LES PHOTOS, et c'est le
/// cahier des charges qui gagne : il les met en cinquième. Une maquette montre
/// un état de l'écran, la spécification donne l'ordre.
enum EtapePublication {
  /// Le nom, et ce qu'elle a de particulier.
  identite('Votre salle', 'Comment s’appelle-t-elle ?'),

  /// Où elle se trouve.
  lieu(
    'Où est-elle ?',
    'La wilaya et la commune, comme les clients les cherchent. L’adresse, elle, '
        'ne sera montrée à personne : elle sert à vérifier votre salle.',
  ),

  /// Combien elle tient.
  capacite(
    'Combien de couverts ?',
    'C’est le premier chiffre que regarde une famille.',
  ),

  /// Ce qu'elle offre, et ce qu'elle accueille.
  equipements(
    'Ce qu’elle offre',
    'Tout est facultatif — mais chaque équipement coché la fait sortir dans une recherche de plus.',
  );

  const EtapePublication(this.titre, this.explication);

  /// Le titre de la barre, celui qui dit où l'on est.
  final String titre;

  /// La phrase sous le titre : ce qu'on demande, et pourquoi.
  ///
  /// L'écran 10 en porte une — « Ajoutez au moins 5 photos. Les salles qui en
  /// ont plus de 10 reçoivent en moyenne trois fois plus de demandes. » Elle
  /// dit le geste ET son intérêt, et c'est ce qui fait qu'on le fait.
  final String explication;

  /// « Étape 2 sur 5 » — le rang lu par un humain.
  int get rang => index + 1;

  /// Le nombre d'étapes, tel qu'on l'annonce — « étape 2 sur 4 ».
  ///
  /// CINQ, ALORS QUE QUATRE EXISTENT, et c'est un mensonge qu'on n'écrit pas :
  /// [total] vaut le nombre réel d'étapes du formulaire d'aujourd'hui. Le jour
  /// où les photos arriveront, elles s'ajouteront à cette énumération et le
  /// compte suivra tout seul. Annoncer « sur 5 » maintenant ferait chercher une
  /// cinquième étape qui n'existe pas.
  static int get total => EtapePublication.values.length;
}
