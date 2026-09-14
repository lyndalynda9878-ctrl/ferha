import 'package:flutter/foundation.dart';

/// Une salle citée par l'assistant — la carte cliquable de l'écran 8.
///
/// TOUT VIENT DE LA RÉPONSE DE LA FONCTION, ET RIEN N'EST RECALCULÉ ICI. Le prix
/// surtout : il arrive déjà calculé par `estimate_price()`, à travers
/// `salles_pour_agent()` puis l'Edge Function. Une seconde formule en Dart —
/// même une multiplication par un coefficient de week-end — serait exactement ce
/// que le cahier des charges interdit, et l'agent afficherait un prix que la
/// fiche démentirait deux écrans plus loin.
///
/// [prix] EST DONC NULLABLE, et la carte le dit plutôt que d'écrire un zéro. Une
/// salle sans grille tarifaire pour ce créneau n'a pas de prix ; « 0 DA » serait
/// une affirmation, et une fausse.
@immutable
class SalleCitee {
  /// Crée une salle citée.
  const SalleCitee({
    required this.venueId,
    required this.nom,
    required this.commune,
    this.wilaya,
    this.photo,
    this.capacite,
    this.prix,
    this.note,
  });

  /// Construit depuis un élément du tableau `salles` de l'Edge Function.
  ///
  /// LES CLÉS SONT CELLES DE LA FONCTION, en français : c'est elle qui compose
  /// cet objet, dans `ai-chat/index.ts`. Le jour où l'une change, c'est ici que
  /// la compilation le dira — pas à l'exécution, devant l'utilisateur.
  factory SalleCitee.depuisJson(Map<String, dynamic> j) => SalleCitee(
    venueId: j['venue_id'] as String,
    nom: (j['nom'] as String?) ?? '',
    commune: (j['commune'] as String?) ?? '',
    wilaya: j['wilaya'] as String?,
    photo: j['photo'] as String?,
    capacite: (j['capacite'] as num?)?.toInt(),
    prix: (j['prix_da'] as num?)?.toInt(),
    note: (j['note'] as num?)?.toDouble(),
  );

  /// L'identifiant — celui qu'ouvre la carte.
  final String venueId;

  /// Le nom, tel que la base le porte.
  final String nom;

  /// La commune.
  final String commune;

  /// La wilaya, quand elle diffère de la commune.
  final String? wilaya;

  /// Chemin de Storage ou URL de la photo de couverture.
  final String? photo;

  /// La capacité assise.
  final int? capacite;

  /// Le prix en dinars, tel qu'`estimate_price()` l'a rendu. `null` quand la
  /// salle n'a pas de tarif pour le créneau demandé.
  final int? prix;

  /// La note bayésienne (§5.4). `null` quand la salle n'a aucun avis.
  final double? note;

  /// « Bir El Djir · 400 », comme la maquette : la commune, puis la capacité.
  String get sousTitre {
    final capacite = this.capacite;
    return capacite == null ? commune : '$commune · $capacite';
  }
}

/// Qui a écrit un message de la conversation.
enum AuteurDuMessage {
  /// La personne devant l'écran.
  moi,

  /// L'assistant.
  assistant,
}

/// Ce qui a empêché l'assistant de répondre.
///
/// TROIS PANNES ET PAS UNE DE PLUS, parce que ce sont les trois que
/// l'utilisateur peut comprendre et parfois corriger (§4.2). Chacune a sa
/// phrase, et aucune n'affiche de trace technique : un message d'erreur brut
/// n'aide personne à finir ce qu'il était venu faire.
enum EchecAssistant {
  /// Le quota gratuit du modèle est épuisé. Ce n'est pas une panne : c'est
  /// « revenez dans une minute », et la recherche classique marche toujours.
  quota,

  /// Le service d'empreintes dormait. Le premier appel le réveille et peut
  /// prendre une minute — ce n'est pas un échec définitif, c'est une attente
  /// qu'il faut ANNONCER plutôt que laisser deviner.
  serviceEndormi,

  /// Aucune connexion. Rien n'est parti, rien n'est perdu.
  reseau,

  /// Tout le reste. La fonction a répondu autre chose qu'une réponse.
  panne,
}

/// Un message de la conversation — le mien, ou celui de l'assistant.
///
/// LA CONVERSATION VIT LE TEMPS DE LA SESSION, et ces objets avec elle. Rien
/// n'est écrit sur l'appareil : `shared_preferences` ne garde que des
/// préférences d'affichage (la salle choisie par un propriétaire), et une
/// question posée à un assistant n'en est pas une. Fermer l'application efface
/// la conversation, et c'est ce qu'on veut.
///
/// L'AGENT, LUI, N'A AUCUNE MÉMOIRE. `ai-chat` reçoit une question et rien
/// d'autre : chaque question est traitée seule. Ce que cet écran affiche est un
/// COMPTE RENDU de ce qui s'est dit, pas un fil que l'assistant relit. C'est
/// pourquoi « et avec un jardin ? » posé après coup ne marche pas — et c'est une
/// limite honnête, pas un bogue à cacher.
@immutable
class MessageAssistant {
  /// Crée un message.
  const MessageAssistant({
    required this.auteur,
    required this.texte,
    this.salles = const <SalleCitee>[],
    this.suggestions = const <String>[],
    this.echec,
  });

  /// Ce que la personne vient d'envoyer.
  const MessageAssistant.moi(String texte)
    : this(auteur: AuteurDuMessage.moi, texte: texte);

  /// Une panne, dite en toutes lettres.
  const MessageAssistant.echec(EchecAssistant echec, String texte)
    : this(auteur: AuteurDuMessage.assistant, texte: texte, echec: echec);

  /// Qui parle.
  final AuteurDuMessage auteur;

  /// Le texte affiché. Il porte sa propre langue : l'écran l'affiche dans son
  /// sens d'écriture, pas dans celui de l'application.
  final String texte;

  /// Les salles citées, devenues des cartes cliquables.
  final List<SalleCitee> salles;

  /// Les relances proposées sous la réponse.
  ///
  /// VIDE AUJOURD'HUI, ET C'EST VOULU. La maquette en dessine trois — « Avec
  /// espace femmes », « Moins de 200 000 » —, mais `ai-chat` n'en renvoie
  /// aucune : elle rédige une réponse, elle ne propose pas de suite. Tant
  /// qu'elle n'en renvoie pas, la rangée n'existe pas. Trois boutons dessinés à
  /// la main qui relanceraient une recherche que personne n'a choisie seraient
  /// de la décoration, et de la décoration qui ment.
  final List<String> suggestions;

  /// Ce qui a échoué, quand c'est un message d'échec.
  final EchecAssistant? echec;

  /// Vrai quand ce message dit une panne plutôt qu'une réponse.
  bool get estUnEchec => echec != null;
}

/// Ce que rend l'Edge Function « ai-chat » — sa réponse, décodée.
@immutable
class ReponseAssistant {
  /// Crée la réponse.
  const ReponseAssistant({
    required this.texte,
    required this.statut,
    this.salles = const <SalleCitee>[],
    this.suggestions = const <String>[],
  });

  /// Construit depuis le corps JSON de la fonction.
  factory ReponseAssistant.depuisJson(Map<String, dynamic> j) =>
      ReponseAssistant(
        texte: ((j['reponse'] as String?) ?? '').trim(),
        statut: (j['statut'] as String?) ?? '',
        salles: ((j['salles'] as List<dynamic>?) ?? const <dynamic>[])
            .cast<Map<String, dynamic>>()
            .map(SalleCitee.depuisJson)
            .toList(growable: false),
        // Voir `MessageAssistant.suggestions` : on lit le champ, la fonction ne
        // le remplit pas encore, et rien ne s'affiche tant qu'elle ne le fait
        // pas. Le jour où elle le fera, il n'y aura rien à changer ici.
        suggestions: ((j['suggestions'] as List<dynamic>?) ?? const <dynamic>[])
            .map((s) => s.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList(growable: false),
      );

  /// La réponse rédigée, dans la langue de la question.
  final String texte;

  /// Ce que la fonction a fait : `ok`, `aucune_salle`, `liste_brute`,
  /// `hors_sujet`, `procedure`, `date_passee`, `quota`.
  final String statut;

  /// Les salles du contexte — celles que l'agent avait le droit de citer.
  final List<SalleCitee> salles;

  /// Les relances, si la fonction en propose.
  final List<String> suggestions;

  /// LE STATUT `quota` ARRIVE EN 200, avec une phrase déjà rédigée.
  ///
  /// C'est un choix de l'Edge Function, et un bon : côté application, un quota
  /// épuisé n'est pas une panne à réessayer en boucle, c'est une réponse à
  /// afficher. On la reconnaît quand même, pour lui donner la mise en forme d'un
  /// échec plutôt que celle d'une réponse — elle ne cite aucune salle, et une
  /// bulle ordinaire laisserait croire que l'assistant a cherché.
  bool get estUnQuotaEpuise => statut == 'quota';
}
