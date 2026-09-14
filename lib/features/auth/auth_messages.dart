/// Ce qu'on dit d'un refus de GoTrue, dans la langue de l'application.
///
/// =============================================================================
/// IL A REJOINT `message_erreur.dart`, ET NON L'INVERSE
///
/// C'est ce que le J22 avait annoncé : ce fichier traduisait les refus des
/// écrans de connexion, qui étaient alors les seuls à ne pas parler arabe, et
/// `core/l10n/message_erreur.dart` traduisait pour les six autres. Les deux
/// disaient les mêmes phrases pour les cas qu'ils partagent — réseau, délai,
/// session, refus de la base.
///
/// Ils ne les disent plus deux fois : CE FICHIER NE TRAITE QUE CE QUI EST
/// PROPRE À GOTRUE — mot de passe faible, adresse déjà prise, compte
/// suspendu — et passe tout le reste au traducteur commun. Les clés partagées
/// sont les mêmes des deux côtés : `erreurReseau`, `erreurDelaiDepasse`,
/// `erreurSessionExpiree`, `erreurBaseRefuse`, `erreurInattendue`.
///
/// =============================================================================
/// ON LIT LE CODE, JAMAIS LE TEXTE ANGLAIS DU SERVEUR
///
/// « AuthApiException(message: Invalid login credentials, statusCode: 400) »
/// n'apprend rien à personne. Le code d'erreur de GoTrue, lui, est stable et
/// documenté.
///
/// UN REPLI SUR LE MESSAGE ANGLAIS VIVAIT ICI, pour les versions de GoTrue qui
/// ne renvoyaient pas encore de code sur certaines réponses. Il est parti le
/// jour où ces écrans sont passés à l'arabe, pour une raison qui n'existait pas
/// tant qu'ils étaient français : reconnaître une phrase anglaise pour en
/// choisir une française marchait ; le faire pour en choisir une arabe revient
/// à traduire une traduction. Le code est un contrat, le message est une formulation — et une
/// formulation peut changer d'une version à l'autre sans prévenir.
///
/// Quand le code est inconnu, on le NOMME et on montre le message d'origine.
/// Il est en anglais, et c'est mieux qu'un « une erreur est survenue » qui
/// ferait perdre le temps qu'il prétend faire gagner.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../core/l10n/generated/app_localizations_fr.dart';
import '../../core/l10n/message_erreur.dart';

/// Traduit une erreur d'authentification en une phrase qui dit quoi faire.
String messageErreurAuth(AppLocalizations textes, Object erreur) {
  // `AuthWeakPasswordException` porte son propre type ET le code
  // `weak_password` selon les versions : on la nomme ici pour ne pas dépendre
  // de laquelle on a en face.
  if (erreur is AuthWeakPasswordException) {
    return textes.authMotDePasseTropFaible;
  }

  // `AuthRetryableFetchException` EST UNE `AuthException`, et elle n'a pas de
  // code : c'est un réseau tombé, pas un refus. On la laisse au traducteur
  // commun, qui la connaît déjà — sans cette exclusion, elle tomberait dans le
  // repli ci-dessous et parlerait de « connexion impossible » à quelqu'un dont
  // c'est le Wi-Fi qui est coupé.
  if (erreur is AuthException && erreur is! AuthRetryableFetchException) {
    final traduit = _parCode(textes, erreur.code);
    if (traduit != null) return traduit;

    return textes.authRefusNonTraduit(
      erreur.code ?? '${erreur.statusCode}',
      erreur.message,
    );
  }

  // Réseau, délai dépassé, refus de la base, erreur inconnue : le traducteur
  // commun sait déjà les dire, et il les dit dans les mêmes mots que sur les
  // sept écrans du parcours client.
  return messageErreur(textes, erreur);
}

/// La même phrase, en français, pour les écrans qui ne sont pas traduits.
///
/// LES ÉCRANS DU PROPRIÉTAIRE ET LES AVIS S'EN SERVENT comme repli, au bout de
/// leurs propres traducteurs. Ils restent en français, et ce n'est pas une
/// raison pour que leurs phrases vivent ailleurs que dans les fichiers ARB :
/// celle-ci lit le MODÈLE français, la même source que la version traduite.
///
/// Le jour où ces écrans passeront à l'arabe, cette fonction disparaîtra et
/// leurs traducteurs prendront les textes en paramètre, comme ici.
String messageErreurAuthEnFrancais(Object erreur) =>
    messageErreurAuth(AppLocalizationsFr(), erreur);

/// Les codes que GoTrue renvoie sur les gestes de ces écrans.
///
/// La liste complète vit dans l'énumération `ErrorCode` du paquet gotrue ;
/// seuls les cas qu'un client peut réellement provoquer sont traduits ici.
String? _parCode(AppLocalizations textes, String? code) {
  switch (code) {
    case 'invalid_credentials':
      return textes.authIdentifiantsInvalides;
    case 'email_not_confirmed':
      return textes.authAdresseNonConfirmee;
    case 'user_not_found':
      return textes.authCompteIntrouvable;
    case 'email_exists':
    case 'user_already_exists':
      return textes.authCompteExisteDeja;
    case 'weak_password':
      return textes.authMotDePasseTropFaible;
    case 'same_password':
      return textes.authMemeMotDePasse;
    case 'validation_failed':
      return textes.authAdresseInvalide;
    case 'over_request_rate_limit':
    case 'over_email_send_rate_limit':
      return textes.authTropDeTentatives;
    case 'user_banned':
      return textes.authCompteSuspendu;
    case 'signup_disabled':
      return textes.authInscriptionsFermees;
    case 'email_provider_disabled':
      return textes.authEmailDesactive;
    // LA MÊME CLÉ QUE LES SEPT AUTRES ÉCRANS : une session expirée se dit
    // pareil, qu'on la découvre en se connectant ou en envoyant une demande.
    case 'session_expired':
    case 'session_not_found':
    case 'session_missing':
      return textes.erreurSessionExpiree;
    case 'captcha_failed':
      return textes.authCaptchaEchoue;
    default:
      return null;
  }
}
