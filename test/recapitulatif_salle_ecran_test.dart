import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:ferha/core/preferences/preferences_affichage.dart';
import 'package:ferha/core/router/routes.dart';
import 'package:ferha/core/theme/ferha_theme.dart';
import 'package:ferha/features/auth/auth_providers.dart';
import 'package:ferha/features/owner/owner_repository.dart';
import 'package:ferha/features/owner/recapitulatif_salle_screen.dart';
import 'package:ferha/features/owner/salle_du_proprietaire.dart';

import 'owner_fakes.dart';

/// Le récapitulatif d'un brouillon, et le numéro qu'on y demande (ADM-01).
///
/// CE QUE CE FICHIER SURVEILLE :
///
///   1. QUE « ENVOYER POUR VALIDATION » RESTE ÉTEINT SANS NUMÉRO VALIDE. ADM-01
///      demande un « propriétaire joignable » : `envoyer_salle_en_validation()`
///      (020) refuse en FE037, et un bouton allumé mènerait à ce refus après
///      coup, sur un écran où l'on croit avoir fini.
///
///   2. QUE LE NUMÉRO DU PROFIL PRÉREMPLISSE LE CHAMP. Karim a quatre salles :
///      il ne retape pas son numéro quatre fois.
///
///   3. QUE LE NUMÉRO ARRIVE AU DÉPÔT TEL QU'IL A ÉTÉ TAPÉ, espaces compris.
///      C'est `telephone_normalise()` (020) qui les retire, en base — un seul
///      endroit décide de la forme rangée.
void main() {
  const venueId = '5a11e000-0000-4000-a000-0000000000ff';

  Future<DepotDeTest> ouvre(
    WidgetTester tester, {
    String? telephoneDuProfil,
    StatutSalle statut = StatutSalle.brouillon,
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final depot = DepotDeTest(
      sallesRendues: <SalleDuProprietaire>[
        salleDeTest(id: venueId, nom: 'Salle Les Palmiers', statut: statut),
      ],
    );

    final routeur = GoRouter(
      initialLocation: FerhaRoutes.publierRecapitulatifDe(venueId),
      routes: <RouteBase>[
        GoRoute(
          path: FerhaRoutes.publierRecapitulatif,
          builder: (context, state) =>
              RecapitulatifSalleScreen(venueId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: FerhaRoutes.proprietaireTableau,
          builder: (context, state) =>
              const Scaffold(body: Text('Le tableau de bord')),
        ),
      ],
    );
    addTearDown(routeur.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          estConnecteProvider.overrideWithValue(true),
          preferencesAffichageProvider.overrideWithValue(
            PreferencesEnMemoire(),
          ),
          ownerRepositoryProvider.overrideWithValue(depot),
          profilProvider.overrideWith(
            (ref) async => telephoneDuProfil == null
                ? null
                : <String, dynamic>{'phone': telephoneDuProfil},
          ),
        ],
        child: MaterialApp.router(
          theme: theme ?? FerhaTheme.light(),
          routerConfig: routeur,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return depot;
  }

  bool envoyerEstAllume(WidgetTester tester) {
    final bouton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Envoyer pour validation'),
    );
    return bouton.onPressed != null;
  }

  Finder champTelephone() => find.byType(TextField);

  group('Le téléphone, et le bouton qu’il commande', () {
    testWidgets('sans numéro, le bouton est éteint et dit ce qui manque', (
      tester,
    ) async {
      await ouvre(tester);

      expect(envoyerEstAllume(tester), isFalse);
      expect(find.text('Indiquez un numéro de téléphone.'), findsOneWidget);
      expect(find.text('TÉLÉPHONE POUR VOUS JOINDRE'), findsOneWidget);

      // À QUOI IL SERT, ET QUI D'AUTRE LE VERRA. Les deux questions qu'on se
      // pose devant un champ de téléphone, répondues avant qu'on les pose.
      expect(
        find.text(
          'L’équipe Ferha vous appelle pour vérifier votre salle. Vos clients '
          'ne le voient qu’après avoir accepté une réservation.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('un numéro incomplet n’allume pas le bouton', (tester) async {
      await ouvre(tester);

      await tester.enterText(champTelephone(), '0770 11');
      await tester.pumpAndSettle();

      expect(envoyerEstAllume(tester), isFalse);
      // Un exemple, pas une règle : c'est ce qui se recopie.
      expect(find.textContaining('0770 11 22 33'), findsWidgets);
    });

    testWidgets('un numéro valide allume le bouton', (tester) async {
      await ouvre(tester);

      await tester.enterText(champTelephone(), '0770 11 22 33');
      await tester.pumpAndSettle();

      expect(envoyerEstAllume(tester), isTrue);
      expect(find.text('Indiquez un numéro de téléphone.'), findsNothing);
    });

    testWidgets('un fixe est un numéro comme un autre', (tester) async {
      await ouvre(tester);

      await tester.enterText(champTelephone(), '041 23 45 67');
      await tester.pumpAndSettle();

      expect(envoyerEstAllume(tester), isTrue);
    });
  });

  group('Ce qui part vers la base', () {
    testWidgets('le numéro du profil préremplit le champ', (tester) async {
      // Karim a quatre salles. Il ne retape pas son numéro quatre fois — et le
      // bouton est allumé d'emblée, puisque le numéro du profil est valide.
      await ouvre(tester, telephoneDuProfil: '0770112233');

      expect(find.text('0770112233'), findsOneWidget);
      expect(envoyerEstAllume(tester), isTrue);
    });

    testWidgets('le numéro part tel qu’il a été tapé, espaces compris', (
      tester,
    ) async {
      // Les espaces sont retirés par `telephone_normalise()` (020), en base et
      // à un seul endroit. Les nettoyer ici ferait un second endroit où la
      // forme rangée se décide, et les deux finiraient par différer.
      final depot = await ouvre(tester);

      await tester.enterText(champTelephone(), '0770 11 22 33');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Envoyer pour validation'));
      await tester.pumpAndSettle();

      expect(depot.envoyees, hasLength(1));
      expect(depot.envoyees.single.venueId, venueId);
      expect(depot.envoyees.single.telephone, '0770 11 22 33');
    });

    testWidgets('une correction du champ efface le refus précédent', (
      tester,
    ) async {
      // Le refus reprochait le numéro ; on vient de le changer. Le laisser à
      // l'écran ferait croire que la correction n'a pas été prise.
      final depot = await ouvre(tester);
      depot.erreurDePublication = StateError('réseau');

      await tester.enterText(champTelephone(), '0770 11 22 33');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Envoyer pour validation'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.error_outline), findsOneWidget);

      await tester.enterText(champTelephone(), '0661 44 55 66');
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.error_outline), findsNothing);
    });
  });

  group('Une salle déjà envoyée', () {
    testWidgets('n’a plus ni bouton ni champ à remplir', (tester) async {
      // On arrive ici par un lien direct, ou en revenant en arrière après
      // l'envoi. Il n'y a plus rien à demander : le numéro est déjà parti avec
      // la salle.
      await ouvre(tester, statut: StatutSalle.enValidation);

      expect(find.text('Envoyer pour validation'), findsNothing);
      expect(champTelephone(), findsNothing);
      expect(find.text('Mes salles'), findsOneWidget);
    });
  });

  testWidgets('le récapitulatif s’affiche aussi en thème sombre', (
    tester,
  ) async {
    await ouvre(tester, theme: FerhaTheme.dark());

    expect(tester.takeException(), isNull);
    expect(find.text('Salle Les Palmiers'), findsOneWidget);
  });
}
