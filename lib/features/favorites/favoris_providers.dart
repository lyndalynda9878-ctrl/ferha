/// Les salles mises de côté : ce qui est aimé, et ce que l'onglet affiche.
///
/// =============================================================================
/// DEUX FOURNISSEURS, ET ILS NE RÉPONDENT PAS À LA MÊME QUESTION
///
/// [favorisIdsProvider] porte un ENSEMBLE D'IDENTIFIANTS. C'est ce que lit le
/// cœur, sur chaque carte de l'accueil et des résultats : « cette salle-là
/// est-elle aimée ? ». Une seule requête pour tout l'écran, et chaque cœur y
/// puise sans rien redemander.
///
/// [mesFavorisProvider] porte des SALLES ENTIÈRES — nom, photo, prix, note.
/// C'est ce que lit l'onglet, et lui seul. Il coûte une jointure et un calcul
/// de prix par ligne : le faire tourner pour allumer un cœur serait payer une
/// carte pour lire un booléen.
///
/// C'est pourquoi le premier ne meurt pas avec l'écran et le second si : on
/// change d'onglet en permanence, et redemander la liste des identifiants à
/// chaque aller-retour annulerait tout le bénéfice.
///
/// =============================================================================
/// LE CŒUR S'ALLUME AVANT LA BASE, ET SE RÉÉTEINT SI ELLE REFUSE
///
/// [Favoris.basculer] écrit l'état À L'ÉCRAN d'abord, part vers la base
/// ensuite, et REVIENT EN ARRIÈRE si elle refuse. C'est le même ordre que la
/// langue et le thème — ce qui est instantané et sûr passe devant ce qui est
/// long et faillible — avec une différence qui compte : ici, la base peut dire
/// non, et un cœur allumé sur un favori qui n'existe pas serait le même
/// mensonge qu'un prix qui change entre la liste et la fiche.
///
/// La méthode RELANCE donc l'erreur après avoir remis l'état d'avant. L'écran
/// l'attrape et la montre ; sans cela, le cœur se rééteindrait tout seul et
/// personne ne saurait pourquoi.
///
/// =============================================================================
/// PAS DE COMPTEUR, ET C'EST UNE DÉCISION
///
/// Rien ici ne compte combien de personnes aiment une salle, et rien ne le
/// pourra : la politique RLS de `favorites` ne rend que MES lignes. « 12
/// personnes aiment cette salle » sur un catalogue de démonstration serait une
/// preuve sociale fabriquée — le même refus que pour les numéros de téléphone
/// des comptes partagés.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import '../search/venue_summary.dart';
import 'favoris_repository.dart';

/// Les identifiants des salles que la personne connectée a mises de côté.
class Favoris extends AsyncNotifier<Set<String>> {
  @override
  Future<Set<String>> build() async {
    // Se déconnecter vide l'ensemble, se connecter le recharge : aucun écran
    // n'a à s'en occuper, et le cœur s'éteint partout d'un coup.
    //
    // C'EST AUSSI CE QUI TERMINE LE GESTE INTERROMPU. `exigerConnexion` ouvre
    // la connexion par-dessus l'écran ; quand elle se referme, la session a
    // changé, ce fournisseur se reconstruit, et l'appel à [basculer] qui suit
    // travaille sur l'ensemble du bon compte.
    final session = ref.watch(sessionProvider);
    if (session == null) return <String>{};

    return ref.read(favorisRepositoryProvider).identifiantsDe(session.user.id);
  }

  /// Ajoute ou retire la salle, selon son état actuel.
  ///
  /// Relance l'erreur de la base après avoir remis l'état d'avant : c'est
  /// l'écran qui décide quoi en dire. Voir l'en-tête.
  Future<void> basculer(String venueId) async {
    // Personne n'est connecté : il n'y a rien à écrire. C'est l'écran qui
    // réclame la connexion, par `exigerConnexion`, avant d'arriver ici.
    final session = ref.read(sessionProvider);
    if (session == null) return;

    final utilisateur = session.user.id;
    final depot = ref.read(favorisRepositoryProvider);

    final avant = state.value ?? <String>{};
    final etaitAime = avant.contains(venueId);

    final apres = <String>{...avant};
    if (etaitAime) {
      apres.remove(venueId);
    } else {
      apres.add(venueId);
    }

    // LE DOIGT VOIT TOUT DE SUITE.
    state = AsyncData(apres);

    try {
      if (etaitAime) {
        await depot.retirer(utilisateur: utilisateur, venueId: venueId);
      } else {
        await depot.ajouter(utilisateur: utilisateur, venueId: venueId);
      }
    } on Object {
      // IL SE RÉÉTEINT. On remet exactement l'ensemble d'avant — et non le
      // contraire du nouveau, qui divergerait si deux cœurs partaient ensemble.
      if (ref.mounted) state = AsyncData(avant);
      rethrow;
    }

    // L'ONGLET SUIT. On l'invalide plutôt que de lui glisser la salle : il
    // porte un prix et une note que seule la base sait calculer, et les
    // recomposer ici en ferait une seconde source.
    if (ref.mounted) ref.invalidate(mesFavorisProvider);
  }
}

/// Les identifiants des salles mises de côté par la personne connectée.
final favorisIdsProvider = AsyncNotifierProvider<Favoris, Set<String>>(
  Favoris.new,
);

/// Les salles mises de côté, dans la forme exacte d'une carte.
///
/// `mes_favoris()` rend les douze colonnes de `search_venues`, donc
/// [VenueSummary] les lit avec son constructeur habituel et l'onglet réutilise
/// la carte de l'accueil et des résultats sans en redessiner une.
///
/// `autoDispose` : on quitte l'onglet plus souvent qu'on n'y revient, et la
/// liste a un coût — une jointure et un `estimate_price()` par ligne.
final mesFavorisProvider = FutureProvider.autoDispose<List<VenueSummary>>((
  ref,
) async {
  // SANS SESSION, ON NE DEMANDE RIEN. `mes_favoris()` est révoquée pour `anon`
  // et l'appel serait refusé : l'onglet afficherait une erreur là où il doit
  // afficher une invitation à se connecter.
  if (!ref.watch(estConnecteProvider)) return const <VenueSummary>[];

  return ref.read(favorisRepositoryProvider).mesFavoris();
});
