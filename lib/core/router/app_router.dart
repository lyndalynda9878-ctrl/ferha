import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../theme/design_gallery_screen.dart';
import 'home_shell.dart';
import 'placeholder_screen.dart';
import 'routes.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

/// Le routeur de l'application.
///
/// Exposé par un provider pour que les futures redirections (session, rôle)
/// puissent lire l'état Riverpod sans le faire remonter jusqu'à `main()`.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: FerhaRoutes.accueil,
    debugLogDiagnostics: false,
    routes: <RouteBase>[
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            HomeShell(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          _branch(
            FerhaRoutes.accueil,
            const PlaceholderScreen(
              title: 'Accueil',
              icon: Icons.home_outlined,
            ),
          ),
          _branch(
            FerhaRoutes.assistant,
            const PlaceholderScreen(
              title: 'Assistant',
              icon: Icons.auto_awesome_outlined,
            ),
          ),
          _branch(
            FerhaRoutes.favoris,
            const PlaceholderScreen(
              title: 'Favoris',
              icon: Icons.favorite_outline,
            ),
          ),
          _branch(
            FerhaRoutes.profil,
            const PlaceholderScreen(
              title: 'Profil',
              icon: Icons.person_outline,
            ),
          ),
        ],
      ),
      // Route cachée : hors de la coque d'onglets, donc jamais atteignable
      // depuis la barre de navigation.
      GoRoute(
        path: FerhaRoutes.design,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const DesignGalleryScreen(),
      ),
    ],
  );
});

StatefulShellBranch _branch(String path, Widget child) {
  return StatefulShellBranch(
    routes: <RouteBase>[GoRoute(path: path, builder: (_, _) => child)],
  );
}
