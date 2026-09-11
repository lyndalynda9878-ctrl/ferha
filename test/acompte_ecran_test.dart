import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ferha/core/router/routes.dart';
import 'package:ferha/core/theme/ferha_theme.dart';
import 'package:ferha/features/booking/acompte.dart';
import 'package:ferha/features/booking/acompte_messages.dart';
import 'package:ferha/features/booking/acompte_providers.dart';
import 'package:ferha/features/booking/acompte_screen.dart';
import 'package:ferha/features/search/search_filters.dart';

/// L'écran 6 — « Verser l'acompte ».
///
/// LE TEST LE PLUS IMPORTANT DE CE FICHIER EST CELUI DU MONTANT. Le bouton dit
/// « Payer X DA » et Chargily encaisse X : si l'écran arrondissait de son côté,
/// les deux nombres divergeraient d'un dinar sur les acomptes à virgule — et
/// c'est juste avant de payer que ce petit mensonge-là coûte le plus cher.
/// L'écran ne doit donc afficher QUE l'entier que la base lui donne.
///
/// LE SECOND EST CELUI QUI NE DIT PAS « PAYÉ ». Revenir de Chargily ne confirme
/// rien ; la seule phrase juste est « en cours de vérification ».
void main() {
  const bookingId = 'bkg-011';

  // Les montants s'écrivent avec une ESPACE FINE INSÉCABLE (U+202F) entre les
  // milliers — c'est ce que pose montantEnDinars(), et c'est la typographie
  // française. Une espace ordinaire dans une attente ci-dessous ferait échouer
  // le test pour une raison qui n'a rien à voir avec l'écran.

  AcompteAVerser acompte({
    num montantConvenu = 205333,
    int montant = 51334,
    num solde = 153999,
    bool paiementEnCours = false,
    bool especesEnAttente = false,
    Duration reste = const Duration(hours: 71, minutes: 12, seconds: 30),
  }) => AcompteAVerser(
    groupId: 'grp-011',
    bookingId: bookingId,
    venueId: '5a11e000-0000-4000-a000-000000000001',
    salle: 'Salle Nour El Bahdja',
    commune: 'Bir El Djir',
    wilayaNom: 'Oran',
    date: DateTime(2027, 8, 14),
    creneau: Creneau.soir,
    invites: 300,
    typeEvenement: 'Mariage',
    proprietaire: 'Karim',
    montantConvenu: montantConvenu,
    acompte: montant,
    solde: solde,
    optionExpireLe: DateTime.now().add(reste),
    paiementEnCours: paiementEnCours,
    especesEnAttente: especesEnAttente,
  );

  Future<void> ouvre(
    WidgetTester tester, {
    AcompteAVerser? du,
    Object? erreur,
    ThemeData? theme,
    TextDirection direction = TextDirection.ltr,
  }) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          acompteProvider(bookingId).overrideWith(
            (ref) async => erreur != null ? throw erreur : du ?? acompte(),
          ),
        ],
        child: MaterialApp(
          theme: theme ?? FerhaTheme.light(),
          home: Directionality(
            textDirection: direction,
            child: const AcompteScreen(bookingId: bookingId),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Un refus de la base, tel que PostgREST le remonte : le code Ferha vit dans
  /// le `hint`, jamais dans le message.
  PostgrestException refus(String hint) =>
      PostgrestException(message: 'peu importe', hint: hint);

  group('Le montant', () {
    testWidgets('le bouton affiche l’entier de la base, tel quel', (
      tester,
    ) async {
      await ouvre(tester);

      // 51 334, et non 51 333 : c'est ceil(51 333,25) que la base a déjà
      // calculé, et l'écran n'y touche pas.
      expect(find.text('Payer 51 334 DA'), findsOneWidget);
    });

    testWidgets('le récapitulatif montre le convenu, l’acompte et le solde', (
      tester,
    ) async {
      await ouvre(tester);

      expect(find.text('205 333 DA'), findsOneWidget);
      expect(find.text('51 334 DA'), findsOneWidget);
      expect(
        find.textContaining('Solde de 153 999 DA réglé sur place'),
        findsOneWidget,
      );
    });

    testWidgets('la part se calcule, elle ne s’écrit pas « 25 % » en dur', (
      tester,
    ) async {
      // Un propriétaire qui fixe 30 % reste dans les bornes du §5.3. L'écran
      // doit dire 30 %, pas le taux de la plateforme.
      await ouvre(
        tester,
        du: acompte(montantConvenu: 200000, montant: 60000, solde: 140000),
      );

      expect(find.text('Acompte (30 %)'), findsOneWidget);
      expect(find.text('Acompte (25 %)'), findsNothing);
    });
  });

  group('Le compte à rebours', () {
    testWidgets('il est en haut, en toutes lettres', (tester) async {
      await ouvre(tester);

      expect(find.text('71 h 12 min'), findsOneWidget);
      expect(
        find.textContaining('La date vous est réservée pendant'),
        findsOneWidget,
      );
    });

    testWidgets('le bandeau nomme le propriétaire, comme la maquette', (
      tester,
    ) async {
      await ouvre(tester);

      expect(find.text('Demande acceptée'), findsOneWidget);
      expect(find.textContaining('Karim a confirmé'), findsOneWidget);
    });
  });

  group('Le moyen de paiement', () {
    testWidgets('les trois choix de la maquette, espèces comprises', (
      tester,
    ) async {
      await ouvre(tester);

      expect(find.text('Carte CIB'), findsOneWidget);
      expect(find.text('Carte Edahabia'), findsOneWidget);
      // Le troisième mène maintenant quelque part — payer_en_especes() (025).
      // Tant qu'il ne menait nulle part, il n'était pas là.
      expect(find.text('Espèces sur place'), findsOneWidget);
    });

    testWidgets(
      'CIB est choisie d’avance : le bouton est actif à l’ouverture',
      (tester) async {
        await ouvre(tester);

        expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
        final bouton = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Payer 51 334 DA'),
        );
        expect(bouton.onPressed, isNotNull);
      },
    );

    testWidgets('choisir Edahabia déplace le point, et un seul', (
      tester,
    ) async {
      await ouvre(tester);

      await tester.tap(find.text('Carte Edahabia'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
      expect(find.byIcon(Icons.radio_button_unchecked), findsNWidgets(2));
    });
  });

  group('Les espèces sur place', () {
    testWidgets(
      'le bouton ne dit plus « Payer » : on annonce, on ne paie pas',
      (tester) async {
        await ouvre(tester);
        await tester.tap(find.text('Espèces sur place'));
        await tester.pumpAndSettle();

        // « Payer 51 334 DA » devant un choix « espèces » promettrait que
        // l'argent part maintenant. Il ne part pas.
        expect(find.text('Payer 51 334 DA'), findsNothing);
        expect(find.text('Annoncer un versement de 51 334 DA'), findsOneWidget);
      },
    );

    testWidgets(
      'le mode test ne s’affiche plus : un billet est un vrai billet',
      (tester) async {
        await ouvre(tester);

        expect(
          find.textContaining('aucune somme n’est réellement débitée'),
          findsOneWidget,
        );

        await tester.tap(find.text('Espèces sur place'));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('aucune somme n’est réellement débitée'),
          findsNothing,
        );
      },
    );

    testWidgets('une annonce déjà posée se voit, et n’est pas reproposée', (
      tester,
    ) async {
      await ouvre(tester, du: acompte(especesEnAttente: true));

      expect(find.text('Versement en espèces annoncé'), findsOneWidget);
      expect(find.textContaining('vous attend avec 51 334 DA'), findsOneWidget);
      // L'option court toujours : le bandeau ne doit pas laisser croire
      // l'inverse.
      expect(find.textContaining('l’option court toujours'), findsOneWidget);

      await tester.tap(find.text('Espèces sur place'));
      await tester.pumpAndSettle();

      expect(find.text('Versement déjà annoncé'), findsOneWidget);
      final bouton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Versement déjà annoncé'),
      );
      expect(bouton.onPressed, isNull);
    });

    testWidgets('annoncer des espèces ne dit jamais « confirmée »', (
      tester,
    ) async {
      await ouvre(tester, du: acompte(especesEnAttente: true));

      expect(find.textContaining('Réservation confirmée'), findsNothing);
      // « Solde … réglé sur place le jour J » reste, et c'est juste : c'est le
      // SOLDE. Ce qu'on ne doit jamais lire, c'est que l'ACOMPTE est réglé.
      expect(find.textContaining('acompte est déjà réglé'), findsNothing);
      expect(find.textContaining('Paiement reçu'), findsNothing);
      // Le compte à rebours, lui, est toujours là : c'est le rappel qui compte.
      expect(find.text('71 h 12 min'), findsOneWidget);
    });
  });

  group('Ce que l’écran ne dit pas', () {
    testWidgets('un paiement en cours n’est jamais annoncé « payé »', (
      tester,
    ) async {
      await ouvre(tester, du: acompte(paiementEnCours: true));

      expect(
        find.textContaining('Un paiement est en cours de vérification'),
        findsOneWidget,
      );
      expect(find.textContaining('confirmée dès que'), findsOneWidget);
      // Ni « payé », ni « confirmée » au passé : seul le webhook confirme.
      expect(find.textContaining('Paiement reçu'), findsNothing);
    });

    testWidgets('le mode test est dit, pas caché', (tester) async {
      await ouvre(tester);

      expect(
        find.textContaining('aucune somme n’est réellement débitée'),
        findsOneWidget,
      );
    });
  });

  group('Les refus de la base', () {
    testWidgets(
      'FE052 — le propriétaire n’a pas répondu, et rien à réessayer',
      (tester) async {
        await ouvre(tester, erreur: refus('FE052'));

        expect(
          find.text('Il n’y a pas d’acompte à verser ici'),
          findsOneWidget,
        );
        expect(find.textContaining('n’a pas encore répondu'), findsOneWidget);
        // Définitif : pas de bouton « Réessayer », qui rendrait la même phrase.
        expect(find.text('Réessayer'), findsNothing);
        expect(find.text('Mes réservations'), findsOneWidget);
      },
    );

    testWidgets('FE053 — l’option est échue, et la phrase dit la suite', (
      tester,
    ) async {
      await ouvre(tester, erreur: refus('FE053'));

      expect(find.textContaining('délai de 72 h est passé'), findsOneWidget);
      expect(find.textContaining('nouvelle demande'), findsOneWidget);
      expect(find.text('Réessayer'), findsNothing);
    });

    testWidgets('FE051 — la réservation d’un autre, sans en dire plus', (
      tester,
    ) async {
      await ouvre(tester, erreur: refus('FE051'));

      expect(
        find.text('Cette réservation n’est pas la vôtre.'),
        findsOneWidget,
      );
    });

    testWidgets('FE050 — session expirée : réessayer a du sens', (
      tester,
    ) async {
      await ouvre(tester, erreur: refus('FE050'));

      expect(find.textContaining('session a expiré'), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
    });

    testWidgets('un code inconnu ne montre jamais le code brut', (
      tester,
    ) async {
      await ouvre(tester, erreur: refus('FE999'));

      expect(find.textContaining('FE999'), findsNothing);
    });
  });

  testWidgets('l’écran se rend en thème sombre', (tester) async {
    await ouvre(tester, theme: FerhaTheme.dark());

    expect(find.text('Payer 51 334 DA'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('l’écran se rend en RTL', (tester) async {
    await ouvre(tester, direction: TextDirection.rtl);

    expect(find.text('Payer 51 334 DA'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('La traduction des refus', () {
    test('les codes de la Edge Function se lisent dans son corps JSON', () {
      // La fonction recopie dans son JSON le hint que la base lui a donné : les
      // deux chemins doivent aboutir à la MÊME phrase, sinon le même refus se
      // dirait de deux façons selon l'endroit où il a été attrapé.
      final parLaBase = refusAcompte(refus('FE053'));
      final parLaFonction = refusAcompte(
        const FunctionsHttpException(
          status: 409,
          details: <String, dynamic>{'hint': 'FE053', 'message': 'peu importe'},
        ),
      );

      expect(parLaFonction.message, parLaBase.message);
      expect(parLaFonction.definitif, isTrue);
    });

    test('un corps qui n’est pas du JSON retombe sur la phrase commune', () {
      // Un 401 de la passerelle Supabase, avant même que la fonction tourne :
      // `details` est alors du texte, et il ne faut pas planter dessus.
      final refus = refusAcompte(
        const FunctionsHttpException(status: 401, details: 'Unauthorized'),
      );

      expect(refus.message, isNotEmpty);
      expect(refus.definitif, isFalse);
    });

    test(
      'FE058 est définitif : une clé absente ne se répare pas en tapant',
      () {
        expect(refusAcompte(refus('FE058')).definitif, isTrue);
        // Et la phrase ne nomme aucun secret.
        expect(
          refusAcompte(refus('FE058')).message.toUpperCase(),
          isNot(contains('CHARGILY')),
        );
      },
    );
  });

  group('Les adresses de retour', () {
    test('elles pointent sur « Mes réservations », en fragment', () {
      final retour = adressesDeRetour(
        base: Uri.parse('http://localhost:52731/#/mes-reservations'),
      );

      expect(retour, isNotNull);
      expect(
        retour!.succes,
        'http://localhost:52731/#${FerhaRoutes.mesReservations}'
        '?${FerhaRoutes.parametrePaiement}='
        '${FerhaRoutes.paiementEnVerification}',
      );
      expect(
        retour.echec,
        'http://localhost:52731/#${FerhaRoutes.mesReservations}'
        '?${FerhaRoutes.parametrePaiement}=${FerhaRoutes.paiementEchoue}',
      );
    });

    test('le port courant est repris, jamais figé', () {
      // `flutter run -d chrome` en choisit un neuf à chaque démarrage : une
      // adresse figée serait fausse un jour sur deux.
      final retour = adressesDeRetour(
        base: Uri.parse('http://localhost:40001/#/accueil'),
      );

      expect(retour!.succes, startsWith('http://localhost:40001/#'));
    });

    test('un sous-dossier de déploiement est conservé', () {
      final retour = adressesDeRetour(
        base: Uri.parse('https://exemple.dz/ferha/#/mes-reservations'),
      );

      expect(retour!.succes, startsWith('https://exemple.dz/ferha/#'));
    });

    test('hors du web, il n’y a pas d’adresse de retour', () {
      // Chargily renvoie sur du http(s) ; sur Android il faudrait un lien
      // d'application, et il n'est pas déclaré. On rend null plutôt que
      // d'envoyer quelqu'un payer sans retour possible.
      expect(adressesDeRetour(base: Uri.parse('file:///data/app/')), isNull);
    });

    test('l’adresse de succès ne promet rien : elle dit « verification »', () {
      final retour = adressesDeRetour(
        base: Uri.parse('http://localhost:1234/#/accueil'),
      );

      expect(retour!.succes, contains('verification'));
      expect(retour.succes, isNot(contains('succes')));
      expect(retour.succes, isNot(contains('paye')));
    });
  });
}
