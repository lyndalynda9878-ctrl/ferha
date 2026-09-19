import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase/session_providers.dart';
import '../../core/supabase/supabase_providers.dart';

/// CETTE LIGNE N'EST PAS UN OUBLI — NE LA RETIREZ PAS SANS LIRE CECI.
///
/// `sessionProvider`, `estConnecteProvider` et `SessionController` ont déménagé
/// au J27 dans `lib/core/supabase/session_providers.dart` : le socle les
/// lisait, et le socle ne doit pas dépendre d'une fonctionnalité. L'en-tête du
/// nouveau fichier dit où passe la frontière.
///
/// Cet `export` existe pour que le déménagement ne coûte rien à personne :
/// **8 fichiers de `lib/features/` — sur les cinq domaines auth, booking,
/// favorites, notifications et owner — et 17 fichiers de test continuent
/// d'importer ce fichier-ci comme avant.** Surtout, les 26 surcharges de test
/// (`estConnecteProvider.overrideWithValue(…)`, `sessionProvider.overrideWith(…)`)
/// restent valides telles quelles : un `export` ne fabrique pas un second
/// fournisseur, il rend visible le MÊME objet. Une surcharge posée sur l'objet
/// exporté est posée sur l'objet déclaré.
///
/// La retirer obligerait à corriger 25 imports pour ne rien gagner. Le jour où
/// l'on voudra vraiment que chaque fichier nomme sa source, ce sera un passage
/// à part, et il se verra dans son propre commit.
export '../../core/supabase/session_providers.dart'
    show SessionController, estConnecteProvider, sessionProvider;

/// Le profil de l'utilisateur connecté, ou `null` s'il n'y a personne.
///
/// IL RESTE ICI, ET C'EST LA FRONTIÈRE. Il lit la table `profiles` — des
/// colonnes, un schéma, des droits RLS —, alors que la session ne connaît que
/// le client Supabase. Savoir s'il y a quelqu'un est du socle ; savoir qui
/// c'est est de l'authentification.
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
