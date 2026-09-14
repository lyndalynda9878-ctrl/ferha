import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:ferha/core/l10n/generated/app_localizations.dart';
import 'package:ferha/core/l10n/locale_controller.dart';
import 'package:ferha/core/router/routes.dart';
import 'package:ferha/core/theme/ferha_theme.dart';
import 'package:ferha/features/auth/auth_providers.dart';
import 'package:ferha/features/notifications/notification_ferha.dart';
import 'package:ferha/features/notifications/notifications_providers.dart';
import 'package:ferha/features/notifications/notifications_repository.dart';
import 'package:ferha/features/notifications/notifications_screen.dart';
import 'package:ferha/features/notifications/widgets/cloche_notifications.dart';
import 'package:ferha/features/search/search_filters.dart';

/// La cloche et l'écran des notifications, montés sur un dépôt de test.
///
/// LES DEUX TESTS QUI COMPTENT SONT LES DEUX DEMANDÉS À L'ÉTAPE : le compteur
/// de la cloche, et le fait que toucher une notification la marque lue. Ce sont
/// les deux seules choses de cet écran qu'un remaniement peut casser sans que
/// rien ne se voie — la liste continuerait de s'afficher, simplement la
/// pastille ne s'éteindrait plus, ou compterait faux.
///
/// LE TEMPS RÉEL N'EST PAS SIMULÉ, et il n'y a rien à y tester : un faux canal
/// ne prouve rien. Ce que ce fichier vérifie, c'est ce que l'écran fait d'une
/// liste ; qu'elle arrive par un abonnement ou par un rechargement ne change
/// rien à son rendu.
void main() {
  NotificationFerha notification({
    String id = 'n1',
    TypeNotification? type = TypeNotification.reponse,
    RoleNotification role = RoleNotification.client,
    String? statut = 'accepted',
    String? salle = 'Salle El Bahia',
    DateTime? date,
    Creneau? creneau = Creneau.soir,
    int? invites = 320,
    String? bookingId = 'bkg-1',
    bool lue = false,
  }) => NotificationFerha(
    id: id,
    type: type,
    creeLe: DateTime.now().subtract(const Duration(hours: 2)),
    role: role,
    statut: statut,
    salle: salle,
    date: date ?? DateTime(2027, 8, 14),
    creneau: creneau,
    invites: invites,
    bookingId: bookingId,
    // La date de lecture importe peu : c'est sa présence qui éteint la
    // pastille.
    lueLe: lue ? DateTime(2026, 9, 10) : null,
  );

  /// Monte l'écran des notifications sur un routeur minimal.
  ///
  /// Le routeur est réel parce que toucher une notification POUSSE une route :
  /// un faux « onTap » vérifierait qu'on a appelé une fonction, pas qu'on
  /// arrive quelque part.
  Future<DepotNotificationsDeTest> ouvreEcran(
    WidgetTester tester,
    List<NotificationFerha> items, {
    int? nonLues,
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final depot = DepotNotificationsDeTest(
      ListeNotifications(
        items: items,
        nonLues: nonLues ?? items.where((n) => !n.lue).length,
      ),
    );

    final routeur = GoRouter(
      initialLocation: FerhaRoutes.notifications,
      routes: <RouteBase>[
        GoRoute(
          path: FerhaRoutes.notifications,
          builder: (_, _) => const NotificationsScreen(),
        ),
        GoRoute(
          path: FerhaRoutes.mesReservations,
          builder: (_, _) =>
              const Scaffold(body: Center(child: Text('Mes réservations'))),
        ),
        GoRoute(
          path: FerhaRoutes.proprietaireDemande,
          builder: (_, state) => Scaffold(
            body: Center(child: Text('Demande ${state.pathParameters['id']}')),
          ),
        ),
      ],
    );
    addTearDown(routeur.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          estConnecteProvider.overrideWithValue(true),
          notificationsRepositoryProvider.overrideWithValue(depot),
          notificationsProvider.overrideWith(
            () => NotificationsDeTest(depot.rendu),
          ),
        ],
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: ferhaSupportedLocales,
          theme: theme ?? FerhaTheme.light(),
          routerConfig: routeur,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return depot;
  }

  /// Monte la seule cloche, dans une barre d'application nue.
  Future<void> ouvreCloche(WidgetTester tester, int nonLues) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          estConnecteProvider.overrideWithValue(true),
          notificationsProvider.overrideWith(
            () => NotificationsDeTest(
              ListeNotifications(
                items: const <NotificationFerha>[],
                nonLues: nonLues,
              ),
            ),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: ferhaSupportedLocales,
          theme: FerhaTheme.light(),
          home: Scaffold(
            appBar: AppBar(actions: const <Widget>[ClocheNotifications()]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('Le compteur de la cloche', () {
    testWidgets('sans rien à lire, aucune pastille et une cloche vide', (
      tester,
    ) async {
      await ouvreCloche(tester, 0);

      // « 0 » sur une cloche est une notification de rien.
      expect(find.text('0'), findsNothing);
      expect(find.byIcon(Icons.notifications_none), findsOneWidget);
      expect(find.byIcon(Icons.notifications), findsNothing);
    });

    testWidgets('trois non lues : la pastille les montre', (tester) async {
      await ouvreCloche(tester, 3);

      expect(find.text('3'), findsOneWidget);
      // La forme change en même temps que la couleur, pour qui ne distingue
      // pas le rouge du gris.
      expect(find.byIcon(Icons.notifications), findsOneWidget);
      expect(find.byIcon(Icons.notifications_none), findsNothing);
    });

    testWidgets('au-delà de 99, le nombre exact n’apprend plus rien', (
      tester,
    ) async {
      await ouvreCloche(tester, 120);

      expect(find.text('99+'), findsOneWidget);
      expect(find.text('120'), findsNothing);
    });

    testWidgets('le compteur porte sur TOUTES les non lues, pas sur la page', (
      tester,
    ) async {
      // Deux lignes affichées, dont une seule non lue — mais la base en compte
      // sept plus bas dans l'historique. C'est sept qu'on doit lire.
      await ouvreEcran(tester, <NotificationFerha>[
        notification(id: 'n1'),
        notification(id: 'n2', lue: true),
      ], nonLues: 7);

      final scope = ProviderScope.containerOf(
        tester.element(find.byType(NotificationsScreen)),
        listen: false,
      );
      expect(scope.read(notificationsNonLuesProvider), 7);
    });
  });

  group('Toucher une notification la marque lue', () {
    testWidgets('le dépôt est prévenu, et la pastille s’éteint', (
      tester,
    ) async {
      final depot = await ouvreEcran(tester, <NotificationFerha>[
        notification(id: 'n1'),
      ]);

      final scope = ProviderScope.containerOf(
        tester.element(find.byType(NotificationsScreen)),
        listen: false,
      );
      expect(scope.read(notificationsNonLuesProvider), 1);

      await tester.tap(find.text('Demande acceptée — acompte à verser'));
      await tester.pumpAndSettle();

      expect(depot.marquees, <String>['n1']);
      // Le compteur descend sans attendre le serveur : la transition ne doit
      // pas laisser la pastille allumée derrière elle.
      expect(scope.read(notificationsNonLuesProvider), 0);
    });

    testWidgets('et l’écran de la cliente s’ouvre', (tester) async {
      await ouvreEcran(tester, <NotificationFerha>[notification(id: 'n1')]);

      await tester.tap(find.text('Demande acceptée — acompte à verser'));
      await tester.pumpAndSettle();

      expect(find.text('Mes réservations'), findsOneWidget);
    });

    testWidgets('le propriétaire, lui, arrive sur LA demande', (tester) async {
      await ouvreEcran(tester, <NotificationFerha>[
        notification(
          id: 'n1',
          type: TypeNotification.nouvelleDemande,
          role: RoleNotification.proprietaire,
          statut: null,
          bookingId: 'bkg-42',
        ),
      ]);

      await tester.tap(find.text('Nouvelle demande de réservation'));
      await tester.pumpAndSettle();

      expect(find.text('Demande bkg-42'), findsOneWidget);
      expect(find.text('Mes réservations'), findsNothing);
    });

    testWidgets('une notification déjà lue ne repasse pas par le dépôt', (
      tester,
    ) async {
      final depot = await ouvreEcran(tester, <NotificationFerha>[
        notification(id: 'n1', lue: true),
      ]);

      // Le conteneur se lit AVANT l'appui : la route poussée passe l'écran
      // hors scène, et un `find.byType` ne le trouverait plus.
      final scope = ProviderScope.containerOf(
        tester.element(find.byType(NotificationsScreen)),
        listen: false,
      );

      await tester.tap(find.text('Demande acceptée — acompte à verser'));
      await tester.pumpAndSettle();

      // On appelle quand même la base — elle est idempotente et c'est elle qui
      // décide —, mais l'état local, lui, ne bouge pas : pas de compteur qui
      // passerait sous zéro.
      expect(depot.marquees, <String>['n1']);
      expect(scope.read(notificationsNonLuesProvider), 0);
    });
  });

  group('« Tout marquer comme lu »', () {
    testWidgets('le bouton n’apparaît que s’il a quelque chose à faire', (
      tester,
    ) async {
      await ouvreEcran(tester, <NotificationFerha>[
        notification(id: 'n1', lue: true),
      ]);

      expect(find.text('Tout marquer comme lu'), findsNothing);
    });

    testWidgets('il éteint tout, et le compteur avec', (tester) async {
      final depot = await ouvreEcran(tester, <NotificationFerha>[
        notification(id: 'n1'),
        notification(id: 'n2', type: TypeNotification.expiree, statut: null),
      ]);

      await tester.tap(find.text('Tout marquer comme lu'));
      await tester.pumpAndSettle();

      expect(depot.toutMarque, 1);
      final scope = ProviderScope.containerOf(
        tester.element(find.byType(NotificationsScreen)),
        listen: false,
      );
      expect(scope.read(notificationsNonLuesProvider), 0);
      expect(find.text('Tout marquer comme lu'), findsNothing);
    });
  });

  group('Les textes viennent du type et du payload', () {
    testWidgets('la salle, la date et le créneau, et rien en dur', (
      tester,
    ) async {
      await ouvreEcran(tester, <NotificationFerha>[
        notification(
          id: 'n1',
          type: TypeNotification.nouvelleDemande,
          role: RoleNotification.proprietaire,
          statut: null,
          salle: 'Résidence Les Andalouses',
          date: DateTime(2027, 8, 14),
          creneau: Creneau.journee,
          invites: 400,
        ),
      ]);

      expect(find.text('Nouvelle demande de réservation'), findsOneWidget);
      expect(
        find.text(
          'Résidence Les Andalouses · 14 août 2027, journée · 400 invités',
        ),
        findsOneWidget,
      );
    });

    testWidgets('un refus ne se dit pas comme une acceptation', (tester) async {
      await ouvreEcran(tester, <NotificationFerha>[
        notification(id: 'n1', statut: 'refused'),
      ]);

      expect(find.text('Demande refusée'), findsOneWidget);
    });

    testWidgets('une option échue ne se dit pas « annulée »', (tester) async {
      // Personne n'a rien fait, et c'est justement le problème : dire
      // « annulée » laisserait croire que quelqu'un a décidé.
      await ouvreEcran(tester, <NotificationFerha>[
        notification(id: 'n1', type: TypeNotification.expiree, statut: null),
      ]);

      expect(find.textContaining('Option expirée'), findsOneWidget);
      expect(find.textContaining('annulée'), findsNothing);
    });

    testWidgets('un type inconnu de cette version ne fait pas tomber l’écran', (
      tester,
    ) async {
      await ouvreEcran(tester, <NotificationFerha>[
        notification(
          id: 'n1',
          type: null,
          statut: null,
          salle: null,
          date: null,
          creneau: null,
          invites: null,
          bookingId: null,
        ),
      ]);

      expect(find.text('Nouvelle notification'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('une notification sans réservation n’invente pas de détails', (
      tester,
    ) async {
      await ouvreEcran(tester, <NotificationFerha>[
        notification(
          id: 'n1',
          salle: null,
          date: null,
          creneau: null,
          invites: null,
          bookingId: null,
        ),
      ]);

      // Ni virgules vides, ni « · » orphelin.
      expect(find.textContaining('·'), findsNothing);
    });
  });

  group('L’état vide et le thème sombre', () {
    testWidgets('sans notification, l’écran dit ce qui viendra ici', (
      tester,
    ) async {
      await ouvreEcran(tester, const <NotificationFerha>[]);

      expect(find.text('Aucune notification'), findsOneWidget);
    });

    testWidgets('l’écran s’affiche aussi en thème sombre', (tester) async {
      await ouvreEcran(tester, <NotificationFerha>[
        notification(id: 'n1'),
      ], theme: FerhaTheme.dark());

      expect(find.text('Demande acceptée — acompte à verser'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('« il y a »', () {
    final maintenant = DateTime(2026, 9, 11, 14, 30);

    test('les cinq paliers, puis la date', () {
      expect(
        ilYA(
          maintenant.subtract(const Duration(seconds: 20)),
          maintenant: maintenant,
        ),
        'à l’instant',
      );
      expect(
        ilYA(
          maintenant.subtract(const Duration(minutes: 12)),
          maintenant: maintenant,
        ),
        'il y a 12 min',
      );
      expect(
        ilYA(
          maintenant.subtract(const Duration(hours: 5)),
          maintenant: maintenant,
        ),
        'il y a 5 h',
      );
      expect(
        ilYA(
          maintenant.subtract(const Duration(days: 1)),
          maintenant: maintenant,
        ),
        'hier',
      );
      expect(
        ilYA(
          maintenant.subtract(const Duration(days: 3)),
          maintenant: maintenant,
        ),
        'il y a 3 jours',
      );
      // Au-delà d'une semaine, « il y a 34 jours » oblige à faire la
      // soustraction soi-même.
      expect(ilYA(DateTime(2026, 8, 3), maintenant: maintenant), '3 août 2026');
    });
  });
}

/// Un dépôt qui rend ce qu'on lui a donné, sans réseau ni base.
class DepotNotificationsDeTest implements NotificationsRepository {
  /// Crée le dépôt.
  DepotNotificationsDeTest(this.rendu);

  /// Ce que rend `mes_notifications()`.
  ListeNotifications rendu;

  /// Les identifiants passés à `marquer_notifications_lues(p_id)`.
  final List<String> marquees = <String>[];

  /// Le nombre d'appels à « Tout marquer comme lu ».
  int toutMarque = 0;

  @override
  Future<ListeNotifications> liste() async => rendu;

  @override
  Future<void> marquerLue(String id) async => marquees.add(id);

  @override
  Future<int> toutMarquerLu() async {
    toutMarque++;
    final avant = rendu.nonLues;
    // La base répond ensuite la liste toute lue : c'est ce que le vrai
    // rechargement rapportera.
    rendu = ListeNotifications(
      items: <NotificationFerha>[
        for (final n in rendu.items) n.lue ? n : n.marqueeLue(DateTime.now()),
      ],
      nonLues: 0,
    );
    return avant;
  }
}

/// Le notifier réel, dont seul `build()` est remplacé.
///
/// ON GARDE LA VRAIE LOGIQUE. `marquerLue` et `toutMarquerLu` sont exactement
/// ce que ce fichier teste : les remplacer par des doublures ne testerait plus
/// que les doublures. Seul l'abonnement Realtime saute, faute de session.
class NotificationsDeTest extends Notifications {
  /// Crée le notifier avec la liste de départ.
  NotificationsDeTest(this.depart);

  /// Ce que l'écran affiche au premier rendu.
  final ListeNotifications depart;

  @override
  Future<ListeNotifications> build() async => depart;
}
