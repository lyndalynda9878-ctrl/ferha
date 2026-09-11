import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/auth_providers.dart';
import '../../features/auth/connexion_screen.dart';
import '../../features/auth/inscription_screen.dart';
import '../../features/auth/profil_screen.dart';
import '../../features/booking/acompte_screen.dart';
import '../../features/booking/booking_providers.dart';
import '../../features/booking/demande_envoyee_screen.dart';
import '../../features/booking/demande_screen.dart';
import '../../features/booking/mes_reservations_screen.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../features/owner/agenda_screen.dart';
import '../../features/owner/detail_demande_screen.dart';
import '../../features/owner/photos_salle_screen.dart';
import '../../features/owner/publier_salle_screen.dart';
import '../../features/owner/recapitulatif_salle_screen.dart';
import '../../features/owner/tableau_de_bord_screen.dart';
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

      // AUCUNE REDIRECTION VERS LA CONNEXION SUR LES ROUTES DE CONSULTATION.
      //
      // Un visiteur non connecté doit pouvoir chercher une salle et consulter
      // une fiche : c'est le parcours du §3, dont les deux premières étapes se
      // font sans compte. La connexion se demande au moment d'agir, par
      // `exigerConnexion` (exiger_connexion.dart), depuis l'écran qui porte le
      // geste. Une `redirect` posée ici fermerait le catalogue.
      //
      // Le tableau de bord du propriétaire, plus bas, est la seule exception —
      // et il n'est pas une route de consultation. Sa `redirect` porte sa propre
      // justification.
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

      // La demande de réservation. AUCUNE REDIRECTION NON PLUS, et c'est le
      // point de l'étape : un visiteur non connecté compose sa demande
      // entièrement, et la connexion ne lui est réclamée qu'au moment où il
      // appuie sur « Envoyer », depuis l'écran lui-même. Une `redirect` posée
      // ici le renverrait à la connexion avant qu'il ait vu un seul prix.
      GoRoute(
        path: FerhaRoutes.demande,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final p = state.uri.queryParameters;
          return DemandeScreen(
            venueId: state.pathParameters['id']!,
            // Une demande sans date n'a pas de prix : on retombe sur
            // aujourd'hui plutôt que d'afficher un écran vide. En pratique le
            // calendrier passe toujours la date qu'il a fait choisir.
            date: DateTime.tryParse(p['date'] ?? '') ?? DateTime.now(),
            creneau: Creneau.depuisCode(p['creneau']),
            invites: int.tryParse(p['invites'] ?? ''),
          );
        },
      ),

      // La confirmation. `extra` porte le récapitulatif ; sur un rechargement
      // de page il est perdu, et l'écran se replie sur la seule référence que
      // l'adresse ait conservée — plutôt que d'inventer un détail qu'il n'a
      // plus.
      GoRoute(
        path: FerhaRoutes.demandeEnvoyee,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => DemandeEnvoyeeScreen(
          demande: state.extra as DemandeEnvoyee?,
          reference: state.uri.queryParameters['ref'],
        ),
      ),

      // LE VERSEMENT DE L'ACOMPTE EST DÉCLARÉ AVANT « Mes réservations », par
      // la même prudence qu'entre les photos et le récapitulatif d'une salle :
      // les deux chemins partagent leur début, et l'ordre lève tout doute.
      //
      // Pas de redirection ici non plus. `acompte_a_verser()` (024) refuse
      // d'elle-même un appel sans session (FE050) et la réservation d'un autre
      // (FE051) ; l'écran traduit ses refus en une phrase et propose le geste
      // qui reste. Une `redirect` ferait un second gardien pour la même règle,
      // et renverrait vers la connexion quelqu'un dont le seul tort est d'avoir
      // gardé un onglet ouvert trois jours.
      GoRoute(
        path: FerhaRoutes.acompte,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) =>
            AcompteScreen(bookingId: state.pathParameters['id']!),
      ),

      // Le suivi des réservations. Pas de redirection ici non plus : c'est le
      // profil qui n'offre l'entrée qu'à un compte connecté, et
      // `client_bookings()` qui refuse un appel sans session. Une `redirect`
      // ferait un troisième gardien pour la même règle.
      //
      // Le paramètre `paiement` est ce que Chargily renvoie après la caisse :
      // il ne dit pas qu'un paiement a réussi, il dit qu'il a eu lieu. Voir
      // [FerhaRoutes.parametrePaiement].
      GoRoute(
        path: FerhaRoutes.mesReservations,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => MesReservationsScreen(
          retourDePaiement:
              state.uri.queryParameters[FerhaRoutes.parametrePaiement],
        ),
      ),

      // Les notifications. Pas de redirection ici non plus : c'est la cloche
      // qui appelle `exigerConnexion` avant d'ouvrir l'écran, et
      // `mes_notifications()` qui ne rend rien sans session. Une `redirect`
      // ferait un troisième gardien pour la même règle.
      GoRoute(
        path: FerhaRoutes.notifications,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const NotificationsScreen(),
      ),

      // LE TABLEAU DE BORD DU PROPRIÉTAIRE, ET LA SEULE REDIRECTION DU ROUTEUR.
      //
      // Elle ne contredit pas la règle écrite plus haut, elle en marque la
      // frontière : cette règle protège la CONSULTATION — chercher une salle,
      // ouvrir une fiche, lire des avis se font sans compte, et une redirection
      // posée là fermerait le catalogue. Un tableau de bord n'est pas une
      // vitrine. Il n'a rien à montrer à qui n'est pas connecté, et il n'a même
      // pas de quoi le dire proprement : sans session, `owner_venues()` rend une
      // liste vide, que l'écran lirait comme « vous n'avez aucune salle ».
      // Répondre « connectez-vous » est la seule phrase juste.
      //
      // Elle est posée sur cette route et sur elle seule, et elle ne remplace
      // aucun garde-fou : les trois fonctions de 014 refusent d'elles-mêmes un
      // appel sans session, et une salle qui n'est pas la vôtre.
      //
      // `matchedLocation` et non `uri` : la salle regardée ne voyage pas dans
      // l'adresse, il n'y a donc pas de paramètre à préserver au retour.
      GoRoute(
        path: FerhaRoutes.proprietaireTableau,
        parentNavigatorKey: _rootNavigatorKey,
        redirect: (context, state) => ref.read(estConnecteProvider)
            ? null
            : Uri(
                path: FerhaRoutes.connexion,
                queryParameters: <String, String>{
                  FerhaRoutes.parametreRetour: state.matchedLocation,
                },
              ).toString(),
        builder: (context, state) => const TableauDeBordScreen(),
      ),

      // L'agenda. Même redirection que le tableau de bord, et pour la même
      // raison : sans session, `owner_agenda()` refuse, et un écran vide se
      // lirait comme « vous n'avez aucune date ».
      GoRoute(
        path: FerhaRoutes.proprietaireAgenda,
        parentNavigatorKey: _rootNavigatorKey,
        redirect: (context, state) => ref.read(estConnecteProvider)
            ? null
            : Uri(
                path: FerhaRoutes.connexion,
                queryParameters: <String, String>{
                  FerhaRoutes.parametreRetour: state.matchedLocation,
                },
              ).toString(),
        builder: (context, state) => const AgendaScreen(),
      ),

      // L'INSCRIPTION D'UNE SALLE, ET SON RÉCAPITULATIF. Même redirection que
      // les deux écrans précédents : `creer_salle()` refuse un appel sans
      // session (FE030), et un formulaire qu'on remplirait pour se voir
      // demander de se connecter à la dernière ligne aurait fait perdre quatre
      // étapes. Ici, contrairement à la fiche salle, il n'y a rien à consulter
      // avant d'agir : la connexion se demande donc à l'entrée.
      GoRoute(
        path: FerhaRoutes.publierSalle,
        parentNavigatorKey: _rootNavigatorKey,
        redirect: (context, state) => ref.read(estConnecteProvider)
            ? null
            : Uri(
                path: FerhaRoutes.connexion,
                queryParameters: <String, String>{
                  FerhaRoutes.parametreRetour: state.matchedLocation,
                },
              ).toString(),
        builder: (context, state) => const PublierSalleScreen(),
      ),
      // L'ÉTAPE DES PHOTOS EST DÉCLARÉE AVANT LE RÉCAPITULATIF, et ce n'est pas
      // décoratif : `/proprietaire/publier/:id` filerait `photos` comme
      // identifiant de salle si `/proprietaire/publier/:id/photos` était
      // déclaré après lui.
      GoRoute(
        path: FerhaRoutes.publierPhotos,
        parentNavigatorKey: _rootNavigatorKey,
        redirect: (context, state) => ref.read(estConnecteProvider)
            ? null
            : Uri(
                path: FerhaRoutes.connexion,
                queryParameters: <String, String>{
                  FerhaRoutes.parametreRetour: state.matchedLocation,
                },
              ).toString(),
        builder: (context, state) =>
            PhotosSalleScreen(venueId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: FerhaRoutes.publierRecapitulatif,
        parentNavigatorKey: _rootNavigatorKey,
        redirect: (context, state) => ref.read(estConnecteProvider)
            ? null
            : Uri(
                path: FerhaRoutes.connexion,
                queryParameters: <String, String>{
                  FerhaRoutes.parametreRetour: state.matchedLocation,
                },
              ).toString(),
        builder: (context, state) =>
            RecapitulatifSalleScreen(venueId: state.pathParameters['id']!),
      ),

      // Le détail d'une demande. Même redirection, et pour la même raison : il
      // n'y a rien à y montrer sans session, et `owner_request_detail()` refuse
      // de toute façon un appel qui n'en a pas.
      GoRoute(
        path: FerhaRoutes.proprietaireDemande,
        parentNavigatorKey: _rootNavigatorKey,
        redirect: (context, state) => ref.read(estConnecteProvider)
            ? null
            : Uri(
                path: FerhaRoutes.connexion,
                queryParameters: <String, String>{
                  FerhaRoutes.parametreRetour: state.matchedLocation,
                },
              ).toString(),
        builder: (context, state) =>
            DetailDemandeScreen(bookingId: state.pathParameters['id']!),
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
