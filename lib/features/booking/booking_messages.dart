import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_messages.dart';

/// Traduit le refus d'une demande de réservation en une phrase qui dit quoi
/// faire.
///
/// ON LIT LE CODE FERHA, JAMAIS LE MESSAGE. `request_booking()` (migration 012)
/// pose sur chacun de ses refus un code à lui — `FE001` à `FE006` — dans le
/// `hint` de l'exception. C'est un contrat, là où un message est une
/// formulation : celle de la base est en français, ne sera jamais traduite en
/// arabe, et peut être reprise demain sans que personne ne pense à cet écran.
///
/// POURQUOI LE `hint` ET NON LE `code`. Chez PostgREST, le SQLSTATE ne sert pas
/// à identifier l'erreur : il choisit le code HTTP de la réponse. Un code
/// inventé n'appartient à aucune classe connue, et la passerelle répond alors
/// 500 — or « ce créneau vient d'être pris » n'est pas une panne de serveur.
/// `request_booking()` met donc un `PTxxx` dans son SQLSTATE, qui devient un
/// 409, un 403 ou un 401 honnête, et son code Ferha dans le `hint`, que
/// PostgREST recopie tel quel.
///
/// Les six codes sont documentés en tête de `012_booking_request.sql`. Le
/// premier est le seul que la maquette exige explicitement : « Ce créneau
/// vient d'être réservé », pas un code.
String messageErreurDemande(Object erreur) {
  if (erreur is PostgrestException) {
    final traduit = _parCodeFerha(erreur.hint) ?? _parSqlstate(erreur.code);
    if (traduit != null) return traduit;
  }

  // Réseau, session expirée, erreur inconnue : la traduction commune sait déjà
  // les dire, et montre le message d'origine quand elle ne sait pas.
  return messageErreurAuth(erreur);
}

/// Les refus de `request_booking()`, et ce qu'ils veulent dire pour quelqu'un
/// qui vient d'appuyer sur « Envoyer la demande ».
String? _parCodeFerha(String? hint) {
  switch (hint) {
    // FE001 — la course perdue. Le calendrier disait « libre » quand le client
    // l'a ouvert ; quelqu'un a confirmé entre-temps. Ce n'est pas sa faute, et
    // la phrase doit le dire ainsi : au passé récent, avec la suite à faire.
    case 'FE001':
      return 'Ce créneau vient d’être réservé. Revenez au calendrier pour '
          'choisir une autre date.';

    case 'FE002':
      return 'Le propriétaire a bloqué ce créneau. Choisissez une autre date '
          'au calendrier.';

    case 'FE003':
      return 'Cette date est passée. Choisissez une date à venir.';

    case 'FE004':
      return 'Cette salle n’accepte plus de réservation pour le moment.';

    case 'FE005':
      return 'Vous ne pouvez pas réserver votre propre salle.';

    // FE006 ne devrait jamais atteindre l'écran : la connexion est demandée
    // avant l'envoi. Il reste traduit pour le cas où la session expire entre
    // les deux.
    case 'FE006':
      return 'Votre session a expiré. Reconnectez-vous, votre demande est '
          'conservée.';

    default:
      return null;
  }
}

/// Les erreurs qui n'ont pas de code Ferha parce qu'elles ne viennent pas de
/// `request_booking()`, mais des garde-fous posés sous elle.
String? _parSqlstate(String? code) {
  switch (code) {
    // Levé par le trigger bookings_set_price quand une option ne vient pas de
    // cette salle — une option retirée du catalogue pendant que l'écran était
    // ouvert, par exemple.
    case '23503':
      return 'Une des options choisies n’est plus proposée par cette salle. '
          'Décochez-la et renvoyez la demande.';

    // Levé par estimate_price() quand la salle ne tarife pas ce créneau, et
    // par booking_quote() sur une salle qu'on n'a pas le droit de voir.
    case 'P0002':
      return 'Cette salle ne propose pas ce créneau à cette date.';

    default:
      return null;
  }
}
