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
