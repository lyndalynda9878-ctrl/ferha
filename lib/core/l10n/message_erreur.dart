/// Ce qu'on dit d'une erreur, dans la langue de l'application.
///
/// =============================================================================
/// POURQUOI UN SECOND TRADUCTEUR, À CÔTÉ DE `messageErreurAuth`
///
/// `auth_messages.dart` traduit les refus de GoTrue — mot de passe faible,
/// adresse déjà prise, compte suspendu. Ce sont les erreurs des écrans de
/// CONNEXION, et ces écrans-là restent en français au J22.
///
/// Les six écrans du parcours client ne peuvent rencontrer qu'une poignée
/// d'erreurs, et ce ne sont pas celles-là : un réseau qui tombe, un serveur qui
/// met trop de temps, une session qui expire, un refus de la base. Ce fichier
/// traduit CELLES-LÀ, et rien d'autre.
///
/// LES DEUX DIRONT LA MÊME CHOSE EN FRANÇAIS, et c'est voulu : les phrases
/// d'ici reprennent mot pour mot celles de `auth_messages.dart` pour les cas
/// qu'ils partagent. Le jour où les écrans de connexion seront traduits, c'est
/// `auth_messages.dart` qui viendra ici, pas l'inverse — et il n'y aura rien à
/// réécrire.
///
/// LE REPLI N'INVENTE RIEN. Quand on ne sait pas, on le dit et on montre le
/// message d'origine : une erreur imprévue doit rester lisible pour celui qui
/// devra la corriger. « Une erreur est survenue » fait perdre le temps qu'il
/// prétend faire gagner.
library;

import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'generated/app_localizations.dart';

/// Les codes de session de GoTrue — ceux qu'un parcours client peut voir.
const Set<String> _codesDeSession = <String>{
  'session_expired',
  'session_not_found',
  'session_missing',
};

/// Traduit [erreur] en une phrase qui dit quoi faire.
String messageErreur(AppLocalizations textes, Object erreur) {
  // Réseau injoignable, DNS en échec, requête interrompue : GoTrue enveloppe
  // tout cela dans une seule exception. Pas de dart:io ici — l'application
  // tourne aussi sur le web, où SocketException n'existe pas.
  if (erreur is AuthRetryableFetchException) return textes.erreurReseau;

  if (erreur is TimeoutException) return textes.erreurDelaiDepasse;

  if (erreur is AuthException) {
    if (_codesDeSession.contains(erreur.code)) {
      return textes.erreurSessionExpiree;
    }
    return textes.erreurBaseRefuse(erreur.message);
  }

  if (erreur is PostgrestException) {
    return textes.erreurBaseRefuse(erreur.message);
  }

  // Le repli sur le texte anglais, pour ce qui n'arrive ni typé ni codé : une
  // `ClientException` du navigateur, par exemple, n'est rien d'autre qu'une
  // chaîne.
  final message = erreur.toString().toLowerCase();
  if (message.contains('failed host lookup') ||
      message.contains('connection refused') ||
      message.contains('clientexception') ||
      message.contains('xmlhttprequest') ||
      message.contains('network')) {
    return textes.erreurReseau;
  }

  return textes.erreurInattendue('$erreur');
}
