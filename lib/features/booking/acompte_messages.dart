import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../core/l10n/message_erreur.dart';
import 'acompte.dart';

/// Un refus de l'écran 6 : ce qu'on en dit, et s'il sert de rappuyer.
///
/// [definitif] éteint le bouton. « La date n'est plus tenue » ne se répare pas
/// en réessayant — l'option est éteinte, et elle ne se rallume pas depuis cet
/// écran. Un réseau tombé, lui, se répare tout seul au second essai.
typedef RefusAcompte = ({String message, bool definitif});

/// Traduit un refus du parcours de paiement en une phrase qui dit quoi faire.
///
/// DEUX SOURCES, UN SEUL VOCABULAIRE. L'écran appelle `acompte_a_verser()` en
/// RPC — les refus arrivent alors en [PostgrestException], le code Ferha dans
/// `hint`. Le bouton « Payer » appelle la Edge Function `create-checkout` — les
/// refus arrivent en [FunctionException], et la fonction recopie dans son corps
/// JSON le même `hint` que la base lui a donné. C'est pour cela que les deux se
/// traduisent ici, ensemble : ce sont les mêmes codes, et une seule phrase leur
/// correspond.
///
/// ON LIT LE CODE, JAMAIS LE MESSAGE, comme dans `booking_messages.dart` : le
/// message de la base est une formulation, le code est un contrat. Les codes de
/// ce parcours sont documentés en tête de `024_acompte_chargily.sql` (FE050 à
/// FE055) et de `supabase/functions/create-checkout/index.ts` (FE056 à FE059).
RefusAcompte refusAcompte(AppLocalizations textes, Object erreur) {
  // Aucune adresse de retour à donner à Chargily : on est hors du web, et le
  // lien d'application Android n'existe pas encore. Définitif — rappuyer ne
  // fera pas apparaître de navigateur.
  if (erreur is PaiementHorsDuWebException) {
    return (message: textes.refusPaiementHorsDuWeb, definitif: true);
  }

  if (erreur is PostgrestException) {
    final traduit = _parCodeFerha(textes, erreur.hint);
    if (traduit != null) return traduit;
  }

  if (erreur is FunctionException) {
    final traduit = _parCodeFerha(textes, _hintDeLaFonction(erreur.details));
    if (traduit != null) return traduit;
  }

  // Réseau, session expirée, erreur inconnue : la traduction commune sait déjà
  // les dire. Rien de définitif là-dedans.
  return (message: messageErreur(textes, erreur), definitif: false);
}

/// La phrase seule, pour les endroits qui n'ont aucun bouton à éteindre.
String messageErreurAcompte(AppLocalizations textes, Object erreur) =>
    refusAcompte(textes, erreur).message;

/// Le code Ferha caché dans le corps d'erreur d'une Edge Function.
///
/// `details` porte le JSON décodé quand la fonction a répondu en
/// `application/json` — c'est le cas de `create-checkout`, qui répond toujours
/// `{"hint": …, "message": …}`. Une passerelle qui répondrait autre chose (un
/// 401 du portail avant même que la fonction tourne, une page d'erreur HTML)
/// donne un `details` qui n'est pas une Map : on rend null, et l'appelant
/// retombe sur la traduction commune.
String? _hintDeLaFonction(Object? details) {
  if (details is Map && details['hint'] is String) {
    return details['hint'] as String;
  }
  return null;
}

/// Les refus du parcours de l'acompte, et ce qu'ils veulent dire pour quelqu'un
/// qui vient d'appuyer sur « Payer ».
RefusAcompte? _parCodeFerha(AppLocalizations textes, String? hint) {
  switch (hint) {
    // FE050 — la session a expiré entre l'ouverture de l'écran et le paiement.
    // Pas définitif : se reconnecter suffit, et la réservation attend.
    case 'FE050':
      return (message: textes.refusSessionAcompte, definitif: false);

    // FE051 — la réservation n'est pas la sienne, ou n'existe pas. La base ne
    // distingue pas les deux, et l'écran non plus : rien ici ne doit apprendre
    // à un curieux qu'un identifiant existe.
    case 'FE051':
      return (message: textes.refusPasVotreReservation, definitif: true);

    // FE052 — le propriétaire n'a pas encore répondu. Il n'y a rien à payer, et
    // rien à faire qu'attendre : l'écran « Mes réservations » suivra la réponse
    // tout seul.
    case 'FE052':
      return (message: textes.refusPasEncoreRepondu, definitif: true);

    // FE053 — l'option de 72 h est éteinte, ou la demande a été refusée ou
    // annulée. C'est le refus le plus dur de la liste, et la phrase doit dire
    // la suite sans détour : la date est repartie à la vente.
    case 'FE053':
      return (message: textes.refusOptionEteinte, definitif: true);

    // FE054 — déjà réglé. Une bonne nouvelle, pas une erreur.
    case 'FE054':
      return (message: textes.refusDejaRegle, definitif: true);

    // FE055 — aucun moyen de paiement choisi, ou un moyen que la base ne
    // connaît pas. Le geste est sur l'écran, à deux centimètres du bouton.
    case 'FE055':
      return (message: textes.refusChoisirUneCarte, definitif: false);

    // FE056 et FE057 sont des erreurs de programme — une méthode HTTP ou un
    // corps de requête que seule cette application construit. Le client n'y
    // peut rien, et la phrase ne lui demande donc rien.
    case 'FE056':
    case 'FE057':
      return (message: textes.refusPaiementNonLance, definitif: false);

    // FE058 — la clé Chargily n'est pas posée sur le serveur. C'est un défaut
    // d'installation, pas un incident : il ne se répare pas en réessayant, et
    // la phrase ne doit pas le faire croire. Elle ne nomme aucun secret.
    case 'FE058':
      return (message: textes.refusPaiementPasOuvert, definitif: true);

    // FE059 — Chargily n'a pas répondu, ou a répondu de travers. Le journal de
    // la Edge Function dit quoi ; le client, lui, réessaie.
    case 'FE059':
      return (message: textes.refusPageNonOuverte, definitif: false);

    default:
      return null;
  }
}
