import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_providers.dart';
import 'message_assistant.dart';

/// Ce que lève le dépôt quand l'assistant n'a pas pu répondre.
///
/// UN TYPE À NOUS, ET NON L'EXCEPTION DU PAQUET. `FunctionsFetchException`,
/// `FunctionsHttpException` et `TimeoutException` disent trois pannes de
/// transport ; l'écran, lui, a besoin de savoir laquelle des trois phrases
/// écrire. La traduction se fait UNE FOIS, ici, à l'endroit qui voit l'erreur
/// d'origine — et l'écran ne connaît plus que [EchecAssistant].
class EchecDeLAssistant implements Exception {
  /// Crée l'échec.
  const EchecDeLAssistant(this.echec, [this.cause]);

  /// Laquelle des trois pannes.
  final EchecAssistant echec;

  /// L'erreur d'origine — pour le journal, jamais pour l'écran.
  final Object? cause;

  @override
  String toString() => 'EchecDeLAssistant($echec, $cause)';
}

/// L'appel à l'agent de recherche (§8.1 ; Edge Function « ai-chat »).
///
/// UNE INTERFACE PLUTÔT QU'UNE FONCTION LIBRE, comme `AvisRepository` : les
/// tests la remplacent en bloc, et l'écran 8 se monte alors sans réseau, sans
/// session et sans quota.
abstract interface class AssistantRepository {
  /// Pose une question à l'agent et attend sa réponse.
  ///
  /// Lève [EchecDeLAssistant] et rien d'autre.
  Future<ReponseAssistant> demander(String question);
}

/// Celui qui appelle vraiment l'Edge Function.
class AssistantRepositorySupabase implements AssistantRepository {
  /// Crée le dépôt autour d'un client Supabase.
  const AssistantRepositorySupabase(this._client);

  final SupabaseClient _client;

  /// LE DÉLAI D'ABANDON, ET POURQUOI IL EST SI LONG.
  ///
  /// L'Edge Function s'accorde elle-même 90 secondes pour l'empreinte — le
  /// temps qu'un Space Hugging Face endormi se réveille — et 60 pour le modèle.
  /// Abandonner avant elle transformerait une attente longue mais aboutie en
  /// panne, et l'utilisateur ne saurait jamais que la réponse arrivait.
  ///
  /// Trois minutes, donc : au-delà, ce n'est plus une lenteur, c'est un silence.
  static const Duration _delai = Duration(minutes: 3);

  @override
  Future<ReponseAssistant> demander(String question) async {
    try {
      final reponse = await _client.functions.invoke(
        'ai-chat',
        body: <String, dynamic>{'question': question},
        // Le signal d'abandon du paquet : la requête est vraiment interrompue,
        // et non simplement oubliée. Sur le web, une requête oubliée continue
        // de consommer une connexion.
        abortSignal: Future<void>.delayed(_delai),
      );

      final corps = reponse.data;
      if (corps is! Map) {
        throw const EchecDeLAssistant(EchecAssistant.panne);
      }

      return ReponseAssistant.depuisJson(corps.cast<String, dynamic>());
    } on EchecDeLAssistant {
      rethrow;
    } on Object catch (erreur) {
      throw EchecDeLAssistant(_traduire(erreur), erreur);
    }
  }
}

/// De l'erreur de transport à la phrase que l'écran devra écrire.
///
/// L'ORDRE DES CAS COMPTE. `FunctionsFetchException` hérite de
/// `FunctionException` comme les deux autres : le tester en dernier ferait
/// passer une coupure réseau pour une panne du serveur, et l'on dirait
/// « réessayez » à quelqu'un qui n'a pas de réseau.
EchecAssistant _traduire(Object erreur) {
  return switch (erreur) {
    // Le délai a expiré. La cause la plus fréquente, et de loin, est le service
    // d'empreintes qui se réveille — c'est ce qui prend une minute la première
    // fois. On le dit plutôt que d'écrire « délai dépassé », qui n'apprend rien
    // et ne dit pas quoi faire.
    RequestAbortedException() ||
    TimeoutException() => EchecAssistant.serviceEndormi,

    // Rien n'est parti : ni DNS, ni socket, ni CORS. `status` vaut 0.
    FunctionsFetchException() => EchecAssistant.reseau,

    // La fonction a répondu, mais pas 2xx. Le quota, lui, arrive en 200 avec sa
    // phrase : un 429 ici viendrait de la passerelle, pas du modèle.
    FunctionException(status: final s) when s == 429 => EchecAssistant.quota,

    _ => EchecAssistant.panne,
  };
}

/// Le dépôt de l'assistant.
final assistantRepositoryProvider = Provider<AssistantRepository>(
  (ref) => AssistantRepositorySupabase(ref.watch(supabaseClientProvider)),
);
