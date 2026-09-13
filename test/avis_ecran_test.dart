import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ferha/core/preferences/preferences_affichage.dart';
import 'package:ferha/core/theme/ferha_theme.dart';
import 'package:ferha/features/auth/auth_providers.dart';
import 'package:ferha/features/owner/indicateurs_salle.dart';
import 'package:ferha/features/owner/owner_repository.dart';
import 'package:ferha/features/owner/salle_du_proprietaire.dart';
import 'package:ferha/features/reviews/avis.dart';
import 'package:ferha/features/reviews/avis_repository.dart';
import 'package:ferha/features/reviews/avis_screen.dart';

import 'avis_fakes.dart';
import 'owner_fakes.dart';

/// L'écran 7 — les avis d'une salle.
///
/// LE TEST LE PLUS IMPORTANT DE CE FICHIER EST « AUCUNE SYNTHÈSE IA ». La
/// maquette dessine un encart « ✦ Synthèse des 34 avis », pré-calculé la nuit
/// par un index sémantique qui n'existe pas encore (J21). Il serait facile de
/// poser le cadre maintenant « pour que ce soit prêt » — et un cadre vide dit au
/// visiteur que l'application est inachevée, plus fort que son absence. Ce test
/// est là pour que personne ne l'ajoute par distraction.
///
/// LE SECOND EST CELUI DU BOUTON « Répondre ». Il ne doit apparaître que sur les
/// avis d'une salle que le lecteur possède, et jamais sur un avis déjà répondu :
/// le §4.3 en donne UNE, et proposer la seconde mènerait à un refus FE082.
void main() {
  const bahia = '5a11e000-0000-4000-a000-000000000001';

  /// Monte l'écran 7.
  ///
  /// [proprietaire] décide de ce que voit le lecteur : le dépôt propriétaire
  /// rend la salle ou ne la rend pas, exactement comme `owner_venues()` le
  /// ferait. C'est `estMaSalleProvider` qui en déduit le reste — on ne triche
  /// pas en surchargeant directement le booléen.
  Future<DepotAvisDeTest> ouvre(
    WidgetTester tester,
    AvisDeLaSalle salle, {
    bool proprietaire = false,
    ThemeData? theme,
    Object? erreurDeReponse,
  }) async {
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final depot = DepotAvisDeTest(
      salles: <String, AvisDeLaSalle>{salle.venueId: salle},
      erreurDeReponse: erreurDeReponse,
    );

    final depotProprietaire = DepotDeTest(
      sallesRendues: proprietaire
          ? <SalleDuProprietaire>[salleDeTest(id: salle.venueId)]
          : const <SalleDuProprietaire>[],
      indicateursRendus: <String, IndicateursSalle>{
        salle.venueId: indicateursDeTest(),
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          estConnecteProvider.overrideWithValue(proprietaire),
          preferencesAffichageProvider.overrideWithValue(
            PreferencesEnMemoire(salle.venueId),
          ),
          ownerRepositoryProvider.overrideWithValue(depotProprietaire),
          avisRepositoryProvider.overrideWithValue(depot),
        ],
        child: MaterialApp(
          theme: theme ?? FerhaTheme.light(),
          home: AvisScreen(venueId: salle.venueId),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return depot;
  }

  group('Ce que l’écran montre', () {
    testWidgets('la note, le compte, les quatre sous-notes et la liste', (
      tester,
    ) async {
      await ouvre(
        tester,
        avisDeLaSalleDeTest(
          venueId: bahia,
          note: 4.6,
          nombre: 34,
          avis: <AvisPublie>[
            avisDeTest(
              id: 'a1',
              auteur: 'Sarah B.',
              commentaire: 'Salle impeccable, le personnel a tout installé.',
              publieLe: DateTime(2026, 8, 20),
            ),
          ],
        ),
      );

      // « Avis · 34 », comme la maquette.
      expect(find.text('Avis · 34'), findsOneWidget);
      // La virgule décimale, pas le point : on écrit en français.
      expect(find.text('4,6'), findsOneWidget);
      expect(find.text('34 avis'), findsOneWidget);

      for (final libelle in <String>[
        'Propreté',
        'Service',
        'Rapport q/p',
        'Conformité',
      ]) {
        expect(find.text(libelle), findsOneWidget);
      }

      expect(find.text('Sarah B.'), findsOneWidget);
      expect(find.text('SB'), findsOneWidget);
      expect(find.text('août 2026'), findsOneWidget);
      expect(
        find.text('Salle impeccable, le personnel a tout installé.'),
        findsOneWidget,
      );

      // La phrase qui porte toute la règle du §5.4 : il n'existe pas d'avis non
      // vérifié dans Ferha, et le lecteur doit le savoir.
      expect(find.text('Réservation vérifiée'), findsOneWidget);
    });

    testWidgets('AUCUN bloc « synthèse IA » — elle arrive au J21', (
      tester,
    ) async {
      await ouvre(
        tester,
        avisDeLaSalleDeTest(
          venueId: bahia,
          nombre: 34,
          avis: <AvisPublie>[avisDeTest(id: 'a1')],
        ),
      );

      // Un cadre vide dirait que l'application est inachevée. Tant que l'index
      // sémantique n'existe pas, il n'y a rien à dessiner ici.
      expect(find.textContaining('Synthèse'), findsNothing);
      expect(find.textContaining('synthèse'), findsNothing);
      expect(find.textContaining('✦'), findsNothing);
    });

    testWidgets('la réponse du propriétaire s’affiche sous son avis', (
      tester,
    ) async {
      await ouvre(
        tester,
        avisDeLaSalleDeTest(
          venueId: bahia,
          nombre: 2,
          avis: <AvisPublie>[
            avisDeTest(
              id: 'a1',
              auteur: 'Mohamed T.',
              note: 4,
              commentaire: 'Il faisait chaud vers minuit.',
              reponse: 'Nous avons ajouté deux climatiseurs en septembre.',
            ),
          ],
        ),
      );

      expect(find.text('Réponse du propriétaire'), findsOneWidget);
      expect(
        find.text('Nous avons ajouté deux climatiseurs en septembre.'),
        findsOneWidget,
      );
    });

    testWidgets('une sous-note absente n’a pas de barre', (tester) async {
      await ouvre(
        tester,
        avisDeLaSalleDeTest(
          venueId: bahia,
          nombre: 3,
          // Personne n'a noté le rapport qualité/prix ni la conformité.
          moyennes: const <SousNote, double>{
            SousNote.proprete: 4.8,
            SousNote.service: 4.4,
          },
          avis: <AvisPublie>[avisDeTest(id: 'a1')],
        ),
      );

      expect(find.text('Propreté'), findsOneWidget);
      expect(find.text('Service'), findsOneWidget);
      // Une barre à zéro se lirait « 0 sur 5 », c'est-à-dire le contraire de
      // « on ne sait pas ».
      expect(find.text('Rapport q/p'), findsNothing);
      expect(find.text('Conformité'), findsNothing);
    });

    testWidgets('une salle neuve dit qu’il n’y a rien, pas qu’elle vaut 0', (
      tester,
    ) async {
      await ouvre(
        tester,
        avisDeLaSalleDeTest(
          venueId: bahia,
          note: null,
          nombre: 0,
          moyennes: const <SousNote, double>{},
        ),
      );

      expect(find.text('Aucun avis pour l’instant'), findsOneWidget);
      expect(find.text('0,0'), findsNothing);
      // Le titre ne compte pas non plus : « Avis · 0 » se lirait comme une
      // réponse, et c'en est une qu'on préfère écrire en toutes lettres.
      expect(find.text('Avis · 0'), findsNothing);
      expect(find.text('Avis'), findsOneWidget);
    });
  });

  group('Le droit de réponse (§4.3, OWN-06)', () {
    testWidgets('un visiteur ne voit aucun bouton « Répondre »', (
      tester,
    ) async {
      await ouvre(
        tester,
        avisDeLaSalleDeTest(
          venueId: bahia,
          nombre: 1,
          avis: <AvisPublie>[avisDeTest(id: 'a1')],
        ),
      );

      expect(find.byKey(cleRepondreAvis('a1')), findsNothing);
    });

    testWidgets('le propriétaire de la salle, si', (tester) async {
      await ouvre(
        tester,
        avisDeLaSalleDeTest(
          venueId: bahia,
          nombre: 1,
          avis: <AvisPublie>[avisDeTest(id: 'a1')],
        ),
        proprietaire: true,
      );

      expect(find.byKey(cleRepondreAvis('a1')), findsOneWidget);
    });

    testWidgets('mais jamais sur un avis auquel il a déjà répondu', (
      tester,
    ) async {
      await ouvre(
        tester,
        avisDeLaSalleDeTest(
          venueId: bahia,
          nombre: 2,
          avis: <AvisPublie>[
            avisDeTest(id: 'a1'),
            avisDeTest(id: 'a2', reponse: 'Merci, à bientôt.'),
          ],
        ),
        proprietaire: true,
      );

      expect(find.byKey(cleRepondreAvis('a1')), findsOneWidget);
      // Le §4.3 en donne UNE. Proposer la seconde mènerait à FE082.
      expect(find.byKey(cleRepondreAvis('a2')), findsNothing);
    });

    testWidgets('la réponse part telle qu’elle a été écrite', (tester) async {
      final depot = await ouvre(
        tester,
        avisDeLaSalleDeTest(
          venueId: bahia,
          nombre: 1,
          avis: <AvisPublie>[avisDeTest(id: 'a1')],
        ),
        proprietaire: true,
      );

      await tester.tap(find.byKey(cleRepondreAvis('a1')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(cleChampReponse),
        '  Merci Amina, à très bientôt.  ',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(cleEnvoyerReponse));
      await tester.pumpAndSettle();

      expect(depot.reponses, hasLength(1));
      expect(depot.reponses.single.avisId, 'a1');
      // Détourée de ses espaces avant l'envoi : la base refuse une réponse vide
      // (FE083), et « trois espaces » ne doit pas compter comme un texte.
      expect(depot.reponses.single.texte, 'Merci Amina, à très bientôt.');
    });

    testWidgets('une réponse vide ne se publie pas', (tester) async {
      final depot = await ouvre(
        tester,
        avisDeLaSalleDeTest(
          venueId: bahia,
          nombre: 1,
          avis: <AvisPublie>[avisDeTest(id: 'a1')],
        ),
        proprietaire: true,
      );

      await tester.tap(find.byKey(cleRepondreAvis('a1')));
      await tester.pumpAndSettle();

      // Le bouton est éteint : un bouton allumé qui mène à un refus est une
      // promesse non tenue.
      final bouton = tester.widget<FilledButton>(find.byKey(cleEnvoyerReponse));
      expect(bouton.onPressed, isNull);

      await tester.enterText(find.byKey(cleChampReponse), '   ');
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byKey(cleEnvoyerReponse)).onPressed,
        isNull,
      );

      expect(depot.reponses, isEmpty);
    });

    testWidgets('FE082 est traduit, et ne gronde personne', (tester) async {
      await ouvre(
        tester,
        avisDeLaSalleDeTest(
          venueId: bahia,
          nombre: 1,
          avis: <AvisPublie>[avisDeTest(id: 'a1')],
        ),
        proprietaire: true,
        erreurDeReponse: const PostgrestException(
          message: 'Vous avez déjà répondu à cet avis.',
          code: 'PT409',
          hint: 'FE082',
        ),
      );

      await tester.tap(find.byKey(cleRepondreAvis('a1')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(cleChampReponse), 'Merci.');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(cleEnvoyerReponse));
      await tester.pumpAndSettle();

      // La phrase de l'application, jamais celle de la base.
      expect(
        find.textContaining('Vous avez déjà répondu à cet avis'),
        findsOneWidget,
      );
      expect(find.textContaining('§4.3'), findsNothing);
    });
  });

  testWidgets('l’écran s’affiche aussi en thème sombre', (tester) async {
    await ouvre(
      tester,
      avisDeLaSalleDeTest(
        venueId: bahia,
        nombre: 2,
        avis: <AvisPublie>[
          avisDeTest(id: 'a1'),
          avisDeTest(id: 'a2', reponse: 'Merci.'),
        ],
      ),
      theme: FerhaTheme.dark(),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Avis · 2'), findsOneWidget);
  });
}
