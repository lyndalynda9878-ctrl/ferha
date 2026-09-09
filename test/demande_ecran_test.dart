import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ferha/core/theme/ferha_theme.dart';
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
  Future<void> ouvre(WidgetTester tester, ThemeData theme) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ficheProvider.overrideWith((ref, demande) async => salle()),
          devisProvider.overrideWith((ref, demande) async => devis()),
        ],
        child: MaterialApp(
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
