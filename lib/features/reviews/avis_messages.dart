import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_messages.dart';

/// Un refus du parcours des avis : ce qu'on en dit, et s'il sert de rappuyer.
///
/// [definitif] éteint le bouton. « Le propriétaire a répondu, votre avis est
/// figé » ne se répare pas en réessayant — rien de ce que le client peut faire
/// ne le déverrouillera. Un réseau tombé, lui, se répare tout seul au second
/// essai. C'est la même distinction que pour l'acompte (024), et pour la même
/// raison : un bouton qui reste allumé sous un refus définitif invite à
/// rappuyer, et chaque appui redonne la même phrase.
typedef RefusAvis = ({String message, bool definitif});

/// Traduit un refus du dépôt d'un avis en une phrase qui dit quoi faire.
///
/// ON LIT LE CODE FERHA, JAMAIS LE MESSAGE — le contrat inauguré par 012. Le
/// message français de la base est une formulation : il ne sera jamais traduit
/// en arabe, et peut être réécrit demain sans que personne ne pense à cet écran.
///
/// Les codes FE074 à FE079 sont documentés en tête de `026_les_avis.sql`, et
/// `supabase/tests/015_les_avis.sql` vérifie que la base les pose bien — c'est
/// ce test qui empêche ce fichier de mentir.
RefusAvis refusAvis(Object erreur) {
  if (erreur is PostgrestException) {
    final traduit = _parCodeDepot(erreur.hint);
    if (traduit != null) return traduit;
  }

  // Réseau, session expirée, erreur inconnue : la traduction commune sait déjà
  // les dire. Rien de définitif là-dedans.
  return (message: messageErreurAuthEnFrancais(erreur), definitif: false);
}

/// La phrase seule, pour les endroits qui n'ont aucun bouton à éteindre.
String messageErreurAvis(Object erreur) => refusAvis(erreur).message;

/// Les refus de `deposer_avis()` et d'`avis_a_deposer()` (026).
RefusAvis? _parCodeDepot(String? hint) {
  switch (hint) {
    // FE074 ne devrait pas atteindre l'écran : on n'y entre que depuis « Mes
    // réservations » ou une notification, donc connecté. Il reste traduit pour
    // la session qui expire pendant qu'on écrit — et c'est justement un écran
    // où l'on reste longtemps.
    case 'FE074':
      return (
        message:
            'Votre session a expiré. Reconnectez-vous, puis publiez à '
            'nouveau — ce que vous avez écrit est toujours là.',
        definitif: false,
      );

    case 'FE075':
      return (
        message: 'Cette réservation n’est pas la vôtre.',
        definitif: true,
      );

    // FE076 — le propriétaire n'a pas encore marqué la soirée comme honorée.
    // Ce n'est pas une faute du client, et la phrase ne le renvoie pas à un
    // geste qu'il ne peut pas faire : elle dit qui doit agir.
    case 'FE076':
      return (
        message:
            'Le propriétaire n’a pas encore confirmé que la soirée a eu lieu. '
            'Vous pourrez déposer votre avis dès qu’il l’aura fait.',
        definitif: true,
      );

    // FE077 — hors de la fenêtre du §5.4. Elle couvre les deux bords, et
    // l'écran a de quoi dire lequel : il connaît les deux dates. Cette phrase-ci
    // est le repli, quand le refus arrive sans que l'écran ait pu s'ouvrir.
    case 'FE077':
      return (
        message:
            'Les avis s’écrivent entre le lendemain de l’événement et trente '
            'jours après. Cette période n’est pas ouverte.',
        definitif: true,
      );

    // FE078 — L'AVIS EST FIGÉ (§5.4). La phrase dit POURQUOI, parce que la
    // raison est la seule chose qui rende la règle acceptable : une réponse
    // publique sous un avis qu'on réécrirait ensuite ne voudrait plus rien dire.
    case 'FE078':
      return (
        message:
            'Le propriétaire a répondu à votre avis : il n’est plus '
            'modifiable. Une réponse sous un avis réécrit ne voudrait plus '
            'rien dire.',
        definitif: true,
      );

    // FE079 ne devrait pas s'afficher : « Publier » reste éteint tant qu'aucune
    // étoile n'est allumée. S'il arrive, c'est que l'écran et la base ne disent
    // plus la même chose — et le dire vaut mieux que de laisser croire à une
    // panne de réseau.
    case 'FE079':
      return (
        message: 'Donnez d’abord une note globale, de 1 à 5 étoiles.',
        definitif: false,
      );

    default:
      return null;
  }
}

/// Traduit le refus d'une réponse à un avis (§4.3, OWN-06).
///
/// UNE SECONDE FONCTION PLUTÔT QU'UN SEUL GRAND `switch`, comme dans
/// `owner_messages.dart` : les deux écrans ne peuvent pas recevoir les mêmes
/// codes. Le client ne verra jamais « cet avis ne porte pas sur une de vos
/// salles », et le propriétaire ne verra jamais « votre avis est figé ». Les
/// mettre ensemble obligerait chacun à porter le vocabulaire de l'autre.
///
/// Les codes FE080 à FE083 sont documentés en tête de `026_les_avis.sql`, et
/// `supabase/tests/015_les_avis.sql` les vérifie.
String messageErreurReponseAvis(Object erreur) {
  if (erreur is PostgrestException) {
    switch (erreur.hint) {
      case 'FE080':
        return 'Votre session a expiré. Reconnectez-vous, puis répondez à '
            'nouveau.';

      case 'FE081':
        return 'Cet avis ne porte pas sur une de vos salles.';

      // FE082 — le cas courant, et presque jamais une erreur : deux téléphones
      // ouverts sur le même avis, ou un double appui. La phrase ne gronde donc
      // personne, et elle rappelle la règle.
      case 'FE082':
        // On ne cite pas le cahier des charges à un propriétaire : la règle se
        // dit en français, la référence reste dans le code.
        return 'Vous avez déjà répondu à cet avis. Une seule réponse est '
            'possible — tirez la liste vers le bas pour voir la vôtre.';

      case 'FE083':
        return 'Une réponse vide ne se publie pas.';
    }
  }

  return messageErreurAuthEnFrancais(erreur);
}

/// Traduit le refus de « Marquer comme honorée » (§3, étape 6).
///
/// TROISIÈME VOCABULAIRE DISJOINT DE CE PARCOURS, et il vit ici plutôt que dans
/// `owner_messages.dart` pour une raison simple : ces quatre refus n'existent
/// que parce que les avis existent. `complete_booking()` (026) est le premier
/// des deux bouts que l'étape des avis recolle — sans elle, aucune réservation
/// n'atteint jamais « honorée », et aucun avis n'est possible.
///
/// Les codes FE070 à FE073 sont documentés en tête de `026_les_avis.sql`.
String messageErreurHonorer(Object erreur) {
  if (erreur is PostgrestException) {
    switch (erreur.hint) {
      case 'FE070':
        return 'Votre session a expiré. Reconnectez-vous, la réservation vous '
            'attend.';

      case 'FE071':
        return 'Cette réservation ne concerne pas vos salles.';

      // FE072 — le double appui, le plus souvent : l'événement vient d'être
      // marqué honoré et l'écran n'a pas fini de se rafraîchir. Ou bien la
      // réservation a été annulée entre-temps. La phrase ne gronde personne.
      case 'FE072':
        return 'Cette réservation n’est plus confirmée. Elle a peut-être déjà '
            'été marquée comme honorée, ou annulée entre-temps.';

      // FE073 — le seul refus qu'un propriétaire rencontrera pour de bon. La
      // phrase dit quand revenir, plutôt que « impossible ».
      case 'FE073':
        return 'L’événement n’a pas encore eu lieu. Vous pourrez le marquer '
            'comme honoré à partir du jour J.';
    }
  }

  return messageErreurAuthEnFrancais(erreur);
}
