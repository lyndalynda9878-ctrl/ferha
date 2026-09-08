import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_providers.dart';

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

/// Le profil de l'utilisateur connecté, ou `null` s'il n'y a personne.
///
/// Relu à chaque changement de session : se déconnecter vide le profil, se
/// connecter le recharge, sans qu'aucun écran ait à s'en occuper.
final profilProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return null;

  final client = ref.watch(supabaseClientProvider);

  // maybeSingle et non single : un compte sans profil ne doit pas faire
  // tomber l'écran. Le déclencheur de la migration 007 rend ce cas
  // impossible, mais un profil manquant reste plus lisible qu'une exception.
  return client
      .from('profiles')
      .select(
        'id, full_name, email, phone, phone_verified, is_owner, is_admin, locale',
      )
      .eq('id', session.user.id)
      .maybeSingle();
});
