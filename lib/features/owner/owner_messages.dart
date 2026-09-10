import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_messages.dart';
import 'compression_photo.dart';

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
/// une panne de réseau. FE036 et FE037 sont dans le même cas : l'adresse et le
/// téléphone éteignent chacun leur bouton avant qu'on appuie.
///
/// Les six premiers codes sont documentés en tête de
/// `017_publier_une_salle.sql`, FE036 en tête de `019_adresse_de_la_salle.sql`,
/// FE037 en tête de `020_telephone_joignable.sql` et FE041 en tête de
/// `021_photos_de_la_salle.sql`. `supabase/tests/005_publier_une_salle.sql`,
/// `007_adresse_et_telephone.sql` et `008_photos_de_la_salle.sql` vérifient que
/// la base les pose bien — ce sont ces tests qui empêchent ce fichier de mentir.
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

    // FE036 — l'adresse (019). La phrase dit OÙ la remplir : le refus arrive
    // au bout de l'étape 4, et l'adresse est à l'étape 2.
    case 'FE036':
      return 'L’adresse de votre salle est obligatoire. Revenez à l’étape '
          '« Où est-elle ? » pour l’ajouter.';

    // FE037 — le téléphone (020). On redonne la forme attendue plutôt que de
    // dire « invalide » : c'est un chiffre oublié dans neuf cas sur dix.
    case 'FE037':
      return 'Un numéro de téléphone valide est nécessaire : 0770 11 22 33 '
          'pour un mobile, 041 23 45 67 pour un fixe.';

    // FE041 — les photos (021). Il arrive sur le récapitulatif, pas sur l'écran
    // des photos : c'est « Envoyer pour validation » qui le déclenche, et la
    // phrase dit donc où retourner.
    case 'FE041':
      return 'Il faut au moins 5 photos pour envoyer votre salle. Revenez à '
          'l’étape des photos pour en ajouter.';

    default:
      return null;
  }
}

/// Traduit le refus d'un geste sur les photos (§4.3, OWN-02 ; §7.3).
///
/// QUATRIÈME TABLE DE CODES DE CE FICHIER, et quatrième vocabulaire disjoint —
/// voir [messageErreurAgenda] pour la raison de ce découpage. Elle a en plus
/// quelque chose qu'aucune des trois autres n'a : deux sources d'échec qui ne
/// sont PAS des `PostgrestException`.
///
///   * [EchecDeCompression] — l'encodeur du navigateur n'a rien rendu
///     d'acceptable. Cela n'a jamais touché la base : rien n'est parti.
///   * [StorageException] — le bucket a refusé le fichier lui-même. Ses deux
///     refus attendus sont ceux que 021 pose sur le bucket : le poids et le
///     type. Ils ne devraient pas arriver après une compression réussie ; s'ils
///     arrivent, c'est que la compression n'a pas fait son travail, et le dire
///     vaut mieux que « une erreur est survenue ».
///
/// Les cinq codes FE sont documentés en tête de `021_photos_de_la_salle.sql`, et
/// `supabase/tests/008_photos_de_la_salle.sql` vérifie que la base les pose
/// bien — c'est ce test qui empêche ce fichier de mentir.
String messageErreurPhotos(Object erreur) {
  if (erreur is EchecDeCompression) return erreur.message;

  if (erreur is StorageException) {
    final traduit = _parRefusDuBucket(erreur);
    if (traduit != null) return traduit;
  }

  if (erreur is PostgrestException) {
    final traduit = _parCodePhotos(erreur.hint);
    if (traduit != null) return traduit;
  }

  return messageErreurAuth(erreur);
}

/// Les refus du bucket lui-même (021), et non ceux du SQL.
String? _parRefusDuBucket(StorageException erreur) {
  // 413 : le fichier dépasse `file_size_limit`. Après une compression à 1600 px
  // c'est presque impossible — donc si cela arrive, la photo est passée à côté
  // de la compression, et la refaire est la bonne suite.
  if (erreur.statusCode == '413') {
    return 'Cette photo est trop lourde même après compression. Essayez-en '
        'une autre.';
  }

  // Le type refusé : `allowed_mime_types` ne connaît que WebP et JPEG. C'est le
  // filet sous le reniflement de `compression_photo.dart` ; l'atteindre veut
  // dire que le navigateur a produit un format qu'on n'avait pas prévu.
  final message = erreur.message.toLowerCase();
  if (message.contains('mime type')) {
    return 'Le format de cette photo n’est pas accepté. Essayez une autre '
        'photo, ou un autre navigateur.';
  }

  return null;
}

/// Les refus de 021, et ce qu'ils veulent dire pour quelqu'un qui vient
/// d'ajouter, de déplacer ou de supprimer une photo.
String? _parCodePhotos(String? hint) {
  switch (hint) {
    // FE030 ne devrait jamais atteindre l'écran : on n'y entre que connecté. Il
    // reste traduit pour le cas où la session expire pendant un envoi — ce qui
    // est justement le moment où l'écran reste ouvert longtemps.
    case 'FE030':
      return 'Votre session a expiré. Reconnectez-vous, puis renvoyez cette '
          'photo.';

    case 'FE034':
      return 'Cette salle n’est pas la vôtre.';

    // FE038 — la borne haute d'OWN-02. Elle n'est presque jamais une surprise :
    // l'écran cesse de proposer « Ajouter » à vingt photos. Elle arrive quand
    // deux appareils ajoutent en même temps.
    case 'FE038':
      return 'Votre salle a déjà 20 photos, le maximum. Supprimez-en une pour '
          'en ajouter une autre.';

    // FE039 — la photo a disparu entre-temps, supprimée depuis un autre
    // appareil. Ce n'est pas une faute : la phrase le dit et propose la suite.
    case 'FE039':
      return 'Cette photo n’existe plus. Tirez la liste vers le bas pour la '
          'remettre à jour.';

    // FE040 — l'ordre envoyé ne correspond plus. Même cause que FE039, vue de
    // l'autre bout : quelqu'un a ajouté ou retiré une photo pendant qu'on
    // réordonnait. On ne gronde personne, on dit quoi faire.
    case 'FE040':
      return 'Vos photos ont changé depuis un autre appareil. Tirez la liste '
          'vers le bas, puis reprenez le classement.';

    // FE042 ne devrait jamais s'afficher : le chemin est fabriqué par
    // l'application, à partir de l'identifiant de la salle qu'elle affiche.
    // S'il arrive, c'est un défaut de programme, et le taire ferait chercher
    // une panne de réseau.
    case 'FE042':
      return 'Cette photo a été envoyée au mauvais endroit. Réessayez ; si cela '
          'se reproduit, signalez-le.';

    default:
      return null;
  }
}
