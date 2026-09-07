import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/l10n/generated/app_localizations.dart';
import 'core/l10n/locale_controller.dart';
import 'core/router/app_router.dart';
import 'core/theme/ferha_theme.dart';

void main() {
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
