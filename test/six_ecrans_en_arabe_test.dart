import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ferha/core/l10n/generated/app_localizations.dart';
import 'package:ferha/core/l10n/locale_controller.dart';
import 'package:ferha/core/preferences/preferences_affichage.dart';
import 'package:ferha/core/theme/ferha_theme.dart';
import 'package:ferha/features/auth/auth_providers.dart';
import 'package:ferha/features/booking/acompte.dart';
import 'package:ferha/features/booking/acompte_providers.dart';
import 'package:ferha/features/booking/acompte_screen.dart';
import 'package:ferha/features/booking/booking_providers.dart';
import 'package:ferha/features/booking/demande_envoyee_screen.dart';
import 'package:ferha/features/booking/demande_screen.dart';
import 'package:ferha/features/booking/devis_reservation.dart';
import 'package:ferha/features/booking/mes_reservations_providers.dart';
import 'package:ferha/features/booking/reservation.dart';
import 'package:ferha/features/owner/owner_repository.dart';
import 'package:ferha/features/search/accueil_screen.dart';
import 'package:ferha/features/search/resultats_screen.dart';
import 'package:ferha/features/search/search_filters.dart';
// TypeEvenement est masqué : `venue_detail.dart` en déclare un identique, et
// deux typedef du même type d'enregistrement sont le même type. En garder un
// seul visible évite de préfixer les deux imports.
import 'package:ferha/features/search/search_providers.dart' hide TypeEvenement;
import 'package:ferha/features/search/venue_summary.dart';
import 'package:ferha/features/venue/calendrier_screen.dart';
import 'package:ferha/features/venue/venue_detail.dart';
import 'package:ferha/features/venue/venue_providers.dart';
import 'package:ferha/features/venue/venue_screen.dart';

import 'owner_fakes.dart';
import 'textes_traduits.dart';

/// LES SIX ÉCRANS DU PARCOURS CLIENT, CONSTRUITS EN ARABE (§10, CORE-03).
///
/// Un écran traduit peut être faux de quatre façons, et aucune des quatre ne se
/// voit dans une revue de code française :
///
///   1. il DÉBORDE — l'arabe n'a pas la longueur du français, et une rangée
///      qui tenait de justesse à 390 px ne tient plus ;
///   2. il se lit dans le MAUVAIS SENS — un `left` oublié quelque part, et la
///      page reste posée à gauche sous un texte qui va à droite ;
///   3. sa FLÈCHE DE RETOUR pointe encore vers la gauche, c'est-à-dire vers
///      l'avant ;
///   4. ses PRIX passent en chiffres arabes-indiens, illisibles pour qui achète
///      en Algérie.
///
/// Ce sont les trois pièges du §10 des maquettes, plus le débordement. Ce
/// fichier les vérifie sur les six écrans, un par un.
///
/// =============================================================================
/// LA TAILLE EST CELLE D'UN TÉLÉPHONE, ET C'EST TOUT L'INTÉRÊT
///
/// Les autres tests d'écran montent une fenêtre de 1000 × 2400 : ils vérifient
/// une logique, et une fenêtre haute leur évite d'avoir à faire défiler. Ici on
/// vérifie une MISE EN PAGE — 390 × 844, la taille du téléphone des maquettes.
/// Sur une fenêtre géante, aucun débordement ne se produirait jamais, et le
/// premier des quatre contrôles ne dirait rien.
void main() {
  const venueId = '5a11e000-0000-4000-a000-000000000001';
  const bookingId = 'bkg-022';
  const refDemande = '7f3a91c2-0000-4000-a000-000000000001';
  final date = DateTime(2027, 8, 14);

  /// Le téléphone des maquettes.
  const telephone = Size(390, 844);

  VenueDetail fiche() => VenueDetail(
    id: venueId,
    nom: 'Salle El Bahia',
    commune: 'Oran',
    wilayaCode: '31',
    wilayaNom: 'Oran',
    capacite: 450,
    superficie: 620,
    placesParking: 60,
    photos: const <String>[],
    equipements: const <EquipementSalle>[
      (
        code: 'climatisation',
        libelle: 'تكييف',
        icone: 'ac_unit',
        categorie: 'confort',
      ),
      (code: 'jardin', libelle: 'حديقة', icone: 'yard', categorie: 'espaces'),
    ],
    typesEvenement: const <TypeEvenement>[(code: 'mariage', libelle: 'زفاف')],
    tarifs: <LigneTarif>[
      const LigneTarif(
        creneau: 'soir',
        prixBase: 220000,
        couvertsInclus: 300,
        prixCouvertSup: 900,
        coefJour: 1.3,
        coefSaison: 1.2,
        couvertsSup: 50,
        montantCouvertsSup: 45000,
        total: 343200,
      ),
    ],
    options: const <OptionSalle>[],
    dateEstimation: DateTime(2027, 8, 14),
  );

  VenueSummary resume() => const VenueSummary(
    id: venueId,
    nom: 'Salle El Bahia',
    wilayaCode: '31',
    commune: 'Oran',
    capacite: 450,
    placesParking: 60,
    prix: 343200,
    creneauPrix: 'soir',
    equipements: <String>['climatisation', 'jardin'],
    note: 4.6,
    nombreAvis: 12,
  );

  DevisReservation devis() => DevisReservation(
    date: date,
    creneau: 'soir',
    invites: 350,
    prixBase: 220000,
    coefJour: 1.3,
    coefSaison: 1.2,
    prixCreneau: 343200,
    couvertsInclus: 300,
    couvertsSup: 50,
    montantCouvertsSup: 45000,
    montantOptions: 0,
    total: 388200,
    tauxAcompte: 0.25,
    montantAcompte: 97050,
    options: const <OptionSalle>[],
  );

  AcompteAVerser acompte() => AcompteAVerser(
    groupId: 'grp-022',
    bookingId: bookingId,
    venueId: venueId,
    salle: 'Salle El Bahia',
    commune: 'Oran',
    wilayaNom: 'Oran',
    date: date,
    creneau: Creneau.soir,
    invites: 350,
    typeEvenement: 'زفاف',
    proprietaire: 'Karim',
    montantConvenu: 388200,
    acompte: 97050,
    solde: 291150,
    optionExpireLe: DateTime.now().add(const Duration(hours: 71, minutes: 12)),
    paiementEnCours: false,
    especesEnAttente: false,
  );

  /// La demande que la confirmation relit par sa référence.
  ///
  /// Elle ne lui est plus TENDUE : l'écran la retrouve dans
  /// `client_bookings()`. Voir `demande_envoyee_rechargement_test.dart`.
  Reservation reservationEnvoyee() => Reservation(
    groupId: refDemande,
    bookingId: 'bkg-022',
    venueId: venueId,
    salle: 'Salle El Bahia',
    commune: 'Oran',
    wilayaNom: 'Oran',
    date: date,
    creneau: Creneau.soir,
    invites: 350,
    typeEvenement: 'زفاف',
    etat: EtatReservation.enAttente,
    montant: 388200,
    creeLe: DateTime(2026, 9, 14),
    options: const <String>['تكييف'],
  );

  /// Un conteneur chargé de tout ce que les six écrans lisent.
  ///
  /// UN SEUL JEU POUR LES SIX, et c'est délibéré : ce fichier ne teste pas ce
  /// que chaque écran lit — d'autres tests s'en chargent — mais ce qu'il
  /// DEVIENT en arabe. Six variantes de cette liste seraient six endroits à
  /// tenir à jour pour un test qui n'en regarde aucun.
  ///
  /// UN CONTENEUR PLUTÔT QU'UNE LISTE D'`Override` : ce type n'est pas exporté
  /// par `flutter_riverpod`, et une fonction doit annoncer ce qu'elle rend. Le
  /// conteneur est public, et il sert des deux côtés — au `ProviderScope` des
  /// écrans, et à la bascule de langue, qui lit le fournisseur directement.
  ProviderContainer conteneurDeTest({PreferencesAffichage? preferences}) =>
      ProviderContainer(
        overrides: [
          // PERSONNE N'EST CONNECTÉ, ET C'EST LE CAS QUI COMPTE ICI : les
          // six écrans se parcourent sans compte (§3), et la bascule de langue
          // doit marcher pour un visiteur. C'est aussi ce qui garde Supabase
          // hors de ce test — `LocaleController` n'écrit dans `profiles` que
          // s'il y a quelqu'un, et ne touche pas au client sinon.
          estConnecteProvider.overrideWithValue(false),
          preferencesAffichageProvider.overrideWithValue(
            preferences ?? PreferencesEnMemoire(),
          ),
          ownerRepositoryProvider.overrideWithValue(DepotDeTest()),
          profilProvider.overrideWith(
            (ref) async => <String, dynamic>{'phone': '0770112233'},
          ),
          wilayasProvider.overrideWith(
            (ref) async => <WilayaAvecSalles>[
              (code: '31', nom: 'Oran', nombreSalles: 3),
              (code: '16', nom: 'Alger', nombreSalles: 5),
            ],
          ),
          typesEvenementProvider.overrideWith(
            (ref) async => <TypeEvenement>[
              (code: 'mariage', libelle: 'زفاف'),
              (code: 'henne', libelle: 'حنة'),
            ],
          ),
          equipementsProvider.overrideWith(
            (ref) async => <String, String>{
              'climatisation': 'تكييف',
              'jardin': 'حديقة',
            },
          ),
          mieuxNoteesProvider.overrideWith(
            (ref, filtres) async =>
                (salles: <VenueSummary>[resume()], total: 1),
          ),
          resultatsProvider.overrideWith(
            (ref, filtres) async =>
                (salles: <VenueSummary>[resume()], total: 1),
          ),
          ficheProvider.overrideWith((ref, demande) async => fiche()),
          devisProvider.overrideWith((ref, demande) async => devis()),
          calendrierProvider.overrideWith(
            (ref, demande) async => <DateTime, EtatJour>{
              DateTime(2027, 8, 21): EtatJour.reserve,
            },
          ),
          acompteProvider.overrideWith((ref, id) async => acompte()),
          mesReservationsProvider.overrideWith(
            () => _MesReservationsDeTest(<Reservation>[reservationEnvoyee()]),
          ),
        ],
      );

  /// Monte [ecran] en arabe, PAR-DESSUS UNE PREMIÈRE PAGE.
  ///
  /// Le `push` n'est pas une coquetterie : c'est lui qui donne à l'`AppBar` sa
  /// flèche de retour. Un écran monté en `home` n'a rien derrière lui, donc
  /// aucune flèche — et le troisième contrôle n'aurait rien à regarder.
  Future<void> pompe(
    WidgetTester tester,
    Widget ecran, {
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = telephone;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final cle = GlobalKey<NavigatorState>();
    final conteneur = conteneurDeTest();
    addTearDown(conteneur.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: conteneur,
        child: MaterialApp(
          navigatorKey: cle,
          locale: const Locale('ar'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: ferhaSupportedLocales,
          theme: theme ?? FerhaTheme.light(),
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      ),
    );

    // SANS `await` SUR LE PUSH : la Future d'une route ne se termine qu'au
    // POP. L'attendre ici bloquerait le test jusqu'à son délai de garde, sur
    // un écran parfaitement construit.
    unawaited(
      cle.currentState!.push(MaterialPageRoute<void>(builder: (_) => ecran)),
    );
    await tester.pumpAndSettle();
  }

  /// La direction sous laquelle l'écran s'est réellement construit.
  TextDirection directionDe(WidgetTester tester) =>
      Directionality.of(tester.element(find.byType(Scaffold).last));

  /// Tout le texte affiché, rassemblé.
  List<String> textesAffiches(WidgetTester tester) => <String>[
    for (final t in tester.widgetList<Text>(find.byType(Text)))
      t.data ?? t.textSpan?.toPlainText() ?? '',
  ];

  /// L'espace fine insécable des milliers (U+202F).
  ///
  /// NOMMÉE PLUTÔT QU'ÉCRITE : dans une chaîne de test, elle est
  /// invisible — et une attente qui échoue sur un caractère qu'on ne
  /// voit pas coûte une demi-heure à comprendre.
  final fine = String.fromCharCode(0x202f);

  /// Les chiffres arabes-indiens — ceux qu'on ne veut nulle part (§10).
  final chiffresArabes = RegExp(r'[٠-٩۰-۹]');

  /// Les écrans, et le nom sous lequel ils passent au banc.
  final ecrans = <String, Widget>{
    'écran 1 — accueil': const AccueilScreen(),
    'écran 2 — résultats': ResultatsScreen(
      filtres: SearchFilters(wilayaCode: '31', date: date, invites: 350),
    ),
    'écran 3 — fiche salle': const VenueScreen(venueId: venueId),
    'écran 4 — calendrier': const CalendrierScreen(venueId: venueId),
    'écran 5 — demande': DemandeScreen(
      venueId: venueId,
      date: date,
      creneau: Creneau.soir,
      invites: 350,
    ),
    'écran 5 bis — demande envoyée': const DemandeEnvoyeeScreen(
      reference: refDemande,
    ),
    'écran 6 — acompte': const AcompteScreen(bookingId: bookingId),
  };

  group('En arabe, les six écrans', () {
    ecrans.forEach((nom, ecran) {
      testWidgets('$nom se construit sans déborder', (tester) async {
        await pompe(tester, ecran);

        // UN DÉBORDEMENT EST UNE EXCEPTION, pas un avertissement : `RenderFlex
        // overflowed by N pixels` passe par FlutterError, et `takeException`
        // la ramasse. Rien à ramasser veut dire que tout tient dans 390 px.
        expect(
          tester.takeException(),
          isNull,
          reason:
              '$nom déborde en arabe. Les mots arabes n’ont pas la longueur '
              'des mots français : une rangée qui tenait de justesse ne tient '
              'plus. Laissez le texte se replier — Expanded, Flexible, ou deux '
              'lignes — plutôt que de raccourcir la traduction.',
        );
      });

      testWidgets('$nom se lit de droite à gauche', (tester) async {
        await pompe(tester, ecran);

        expect(
          directionDe(tester),
          TextDirection.rtl,
          reason:
              '$nom s’est construit en LTR alors que la langue est l’arabe. '
              'C’est `MaterialApp.locale` qui pose la direction : si elle ne '
              'descend pas jusqu’ici, un `Directionality` la bloque en route.',
        );
      });

      testWidgets('$nom écrit ses nombres en chiffres latins', (tester) async {
        await pompe(tester, ecran);

        final fautifs = textesAffiches(
          tester,
        ).where(chiffresArabes.hasMatch).toList();

        expect(
          fautifs,
          isEmpty,
          reason:
              '$nom affiche des chiffres arabes-indiens : '
              '${fautifs.join(' | ')}\n'
              'En Algérie, les prix, les dates et les numéros s’écrivent en '
              'chiffres latins, en arabe comme en français (§10). Passez par '
              'FormatsFerha, qui met en forme à la main et ne laisse jamais '
              'intl choisir.',
        );
      });
    });
  });

  group('Les trois pièges du §10', () {
    testWidgets('le prix garde ses chiffres latins et prend la devise arabe', (
      tester,
    ) async {
      await pompe(tester, const VenueScreen(venueId: venueId));

      // 343 200, avec l'espace fine insécable des milliers, suivi de « دج ».
      final attendu = textesAr.montantEnDinars('343${fine}200');
      expect(
        textesAffiches(tester).where((t) => t.contains(attendu)),
        isNotEmpty,
        reason:
            'Le prix devrait s’écrire « $attendu » : le nombre en chiffres '
            'latins, la devise en arabe. C’est la seule partie d’un montant '
            'qui se traduit.',
      );
    });

    testWidgets('la flèche de retour est retournée, la loupe non', (
      tester,
    ) async {
      await pompe(tester, const CalendrierScreen(venueId: venueId));

      // COMMENT FLUTTER RETOURNE UNE ICÔNE : quand `IconData.matchTextDirection`
      // est vrai et que la direction est RTL, `Icon` enveloppe son glyphe dans
      // un `Transform` qui inverse l'axe des x. On ne teste donc pas un
      // booléen de la charte — on regarde la matrice réellement posée.
      final fleche = find.byIcon(Icons.arrow_back);
      expect(
        fleche,
        findsOneWidget,
        reason:
            'Le calendrier est ouvert par-dessus une page : il doit '
            'porter une flèche de retour.',
      );

      // LE TRANSFORM EST DESSOUS, PAS AU-DESSUS : c'est `Icon.build` qui le
      // pose autour de son glyphe. Chercher un ancêtre ne trouverait rien, et
      // le test échouerait sur une flèche parfaitement retournée.
      final retournements = tester
          .widgetList<Transform>(
            find.descendant(of: fleche, matching: find.byType(Transform)),
          )
          .where((t) => t.transform.storage[0] == -1.0);

      expect(
        retournements,
        isNotEmpty,
        reason:
            'La flèche de retour n’est pas retournée en arabe. Elle est '
            'DIRECTIONNELLE : elle montre d’où l’on vient, et l’on vient de '
            'la droite. Si elle ne se retourne plus, c’est qu’une icône sans '
            '`matchTextDirection` a pris sa place.',
      );
    });

    testWidgets('une icône non directionnelle ne se retourne pas', (
      tester,
    ) async {
      await pompe(tester, const AccueilScreen());

      final loupe = find.byIcon(Icons.search);
      expect(loupe, findsWidgets);

      final retournees = tester
          .widgetList<Transform>(
            find.descendant(of: loupe.first, matching: find.byType(Transform)),
          )
          .where((t) => t.transform.storage[0] == -1.0);

      expect(
        retournees,
        isEmpty,
        reason:
            'La loupe s’est retournée. Seules les icônes qui montrent une '
            'DIRECTION se retournent ; une loupe retournée n’est pas une '
            'loupe arabe, c’est une loupe à l’envers.',
      );
    });

    testWidgets('le calendrier commence toujours par dimanche', (tester) async {
      await pompe(tester, const CalendrierScreen(venueId: venueId));

      // LE MIROIR EST AFFAIRE DE DIRECTION, PAS D'ORDRE. Les sept initiales
      // restent dans l'ordre dimanche → samedi ; c'est le `Row` qui, en RTL,
      // pose la première à droite. Inverser la liste mettrait samedi en tête
      // et décalerait toutes les dates d'un cran — un calendrier faux.
      final entetes = textesAffiches(tester);
      final premiere = entetes.indexOf(textesAr.initialeDimanche);
      final derniere = entetes.indexOf(textesAr.initialeSamedi);

      expect(premiere, isNonNegative);
      expect(derniere, isNonNegative);
      expect(
        premiere,
        lessThan(derniere),
        reason:
            'Les initiales des jours ne sont plus dans l’ordre dimanche → '
            'samedi. Le §10 est explicite : « le calendrier commence toujours '
            'par dimanche, mais se lit de droite à gauche ».',
      );
    });
  });

  group('En arabe ET en thème sombre', () {
    // LA RÈGLE DU PROJET VAUT AUSSI ICI : clair et sombre, pour chaque écran.
    // Un thème ne change pas la longueur d'un mot, mais il change les tailles
    // de police et les épaisseurs — et c'est assez pour faire déborder une
    // rangée qui tenait de justesse dans l'autre.
    ecrans.forEach((nom, ecran) {
      testWidgets('$nom se construit sans déborder', (tester) async {
        await pompe(tester, ecran, theme: FerhaTheme.dark());

        expect(tester.takeException(), isNull);
        expect(directionDe(tester), TextDirection.rtl);
      });
    });
  });

  group('La bascule de langue', () {
    testWidgets('l’arabe s’applique sans redémarrer', (tester) async {
      // CE QUE CE TEST VÉRIFIE : que changer `localeProvider` suffit. Pas de
      // rechargement, pas de reconstruction manuelle — la même image qui suit.
      tester.view.physicalSize = telephone;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final conteneur = conteneurDeTest();
      addTearDown(conteneur.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: conteneur,
          child: Consumer(
            builder: (context, ref, _) => MaterialApp(
              locale: ref.watch(localeProvider),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: ferhaSupportedLocales,
              theme: FerhaTheme.light(),
              home: const AccueilScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(textesFr.rechercher), findsOneWidget);
      expect(directionDe(tester), TextDirection.ltr);

      await conteneur.read(localeProvider.notifier).choisir(const Locale('ar'));
      await tester.pumpAndSettle();

      expect(find.text(textesAr.rechercher), findsOneWidget);
      expect(directionDe(tester), TextDirection.rtl);
    });

    testWidgets('la langue choisie est retenue par l’appareil', (tester) async {
      final memoire = PreferencesEnMemoire();
      final conteneur = conteneurDeTest(preferences: memoire);
      addTearDown(conteneur.dispose);

      await conteneur.read(localeProvider.notifier).choisir(const Locale('ar'));

      expect(
        await memoire.langue(),
        'ar',
        reason:
            'La langue doit être retenue sur l’appareil : c’est la seule des '
            'deux écritures qui vaut pour un visiteur sans compte, et la seule '
            'lisible avant la première image.',
      );
    });
  });
}

/// Le fournisseur de « Mes réservations », remplacé par une liste fixe.
class _MesReservationsDeTest extends MesReservations {
  _MesReservationsDeTest(this._reservations);

  final List<Reservation> _reservations;

  @override
  Future<List<Reservation>> build() async => _reservations;
}
