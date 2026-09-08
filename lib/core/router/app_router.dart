import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/connexion_screen.dart';
import '../../features/auth/inscription_screen.dart';
import '../../features/auth/profil_screen.dart';
import '../../features/search/accueil_screen.dart';
import '../../features/search/resultats_screen.dart';
import '../../features/search/search_filters.dart';
import '../../features/venue/calendrier_screen.dart';
import '../../features/venue/galerie_screen.dart';
import '../../features/venue/venue_screen.dart';
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
          _branch(FerhaRoutes.accueil, const AccueilScreen()),
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
          _branch(FerhaRoutes.profil, const ProfilScreen()),
        ],
      ),

      // AUCUNE REDIRECTION VERS LA CONNEXION, ICI NI AILLEURS.
      //
      // Un visiteur non connecté doit pouvoir chercher une salle et consulter
      // une fiche : c'est le parcours du §3, dont les deux premières étapes se
      // font sans compte. La connexion se demande au moment d'agir, par
      // `exigerConnexion` (exiger_connexion.dart), depuis l'écran qui porte le
      // geste. Une `redirect` posée ici fermerait le catalogue.
      //
      // Les routes qui suivent sont hors de la coque d'onglets : elles
      // s'ouvrent par-dessus l'écran en cours, et se referment dessus.

      // Les résultats de recherche. Le bouton retour ramène à l'accueil avec
      // ses critères intacts, et l'URL porte la recherche entière.
      GoRoute(
        path: FerhaRoutes.resultats,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => ResultatsScreen(
          filtres: SearchFilters.depuisParametres(state.uri.queryParameters),
        ),
      ),

      // La fiche salle, sa galerie et son calendrier. Aucune redirection : ce
      // sont les étapes 2 du parcours du §3, et elles se font sans compte.
      // Le bouton « Disponibilité » ne demande donc rien non plus.
      GoRoute(
        path: FerhaRoutes.salle,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final p = state.uri.queryParameters;
          return VenueScreen(
            venueId: state.pathParameters['id']!,
            date: DateTime.tryParse(p['date'] ?? ''),
            invites: int.tryParse(p['invites'] ?? ''),
            creneau: Creneau.depuisCode(p['creneau']),
          );
        },
      ),
      GoRoute(
        path: FerhaRoutes.galerie,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => GalerieScreen(
          venueId: state.pathParameters['id']!,
          // Passées par la fiche, qui les a déjà chargées ; relues si l'on
          // entre par un lien profond.
          photos: (state.extra as List<String>?),
        ),
      ),
      GoRoute(
        path: FerhaRoutes.calendrier,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final p = state.uri.queryParameters;
          return CalendrierScreen(
            venueId: state.pathParameters['id']!,
            creneau: Creneau.depuisCode(p['creneau']),
            date: DateTime.tryParse(p['date'] ?? ''),
            invites: int.tryParse(p['invites'] ?? ''),
          );
        },
      ),

      GoRoute(
        path: FerhaRoutes.connexion,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => ConnexionScreen(
          retour: state.uri.queryParameters[FerhaRoutes.parametreRetour],
        ),
      ),
      GoRoute(
        path: FerhaRoutes.inscription,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const InscriptionScreen(),
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
