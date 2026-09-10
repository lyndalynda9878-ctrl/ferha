import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_messages.dart';

/// Un refus d'envoi : ce qu'on en dit, et s'il sert de réessayer.
///
/// LE SECOND CHAMP EXISTE POUR UN BOUTON. « Ce créneau vient d'être réservé »
/// ne se répare pas en rappuyant : la date est prise, et elle ne se change pas
/// depuis l'écran de demande. Laisser « Envoyer la demande » plein et ambre
/// sous cette phrase-là invite à un geste dont la réponse est déjà connue.
/// [definitif] distingue ces refus-là d'une session expirée ou d'un réseau
/// tombé, que le même bouton répare.
typedef RefusDemande = ({String message, bool definitif});

/// Traduit le refus d'une demande de réservation en une phrase qui dit quoi
/// faire.
///
/// ON LIT LE CODE FERHA, JAMAIS LE MESSAGE. `request_booking()` (migration 012)
/// pose sur chacun de ses refus un code à lui — `FE001` à `FE007` — dans le
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
/// Les six premiers codes sont documentés en tête de `012_booking_request.sql`,
/// et FE007 en tête de `020_telephone_joignable.sql`. Le premier est le seul
/// que la maquette exige explicitement : « Ce créneau vient d'être réservé »,
/// pas un code.
RefusDemande refusDemande(Object erreur) {
  if (erreur is PostgrestException) {
    final traduit = _parCodeFerha(erreur.hint) ?? _parSqlstate(erreur.code);
    if (traduit != null) return traduit;
  }

  // Réseau, session expirée, erreur inconnue : la traduction commune sait déjà
  // les dire, et montre le message d'origine quand elle ne sait pas. Rien de
  // définitif là-dedans — un réseau qui revient fait aboutir le même envoi.
  return (message: messageErreurAuth(erreur), definitif: false);
}

/// La phrase seule, pour les endroits qui n'ont aucun bouton à éteindre.
String messageErreurDemande(Object erreur) => refusDemande(erreur).message;

/// Les refus de `request_booking()`, et ce qu'ils veulent dire pour quelqu'un
/// qui vient d'appuyer sur « Envoyer la demande ».
///
/// LES CINQ PREMIERS SONT DÉFINITIFS : ce qu'ils refusent est la date, le
/// créneau ou la salle, et aucun de ces trois-là ne se change depuis cet écran.
/// Rappuyer sur « Envoyer » rendrait mot pour mot la même phrase — d'où leur
/// `definitif: true`, qui éteint le bouton plutôt que de laisser un rectangle
/// ambre inviter à un second essai perdu d'avance. Leurs phrases disent déjà
/// où aller, et c'est le calendrier, pas ce bouton.
///
/// LES DEUX DERNIERS NE LE SONT PAS : la session (FE006) et le numéro (FE007)
/// se réparent sans quitter cet écran — le champ du téléphone est à quelques
/// centimètres du bouton.
RefusDemande? _parCodeFerha(String? hint) {
  switch (hint) {
    // FE001 — la course perdue. Le calendrier disait « libre » quand le client
    // l'a ouvert ; quelqu'un a confirmé entre-temps. Ce n'est pas sa faute, et
    // la phrase doit le dire ainsi : au passé récent, avec la suite à faire.
    case 'FE001':
      return (
        message:
            'Ce créneau vient d’être réservé. Revenez au calendrier pour '
            'choisir une autre date.',
        definitif: true,
      );

    case 'FE002':
      return (
        message:
            'Le propriétaire a bloqué ce créneau. Choisissez une autre date '
            'au calendrier.',
        definitif: true,
      );

    case 'FE003':
      return (
        message: 'Cette date est passée. Choisissez une date à venir.',
        definitif: true,
      );

    case 'FE004':
      return (
        message: 'Cette salle n’accepte plus de réservation pour le moment.',
        definitif: true,
      );

    // FE005 ne devrait plus atteindre l'écran : le formulaire ne s'affiche pas
    // sur sa propre salle, et ni la fiche ni le calendrier n'y mènent. Il reste
    // traduit — la base est la garde, cet écran n'en est que la politesse.
    case 'FE005':
      return (
        message: 'Vous ne pouvez pas réserver votre propre salle.',
        definitif: true,
      );

    // FE006 ne devrait jamais atteindre l'écran non plus : la connexion est
    // demandée avant l'envoi. Il reste traduit pour le cas où la session expire
    // entre les deux — et il n'est PAS définitif : c'est le seul de la liste
    // qu'un geste depuis cet écran répare.
    case 'FE006':
      return (
        message:
            'Votre session a expiré. Reconnectez-vous, votre demande est '
            'conservée.',
        definitif: false,
      );

    // FE007 — le numéro de téléphone (020). Pas définitif, et c'est le seul de
    // la liste avec FE006 : le champ est sur cet écran, à quelques centimètres
    // du bouton. On redonne la forme attendue plutôt que de dire « invalide ».
    case 'FE007':
      return (
        message:
            'Un numéro de téléphone valide est nécessaire : 0770 11 22 33 '
            'pour un mobile, 041 23 45 67 pour un fixe.',
        definitif: false,
      );

    default:
      return null;
  }
}

/// Les erreurs qui n'ont pas de code Ferha parce qu'elles ne viennent pas de
/// `request_booking()`, mais des garde-fous posés sous elle.
RefusDemande? _parSqlstate(String? code) {
  switch (code) {
    // Levé par le trigger bookings_set_price quand une option ne vient pas de
    // cette salle — une option retirée du catalogue pendant que l'écran était
    // ouvert, par exemple.
    //
    // Pas définitif : la phrase demande de décocher puis de renvoyer, et
    // éteindre le bouton empêcherait justement le geste qu'on réclame.
    case '23503':
      return (
        message:
            'Une des options choisies n’est plus proposée par cette salle. '
            'Décochez-la et renvoyez la demande.',
        definitif: false,
      );

    // Levé par estimate_price() quand la salle ne tarife pas ce créneau, et
    // par booking_quote() sur une salle qu'on n'a pas le droit de voir. Ni le
    // créneau ni la salle ne se changent d'ici.
    case 'P0002':
      return (
        message: 'Cette salle ne propose pas ce créneau à cette date.',
        definitif: true,
      );

    default:
      return null;
  }
}
