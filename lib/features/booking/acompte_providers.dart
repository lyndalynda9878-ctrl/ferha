import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/router/routes.dart';
import '../../core/supabase/supabase_providers.dart';
import 'acompte.dart';

/// Ce qui est dû pour une réservation, tel que la base le dit.
///
/// UN APPEL, ET AUCUN CHECKOUT. `acompte_a_verser()` (024) ne parle pas à
/// Chargily : elle lit le devis, l'acompte, l'échéance de l'option, et vérifie à
/// qui est la réservation. L'écran peut donc s'ouvrir, se recharger, être quitté
/// et rouvert sans qu'une seule page de paiement soit créée — on n'en crée une
/// qu'au moment où l'on appuie sur « Payer ».
///
/// `family` sur l'identifiant de la ligne représentative du groupe : c'est ce
/// qu'attendent toutes les fonctions du projet depuis 013.
final acompteProvider = FutureProvider.autoDispose
    .family<AcompteAVerser, String>(
      // AUCUN RÉESSAI AUTOMATIQUE, ET C'EST IMPORTANT ICI. Riverpod 3 réessaie
      // par défaut dix fois, en doublant l'attente jusqu'à 6,4 secondes — une
      // bonne idée pour une requête qu'un réseau a fait tomber, une mauvaise
      // pour un REFUS. « Le délai de 72 h est passé » n'est pas une panne :
      // c'est une réponse, et la même reviendra dix fois. Pendant une demi-
      // minute l'écran resterait sur son squelette, à redemander une phrase
      // qu'il a déjà reçue, avant de l'afficher enfin.
      //
      // On coupe donc le réessai et l'écran dit ce qu'il sait, tout de suite.
      // Pour les vraies pannes — réseau, serveur muet — il y a un bouton
      // « Réessayer », et un geste volontaire vaut mieux qu'une roue qui tourne
      // sans rien dire.
      retry: (_, _) => null,
      (ref, bookingId) async {
        final lignes = await ref
            .read(supabaseClientProvider)
            .rpc<List<dynamic>>(
              'acompte_a_verser',
              params: <String, dynamic>{'p_booking_id': bookingId},
            );

        // La fonction lève sur tous ses refus ; une liste vide ne devrait pas
        // arriver. Si elle arrivait, se taire afficherait un écran vide.
        if (lignes.isEmpty) {
          throw StateError('Aucun acompte pour la réservation $bookingId.');
        }

        return AcompteAVerser.depuisJson(
          (lignes.first as Map).cast<String, dynamic>(),
        );
      },
    );

/// Les adresses où Chargily renvoie le client, une fois la caisse passée.
///
/// ELLES SE CALCULENT DEPUIS L'ADRESSE COURANTE, et non depuis une constante.
/// `flutter run -d chrome` choisit un port neuf à chaque démarrage : une adresse
/// figée serait fausse un jour sur deux. `Uri.base` sait toujours d'où
/// l'application est servie, en développement comme en production.
///
/// REVENIR ICI NE CONFIRME RIEN. Ces deux adresses ne sont qu'un retour à
/// l'écran « Mes réservations » avec un mot sur ce qui vient de se passer ;
/// c'est le webhook du J16 qui décidera si la réservation devient « confirmée ».
/// Le paramètre s'appelle donc [FerhaRoutes.parametrePaiement] et vaut
/// « verification », pas « succes » : le nom dit déjà qu'on ne sait pas encore.
///
/// NULL HORS DU WEB. Chargily renvoie vers une adresse http(s) ; sur mobile il
/// faudrait un lien d'application déclaré côté Android, et il ne l'est pas
/// encore. Plutôt que de fabriquer une adresse où personne n'atterrira, on rend
/// null et l'appelant le dit franchement.
({String succes, String echec})? adressesDeRetour({Uri? base}) {
  final adresse = base ?? Uri.base;
  if (adresse.scheme != 'http' && adresse.scheme != 'https') return null;

  // `origin` plus le chemin de base : une application servie sous un
  // sous-dossier garde son sous-dossier. Le routage de Flutter web est en
  // fragment (`/#/…`), et c'est après ce dièse que la route et ses paramètres
  // se rangent.
  final racine = '${adresse.origin}${adresse.path}';
  const route = FerhaRoutes.mesReservations;
  const cle = FerhaRoutes.parametrePaiement;

  return (
    succes: '$racine#$route?$cle=${FerhaRoutes.paiementEnVerification}',
    echec: '$racine#$route?$cle=${FerhaRoutes.paiementEchoue}',
  );
}

/// Ouvre la page de paiement Chargily de l'acompte.
///
/// TOUT PASSE PAR LA EDGE FUNCTION, ET RIEN PAR L'APPLICATION. Le montant n'est
/// pas envoyé — la base le relit deux fois. La clé secrète Chargily n'est pas
/// connue d'ici, et ne doit jamais l'être : un APK se décompile (§9.4). Ce que
/// cette classe envoie tient en trois choses : quelle réservation, quelle carte,
/// et où revenir.
class PaiementService {
  /// Crée le service autour d'un client Supabase.
  const PaiementService(this._client);

  final SupabaseClient _client;

  /// Demande la page de paiement de [bookingId], réglée par [moyen].
  ///
  /// Un second appel pour la même réservation ne crée PAS une seconde page :
  /// la fonction retrouve celle qui est déjà ouverte chez Chargily et rend son
  /// adresse. Un double tap, un retour arrière, une page rechargée mènent donc
  /// tous les trois à la même caisse.
  ///
  /// Lève une [FunctionException] dont le corps porte le code Ferha du refus —
  /// `acompte_messages.dart` sait le traduire.
  Future<PageDePaiement> ouvrirPage({
    required String bookingId,
    required MoyenDePaiement moyen,
  }) async {
    final retour = adressesDeRetour();
    if (retour == null) {
      throw const PaiementHorsDuWebException();
    }

    final reponse = await _client.functions.invoke(
      'create-checkout',
      body: <String, dynamic>{
        'booking_id': bookingId,
        'methode': moyen.code,
        'retour_succes': retour.succes,
        'retour_echec': retour.echec,
      },
    );

    return PageDePaiement.depuisJson(
      (reponse.data as Map).cast<String, dynamic>(),
    );
  }
}

/// Le service de paiement.
final paiementServiceProvider = Provider<PaiementService>(
  (ref) => PaiementService(ref.watch(supabaseClientProvider)),
);
