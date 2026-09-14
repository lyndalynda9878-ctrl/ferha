import 'dart:async';

import 'package:ferha/features/assistant/assistant_repository.dart';
import 'package:ferha/features/assistant/message_assistant.dart';

/// Les doublures de l'assistant, partagées par ses tests.
///
/// Ce fichier ne se termine pas par `_test.dart` : `flutter test` ne le lance
/// pas, il l'importe — comme `avis_fakes.dart` et `owner_fakes.dart`.

/// Un dépôt d'assistant qui rend ce qu'on lui a donné, sans réseau ni quota.
///
/// IL SAIT AUSSI NE PAS RÉPONDRE TOUT DE SUITE. `[bloquer]` laisse la réponse en
/// suspens jusqu'à ce que le test appelle [repondre] : c'est ce qui permet de
/// regarder l'écran PENDANT l'attente, et non seulement après. Un dépôt qui
/// répondrait toujours immédiatement rendrait « l'envoi est bloqué pendant
/// l'attente » intestable — il n'y aurait jamais d'attente à observer.
class DepotAssistantDeTest implements AssistantRepository {
  /// Crée le dépôt.
  DepotAssistantDeTest({this.reponse, this.erreur, this.bloquer = false});

  /// Ce que rend l'Edge Function.
  ReponseAssistant? reponse;

  /// Ce qu'elle lève à la place.
  EchecDeLAssistant? erreur;

  /// Quand c'est vrai, la réponse attend [repondre].
  bool bloquer;

  /// Les questions reçues, dans l'ordre. C'est ce que regardent les tests qui
  /// vérifient qu'une seconde question N'EST PAS partie.
  final List<String> questions = <String>[];

  Completer<void>? _attente;

  @override
  Future<ReponseAssistant> demander(String question) async {
    questions.add(question);

    if (bloquer) {
      _attente = Completer<void>();
      await _attente!.future;
    }

    if (erreur != null) throw erreur!;
    return reponse ?? const ReponseAssistant(texte: '', statut: 'ok');
  }

  /// Débloque la réponse en attente.
  void repondre() {
    _attente?.complete();
    _attente = null;
  }
}

/// Une salle citée, tout en valeurs par défaut sauf ce qu'on précise.
SalleCitee salleCiteeDeTest({
  required String venueId,
  String nom = 'Nour El Bahdja',
  String commune = 'Bir El Djir',
  String? wilaya = 'Oran',
  String? photo,
  int? capacite = 400,
  int? prix = 180000,
  double? note = 4.6,
}) => SalleCitee(
  venueId: venueId,
  nom: nom,
  commune: commune,
  wilaya: wilaya,
  photo: photo,
  capacite: capacite,
  prix: prix,
  note: note,
);

/// Une réponse de l'agent.
ReponseAssistant reponseDeTest({
  String texte = 'Voici 3 salles libres ce soir-là :',
  String statut = 'ok',
  List<SalleCitee> salles = const <SalleCitee>[],
  List<String> suggestions = const <String>[],
}) => ReponseAssistant(
  texte: texte,
  statut: statut,
  salles: salles,
  suggestions: suggestions,
);
