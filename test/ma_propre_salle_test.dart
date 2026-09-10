import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ferha/core/preferences/preferences_affichage.dart';
import 'package:ferha/core/router/routes.dart';
import 'package:ferha/core/theme/ferha_theme.dart';
import 'package:ferha/features/auth/auth_providers.dart';
import 'package:ferha/features/booking/booking_messages.dart';
import 'package:ferha/features/booking/booking_providers.dart';
import 'package:ferha/features/booking/demande_screen.dart';
import 'package:ferha/features/booking/devis_reservation.dart';
import 'package:ferha/features/owner/indicateurs_salle.dart';
import 'package:ferha/features/owner/owner_repository.dart';
import 'package:ferha/features/owner/salle_du_proprietaire.dart';
import 'package:ferha/features/owner/tableau_de_bord_screen.dart';
import 'package:ferha/features/search/search_filters.dart';
import 'package:ferha/features/venue/calendrier_screen.dart';
import 'package:ferha/features/venue/venue_detail.dart';
import 'package:ferha/features/venue/venue_providers.dart';
import 'package:ferha/features/venue/venue_screen.dart';

import 'owner_fakes.dart';

/// Le propriétaire devant sa propre salle.
///
/// CE QUE CE FICHIER SURVEILLE : qu'aucun des trois écrans du parcours client
/// ne propose à un propriétaire un geste que `request_booking()` refusera
/// (FE005). Le refus de la base reste, et c'est lui la vraie garde ; ce qui est
/// testé ici est qu'on n'y conduise plus personne.
///
/// LE PROPRIÉTAIRE N'EST PAS DÉCLARÉ, IL EST DÉDUIT DE LA BASE. Aucun de ces
/// tests ne pose un booléen « je suis le propriétaire » : ils font répondre à
/// `owner_venues()` une liste de salles, et c'est la présence de la salle
/// regardée dans CETTE liste-là qui décide. C'est exactement le chemin de
/// l'application — la fiche ne dit toujours rien du propriétaire (§9), c'est le
/// lecteur qui dit ce qu'il possède.
void main() {
  const bahia = '5a11e000-0000-4000-a000-000000000001';
  const ennour = '5a11e000-0000-4000-a000-000000000002';

  final date = DateTime(2027, 8, 14);

  VenueDetail salle() => VenueDetail(
    id: bahia,
    nom: 'Salle El Bahia',
    commune: 'Oran',
    wilayaCode: '31',
    wilayaNom: 'Oran',
    capacite: 450,
    photos: const <String>[],
    equipements: const <EquipementSalle>[],
    typesEvenement: const <TypeEvenement>[
      (code: 'mariage', libelle: 'Mariage'),
    ],
    tarifs: <LigneTarif>[
      const LigneTarif(
        creneau: 'soir',
        prixBase: 220000,
        couvertsInclus: 300,
        prixCouvertSup: 900,
        coefJour: 1.3,
        coefSaison: 1.2,
        couvertsSup: 0,
        montantCouvertsSup: 0,
        total: 343200,
      ),
    ],
    options: const <OptionSalle>[],
    dateEstimation: DateTime(2027, 8, 14),
  );

  DevisReservation devis() => DevisReservation(
    date: date,
    creneau: 'soir',
    invites: 300,
    prixBase: 220000,
    coefJour: 1.3,
    coefSaison: 1.2,
    prixCreneau: 343200,
    couvertsInclus: 300,
    couvertsSup: 0,
    montantCouvertsSup: 0,
    montantOptions: 0,
    total: 343200,
    tauxAcompte: 0.25,
    montantAcompte: 85800,
    options: const <OptionSalle>[],
  );

  /// Le dépôt de l'espace propriétaire, chargé de [sesSalles].
  ///
  /// Une liste vide décrit aussi bien une cliente qu'un propriétaire venu sur
  /// la salle d'un autre : dans les deux cas `owner_venues()` ne rend pas la
  /// salle regardée, et l'écran doit rester celui du client.
  DepotDeTest depot(List<String> sesSalles) => DepotDeTest(
    sallesRendues: <SalleDuProprietaire>[
      for (final id in sesSalles)
        salleDeTest(
          id: id,
          nom: id == bahia ? 'Salle El Bahia' : 'Autre salle',
        ),
    ],
    indicateursRendus: <String, IndicateursSalle>{
      for (final id in sesSalles) id: indicateursDeTest(),
    },
  );

  /// Monte [ecran] sur un espace propriétaire qui possède [sesSalles].
  ///
  /// Les trois fournisseurs de lecture — fiche, devis, calendrier — sont posés
  /// à chaque fois, même quand l'écran n'en lit qu'un : cela coûte trois lignes
  /// et évite trois variantes de cette fonction.
  Future<void> pompe(
    WidgetTester tester,
    Widget ecran, {
    required List<String> sesSalles,
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
            PreferencesEnMemoire(),
          ),
          ownerRepositoryProvider.overrideWithValue(depot(sesSalles)),
          ficheProvider.overrideWith((ref, demande) async => salle()),
          devisProvider.overrideWith((ref, demande) async => devis()),
          calendrierProvider.overrideWith(
            (ref, demande) async => <DateTime, EtatJour>{},
          ),
        ],
        child: MaterialApp(theme: theme ?? FerhaTheme.light(), home: ecran),
      ),
    );
    await tester.pumpAndSettle();
  }

  // ---------------------------------------------------------------------------
  // 1. La fiche salle
  // ---------------------------------------------------------------------------

  group('La fiche salle', () {
    testWidgets('chez le propriétaire, la barre mène au tableau de bord', (
      tester,
    ) async {
      await pompe(
        tester,
        const VenueScreen(venueId: bahia),
        sesSalles: <String>[bahia],
      );

      expect(find.text('Gérer ma salle'), findsOneWidget);
      expect(find.text('Disponibilité'), findsNothing);
    });

    testWidgets('chez un client, la barre reste celle de la réservation', (
      tester,
    ) async {
      await pompe(
        tester,
        const VenueScreen(venueId: bahia),
        sesSalles: const <String>[],
      );

      expect(find.text('Disponibilité'), findsOneWidget);
      expect(find.text('Gérer ma salle'), findsNothing);
    });

    testWidgets('un propriétaire sur la salle d’un autre reste un client', (
      tester,
    ) async {
      await pompe(
        tester,
        const VenueScreen(venueId: bahia),
        sesSalles: <String>[ennour],
      );

      expect(find.text('Disponibilité'), findsOneWidget);
      expect(find.text('Gérer ma salle'), findsNothing);
    });

    testWidgets('l’estimation reste affichée : c’est son tarif à lui', (
      tester,
    ) async {
      await pompe(
        tester,
        const VenueScreen(venueId: bahia),
        sesSalles: <String>[bahia],
      );

      expect(find.textContaining('343'), findsWidgets);
    });
  });

  // ---------------------------------------------------------------------------
  // 2. Le tableau de bord s'ouvre SUR CETTE SALLE
  // ---------------------------------------------------------------------------

  testWidgets('« Gérer ma salle » ouvre le tableau sur la salle regardée', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final routeur = GoRouter(
      initialLocation: FerhaRoutes.salleDe(bahia),
      routes: <RouteBase>[
        GoRoute(
          path: FerhaRoutes.salle,
          builder: (context, state) =>
              VenueScreen(venueId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: FerhaRoutes.proprietaireTableau,
          builder: (context, state) => const TableauDeBordScreen(),
        ),
      ],
    );
    addTearDown(routeur.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          estConnecteProvider.overrideWithValue(true),
          // L'APPAREIL RETENAIT L'AUTRE SALLE, et c'est ce qui rend le test
          // concluant : sans le `choisir()` du bouton, le tableau de bord
          // s'ouvrirait sur Ennour alors qu'on vient de la fiche de Bahia.
          preferencesAffichageProvider.overrideWithValue(
            PreferencesEnMemoire(ennour),
          ),
          ownerRepositoryProvider.overrideWithValue(
            DepotDeTest(
              sallesRendues: <SalleDuProprietaire>[
                salleDeTest(id: bahia, nom: 'Salle El Bahia'),
                salleDeTest(id: ennour, nom: 'Salle Ennour'),
              ],
              indicateursRendus: <String, IndicateursSalle>{
                bahia: indicateursDeTest(),
                ennour: indicateursDeTest(),
              },
            ),
          ),
          ficheProvider.overrideWith((ref, demande) async => salle()),
        ],
        child: MaterialApp.router(
          theme: FerhaTheme.light(),
          routerConfig: routeur,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Gérer ma salle'));
    await tester.pumpAndSettle();

    expect(find.text('Salle El Bahia'), findsWidgets);
    expect(find.text('Salle Ennour'), findsNothing);
  });

  // ---------------------------------------------------------------------------
  // 3. Le calendrier
  // ---------------------------------------------------------------------------

  group('Le calendrier', () {
    testWidgets('chez le propriétaire, « Continuer » n’est pas proposé', (
      tester,
    ) async {
      await pompe(
        tester,
        CalendrierScreen(venueId: bahia, date: date),
        sesSalles: <String>[bahia],
      );

      expect(find.text('Gérer ma salle'), findsOneWidget);
      expect(find.text('Continuer'), findsNothing);
    });

    testWidgets('chez un client, « Continuer » est bien là', (tester) async {
      await pompe(
        tester,
        CalendrierScreen(venueId: bahia, date: date),
        sesSalles: const <String>[],
      );

      expect(find.text('Continuer'), findsOneWidget);
      expect(find.text('Gérer ma salle'), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // 4. Le formulaire de demande
  // ---------------------------------------------------------------------------

  group('Le formulaire de demande', () {
    testWidgets('chez le propriétaire, PAS DE FORMULAIRE — un état vide', (
      tester,
    ) async {
      await pompe(
        tester,
        DemandeScreen(venueId: bahia, date: date, creneau: Creneau.soir),
        sesSalles: <String>[bahia],
      );

      // Ni le bouton d'envoi, ni aucun des champs qui le précédaient : c'est
      // tout le point de la correction. Un formulaire barré au dernier moment
      // reste un formulaire qu'on a fait remplir pour rien.
      expect(find.text('Envoyer la demande'), findsNothing);
      expect(find.text('NOMBRE D’INVITÉS'), findsNothing);
      expect(find.textContaining('Aucun paiement'), findsNothing);

      expect(find.textContaining('est votre salle'), findsOneWidget);
      expect(find.text('Gérer ma salle'), findsOneWidget);
    });

    testWidgets('chez un client, le formulaire est intact', (tester) async {
      await pompe(
        tester,
        DemandeScreen(venueId: bahia, date: date, creneau: Creneau.soir),
        sesSalles: const <String>[],
      );

      expect(find.text('Envoyer la demande'), findsOneWidget);
      expect(find.text('Gérer ma salle'), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // 5. Un refus définitif éteint le bouton
  // ---------------------------------------------------------------------------

  group('Ce qu’un refus laisse faire', () {
    // Ces cinq-là portent sur la date, le créneau ou la salle, et aucun des
    // trois ne se règle depuis l'écran de demande : rappuyer rendrait mot pour
    // mot la même phrase.
    for (final code in <String>['FE001', 'FE002', 'FE003', 'FE004', 'FE005']) {
      test('$code est définitif : le bouton n’a plus rien à envoyer', () {
        final refus = refusDemande(_refusDeLaBase(code));
        expect(refus.definitif, isTrue, reason: code);
        expect(refus.message, isNotEmpty, reason: code);
      });
    }

    test('FE006 laisse une seconde chance : se reconnecter suffit', () {
      expect(refusDemande(_refusDeLaBase('FE006')).definitif, isFalse);
    });

    test('une option disparue se décoche et se renvoie', () {
      expect(refusDemande(_erreurSqlstate('23503')).definitif, isFalse);
    });

    test('un créneau non tarifé ne se rattrape pas d’ici', () {
      expect(refusDemande(_erreurSqlstate('P0002')).definitif, isTrue);
    });

    test('une panne de réseau n’éteint rien', () {
      expect(refusDemande(Exception('SocketException')).definitif, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // 6. Le thème sombre
  // ---------------------------------------------------------------------------

  testWidgets('l’état vide s’affiche aussi en thème sombre', (tester) async {
    await pompe(
      tester,
      DemandeScreen(venueId: bahia, date: date, creneau: Creneau.soir),
      sesSalles: <String>[bahia],
      theme: FerhaTheme.dark(),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Gérer ma salle'), findsOneWidget);
  });
}

/// Un refus de `request_booking()`, tel qu'il arrive par PostgREST : le code
/// Ferha dans le `hint`, un SQLSTATE `PTxxx` dans le `code`. C'est le `hint`
/// que l'application lit — voir booking_messages.dart.
PostgrestException _refusDeLaBase(String codeFerha) =>
    PostgrestException(message: 'refus', code: 'PT403', hint: codeFerha);

/// Une erreur levée SOUS `request_booking()`, qui n'a donc pas de code Ferha.
PostgrestException _erreurSqlstate(String sqlstate) =>
    PostgrestException(message: 'refus', code: sqlstate);
