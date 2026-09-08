import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/env/ferha_env.dart';
import 'core/l10n/generated/app_localizations.dart';
import 'core/l10n/locale_controller.dart';
import 'core/router/app_router.dart';
import 'core/theme/ferha_colors.dart';
import 'core/theme/ferha_radii.dart';
import 'core/theme/ferha_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Pas de configuration, pas de démarrage. On ne lance pas l'application sur
  // une base inexistante pour la voir échouer écran par écran : on s'arrête
  // ici, et on dit quoi faire.
  if (!FerhaEnv.estComplete) {
    debugPrint(FerhaEnv.messageDAide);
    runApp(const _ConfigurationManquanteApp(message: null));
    return;
  }

  try {
    await Supabase.initialize(
      url: FerhaEnv.supabaseUrl,
      // publishableKey et non anonKey : anonKey est déprécié depuis
      // supabase_flutter 2.17. Les deux paramètres aboutissent à la même clé
      // dans le paquet — une clé « anon » se passe donc ici telle quelle.
      publishableKey: FerhaEnv.supabaseAnonKey,
      // La session survit à la fermeture de l'application. C'est le défaut du
      // paquet ; on l'écrit quand même, parce que c'est une exigence du
      // produit et non un détail d'implémentation — personne ne doit le
      // désactiver sans s'en apercevoir.
      //
      // Concrètement : le jeton est rangé dans localStorage sur le web, dans
      // SharedPreferences sur mobile, et `Supabase.initialize` le restaure
      // avant que la première image ne s'affiche. Un utilisateur connecté ne
      // voit donc jamais clignoter l'écran « connectez-vous ».
      authOptions: const FlutterAuthClientOptions(persistSession: true),
    );
  } on Object catch (erreur) {
    // Une URL mal formée échoue ici, et pas plus tard au premier écran.
    debugPrint('Initialisation de Supabase impossible : $erreur');
    runApp(_ConfigurationManquanteApp(message: erreur.toString()));
    return;
  }

  runApp(const ProviderScope(child: FerhaApp()));
}

/// Racine de l'application Ferha.
class FerhaApp extends ConsumerWidget {
  /// Crée la racine de l'application.
  const FerhaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final locale = ref.watch(localeProvider);

    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      routerConfig: router,
      theme: FerhaTheme.light(),
      darkTheme: FerhaTheme.dark(),
      themeMode: ThemeMode.system,
      locale: locale,
      supportedLocales: ferhaSupportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      debugShowCheckedModeBanner: false,
    );
  }
}

/// Écran d'arrêt affiché quand l'application ne peut pas démarrer.
///
/// Il ne s'adresse pas à un client mais à la personne qui lance le projet :
/// il n'est donc pas traduit. Il reste en revanche thématisé, clair et sombre,
/// parce qu'un écran du projet n'a pas d'exception à faire.
class _ConfigurationManquanteApp extends StatelessWidget {
  const _ConfigurationManquanteApp({required this.message});

  /// Message d'erreur technique, quand l'arrêt vient d'une initialisation
  /// ratée plutôt que d'une clé absente.
  final String? message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ferha — configuration',
      theme: FerhaTheme.light(),
      darkTheme: FerhaTheme.dark(),
      themeMode: ThemeMode.system,
      debugShowCheckedModeBanner: false,
      home: _ConfigurationManquanteEcran(message: message),
    );
  }
}

class _ConfigurationManquanteEcran extends StatelessWidget {
  const _ConfigurationManquanteEcran({required this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final colors = context.ferhaColors;
    final text = Theme.of(context).textTheme;
    final erreur = Theme.of(context).colorScheme.error;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsetsDirectional.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.key_off_outlined, size: 40, color: erreur),
                  const SizedBox(height: 16),
                  Text(
                    message == null
                        ? 'Ferha ne peut pas démarrer'
                        : 'Ferha n’a pas pu joindre Supabase',
                    style: text.headlineSmall?.copyWith(color: colors.ink),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsetsDirectional.all(16),
                    decoration: BoxDecoration(
                      color: colors.surfaceSecondary,
                      borderRadius: FerhaRadii.cardBorder,
                      border: Border.all(color: colors.rule),
                    ),
                    child: SelectableText(
                      message ?? FerhaEnv.messageDAide,
                      style: text.bodyMedium?.copyWith(
                        color: colors.inkSecondary,
                        fontFamily: 'monospace',
                        height: 1.5,
                      ),
                    ),
                  ),
                  if (message != null) ...<Widget>[
                    const SizedBox(height: 16),
                    Text(
                      'Vérifiez SUPABASE_URL dans env.json : elle doit être '
                      'de la forme https://xxxx.supabase.co',
                      style: text.bodyMedium?.copyWith(
                        color: colors.inkSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
