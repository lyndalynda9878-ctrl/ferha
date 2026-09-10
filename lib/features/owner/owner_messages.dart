import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_messages.dart';

/// Traduit le refus d'une réponse du propriétaire en une phrase qui dit quoi
/// faire.
///
/// ON LIT LE CODE FERHA, JAMAIS LE MESSAGE — c'est le contrat inauguré par 012
/// et repris ici. `accepter_demande()` et `refuser_demande()` (migration 015)
/// posent un `FExxx` dans le `hint` de leur exception, et un `PTxxx` en
/// SQLSTATE pour que PostgREST réponde 401, 403 ou 409 plutôt que 500. Le
/// message français de la base, lui, est une formulation : il ne sera jamais
/// traduit en arabe, et peut être réécrit demain sans que personne ne pense à
/// cet écran.
///
/// Les quatre codes sont documentés en tête de `015_repondre_a_une_demande.sql`,
/// et `supabase/tests/003_reponse_proprietaire.sql` vérifie que la base les
/// pose bien — c'est ce test qui empêche ce fichier de mentir.
String messageErreurReponse(Object erreur) {
  if (erreur is PostgrestException) {
    final traduit = _parCodeFerha(erreur.hint);
    if (traduit != null) return traduit;
  }

  // Réseau, session expirée, erreur inconnue : la traduction commune sait déjà
  // les dire, et montre le message d'origine quand elle ne sait pas.
  return messageErreurAuth(erreur);
}

/// Les refus de 015, et ce qu'ils veulent dire pour quelqu'un qui vient
/// d'appuyer sur « Accepter » ou « Refuser ».
String? _parCodeFerha(String? hint) {
  switch (hint) {
    // FE010 ne devrait jamais atteindre l'écran : on n'entre dans l'espace
    // propriétaire que connecté. Il reste traduit pour le cas où la session
    // expire pendant que la demande est ouverte.
    case 'FE010':
      return 'Votre session a expiré. Reconnectez-vous, puis répondez à '
          'nouveau.';

    // FE011 ne devrait pas non plus arriver : on n'ouvre que ses propres
    // demandes. S'il arrive, c'est que quelque chose ne va pas — et le dire
    // vaut mieux que de laisser croire à une panne.
    case 'FE011':
      return 'Cette demande ne concerne pas une de vos salles.';

    // FE012 — le cas courant, et il n'est presque jamais une erreur : deux
    // téléphones ouverts sur la même demande, ou le client qui vient
    // d'annuler. La phrase ne gronde donc personne.
    case 'FE012':
      return 'Cette demande a déjà reçu une réponse, ou vient d’être annulée '
          'par le client. Revenez au tableau de bord pour voir où elle en est.';

    // FE013 — la course perdue, celle que le §6.1 protège. Le propriétaire n'y
    // est pour rien : la date a été confirmée pendant que la demande attendait.
    // La phrase le dit au passé récent, avec la suite à faire.
    case 'FE013':
      return 'Ce créneau a été confirmé entre-temps par une autre '
          'réservation. Vous ne pouvez plus accepter celle-ci — vous pouvez '
          'la refuser en expliquant pourquoi.';

    default:
      return null;
  }
}

/// Traduit le refus d'une fermeture ou d'une réouverture de date (§4.3,
/// OWN-06).
///
/// UNE SECONDE FONCTION PLUTÔT QU'UN SEUL GRAND `switch`, et ce n'est pas de la
/// duplication : les deux écrans ne peuvent pas recevoir les mêmes codes.
/// L'agenda ne verra jamais « cette demande a déjà reçu une réponse », et
/// l'écran de réponse ne verra jamais « ce créneau porte une réservation ». Les
/// mettre ensemble obligerait chacun à porter le vocabulaire de l'autre, et la
/// première phrase mal aiguillée passerait inaperçue.
///
/// Les trois codes sont documentés en tête de `016_agenda_proprietaire.sql`, et
/// `supabase/tests/004_agenda_proprietaire.sql` vérifie que la base les pose
/// bien — c'est ce test qui empêche ce fichier de mentir.
String messageErreurAgenda(Object erreur) {
  if (erreur is PostgrestException) {
    final traduit = _parCodeAgenda(erreur.hint);
    if (traduit != null) return traduit;
  }

  return messageErreurAuth(erreur);
}

/// Les refus de 016, et ce qu'ils veulent dire pour quelqu'un qui vient
/// d'appuyer sur « Fermer cette date ».
String? _parCodeAgenda(String? hint) {
  switch (hint) {
    // FE020 ne devrait jamais atteindre l'écran : on n'entre dans l'espace
    // propriétaire que connecté. Il reste traduit pour le cas où la session
    // expire pendant que l'agenda est ouvert.
    case 'FE020':
      return 'Votre session a expiré. Reconnectez-vous, puis fermez la date à '
          'nouveau.';

    case 'FE021':
      return 'Cette salle n’est pas la vôtre.';

    // FE022 — LA RÈGLE QUI PROTÈGE LE CLIENT, et la seule de ces trois qu'un
    // propriétaire rencontrera pour de bon. Il arrive quand une demande a été
    // acceptée ou payée pendant que l'agenda était ouvert : l'écran affichait
    // encore « libre », la base sait déjà que non. La phrase dit ce qui s'est
    // passé et ce qui reste possible — annuler la réservation est un geste, pas
    // un effet de bord d'une fermeture de date.
    case 'FE022':
      return 'Ce créneau vient d’être réservé. Fermer la date n’annulerait pas '
          'la réservation : ouvrez-la d’abord si vous voulez y renoncer.';

    default:
      return null;
  }
}

/// Traduit le refus d'une inscription de salle (§4.3, OWN-01).
///
/// Troisième table de codes de ce fichier, et troisième vocabulaire disjoint :
/// l'écran de publication ne verra jamais « cette demande a déjà reçu une
/// réponse », et l'agenda ne verra jamais « wilaya inconnue ». Voir
/// [messageErreurAgenda] pour la raison de ce découpage.
///
/// LES QUATRE PREMIERS NE DEVRAIENT JAMAIS S'AFFICHER, et c'est le signe que
/// l'écran fait son travail : « Continuer » reste éteint tant qu'un champ
/// obligatoire manque, les wilayas et les équipements viennent de listes que la
/// base a fournies. S'ils arrivent quand même, c'est que l'écran et la base ne
/// disent plus la même chose — et le dire vaut mieux que de laisser croire à
/// une panne de réseau.
///
/// Les six codes sont documentés en tête de `017_publier_une_salle.sql`, et
/// `supabase/tests/005_publier_une_salle.sql` vérifie que la base les pose
/// bien — c'est ce test qui empêche ce fichier de mentir.
String messageErreurPublication(Object erreur) {
  if (erreur is PostgrestException) {
    final traduit = _parCodePublication(erreur.hint);
    if (traduit != null) return traduit;
  }

  return messageErreurAuth(erreur);
}

/// Les refus de 017, et ce qu'ils veulent dire pour quelqu'un qui vient
/// d'appuyer sur « Inscrire ma salle » ou « Envoyer pour validation ».
String? _parCodePublication(String? hint) {
  switch (hint) {
    case 'FE030':
      return 'Votre session a expiré. Reconnectez-vous, puis reprenez — ce que '
          'vous avez rempli est toujours là.';

    case 'FE031':
      return 'Il manque le nom, la wilaya, la commune ou la capacité. '
          'Revenez en arrière pour compléter.';

    case 'FE032':
      return 'Cette wilaya n’existe pas. Choisissez-en une dans la liste.';

    case 'FE033':
      return 'Un équipement ou un type d’événement coché n’existe plus. '
          'Décochez-le et renvoyez.';

    case 'FE034':
      return 'Cette salle n’est pas la vôtre.';

    // FE035 — le cas courant, et il n'est presque jamais une erreur : un double
    // appui, ou un retour en arrière suivi d'un second envoi. La phrase ne
    // gronde donc personne, et elle dit où en est la salle.
    case 'FE035':
      return 'Cette salle a déjà été envoyée. Elle attend maintenant la '
          'validation de l’équipe Ferha.';

    default:
      return null;
  }
}
