import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_providers.dart';

/// Les trois gestes d'authentification du socle.
///
/// Un seul endroit qui parle à GoTrue : les écrans appellent ces méthodes et
/// n'ont pas à savoir comment un compte se crée. Les erreurs remontent telles
/// quelles — c'est `messageErreurAuth` qui les traduit, au moment de
/// l'affichage, et pas ici : une couche de service qui transforme ses
/// exceptions en chaînes fait perdre l'information à celle qui suit.
class AuthService {
  /// Crée le service autour d'un client Supabase.
  const AuthService(this._client);

  final SupabaseClient _client;

  /// Connecte un compte existant.
  Future<void> connexion({
    required String email,
    required String motDePasse,
  }) async {
    await _client.auth.signInWithPassword(
      email: email.trim(),
      password: motDePasse,
    );
  }

  /// Crée un compte.
  ///
  /// Le nom part dans les métadonnées du compte : c'est le déclencheur
  /// `handle_new_user` (migration 007) qui le recopie dans `profiles`, dans la
  /// même transaction que la création du compte. L'application n'écrit pas le
  /// profil elle-même — un second appel pourrait se perdre et laisser un
  /// compte sans profil.
  /// Renvoie `true` si une session s'est ouverte immédiatement, `false` si le
  /// projet Supabase exige une confirmation par e-mail. On lit la réponse du
  /// serveur plutôt que d'aller regarder l'état du client juste après : le flux
  /// `onAuthStateChange` n'a pas forcément encore été délivré.
  Future<bool> inscription({
    required String email,
    required String motDePasse,
    required String nomComplet,
    String locale = 'fr',
  }) async {
    final reponse = await _client.auth.signUp(
      email: email.trim(),
      password: motDePasse,
      data: <String, dynamic>{'full_name': nomComplet.trim(), 'locale': locale},
    );
    return reponse.session != null;
  }

  /// Déconnecte le compte courant.
  Future<void> deconnexion() => _client.auth.signOut();
}

/// Le service d'authentification.
final authServiceProvider = Provider<AuthService>(
  (ref) => AuthService(ref.watch(supabaseClientProvider)),
);
