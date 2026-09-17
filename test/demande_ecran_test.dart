import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ferha/core/l10n/generated/app_localizations.dart';
import 'package:ferha/core/l10n/locale_controller.dart';
import 'package:ferha/core/theme/ferha_theme.dart';
import 'package:ferha/features/auth/auth_providers.dart';
import 'package:ferha/features/booking/booking_providers.dart';
import 'package:ferha/features/booking/demande_screen.dart';
import 'package:ferha/features/booking/devis_reservation.dart';
import 'package:ferha/features/search/search_filters.dart';
import 'package:ferha/features/venue/venue_detail.dart';
import 'package:ferha/features/venue/venue_providers.dart';

/// L'écran de demande, monté sur des fournisseurs de test.
///
/// CE QUE CE FICHIER SURVEILLE VRAIMENT : que le récapitulatif AFFICHE les
/// montants de la base, et rien d'autre. Le devis rendu ici est délibérément
/// incohérent — un total de 1 000 DA sous un prix de créneau de 343 200 —
/// parce qu'un écran qui recalculerait quoi que ce soit corrigerait cette
/// incohérence, et le test le verrait. Un écran qui se contente de lire
/// affiche 1 000, sans broncher.
///
/// C'est la seule façon de tester un invariant négatif : rendre la base
/// menteuse, et vérifier que l'écran la croit.
void main() {
  const venueId = '5a11e000-0000-4000-a000-000000000001';
  final date = DateTime(2027, 8, 14);

  // L'espace fine insécable des milliers, celle que pose montantEnDinars().
  // Écrite en clair ici : une espace ordinaire glissée à sa place ferait
  // échouer ces tests sans qu'on voie pourquoi.
  const fine = '\u202F';

  const fleurs = OptionSalle(
    id: 'opt-fleurs',
    code: 'decoration_florale',
    libelle: 'Décoration florale',
    prix: 25000,
  );
  const chambre = OptionSalle(
    id: 'opt-chambre',
    code: 'chambre_mariee',
    libelle: 'Chambre de la mariée',
    prix: 0,
  );

  VenueDetail salle() => VenueDetail(
    id: venueId,
    nom: 'Salle El Bahia',
    commune: 'Oran',
    wilayaCode: '31',
    wilayaNom: 'Oran',
    capacite: 450,
    photos: const <String>[],
    equipements: const <EquipementSalle>[],
    typesEvenement: const <TypeEvenement>[
      (code: 'mariage', libelle: 'Mariage'),
      (code: 'henne', libelle: 'Henné'),
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
    options: const <OptionSalle>[chambre, fleurs],
    dateEstimation: DateTime(2027, 8, 14),
  );

  // Un devis dont le total ne découle PAS de ses postes : c'est le piège.
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
    montantOptions: 25000,
    total: 1000,
    tauxAcompte: 0.25,
    montantAcompte: 7,
    options: const <OptionSalle>[chambre, fleurs],
  );

  /// L'écran tient sur un téléphone en défilant ; un test, lui, ne construit
  /// que ce qui est à l'écran. On lui donne donc une fenêtre assez haute pour
  /// que le récapitulatif ET le bouton d'envoi soient posés en même temps.
  Future<void> ouvre(
    WidgetTester tester,
    ThemeData theme, {
    String? telephoneDuProfil,
    String? idDuProfil,
  }) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ficheProvider.overrideWith((ref, demande) async => salle()),
          devisProvider.overrideWith((ref, demande) async => devis()),
          profilProvider.overrideWith(
            (ref) async => telephoneDuProfil == null && idDuProfil == null
                ? null
                : <String, dynamic>{
                    'phone': telephoneDuProfil,
                    'id': idDuProfil,
                  },
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: ferhaSupportedLocales,
          theme: theme,
          home: DemandeScreen(
            venueId: venueId,
            date: date,
            creneau: Creneau.soir,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('le récapitulatif affiche les montants de la base, tels quels', (
    tester,
  ) async {
    await ouvre(tester, FerhaTheme.light());

    // Le total est celui que la base a dit — pas la somme des lignes.
    expect(find.text('1${fine}000 DA'), findsOneWidget);

    // L'acompte aussi, et son pourcentage vient du même endroit.
    expect(find.text('Acompte à verser (25 %)'), findsOneWidget);
    expect(find.text('7 DA'), findsOneWidget);

    // Le prix du créneau porte ses majorations, nommées d'après les
    // coefficients de la base : 2027-08-14 est un samedi, et août est en
    // haute saison.
    expect(find.text('Soirée (samedi, haute saison)'), findsOneWidget);
    expect(find.text('343${fine}200 DA'), findsOneWidget);
  });

  testWidgets('une option incluse s’écrit « Incluse », jamais « 0 DA »', (
    tester,
  ) async {
    await ouvre(tester, FerhaTheme.light());

    expect(find.text('Incluse'), findsOneWidget);
    expect(find.text('0 DA'), findsNothing);

    // Et elle ne fabrique pas de ligne dans le récapitulatif : une ligne à
    // zéro dinar n'apprend rien et allonge le devis.
    expect(find.text('Chambre de la mariée'), findsOneWidget);
  });

  testWidgets('la mention rassurante de la maquette est là, sous le bouton', (
    tester,
  ) async {
    await ouvre(tester, FerhaTheme.light());

    expect(find.text('Envoyer la demande'), findsOneWidget);
    expect(
      find.text(
        'Aucun paiement à cette étape. Le propriétaire répond sous 48 h.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('les invités partent des couverts inclus, sans supplément', (
    tester,
  ) async {
    await ouvre(tester, FerhaTheme.light());

    // 300 : les couverts compris dans le prix de base de ce créneau. Le point
    // de départ où le client ne paie aucun supplément.
    expect(find.text('300'), findsOneWidget);
    expect(find.text('Capacité de la salle : 450 couverts.'), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // Le téléphone, et le bouton qu'il commande (§9, FE007)
  //
  // `booking_contact()` ouvre au propriétaire le numéro du client dès
  // « accepted » — mais il n'ouvrait rien tant qu'aucun écran ne remplissait
  // `profiles.phone`. La salle recevait une demande de quelqu'un qu'elle ne
  // pouvait pas rappeler.
  // ---------------------------------------------------------------------------

  bool envoyerEstAllume(WidgetTester tester) {
    final bouton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Envoyer la demande'),
    );
    return bouton.onPressed != null;
  }

  Finder champTelephone() => find.widgetWithText(TextField, '0770 11 22 33');

  group('Le téléphone', () {
    testWidgets('sans numéro, « Envoyer la demande » est éteint et le dit', (
      tester,
    ) async {
      await ouvre(tester, FerhaTheme.light());

      expect(envoyerEstAllume(tester), isFalse);
      expect(find.text('Indiquez un numéro de téléphone.'), findsOneWidget);
    });

    testWidgets('un numéro incomplet n’allume pas le bouton', (tester) async {
      await ouvre(tester, FerhaTheme.light());

      await tester.enterText(champTelephone(), '0770 11');
      await tester.pumpAndSettle();

      expect(envoyerEstAllume(tester), isFalse);
    });

    testWidgets('un numéro valide allume le bouton', (tester) async {
      await ouvre(tester, FerhaTheme.light());

      await tester.enterText(champTelephone(), '0770 11 22 33');
      await tester.pumpAndSettle();

      expect(envoyerEstAllume(tester), isTrue);
      expect(find.text('Indiquez un numéro de téléphone.'), findsNothing);
    });

    testWidgets('le numéro du profil préremplit le champ', (tester) async {
      // Un client qui a déjà réservé une fois ne retape pas son numéro. Le
      // champ reste modifiable : on change de puce, pas de compte.
      await ouvre(tester, FerhaTheme.light(), telephoneDuProfil: '0770112233');

      expect(find.text('0770112233'), findsOneWidget);
      expect(envoyerEstAllume(tester), isTrue);
    });

    testWidgets('l’écran dit quand le propriétaire verra ce numéro (§9)', (
      tester,
    ) async {
      // Sans cette phrase, le champ ressemble à un formulaire de plus qui
      // collecte des coordonnées. C'est la règle du §9, dite à celui dont c'est
      // le numéro.
      await ouvre(tester, FerhaTheme.light());

      expect(
        find.text(
          'Le propriétaire ne le voit qu’après avoir accepté votre demande.',
        ),
        findsOneWidget,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Le numéro jeté, et dit
  //
  // Le 17 septembre 2026, un vrai numéro tapé sur cet écran par un visiteur
  // connecté comme Amina s'est retrouvé affiché en clair dans l'espace
  // propriétaire de la démonstration en ligne. La migration 038 empêche
  // désormais la base de le garder ; ces deux tests surveillent la moitié
  // honnête du correctif — le DIRE à la personne qui tape.
  //
  // LES DEUX ENSEMBLE, OU AUCUN. Le premier seul passerait aussi si la ligne
  // s'affichait pour tout le monde, ce qui inquiéterait un vrai client sans
  // raison : chez lui, le numéro est conservé et sert.
  // ---------------------------------------------------------------------------
  group('la ligne « ce compte est une démonstration »', () {
    const phrase =
        'Ce compte est une démonstration partagée : '
        'le numéro saisi n’est pas conservé.';

    testWidgets('s’affiche sur un compte de démonstration', (tester) async {
      await ouvre(
        tester,
        FerhaTheme.light(),
        // Le préfixe du décor, celui de seed/003 et du déclencheur de 038.
        idDuProfil: 'd0000000-0000-4000-a000-000000000010',
      );

      expect(find.text(phrase), findsOneWidget);
    });

    testWidgets('ne s’affiche pas sur un compte normal', (tester) async {
      await ouvre(
        tester,
        FerhaTheme.light(),
        idDuProfil: '7e000000-0000-4000-a000-000000000019',
      );

      expect(find.text(phrase), findsNothing);

      // Et le champ reste celui de tout le monde : la règle du §9 est dite,
      // sans avertissement par-dessus.
      expect(
        find.text(
          'Le propriétaire ne le voit qu’après avoir accepté votre demande.',
        ),
        findsOneWidget,
      );
    });
  });

  testWidgets('l’écran se rend aussi en thème sombre', (tester) async {
    // Chaque écran doit vivre dans les deux thèmes (règle du projet). Le test
    // ne juge pas les couleurs — il vérifie qu'aucune n'a été oubliée au point
    // de faire tomber le rendu.
    await ouvre(tester, FerhaTheme.dark());

    expect(find.text('Envoyer la demande'), findsOneWidget);
    expect(find.text('Acompte à verser (25 %)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
