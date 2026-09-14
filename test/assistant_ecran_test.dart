import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:ferha/core/l10n/direction_du_texte.dart';
import 'package:ferha/core/l10n/generated/app_localizations.dart';
import 'package:ferha/core/router/routes.dart';
import 'package:ferha/core/theme/ferha_theme.dart';
import 'package:ferha/features/assistant/assistant_messages.dart';
import 'package:ferha/features/assistant/assistant_providers.dart';
import 'package:ferha/features/assistant/assistant_repository.dart';
import 'package:ferha/features/assistant/assistant_screen.dart';
import 'package:ferha/features/assistant/message_assistant.dart';
import 'package:ferha/features/assistant/widgets/carte_salle_citee.dart';
import 'package:ferha/features/search/search_filters.dart';

import 'assistant_fakes.dart';

/// L'écran 8 — l'assistant de recherche.
///
/// LES TROIS TESTS QUI COMPTENT :
///
/// 1. UNE CARTE OUVRE LA BONNE FICHE. C'est toute la promesse de l'écran :
///    « chaque salle citée est une carte cliquable issue de la base — l'agent ne
///    peut rien nommer qui n'existe pas » (maquette). Une carte qui ouvrirait la
///    salle d'à côté serait pire qu'une carte morte : l'utilisateur irait
///    visiter le mauvais lieu.
///
/// 2. L'ENVOI EST BLOQUÉ PENDANT L'ATTENTE, et ça se voit. Sans cela, un double
///    appui coûte deux appels au modèle sur un quota gratuit — et affiche deux
///    réponses à une seule question.
///
/// 3. LES TROIS ÉCHECS SONT DITS EN TOUTES LETTRES. Quota, service endormi,
///    réseau coupé : aucune trace technique ne doit atteindre l'écran, et chacun
///    doit dire ce qu'on peut faire ensuite.
void main() {
  const bahdja = '5a11e000-0000-4000-a000-000000000001';
  const wiam = '5a11e000-0000-4000-a000-000000000002';

  /// La route qu'ouvre une carte, quand elle en ouvre une.
  String? ouverte;

  setUp(() => ouverte = null);

  /// Monte l'écran 8 dans un routeur minimal.
  ///
  /// UN VRAI `GoRouter`, ET NON UN ESPION SUR `onTap`. La carte appelle
  /// `context.push(FerhaRoutes.salleDe(id))` ; remplacer le rappel par une
  /// doublure vérifierait que le test appelle le test. Ici, c'est le routeur qui
  /// résout l'adresse, et `ouverte` porte l'identifiant qu'il a VRAIMENT extrait
  /// du chemin.
  Future<DepotAssistantDeTest> ouvre(
    WidgetTester tester, {
    ReponseAssistant? reponse,
    EchecDeLAssistant? erreur,
    bool bloquer = false,
    ThemeData? theme,
    Locale locale = const Locale('fr'),
  }) async {
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final depot = DepotAssistantDeTest(
      reponse: reponse,
      erreur: erreur,
      bloquer: bloquer,
    );

    final routeur = GoRouter(
      initialLocation: FerhaRoutes.assistant,
      routes: <RouteBase>[
        GoRoute(
          path: FerhaRoutes.assistant,
          builder: (_, _) => const AssistantScreen(),
        ),
        GoRoute(
          path: FerhaRoutes.salle,
          builder: (_, state) {
            ouverte = state.pathParameters['id'];
            return const Scaffold(body: Text('Fiche de la salle'));
          },
        ),
      ],
    );
    addTearDown(routeur.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [assistantRepositoryProvider.overrideWithValue(depot)],
        child: MaterialApp.router(
          theme: theme ?? FerhaTheme.light(),
          locale: locale,
          supportedLocales: const <Locale>[Locale('fr'), Locale('ar')],
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          routerConfig: routeur,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return depot;
  }

  /// Pose une question et laisse la réponse arriver.
  Future<void> demande(WidgetTester tester, String question) async {
    await tester.enterText(find.byKey(cleChampQuestion), question);
    await tester.pump();
    await tester.tap(find.byKey(cleEnvoyerQuestion));
    await tester.pumpAndSettle();
  }

  group('Ce que l’écran montre', () {
    testWidgets('sans question, il explique comment parler à l’assistant', (
      tester,
    ) async {
      await ouvre(tester);

      expect(find.text('Décrivez la fête que vous préparez'), findsOneWidget);
      // Un exemple en darja : c'est ainsi qu'on cherche une salle en Algérie, et
      // rien d'autre dans l'application ne le dit.
      expect(
        find.text('kayen salle f Blida fiha espace femmes ?'),
        findsOneWidget,
      );

      // AUCUNE PUCE DE RELANCE. La maquette en dessine trois ; la fonction n'en
      // renvoie aucune, et un bouton qui ne mène nulle part est pire qu'un
      // bouton absent.
      expect(find.byType(ActionChip), findsNothing);
    });

    testWidgets('la question, la réponse, et une carte par salle citée', (
      tester,
    ) async {
      await ouvre(
        tester,
        reponse: reponseDeTest(
          texte: 'J’ai compris : Oran, 300 invités. Voici 2 salles :',
          salles: <SalleCitee>[
            salleCiteeDeTest(venueId: bahdja),
            salleCiteeDeTest(
              venueId: wiam,
              nom: 'Dar El Wiam',
              commune: 'Canastel',
              capacite: 320,
              prix: 225000,
            ),
          ],
        ),
      );

      await demande(tester, 'une salle à Oran pour 300 personnes');

      expect(find.text('une salle à Oran pour 300 personnes'), findsOneWidget);
      expect(
        find.text('J’ai compris : Oran, 300 invités. Voici 2 salles :'),
        findsOneWidget,
      );

      expect(find.byKey(cleCarteSalleCitee(bahdja)), findsOneWidget);
      expect(find.byKey(cleCarteSalleCitee(wiam)), findsOneWidget);
      expect(find.text('Nour El Bahdja'), findsOneWidget);
      expect(find.text('Bir El Djir · 400'), findsOneWidget);
    });

    testWidgets('LE PRIX EST CELUI DE LA RÉPONSE, jamais un calcul', (
      tester,
    ) async {
      await ouvre(
        tester,
        // Un prix qui ne retombe sur aucune formule ronde : s'il s'affichait
        // « 180 000 » ou « 234 000 », c'est qu'un coefficient serait passé par
        // là — et une seconde formule de prix est précisément ce que le cahier
        // des charges interdit.
        reponse: reponseDeTest(
          salles: <SalleCitee>[salleCiteeDeTest(venueId: bahdja, prix: 187430)],
        ),
      );

      await demande(tester, 'combien coûte cette salle');

      // Le séparateur de milliers est une espace fine insécable (U+202F), celle
      // que `montantEnDinars()` pose partout ailleurs dans l'application : on
      // compare donc à ce qu'elle produit, et non à une chaîne écrite à la main
      // avec une espace ordinaire. Ce qui est vérifié ici est le NOMBRE, pas la
      // typographie.
      expect(find.text('${montantEnDinars(187430)} DA'), findsOneWidget);
      expect(find.textContaining('430'), findsOneWidget);
    });

    testWidgets('une salle sans prix n’affiche pas « 0 »', (tester) async {
      await ouvre(
        tester,
        reponse: reponseDeTest(
          salles: <SalleCitee>[salleCiteeDeTest(venueId: bahdja, prix: null)],
        ),
      );

      await demande(tester, 'une salle à Oran');

      expect(find.byKey(cleCarteSalleCitee(bahdja)), findsOneWidget);
      // Un zéro serait une affirmation, et une fausse : la base ne connaît pas
      // de tarif à cette salle pour ce créneau.
      expect(find.textContaining('DA'), findsNothing);
      expect(find.textContaining('0 DA'), findsNothing);
    });
  });

  group('Une carte ouvre la fiche de SA salle', () {
    testWidgets('la première carte ouvre la première salle', (tester) async {
      await ouvre(
        tester,
        reponse: reponseDeTest(
          salles: <SalleCitee>[
            salleCiteeDeTest(venueId: bahdja),
            salleCiteeDeTest(venueId: wiam, nom: 'Dar El Wiam'),
          ],
        ),
      );

      await demande(tester, 'une salle à Oran');
      await tester.tap(find.byKey(cleCarteSalleCitee(bahdja)));
      await tester.pumpAndSettle();

      expect(ouverte, bahdja);
      expect(find.text('Fiche de la salle'), findsOneWidget);
    });

    testWidgets('la SECONDE carte ouvre la SECONDE salle', (tester) async {
      // Le test qui attrape l'erreur la plus coûteuse : une rangée dont toutes
      // les cartes ouvriraient la même fiche — celle de la première, ou celle
      // capturée par une fermeture mal placée dans l'itération.
      await ouvre(
        tester,
        reponse: reponseDeTest(
          salles: <SalleCitee>[
            salleCiteeDeTest(venueId: bahdja),
            salleCiteeDeTest(venueId: wiam, nom: 'Dar El Wiam'),
          ],
        ),
      );

      await demande(tester, 'une salle à Oran');
      await tester.tap(find.byKey(cleCarteSalleCitee(wiam)));
      await tester.pumpAndSettle();

      expect(ouverte, wiam);
    });
  });

  group('L’envoi est bloqué pendant que l’assistant cherche', () {
    testWidgets('le bouton s’éteint, le champ se ferme, et ça se voit', (
      tester,
    ) async {
      final depot = await ouvre(
        tester,
        reponse: reponseDeTest(),
        bloquer: true,
      );

      await tester.enterText(find.byKey(cleChampQuestion), 'une salle à Oran');
      await tester.pump();
      await tester.tap(find.byKey(cleEnvoyerQuestion));
      await tester.pump();

      // CE QUI SE VOIT : la bulle d'attente, à l'endroit où la réponse viendra.
      expect(find.byKey(cleAssistantCherche), findsOneWidget);
      expect(find.text(assistantCherche), findsWidgets);

      // CE QUI EST BLOQUÉ : le bouton, et le champ.
      final bouton = tester.widget<IconButton>(find.byKey(cleEnvoyerQuestion));
      expect(bouton.onPressed, isNull);

      final champ = tester.widget<TextField>(find.byKey(cleChampQuestion));
      expect(champ.enabled, isFalse);

      depot.repondre();
      await tester.pumpAndSettle();
      expect(find.byKey(cleAssistantCherche), findsNothing);
    });

    testWidgets('une seconde question ne part pas', (tester) async {
      final depot = await ouvre(
        tester,
        reponse: reponseDeTest(),
        bloquer: true,
      );

      await tester.enterText(find.byKey(cleChampQuestion), 'première question');
      await tester.pump();
      await tester.tap(find.byKey(cleEnvoyerQuestion));
      await tester.pump();

      // On force le geste que l'écran empêche — un raccourci clavier, un double
      // appui sur un appareil lent. Le garde-fou du notifier doit tenir seul.
      final conteneur = ProviderScope.containerOf(
        tester.element(find.byType(AssistantScreen)),
      );
      await conteneur
          .read(conversationProvider.notifier)
          .demander('seconde question');
      await tester.pump();

      expect(depot.questions, <String>['première question']);

      depot.repondre();
      await tester.pumpAndSettle();
    });

    testWidgets('au bout de huit secondes, l’écran explique la lenteur', (
      tester,
    ) async {
      // LE CAS QUI ARRIVE QUAND TOUT VA BIEN. Le service d'empreintes s'endort
      // faute d'usage ; la première question de la journée le réveille, et cela
      // prend jusqu'à une minute. Le silence, lui, se lit comme une panne.
      final depot = await ouvre(
        tester,
        reponse: reponseDeTest(),
        bloquer: true,
      );

      await tester.enterText(find.byKey(cleChampQuestion), 'une salle à Oran');
      await tester.pump();
      await tester.tap(find.byKey(cleEnvoyerQuestion));
      await tester.pump();

      expect(find.text(assistantChercheLongtemps), findsNothing);

      await tester.pump(delaiAvantExplication + const Duration(seconds: 1));
      expect(find.text(assistantChercheLongtemps), findsOneWidget);

      depot.repondre();
      await tester.pumpAndSettle();
    });
  });

  group('Les trois échecs, en toutes lettres', () {
    /// Aucune de ces phrases ne doit contenir de trace technique.
    void aucuneTrace(WidgetTester tester) {
      for (final mot in <String>[
        'Exception',
        'SocketException',
        'status',
        '500',
        '429',
        'null',
      ]) {
        expect(
          find.textContaining(mot),
          findsNothing,
          reason: '« $mot » est une trace, pas une phrase.',
        );
      }
    }

    testWidgets('quota épuisé — il renvoie vers la recherche classique', (
      tester,
    ) async {
      // LE QUOTA ARRIVE EN 200, avec le statut « quota ». Ce n'est pas une
      // panne HTTP : l'Edge Function répond normalement, et c'est le statut qui
      // le dit. Un écran qui ne lirait que le code HTTP l'afficherait comme une
      // réponse ordinaire de l'assistant.
      await ouvre(
        tester,
        reponse: reponseDeTest(statut: 'quota', texte: '…'),
      );
      await demande(tester, 'une salle à Oran');

      expect(
        find.text(messageEchecAssistant(EchecAssistant.quota)),
        findsOneWidget,
      );
      expect(find.textContaining('recherche depuis l’accueil'), findsOneWidget);
      aucuneTrace(tester);
    });

    testWidgets('service d’empreintes endormi — il annonce la minute', (
      tester,
    ) async {
      await ouvre(
        tester,
        erreur: const EchecDeLAssistant(EchecAssistant.serviceEndormi),
      );
      await demande(tester, 'une salle à Oran');

      expect(
        find.text(messageEchecAssistant(EchecAssistant.serviceEndormi)),
        findsOneWidget,
      );
      // La phrase doit dire COMBIEN de temps, sans quoi elle ne rassure pas.
      expect(find.textContaining('une minute'), findsOneWidget);
      aucuneTrace(tester);
    });

    testWidgets('réseau coupé — rien n’est perdu, et il le dit', (
      tester,
    ) async {
      await ouvre(
        tester,
        erreur: const EchecDeLAssistant(EchecAssistant.reseau),
      );
      await demande(tester, 'une salle à Oran');

      expect(
        find.text(messageEchecAssistant(EchecAssistant.reseau)),
        findsOneWidget,
      );
      expect(find.textContaining('rien n’est perdu'), findsOneWidget);
      aucuneTrace(tester);
    });

    testWidgets('un échec n’efface pas la question posée', (tester) async {
      // Ce qu'on vient d'écrire reste à l'écran : c'est ce qui permet de
      // recommencer sans retaper, et de comprendre à quoi l'échec répondait.
      await ouvre(
        tester,
        erreur: const EchecDeLAssistant(EchecAssistant.reseau),
      );
      await demande(tester, 'une salle à Oran pour 300 personnes');

      expect(find.text('une salle à Oran pour 300 personnes'), findsOneWidget);
    });

    testWidgets('après un échec, on peut reposer sa question', (tester) async {
      final depot = await ouvre(
        tester,
        erreur: const EchecDeLAssistant(EchecAssistant.reseau),
      );
      await demande(tester, 'une salle à Oran');

      // L'échec n'est pas un état bloquant : le champ et le bouton reviennent.
      final champ = tester.widget<TextField>(find.byKey(cleChampQuestion));
      expect(champ.enabled, isTrue);

      depot.erreur = null;
      depot.reponse = reponseDeTest(texte: 'Voici ce que j’ai trouvé.');
      await demande(tester, 'une salle à Oran');

      expect(find.text('Voici ce que j’ai trouvé.'), findsOneWidget);
      expect(depot.questions.length, 2);
    });
  });

  group('Les suggestions n’existent que si la fonction en renvoie', () {
    testWidgets('aucune suggestion : aucune puce', (tester) async {
      await ouvre(tester, reponse: reponseDeTest());
      await demande(tester, 'une salle à Oran');

      expect(find.byType(ActionChip), findsNothing);
    });

    testWidgets('des suggestions : des puces, et elles relancent', (
      tester,
    ) async {
      final depot = await ouvre(
        tester,
        reponse: reponseDeTest(
          suggestions: <String>['Avec espace femmes', 'Moins de 200 000'],
        ),
      );
      await demande(tester, 'une salle à Oran');

      expect(find.byType(ActionChip), findsNWidgets(2));

      await tester.tap(find.text('Avec espace femmes'));
      await tester.pumpAndSettle();

      // Une puce POSE LA QUESTION, elle ne se contente pas de la préparer dans
      // le champ : c'est une relance, et une relance qui demande un second geste
      // n'en est pas une.
      expect(depot.questions, <String>[
        'une salle à Oran',
        'Avec espace femmes',
      ]);
    });
  });

  group('La conversation, et ce qu’elle ne garde pas', () {
    testWidgets('le bouton « effacer » vide le fil', (tester) async {
      await ouvre(tester, reponse: reponseDeTest(texte: 'Voici 3 salles.'));
      await demande(tester, 'une salle à Oran');

      expect(find.text('Voici 3 salles.'), findsOneWidget);

      await tester.tap(find.byKey(cleEffacerConversation));
      await tester.pumpAndSettle();

      expect(find.text('Voici 3 salles.'), findsNothing);
      expect(find.text('Décrivez la fête que vous préparez'), findsOneWidget);
    });

    testWidgets('« effacer » est éteint sur une conversation vide', (
      tester,
    ) async {
      await ouvre(tester);

      final bouton = tester.widget<IconButton>(
        find.byKey(cleEffacerConversation),
      );
      expect(bouton.onPressed, isNull);
    });
  });

  group('Le thème sombre et l’arabe', () {
    testWidgets('l’écran se monte en sombre', (tester) async {
      await ouvre(
        tester,
        theme: FerhaTheme.dark(),
        reponse: reponseDeTest(
          salles: <SalleCitee>[salleCiteeDeTest(venueId: bahdja)],
        ),
      );
      await demande(tester, 'une salle à Oran');

      expect(tester.takeException(), isNull);
      expect(find.byKey(cleCarteSalleCitee(bahdja)), findsOneWidget);
    });

    testWidgets('en arabe, l’écran se monte et la carte reste lisible', (
      tester,
    ) async {
      await ouvre(
        tester,
        locale: const Locale('ar'),
        reponse: reponseDeTest(
          texte: 'لقيت لك 3 قاعات فاضية في وهران.',
          salles: <SalleCitee>[salleCiteeDeTest(venueId: bahdja)],
        ),
      );
      await demande(tester, 'قاعة في وهران');

      expect(tester.takeException(), isNull);
      // LE NOM RESTE EN ÉCRITURE LATINE, même sous une réponse en arabe : c'est
      // le nom que porte l'enseigne, et celui qu'on retrouvera en cherchant.
      expect(find.text('Nour El Bahdja'), findsOneWidget);
    });

    testWidgets(
      'UNE RÉPONSE EN ARABE SE LIT DE DROITE À GAUCHE, même en français',
      (tester) async {
        // Le cas qui arrive tout le temps : l'application est en français,
        // quelqu'un écrit en darja, et l'agent répond dans SA langue. Poser ce
        // paragraphe à gauche mettrait la ponctuation du mauvais côté.
        await ouvre(
          tester,
          reponse: reponseDeTest(texte: 'لقيت لك 3 قاعات فاضية في وهران.'),
        );
        await demande(tester, 'kayen salle f wahran ?');

        final direction = tester.widget<Directionality>(
          find
              .ancestor(
                of: find.text('لقيت لك 3 قاعات فاضية في وهران.'),
                matching: find.byType(Directionality),
              )
              .first,
        );
        expect(direction.textDirection, TextDirection.rtl);
      },
    );

    testWidgets('et une réponse en français reste de gauche à droite', (
      tester,
    ) async {
      await ouvre(
        tester,
        locale: const Locale('ar'),
        reponse: reponseDeTest(texte: 'Voici 3 salles libres ce soir-là.'),
      );
      await demande(tester, 'une salle à Oran');

      final direction = tester.widget<Directionality>(
        find
            .ancestor(
              of: find.text('Voici 3 salles libres ce soir-là.'),
              matching: find.byType(Directionality),
            )
            .first,
      );
      expect(direction.textDirection, TextDirection.ltr);
    });
  });

  group('directionDuTexte', () {
    test('un texte arabe court de droite à gauche', () {
      expect(directionDuTexte('قاعة في وهران'), TextDirection.rtl);
    });

    test('un texte français court de gauche à droite', () {
      expect(directionDuTexte('Salle à Oran'), TextDirection.ltr);
    });

    test('les chiffres de tête ne décident de rien', () {
      // « 300 invités » et « 300 مدعو » commencent tous deux par un chiffre :
      // c'est le premier MOT qui tranche, comme dans l'algorithme d'Unicode.
      expect(directionDuTexte('300 invités'), TextDirection.ltr);
      expect(directionDuTexte('300 مدعو'), TextDirection.rtl);
    });

    test('un nom latin au milieu ne retourne pas une phrase arabe', () {
      // La règle 9 du prompt de l'agent fait écrire « قاعة Salle Ibn Khaldoun ».
      // Ces lettres latines sont au milieu, pas au début.
      expect(
        directionDuTexte('قاعة Salle Ibn Khaldoun في بليدة'),
        TextDirection.rtl,
      );
    });

    test('un texte sans lettre retombe sur le français', () {
      expect(directionDuTexte('250 000'), TextDirection.ltr);
      expect(directionDuTexte(''), TextDirection.ltr);
    });
  });
}
