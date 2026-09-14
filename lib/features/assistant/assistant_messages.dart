import 'message_assistant.dart';

/// Les phrases des trois échecs — en toutes lettres, jamais une trace.
///
/// LE MÊME PRINCIPE QUE `acompte_messages.dart` ET `avis_messages.dart` : un
/// message d'erreur qui n'indique pas le geste suivant fait perdre le temps
/// qu'il prétend faire gagner. Chacune de ces phrases dit trois choses — ce qui
/// s'est passé, que ce n'est pas la faute de la personne, et ce qu'elle peut
/// faire maintenant.
///
/// AUCUNE NE PROPOSE « RÉESSAYEZ » TOUT COURT. Réessayer sans rien changer sur
/// un quota épuisé ne fait que rallonger l'attente ; on renvoie donc vers la
/// recherche classique, qui elle ne dépend d'aucun modèle.
String messageEchecAssistant(EchecAssistant echec) => switch (echec) {
  // Le quota gratuit du modèle. « Très sollicité » et non « épuisé » : la
  // personne n'a pas à porter le budget d'API du projet, et la conséquence pour
  // elle est la même — attendre, ou chercher autrement.
  EchecAssistant.quota =>
    'L’assistant est très sollicité en ce moment. Réessayez dans une minute, '
        'ou passez par la recherche depuis l’accueil — elle trouve les mêmes '
        'salles, avec des filtres.',

  // LA PLUS IMPORTANTE DES TROIS, parce que c'est la seule qui se produit
  // quand tout va bien. Le service d'empreintes s'endort faute d'usage ; la
  // première question de la journée le réveille, et cela prend jusqu'à une
  // minute. Le dire à l'avance transforme une panne apparente en attente
  // annoncée.
  EchecAssistant.serviceEndormi =>
    'L’assistant met plus longtemps que prévu. La première question de la '
        'journée réveille le service de recherche et peut demander jusqu’à une '
        'minute — reposez la vôtre, elle devrait aboutir.',

  EchecAssistant.reseau =>
    'Pas de connexion. Votre question n’est pas partie : elle vous attend, '
        'rien n’est perdu.',

  EchecAssistant.panne =>
    'L’assistant n’a pas pu répondre. Réessayez dans un moment, ou passez par '
        'la recherche depuis l’accueil.',
};

/// Ce qui s'affiche pendant que l'assistant cherche.
///
/// DEUX PHRASES, ET LA SECONDE ARRIVE AVEC LE TEMPS. Tant que l'attente est
/// courte, « L'assistant cherche… » suffit ; passé quelques secondes, le silence
/// devient inquiétant et il faut dire POURQUOI c'est long. C'est la même
/// information que [messageEchecAssistant] donne pour le service endormi, mais
/// donnée AVANT l'échec — c'est-à-dire au moment où elle sert encore.
const String assistantCherche = 'L’assistant cherche…';

/// La seconde phrase d'attente, au bout de [delaiAvantExplication].
const String assistantChercheLongtemps =
    'La première question de la journée réveille le service de recherche. '
    'Cela peut prendre jusqu’à une minute.';

/// Au bout de combien de temps on explique la lenteur.
///
/// Huit secondes : assez pour qu'une réponse normale soit déjà arrivée — elles
/// mettent deux à quatre secondes —, assez peu pour qu'on n'ait pas encore eu le
/// temps de croire à une panne.
const Duration delaiAvantExplication = Duration(seconds: 8);
