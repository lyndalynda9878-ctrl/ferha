import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ferha/core/theme/ferha_theme.dart';
import 'package:ferha/features/reviews/avis.dart';
import 'package:ferha/features/reviews/avis_repository.dart';
import 'package:ferha/features/reviews/deposer_avis_screen.dart';

import 'avis_fakes.dart';

/// L'écran de dépôt d'un avis — « Racontez votre soirée » (§4.2, CLI-08).
///
/// LE TEST LE PLUS IMPORTANT DE CE FICHIER EST CELUI DE L'AVIS FIGÉ. Le §5.4 dit
/// qu'un avis n'est plus modifiable après la réponse du propriétaire, et la base
/// le refuse (FE078). Mais un écran qui laisserait quand même écrire ferait
/// taper trois paragraphes pour se voir refuser à l'envoi — et le client
/// croirait avoir perdu son texte. L'écran doit donc être en lecture seule, ET
/// dire pourquoi.
///
/// LE SECOND EST « CE QUI PART VERS LA BASE ». Les tests regardent ce qui ARRIVE
/// au dépôt, pas ce que l'écran affiche : une sous-note effacée doit arriver
/// absente, et un commentaire vide doit arriver à `null`.
void main() {
  const bahia = '5a11e000-0000-4000-a000-000000000001';
  const booking = 'bkg-1';

  Future<DepotAvisDeTest> ouvre(
    WidgetTester tester,
    AvisADeposer avis, {
    ThemeData? theme,
    Object? erreurDeDepot,
    Object? erreurDeLecture,
  }) async {
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final depot = DepotAvisDeTest(
      aDeposerRendus: <String, AvisADeposer>{avis.bookingId: avis},
      erreurDeDepot: erreurDeDepot,
      erreurDeLecture: erreurDeLecture,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [avisRepositoryProvider.overrideWithValue(depot)],
        child: MaterialApp(
          theme: theme ?? FerhaTheme.light(),
          home: DeposerAvisScreen(bookingId: avis.bookingId),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return depot;
  }

  /// Appuie sur la n-ième étoile d'un sélecteur.
  Future<void> etoile(WidgetTester tester, String cle, int n) async {
    await tester.tap(find.byKey(Key('etoile-$cle-$n')));
    await tester.pumpAndSettle();
  }

  Future<void> publie(WidgetTester tester) async {
    await tester.tap(find.byKey(clePublierAvis));
    await tester.pumpAndSettle();
  }

  group('Ce que l’écran montre', () {
    testWidgets('la soirée dont on parle, et jusqu’à quand on peut écrire', (
      tester,
    ) async {
      await ouvre(
        tester,
        aDeposerDeTest(
          bookingId: booking,
          venueId: bahia,
          date: DateTime(2026, 8, 14),
          fermeLe: DateTime(2026, 9, 13),
        ),
      );

      // On note parfois deux semaines après : sans ce rappel, l'écran
      // demanderait des étoiles sans dire pour quoi.
      expect(find.text('Salle El Bahia'), findsOneWidget);
      expect(find.textContaining('14 août 2026'), findsOneWidget);
      expect(find.textContaining('300 invités'), findsOneWidget);

      // La date limite vient de la base — J+30 n'est écrit nulle part en Dart.
      expect(
        find.textContaining('À déposer avant le 13 septembre 2026'),
        findsOneWidget,
      );
    });

    testWidgets('un avis déjà écrit revient rempli', (tester) async {
      await ouvre(
        tester,
        aDeposerDeTest(
          bookingId: booking,
          venueId: bahia,
          avisId: 'a1',
          note: 4,
          sousNotes: const <SousNote, int>{SousNote.proprete: 5},
          commentaire: 'Très bien dans l’ensemble.',
        ),
      );

      // C'est ce qui fait de cet écran un écran de CORRECTION autant que de
      // dépôt : le texte revient dans son champ et les étoiles sont allumées.
      expect(find.text('Très bien dans l’ensemble.'), findsOneWidget);
      expect(find.text('Modifier mon avis'), findsOneWidget);
      expect(
        find.textContaining('Modifiable jusqu’au 13 septembre 2026'),
        findsOneWidget,
      );
    });
  });

  group('Ce qui part vers la base', () {
    testWidgets('la note globale seule suffit', (tester) async {
      final depot = await ouvre(
        tester,
        aDeposerDeTest(bookingId: booking, venueId: bahia),
      );

      await etoile(tester, 'globale', 4);
      await publie(tester);

      expect(depot.deposes, hasLength(1));
      final envoye = depot.deposes.single;
      expect(envoye.bookingId, booking);
      expect(envoye.note, 4);
      // Les quatre sous-notes sont facultatives (§4.2, CLI-08) : aucune n'est
      // inventée pour faire nombre.
      expect(envoye.sousNotes, isEmpty);
      // Un champ laissé vide part à `null`, pas à la chaîne vide : « pas de
      // commentaire » et « un commentaire vide » ne se rangent pas pareil.
      expect(envoye.commentaire, isNull);
    });

    testWidgets('les sous-notes et le commentaire arrivent tels quels', (
      tester,
    ) async {
      final depot = await ouvre(
        tester,
        aDeposerDeTest(bookingId: booking, venueId: bahia),
      );

      await etoile(tester, 'globale', 5);
      await etoile(tester, 'proprete', 5);
      await etoile(tester, 'service', 3);
      await tester.enterText(
        find.byKey(cleCommentaireAvis),
        'Le parking a fait la différence.',
      );
      await tester.pumpAndSettle();
      await publie(tester);

      final envoye = depot.deposes.single;
      expect(envoye.note, 5);
      expect(envoye.sousNotes[SousNote.proprete], 5);
      expect(envoye.sousNotes[SousNote.service], 3);
      expect(envoye.sousNotes.containsKey(SousNote.conformite), isFalse);
      expect(envoye.commentaire, 'Le parking a fait la différence.');
    });

    testWidgets('rappuyer sur une sous-note l’efface, et elle part absente', (
      tester,
    ) async {
      final depot = await ouvre(
        tester,
        aDeposerDeTest(bookingId: booking, venueId: bahia),
      );

      await etoile(tester, 'globale', 5);
      await etoile(tester, 'proprete', 4);
      // Le même appui à nouveau : « je ne me prononce pas ». Sans ce geste, une
      // sous-note allumée par erreur ne se retirerait plus.
      await etoile(tester, 'proprete', 4);
      await publie(tester);

      expect(depot.deposes.single.sousNotes, isEmpty);
    });

    testWidgets('la note globale, elle, ne s’éteint pas', (tester) async {
      final depot = await ouvre(
        tester,
        aDeposerDeTest(bookingId: booking, venueId: bahia),
      );

      await etoile(tester, 'globale', 3);
      await etoile(tester, 'globale', 3);
      await publie(tester);

      // Elle est obligatoire : l'éteindre ne mènerait qu'à un bouton qui
      // s'éteint aussi.
      expect(depot.deposes.single.note, 3);
    });

    testWidgets('« Publier » reste éteint sans note globale', (tester) async {
      final depot = await ouvre(
        tester,
        aDeposerDeTest(bookingId: booking, venueId: bahia),
      );

      // La base refuse un avis sans note (FE079) ; un bouton allumé qui mène à
      // un refus est une promesse non tenue.
      expect(
        tester.widget<FilledButton>(find.byKey(clePublierAvis)).onPressed,
        isNull,
      );

      await tester.enterText(find.byKey(cleCommentaireAvis), 'Un long texte.');
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byKey(clePublierAvis)).onPressed,
        isNull,
      );

      expect(depot.deposes, isEmpty);
    });
  });

  group('Quand l’avis est figé (§5.4)', () {
    testWidgets('la réponse du propriétaire ferme l’écran, et dit pourquoi', (
      tester,
    ) async {
      await ouvre(
        tester,
        aDeposerDeTest(
          bookingId: booking,
          venueId: bahia,
          avisId: 'a1',
          note: 4,
          commentaire: 'Très bien.',
          modifiable: false,
          reponse: 'Merci, nous avons ajouté deux climatiseurs.',
        ),
      );

      // Aucun bouton : l'écran ne fait pas taper trois paragraphes pour les
      // refuser à l'envoi.
      expect(find.byKey(clePublierAvis), findsNothing);
      expect(
        tester.widget<TextField>(find.byKey(cleCommentaireAvis)).enabled,
        isFalse,
      );

      // Et il dit POURQUOI. Sans la raison, la règle passe pour une brimade.
      expect(
        find.textContaining('Le propriétaire a répondu à votre avis'),
        findsOneWidget,
      );
      expect(
        find.text('Merci, nous avons ajouté deux climatiseurs.'),
        findsOneWidget,
      );
    });

    testWidgets('trente jours passés : l’avis se relit, il ne se change plus', (
      tester,
    ) async {
      await ouvre(
        tester,
        aDeposerDeTest(
          bookingId: booking,
          venueId: bahia,
          avisId: 'a1',
          note: 5,
          commentaire: 'Une belle soirée.',
          fenetreOuverte: false,
          modifiable: false,
        ),
      );

      expect(find.byKey(clePublierAvis), findsNothing);
      // La cliente doit pouvoir relire ce qu'elle a écrit six mois plus tard :
      // `avis_a_deposer()` ne refuse que lorsqu'il n'y a rien à montrer.
      expect(find.text('Une belle soirée.'), findsOneWidget);
      expect(
        find.textContaining('Les avis s’écrivent du 15 août 2026'),
        findsOneWidget,
      );
    });
  });

  group('Ce que dit la base quand elle refuse', () {
    testWidgets('FE078 s’affiche sans faire perdre ce qui est tapé', (
      tester,
    ) async {
      await ouvre(
        tester,
        aDeposerDeTest(bookingId: booking, venueId: bahia),
        erreurDeDepot: const PostgrestException(
          message: 'Votre avis n’est plus modifiable.',
          code: 'PT409',
          hint: 'FE078',
        ),
      );

      await etoile(tester, 'globale', 5);
      await tester.enterText(find.byKey(cleCommentaireAvis), 'Mon texte.');
      await tester.pumpAndSettle();
      await publie(tester);

      expect(
        find.textContaining('Le propriétaire a répondu à votre avis'),
        findsOneWidget,
      );
      // Le texte reste à l'écran : on ne fait pas retaper quelqu'un à qui l'on
      // vient d'annoncer une mauvaise nouvelle.
      expect(find.text('Mon texte.'), findsOneWidget);
    });

    testWidgets(
      'un refus définitif à l’ouverture ne propose pas « Réessayer »',
      (tester) async {
        await ouvre(
          tester,
          aDeposerDeTest(bookingId: booking, venueId: bahia),
          erreurDeLecture: const PostgrestException(
            message: 'La fenêtre de dépôt n’est pas ouverte.',
            code: 'PT400',
            hint: 'FE077',
          ),
        );

        expect(find.text('Cet avis ne peut pas être déposé'), findsOneWidget);
        // « Réessayer » rendrait la même réponse à chaque appui : ce n'est pas
        // une panne, c'est une règle.
        expect(find.text('Réessayer'), findsNothing);
      },
    );

    testWidgets('un réseau tombé, lui, propose « Réessayer »', (tester) async {
      await ouvre(
        tester,
        aDeposerDeTest(bookingId: booking, venueId: bahia),
        erreurDeLecture: StateError('réseau coupé'),
      );

      expect(find.text('Réessayer'), findsOneWidget);
    });

    testWidgets('FE076 dit qui doit agir, et ce n’est pas la cliente', (
      tester,
    ) async {
      await ouvre(
        tester,
        aDeposerDeTest(bookingId: booking, venueId: bahia),
        erreurDeLecture: const PostgrestException(
          message: 'Un avis demande une réservation honorée.',
          code: 'PT409',
          hint: 'FE076',
        ),
      );

      expect(
        find.textContaining(
          'Le propriétaire n’a pas encore confirmé que la soirée a eu lieu',
        ),
        findsOneWidget,
      );
    });
  });

  testWidgets('l’écran s’affiche aussi en thème sombre', (tester) async {
    await ouvre(
      tester,
      aDeposerDeTest(
        bookingId: booking,
        venueId: bahia,
        avisId: 'a1',
        note: 4,
        commentaire: 'Une belle soirée.',
      ),
      theme: FerhaTheme.dark(),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Modifier mon avis'), findsOneWidget);
  });
}
