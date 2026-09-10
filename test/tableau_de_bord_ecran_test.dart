import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:ferha/core/preferences/preferences_affichage.dart';
import 'package:ferha/core/theme/ferha_theme.dart';
import 'package:ferha/features/auth/auth_providers.dart';
import 'package:ferha/core/router/routes.dart';
import 'package:ferha/features/owner/demande_detail.dart';
import 'package:ferha/features/owner/demande_en_attente.dart';
import 'package:ferha/features/owner/detail_demande_screen.dart';
import 'package:ferha/features/owner/indicateurs_salle.dart';
import 'package:ferha/features/owner/owner_repository.dart';
import 'package:ferha/features/owner/salle_du_proprietaire.dart';
import 'package:ferha/features/owner/tableau_de_bord_screen.dart';

import 'owner_fakes.dart';

/// L'écran 9, monté sur un dépôt de test.
///
/// LE TEST LE PLUS IMPORTANT DE CE FICHIER EST CELUI DE L'ORDRE. La légende de
/// l'écran 9 dit que les demandes en attente passent devant les statistiques
/// dès qu'il y en a une — c'est la seule chose de cet écran qu'un remaniement
/// futur peut casser sans que rien ne se voie, puisque tout reste affiché. Un
/// test qui compare deux ordonnées le remarque, lui.
/// L'espace fine insécable de la typographie française.
///
/// C'est elle qui sépare les milliers dans `montantEnDinars` et qui précède
/// « % » et « pts » dans l'écran. Écrite ici en toutes lettres plutôt qu'en
/// caractère invisible : un test qui échoue sur une espace qu'on ne voit pas
/// coûte une demi-heure.
const fine = ' ';

void main() {
  const bahia = '5a11e000-0000-4000-a000-000000000001';
  const ennour = '5a11e000-0000-4000-a000-000000000002';

  Future<void> ouvre(
    WidgetTester tester, {
    List<SalleDuProprietaire>? salles,
    Map<String, IndicateursSalle>? indicateurs,
    Map<String, List<DemandeEnAttente>>? demandes,
    String? retenue,
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          estConnecteProvider.overrideWithValue(true),
          preferencesAffichageProvider.overrideWithValue(
            PreferencesEnMemoire(retenue),
          ),
          ownerRepositoryProvider.overrideWithValue(
            DepotDeTest(
              sallesRendues:
                  salles ?? <SalleDuProprietaire>[salleDeTest(id: bahia)],
              indicateursRendus:
                  indicateurs ??
                  <String, IndicateursSalle>{bahia: indicateursDeTest()},
              demandesRendues:
                  demandes ?? const <String, List<DemandeEnAttente>>{},
            ),
          ),
        ],
        child: MaterialApp(
          theme: theme ?? FerhaTheme.light(),
          home: const TableauDeBordScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  double hauteurDe(WidgetTester tester, Finder finder) =>
      tester.getTopLeft(finder).dy;

  group('L’ordre : ce qu’il y a à faire d’abord', () {
    testWidgets('avec des demandes, elles passent devant les chiffres', (
      tester,
    ) async {
      await ouvre(
        tester,
        salles: <SalleDuProprietaire>[
          salleDeTest(id: bahia, demandesEnAttente: 2),
        ],
        demandes: <String, List<DemandeEnAttente>>{
          bahia: <DemandeEnAttente>[
            demandeDeTest(id: '1', client: 'Amina K.'),
            demandeDeTest(id: '2', client: 'Yacine M.'),
          ],
        },
      );

      expect(find.text('Demandes en attente · 2'), findsOneWidget);
      expect(
        hauteurDe(tester, find.text('Demandes en attente · 2')),
        lessThan(hauteurDe(tester, find.text('Ce mois-ci'))),
      );
    });

    testWidgets('sans demande, les chiffres reprennent la tête', (
      tester,
    ) async {
      await ouvre(tester);

      expect(find.text('Aucune demande en attente.'), findsOneWidget);
      expect(
        hauteurDe(tester, find.text('Ce mois-ci')),
        lessThan(hauteurDe(tester, find.text('Aucune demande en attente.'))),
      );
    });
  });

  group('Les chiffres viennent de la base, entiers', () {
    testWidgets('les quatre indicateurs s’affichent avec leur variation', (
      tester,
    ) async {
      await ouvre(tester);

      expect(find.text('68$fine%'), findsOneWidget);
      expect(find.text('1,84 M DA'), findsOneWidget);
      expect(find.text('4,6'), findsOneWidget);
      expect(find.text('41$fine%'), findsOneWidget);

      // Des points pour un taux, un pourcentage pour un revenu — et la valeur
      // absolue, puisque la flèche porte le signe.
      expect(find.text('9${fine}pts'), findsOneWidget);
      expect(find.text('6${fine}pts'), findsOneWidget);
      expect(find.text('14$fine%'), findsOneWidget);

      expect(find.text('34 avis'), findsOneWidget);
      expect(find.text('12 dates'), findsOneWidget);
      expect(find.text('Prévisionnel septembre'), findsOneWidget);
    });

    testWidgets('une variation absente s’écrit « — », jamais « 0 »', (
      tester,
    ) async {
      await ouvre(
        tester,
        indicateurs: <String, IndicateursSalle>{
          bahia: indicateursDeTest(
            variationOccupation: null,
            variationRevenu: null,
            variationAcceptation: null,
          ),
        },
      );

      // Un mois précédent vide ne donne pas une variation de zéro : il n'en
      // donne pas. Trois cartes, trois tirets.
      expect(find.text('—'), findsNWidgets(3));
      expect(find.textContaining('0${fine}pts'), findsNothing);
      expect(find.textContaining('0$fine%'), findsNothing);
    });

    testWidgets('une salle sans avis n’a pas une note de 0,0', (tester) async {
      await ouvre(
        tester,
        indicateurs: <String, IndicateursSalle>{
          bahia: indicateursDeTest(note: null, nombreAvis: 0),
        },
      );

      expect(find.text('Aucun avis'), findsOneWidget);
      expect(find.text('0,0'), findsNothing);
    });

    testWidgets('un montant sous le million s’écrit en entier', (tester) async {
      await ouvre(
        tester,
        indicateurs: <String, IndicateursSalle>{
          bahia: indicateursDeTest(revenu: 640000, datesVendues: 1),
        },
      );

      expect(find.text('640${fine}000 DA'), findsOneWidget);
      // Une seule date ne prend pas de « s ».
      expect(find.text('1 date'), findsOneWidget);
    });
  });

  group('Une demande, telle qu’elle arrive', () {
    testWidgets('le client, la date, le devis — et rien d’autre', (
      tester,
    ) async {
      await ouvre(
        tester,
        salles: <SalleDuProprietaire>[
          salleDeTest(id: bahia, demandesEnAttente: 1),
        ],
        demandes: <String, List<DemandeEnAttente>>{
          bahia: <DemandeEnAttente>[demandeDeTest(id: '1')],
        },
      );

      expect(find.text('Amina K.'), findsOneWidget);
      expect(
        find.text('14 août 2027 · soir · 300 invités · Mariage'),
        findsOneWidget,
      );
      expect(find.text('205${fine}000 DA'), findsOneWidget);
      expect(find.text('il y a 2 h'), findsOneWidget);
      expect(find.text('Nouveau'), findsOneWidget);

      // AUCUN BOUTON DE RÉPONSE SUR LA CARTE, alors que la maquette de l'écran
      // 9 en dessine deux. Ce n'est plus faute de fonctions SQL — elles
      // existent depuis 015 : accepter un mariage engage une salle pour une
      // soirée et pose une option de 72 h (§5.1), et la carte ne montre ni le
      // message du client, ni les options qu'il a cochées, ni son nom entier.
      // La décision se prend sur l'écran de détail, où tout cela est écrit.
      expect(find.text('Accepter'), findsNothing);
      expect(find.text('Refuser'), findsNothing);
      expect(find.text('Contre-proposer'), findsNothing);

      // Ce que la carte porte à la place : de quoi s'ouvrir. Le chevron est
      // cherché DANS la carte : depuis le J12, l'entrée de l'agenda en porte un
      // aussi, plus haut sur le même écran.
      expect(
        find.descendant(
          of: find.byType(Card),
          matching: find.byIcon(Icons.chevron_right),
        ),
        findsOneWidget,
      );
    });

    testWidgets('la carte ouvre le détail de SA demande', (tester) async {
      // Un vrai routeur, et non un espion sur la navigation : ce qu'on veut
      // vérifier est que la carte emmène sur la bonne demande — donc que
      // l'identifiant qu'elle met dans l'adresse est celui de sa ligne, et pas
      // celui de la première de la liste.
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final depot = DepotDeTest(
        sallesRendues: <SalleDuProprietaire>[
          salleDeTest(id: bahia, demandesEnAttente: 2),
        ],
        indicateursRendus: <String, IndicateursSalle>{
          bahia: indicateursDeTest(),
        },
        demandesRendues: <String, List<DemandeEnAttente>>{
          bahia: <DemandeEnAttente>[
            demandeDeTest(id: '1', client: 'Amina K.'),
            demandeDeTest(id: '2', client: 'Yacine M.'),
          ],
        },
        detailsRendus: <String, DemandeDetail>{
          'bkg-2': detailDeTest(
            id: '2',
            venueId: bahia,
            client: 'Yacine Meziane',
          ),
        },
      );

      final routeur = GoRouter(
        initialLocation: FerhaRoutes.proprietaireTableau,
        routes: <RouteBase>[
          GoRoute(
            path: FerhaRoutes.proprietaireTableau,
            builder: (_, _) => const TableauDeBordScreen(),
          ),
          GoRoute(
            path: FerhaRoutes.proprietaireDemande,
            builder: (_, state) =>
                DetailDemandeScreen(bookingId: state.pathParameters['id']!),
          ),
        ],
      );
      addTearDown(routeur.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            estConnecteProvider.overrideWithValue(true),
            preferencesAffichageProvider.overrideWithValue(
              PreferencesEnMemoire(bahia),
            ),
            ownerRepositoryProvider.overrideWithValue(depot),
          ],
          child: MaterialApp.router(
            theme: FerhaTheme.light(),
            routerConfig: routeur,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // La SECONDE carte, pas la première.
      await tester.tap(find.text('Yacine M.'));
      await tester.pumpAndSettle();

      expect(find.text('Yacine Meziane'), findsOneWidget);
      expect(find.byKey(cleAccepter), findsOneWidget);
    });

    testWidgets('une demande d’hier ne porte plus « Nouveau »', (tester) async {
      await ouvre(
        tester,
        salles: <SalleDuProprietaire>[
          salleDeTest(id: bahia, demandesEnAttente: 1),
        ],
        demandes: <String, List<DemandeEnAttente>>{
          bahia: <DemandeEnAttente>[
            demandeDeTest(
              id: '1',
              creeLe: DateTime.now().subtract(const Duration(days: 2)),
            ),
          ],
        },
      );

      expect(find.text('Nouveau'), findsNothing);
      expect(find.text('il y a 2 jours'), findsOneWidget);
    });
  });

  group('Le sélecteur de salle (OWN-08)', () {
    final deuxSalles = <SalleDuProprietaire>[
      salleDeTest(id: bahia, nom: 'Salle El Bahia', demandesEnAttente: 3),
      salleDeTest(id: ennour, nom: 'Salle Ennour'),
    ];

    testWidgets('une seule salle : pas de chevron à chercher', (tester) async {
      await ouvre(tester);

      expect(find.text('Salle El Bahia'), findsOneWidget);
      expect(find.byIcon(Icons.expand_more), findsNothing);
    });

    testWidgets('deux salles : le titre s’ouvre, et le choix tient', (
      tester,
    ) async {
      await ouvre(
        tester,
        salles: deuxSalles,
        indicateurs: <String, IndicateursSalle>{
          bahia: indicateursDeTest(),
          ennour: indicateursDeTest(revenu: 320000, note: null, nombreAvis: 0),
        },
      );

      expect(find.byIcon(Icons.expand_more), findsOneWidget);

      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pumpAndSettle();

      // Le nombre de demandes voyage avec la salle : le sélecteur le dit sans
      // un second appel.
      expect(find.text('3'), findsOneWidget);

      await tester.tap(find.text('Salle Ennour'));
      await tester.pumpAndSettle();

      expect(find.text('320${fine}000 DA'), findsOneWidget);
      expect(find.text('Aucun avis'), findsOneWidget);
    });
  });

  group('Ce que l’écran dit quand il n’a rien à montrer', () {
    testWidgets('un compte propriétaire sans salle', (tester) async {
      await ouvre(tester, salles: <SalleDuProprietaire>[]);

      expect(find.text('Aucune salle pour l’instant'), findsOneWidget);
      expect(find.text('Tableau de bord'), findsOneWidget);
    });

    testWidgets('un brouillon dit pourquoi ses chiffres sont à zéro', (
      tester,
    ) async {
      await ouvre(
        tester,
        salles: <SalleDuProprietaire>[
          salleDeTest(id: bahia, statut: StatutSalle.brouillon),
        ],
        indicateurs: <String, IndicateursSalle>{
          bahia: indicateursDeTest(
            tauxOccupation: null,
            variationOccupation: null,
            revenu: 0,
            datesVendues: 0,
            variationRevenu: null,
            note: null,
            nombreAvis: 0,
            tauxAcceptation: null,
            variationAcceptation: null,
            demandesTranchees: 0,
          ),
        },
      );

      expect(find.textContaining('Brouillon'), findsOneWidget);
      expect(
        find.textContaining('n’apparaît pas dans les recherches'),
        findsOneWidget,
      );
    });
  });

  testWidgets('le thème sombre s’affiche aussi', (tester) async {
    await ouvre(
      tester,
      theme: FerhaTheme.dark(),
      salles: <SalleDuProprietaire>[
        salleDeTest(id: bahia, demandesEnAttente: 1),
      ],
      demandes: <String, List<DemandeEnAttente>>{
        bahia: <DemandeEnAttente>[demandeDeTest(id: '1')],
      },
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Amina K.'), findsOneWidget);
    expect(find.text('68$fine%'), findsOneWidget);
  });
}
