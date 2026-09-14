import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'assistant_messages.dart';
import 'assistant_repository.dart';
import 'message_assistant.dart';

/// L'état de l'écran 8 : ce qui s'est dit, et si l'assistant réfléchit.
@immutable
class EtatConversation {
  /// Crée l'état.
  const EtatConversation({
    this.messages = const <MessageAssistant>[],
    this.enAttente = false,
  });

  /// Les messages, du plus ancien au plus récent.
  final List<MessageAssistant> messages;

  /// Vrai pendant que l'assistant cherche.
  ///
  /// C'EST CE BOOLÉEN QUI BLOQUE L'ENVOI, et rien d'autre. Un second champ
  /// « bouton désactivé » finirait par mentir : l'attente et le blocage sont la
  /// même chose, et ils doivent être la même variable.
  final bool enAttente;

  /// Vrai quand personne n'a encore rien dit — l'écran affiche alors son accueil.
  bool get estVide => messages.isEmpty;

  /// Une copie avec ce qui change.
  EtatConversation copieAvec({
    List<MessageAssistant>? messages,
    bool? enAttente,
  }) => EtatConversation(
    messages: messages ?? this.messages,
    enAttente: enAttente ?? this.enAttente,
  );
}

/// La conversation avec l'assistant — l'écran 8.
///
/// ELLE VIT LE TEMPS DE LA SESSION, ET NULLE PART AILLEURS. Aucun stockage sur
/// l'appareil : `shared_preferences` ne garde que des préférences d'affichage,
/// et la question qu'on pose à un assistant n'en est pas une. Le journal du §8.5
/// existe en base, côté serveur, et il est anonyme — c'est un autre objet, pour
/// un autre usage.
///
/// PAS `autoDispose`, ET C'EST LE POINT. La barre d'onglets garde chaque branche
/// vivante, mais un provider jetable se viderait au premier moment où plus
/// personne ne le regarde — revenir de la fiche d'une salle citée effacerait la
/// conversation qui vient de la proposer. Elle se termine avec l'application, et
/// avec le bouton qui l'efface.
///
/// AUCUN COMPTE N'EST DEMANDÉ. Chercher se fait sans s'inscrire (§3, étapes 1
/// et 2), et cet écran est une recherche : rien ici ne lit `estConnecteProvider`,
/// rien ne redirige. La connexion se demande plus loin, au moment d'agir — sur
/// le bouton « Demander cette date » de la fiche que la carte ouvre.
class ConversationAssistant extends Notifier<EtatConversation> {
  @override
  EtatConversation build() => const EtatConversation();

  /// Pose une question et attend la réponse.
  ///
  /// DEUX GESTES REFUSÉS SANS RIEN DIRE : une question vide, et une question
  /// posée pendant qu'on attend. Le second est déjà empêché par l'écran — le
  /// bouton est éteint —, et il est empêché ici aussi : un raccourci clavier,
  /// un double appui sur un appareil lent, et deux questions partiraient pour
  /// un seul quota.
  Future<void> demander(String question) async {
    final propre = question.trim();
    if (propre.isEmpty || state.enAttente) return;

    state = state.copieAvec(
      messages: <MessageAssistant>[
        ...state.messages,
        MessageAssistant.moi(propre),
      ],
      enAttente: true,
    );

    try {
      final reponse = await ref
          .read(assistantRepositoryProvider)
          .demander(propre);

      // LE QUOTA ARRIVE EN 200, avec sa phrase déjà écrite par la fonction. On
      // la remplace par la nôtre : celle du serveur est correcte mais courte, et
      // c'est ici qu'on sait quoi proposer à la place — la recherche classique,
      // qui est un écran de cette application.
      final message = reponse.estUnQuotaEpuise
          ? MessageAssistant.echec(
              EchecAssistant.quota,
              messageEchecAssistant(EchecAssistant.quota),
            )
          : MessageAssistant(
              auteur: AuteurDuMessage.assistant,
              texte: reponse.texte,
              // LES SALLES DU CONTEXTE, ET NON CELLES QUE LE MODÈLE A NOMMÉES.
              // C'est la liste que le §8.5 a validée : toutes publiées, toutes
              // avec un prix venu de la base. Une carte par salle proposée, même
              // si la phrase n'en détaille que deux — l'utilisateur voit ce que
              // l'agent avait sous les yeux.
              salles: reponse.salles,
              suggestions: reponse.suggestions,
            );

      state = state.copieAvec(
        messages: <MessageAssistant>[...state.messages, message],
        enAttente: false,
      );
    } on EchecDeLAssistant catch (erreur) {
      state = state.copieAvec(
        messages: <MessageAssistant>[
          ...state.messages,
          MessageAssistant.echec(
            erreur.echec,
            messageEchecAssistant(erreur.echec),
          ),
        ],
        enAttente: false,
      );
    }
  }

  /// Efface la conversation — le bouton « ⟲ » de la maquette.
  ///
  /// IL N'EFFACE RIEN AILLEURS, et il n'a rien à effacer : la conversation n'est
  /// nulle part d'autre. Le journal du §8.5, lui, reste — il est anonyme, il
  /// sert à savoir si l'agent répond bien, et il n'appartient pas à cet écran.
  void effacer() {
    if (state.enAttente) return;
    state = const EtatConversation();
  }
}

/// La conversation avec l'assistant.
final conversationProvider =
    NotifierProvider<ConversationAssistant, EtatConversation>(
      ConversationAssistant.new,
    );
