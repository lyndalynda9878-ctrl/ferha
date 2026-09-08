import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Le client Supabase de l'application.
///
/// `Supabase.initialize()` est appelé une seule fois, dans `main()`, avant
/// `runApp`. Ce fournisseur ne fait que donner accès au client déjà construit :
/// il ne l'initialise pas, et lire ce fournisseur avant l'initialisation lève
/// une erreur — ce qui est le bon comportement, plutôt qu'un second client
/// silencieux.
///
/// Les écrans passent par ici et jamais par `Supabase.instance.client` en
/// direct : c'est ce qui permettra de substituer un client de test le jour où
/// il y aura des tests de données.
final supabaseClientProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);
