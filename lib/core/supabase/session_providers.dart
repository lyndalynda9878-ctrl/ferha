/// QUI EST CONNECTÉ — la question de socle, rangée dans le socle.
///
/// Ces deux fournisseurs ont vécu jusqu'au J27 dans
/// `lib/features/auth/auth_providers.dart`. Ils n'y étaient pas à leur place :
/// `lib/core/l10n/locale_controller.dart`, `lib/core/router/app_router.dart` et
/// `lib/core/router/exiger_connexion.dart` les lisaient, c'est-à-dire que le
/// SOCLE dépendait d'une FONCTIONNALITÉ. C'est la dépendance qui part dans le
/// mauvais sens : elle ne casse rien tant qu'on ne bouge rien, et elle rend le
/// jour venu un dossier impossible à déplacer sans démonter le reste.
///
/// Ils descendent d'ailleurs tout droit de `supabase_providers.dart`, leur
/// voisin de dossier : ils ne connaissent que le client Supabase, aucune table,
/// aucun écran.
///
/// =============================================================================
/// LA FRONTIÈRE, ÉCRITE PLUTÔT QUE DEVINÉE
///
/// Ici : **la session**, c'est-à-dire l'existence de quelqu'un. Une notion de
/// socle — le routeur s'en sert pour rediriger, la langue pour savoir s'il y a
/// un profil où écrire, et aucun des deux n'a affaire à l'authentification.
///
/// Là-bas, et qui y reste : **`profilProvider`**, dans
/// `lib/features/auth/auth_providers.dart`. Il lit la table `profiles` —
/// `full_name`, `is_owner`, `locale` —, donc il connaît un schéma, des colonnes
/// et des droits. C'est une notion de fonctionnalité, et elle appartient à la
/// fonctionnalité qui la dessine.
///
/// La règle tient en une phrase : **savoir s'il y a quelqu'un est du socle,
/// savoir qui c'est est de l'authentification.**
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_providers.dart';

/// La session courante, ou `null` si personne n'est connecté.
///
/// `build()` renvoie la session déjà restaurée par `Supabase.initialize()` :
/// l'état est donc juste dès la première image, sans passer par un état de
/// chargement. C'est ce qui évite qu'un utilisateur connecté voie clignoter
/// l'écran « connectez-vous » au démarrage.
///
/// L'abonnement qui suit tient l'état à jour : connexion, déconnexion,
/// renouvellement automatique du jeton, expiration.
class SessionController extends Notifier<Session?> {
  @override
  Session? build() {
    final auth = ref.watch(supabaseClientProvider).auth;

    final abonnement = auth.onAuthStateChange.listen((donnees) {
      state = donnees.session;
    });
    ref.onDispose(abonnement.cancel);

    return auth.currentSession;
  }
}

/// La session courante, ou `null`.
final sessionProvider = NotifierProvider<SessionController, Session?>(
  SessionController.new,
);

/// Vrai quand quelqu'un est connecté.
///
/// À lire pour décider d'un affichage, jamais pour décider d'un droit : les
/// droits sont portés par les politiques RLS (§9), et un client qui mentirait
/// ici n'obtiendrait rien de plus de la base.
final estConnecteProvider = Provider<bool>(
  (ref) => ref.watch(sessionProvider) != null,
);
