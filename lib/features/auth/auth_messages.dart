import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Traduit une erreur d'authentification en une phrase qui dit quoi faire.
///
/// « AuthApiException(message: Invalid login credentials, statusCode: 400) »
/// n'apprend rien à personne. Le code d'erreur de GoTrue, lui, est stable et
/// documenté : c'est sur lui qu'on s'appuie, et non sur le texte anglais du
/// serveur, qui change d'une version à l'autre.
///
/// Le repli n'invente rien : quand le code est inconnu, on le dit et on montre
/// le message d'origine. Une erreur qu'on n'a pas prévue doit rester lisible
/// pour celui qui devra la corriger — un « Une erreur est survenue » ferait
/// perdre le temps qu'il prétend faire gagner.
String messageErreurAuth(Object erreur) {
  // Réseau injoignable, DNS en échec, requête interrompue : GoTrue enveloppe
  // tout cela dans une seule exception. Pas de dart:io ici — l'application
  // tourne aussi sur le web, où SocketException n'existe pas.
  if (erreur is AuthRetryableFetchException) {
    return 'Impossible de joindre le serveur. Vérifiez votre connexion, '
        'puis réessayez.';
  }

  if (erreur is AuthWeakPasswordException) {
    return 'Mot de passe trop faible : il faut au moins six caractères.';
  }

  if (erreur is AuthException) {
    final traduit = _parCode(erreur.code) ?? _parMessage(erreur.message);
    if (traduit != null) return traduit;

    // Code inconnu : on le nomme, et on montre le message d'origine.
    return 'Connexion impossible (${erreur.code ?? erreur.statusCode ?? 'erreur'}) : '
        '${erreur.message}';
  }

  if (erreur is TimeoutException) {
    return 'Le serveur met trop de temps à répondre. Réessayez.';
  }

  if (erreur is PostgrestException) {
    return 'La base a refusé la requête : ${erreur.message}';
  }

  return _parMessage(erreur.toString()) ??
      'Une erreur inattendue est survenue : $erreur';
}

/// Les codes que GoTrue renvoie sur les gestes de ces écrans.
///
/// La liste complète vit dans l'énumération `ErrorCode` du paquet gotrue ;
/// seuls les cas qu'un client peut réellement provoquer sont traduits ici.
String? _parCode(String? code) {
  switch (code) {
    case 'invalid_credentials':
      return 'E-mail ou mot de passe incorrect.';
    case 'email_not_confirmed':
      return 'Cette adresse n’a pas encore été confirmée. '
          'Ouvrez le message reçu par e-mail.';
    case 'user_not_found':
      return 'Aucun compte ne correspond à cette adresse.';
    case 'email_exists':
    case 'user_already_exists':
      return 'Un compte existe déjà avec cette adresse. Connectez-vous.';
    case 'weak_password':
      return 'Mot de passe trop faible : il faut au moins six caractères.';
    case 'same_password':
      return 'Le nouveau mot de passe est identique à l’ancien.';
    case 'validation_failed':
      return 'Adresse e-mail invalide.';
    case 'over_request_rate_limit':
    case 'over_email_send_rate_limit':
      return 'Trop de tentatives. Patientez une minute avant de réessayer.';
    case 'user_banned':
      return 'Ce compte est suspendu. Contactez-nous.';
    case 'signup_disabled':
      return 'Les inscriptions sont fermées pour le moment.';
    case 'email_provider_disabled':
      return 'La connexion par e-mail est désactivée sur ce projet Supabase.';
    case 'session_expired':
    case 'session_not_found':
    case 'session_missing':
      return 'Votre session a expiré. Reconnectez-vous.';
    case 'captcha_failed':
      return 'La vérification anti-robot a échoué. Réessayez.';
    default:
      return null;
  }
}

/// Repli sur le texte anglais, pour les versions de GoTrue qui ne renvoient
/// pas encore de code sur certaines réponses.
String? _parMessage(String message) {
  final m = message.toLowerCase();
  if (m.contains('invalid login credentials')) {
    return 'E-mail ou mot de passe incorrect.';
  }
  if (m.contains('email not confirmed')) {
    return 'Cette adresse n’a pas encore été confirmée. '
        'Ouvrez le message reçu par e-mail.';
  }
  if (m.contains('already registered') || m.contains('already exists')) {
    return 'Un compte existe déjà avec cette adresse. Connectez-vous.';
  }
  if (m.contains('password should be at least')) {
    return 'Mot de passe trop court : il faut au moins six caractères.';
  }
  if (m.contains('unable to validate email') ||
      m.contains('invalid email') ||
      m.contains('invalid format')) {
    return 'Adresse e-mail invalide.';
  }
  if (m.contains('failed host lookup') ||
      m.contains('connection refused') ||
      m.contains('clientexception') ||
      m.contains('xmlhttprequest') ||
      m.contains('network')) {
    return 'Impossible de joindre le serveur. Vérifiez votre connexion, '
        'puis réessayez.';
  }
  return null;
}
