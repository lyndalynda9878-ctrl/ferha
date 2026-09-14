import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ferha/core/l10n/generated/app_localizations.dart';
import 'package:ferha/core/l10n/locale_controller.dart';
import 'package:ferha/core/preferences/preferences_affichage.dart';
import 'package:ferha/core/theme/ferha_theme.dart';
import 'package:ferha/features/auth/auth_providers.dart';
import 'package:ferha/features/auth/connexion_screen.dart';
import 'package:ferha/features/auth/inscription_screen.dart';
import 'package:ferha/features/auth/profil_screen.dart';
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
// deux typedef du même type d'enregistrement sont le même type.
import 'package:ferha/features/search/search_providers.dart' hide TypeEvenement;
import 'package:ferha/features/search/venue_summary.dart';
import 'package:ferha/features/venue/calendrier_screen.dart';
import 'package:ferha/features/venue/venue_detail.dart';
import 'package:ferha/features/venue/venue_providers.dart';
import 'package:ferha/features/venue/venue_screen.dart';

import 'controles_arabe.dart';
import 'owner_fakes.dart';

/// LA RELECTURE ÉCRAN PAR ÉCRAN — les dix écrans traduits, dans leurs trois
/// états.
///
/// `six_ecrans_en_arabe_test.dart` et `ecrans_auth_en_arabe_test.dart` montent
/// ces écrans PLEINS : une salle, un devis, un profil. C'est l'état dans lequel
/// on les dessine, et c'est celui qu'on regarde le moins mal.
///
/// Les trois autres ne se dessinent pas, ils se déduisent — et c'est pour cela
/// qu'ils cassent :
///
///   * LE CHARGEMENT — un squelette dont les blocs gris sont calés sur la
///     longueur du texte français qu'ils remplacent ;
///   * LE VIDE — une phrase longue, souvent la plus longue de l'écran, posée au
///     milieu d'une colonne qui n'a plus rien pour la soutenir ;
///   * L'ERREUR DE RÉSEAU — un message, un détail technique et un bouton, tous
///     trois arrivés après coup, parfois sur une seule ligne.
///
/// Trente images, donc — soixante en comptant les deux thèmes —, et quatre
/// contrôles sur chacune. Les contrôles sont dans `controles_arabe.dart`, avec
/// ce qu'ils cherchent et pourquoi.
///
/// =============================================================================
/// ON N'ATTEND PAS LE REPOS, ON AVANCE D'UNE SECONDE
///
/// `pumpAndSettle` rend la main quand plus rien ne bouge. Un squelette qui
/// scintille ne s'arrête jamais, et le compte à rebours de l'acompte bat à la
/// seconde : l'attente irait jusqu'à son délai de garde et le banc échouerait
/// sur des écrans parfaitement construits. On avance donc d'une seconde en
/// cinq images — de quoi finir la transition de route (300 ms) et laisser les
/// fournisseurs se poser — et on regarde ce qui est à l'écran à ce moment-là.
void main() {
  setUpAll(chargeLaPoliceDeLaCharte);

  const venueId = '5a11e000-0000-4000-a000-000000000001';
  const bookingId = 'bkg-024';
  const refDemande = '7f3a91c2-0000-4000-a000-000000000001';
  final date = DateTime(2027, 8, 14);

  // ===========================================================================
  // LE JEU D'ESSAI DE L'ÉTAT « VIDE »
  //
  // Vide ne veut pas dire « sans référentiel ». Les wilayas, les types
  // d'événement et les équipements sont des données de départ : elles existent
  // le premier jour, avant la première salle. Ce qui est vide, c'est ce que le
  // CLIENT a produit — les salles trouvées, les réservations, les photos, les
  // options.
  //
  // Leurs libellés sont en français À DESSEIN : c'est ce que la base rend
  // aujourd'hui (label_fr), et l'un des deux points signalés en fin de fichier.
  // ===========================================================================

  List<WilayaAvecSalles> wilayas() => <WilayaAvecSalles>[
    (code: '31', nom: 'Oran', nombreSalles: 0),
    (code: '16', nom: 'Alger', nombreSalles: 0),
  ];

  List<TypeEvenement> types() => <TypeEvenement>[
    (code: 'mariage', libelle: 'Mariage'),
    (code: 'henne', libelle: 'Henné'),
  ];

  Map<String, String> equipements() => <String, String>{
    'climatisation': 'Climatisation',
    'jardin': 'Jardin',
  };

  /// Une salle dépouillée : pas une photo, pas un équipement, pas un tarif.
  ///
  /// C'est l'état d'une salle qu'on vient de publier, et c'est celui où la
  /// fiche a le moins de matière pour tenir sa mise en page.
  VenueDetail ficheDepouillee() => VenueDetail(
    id: venueId,
    nom: 'Salle El Bahia',
    commune: 'Bir El Djir',
    wilayaCode: '31',
    wilayaNom: 'Oran',
    capacite: 200,
    photos: const <String>[],
    equipements: const <EquipementSalle>[],
    typesEvenement: const <TypeEvenement>[],
    tarifs: const <LigneTarif>[],
    options: const <OptionSalle>[],
    dateEstimation: date,
  );

  /// Un devis sans option ni couvert supplémentaire.
  DevisReservation devisNu() => DevisReservation(
    date: date,
    creneau: 'soir',
    invites: 200,
    prixBase: 220000,
    coefJour: 1,
    coefSaison: 1,
    prixCreneau: 220000,
    couvertsInclus: 300,
    couvertsSup: 0,
    montantCouvertsSup: 0,
    montantOptions: 0,
    total: 220000,
    tauxAcompte: 0.25,
    montantAcompte: 55000,
    options: const <OptionSalle>[],
  );

  /// Un acompte sans type d'événement, sans propriétaire nommé, sans wilaya.
  AcompteAVerser acompteNu() => AcompteAVerser(
    groupId: 'grp-024',
    bookingId: bookingId,
    venueId: venueId,
    salle: 'Salle El Bahia',
    commune: 'Bir El Djir',
    date: date,
    creneau: Creneau.soir,
    invites: 200,
    montantConvenu: 220000,
    acompte: 55000,
    solde: 165000,
    optionExpireLe: DateTime.now().add(const Duration(hours: 71)),
    paiementEnCours: false,
    especesEnAttente: false,
  );

  /// L'écriture de l'état, appliquée à TOUS les fournisseurs de l'écran.
  ///
  /// UN SEUL INTERRUPTEUR POUR TOUT L'ÉCRAN, et c'est le point : un écran à
  /// moitié chargé n'est pas un état, c'est un instant. On veut les trois états
  /// francs, ceux que l'utilisateur voit assez longtemps pour les lire.
  ProviderContainer conteneurPour(Etat etat, {bool connecte = false}) {
    Future<T> selon<T>(T Function() quandVide) async {
      switch (etat) {
        // UNE PROMESSE QUI NE SE TIENT JAMAIS. C'est exactement ce qu'est un
        // chargement : le fournisseur est parti, il n'est pas revenu.
        case Etat.chargement:
          return Completer<T>().future;
        case Etat.vide:
          return quandVide();
        // LE RÉSEAU QUI TOMBE, TEL QUE GOTRUE L'ENVELOPPE. `messageErreur` le
        // reconnaît par son type et rend `erreurReseau` — une phrase traduite,
        // et non le texte anglais du serveur.
        case Etat.erreurReseau:
          throw AuthRetryableFetchException(message: 'Failed host lookup');
      }
    }

    return ProviderContainer(
      // AUCUNE NOUVELLE TENTATIVE. Riverpod 3 replanifie de lui-même un
      // fournisseur qui a échoué : une minuterie traînerait jusqu'à la fin du
      // test. On regarde ici ce que l'écran AFFICHE quand la lecture a échoué,
      // pas la politique de reprise.
      retry: (_, _) => null,
      overrides: [
        estConnecteProvider.overrideWithValue(connecte),
        preferencesAffichageProvider.overrideWithValue(PreferencesEnMemoire()),
        ownerRepositoryProvider.overrideWithValue(DepotDeTest()),
        profilProvider.overrideWith(
          (ref) => selon<Map<String, dynamic>?>(() => null),
        ),
        wilayasProvider.overrideWith((ref) => selon(wilayas)),
        typesEvenementProvider.overrideWith((ref) => selon(types)),
        equipementsProvider.overrideWith((ref) => selon(equipements)),
        mieuxNoteesProvider.overrideWith(
          (ref, filtres) => selon(() => (salles: <VenueSummary>[], total: 0)),
        ),
        resultatsProvider.overrideWith(
          (ref, filtres) => selon(() => (salles: <VenueSummary>[], total: 0)),
        ),
        ficheProvider.overrideWith((ref, demande) => selon(ficheDepouillee)),
        devisProvider.overrideWith((ref, demande) => selon(devisNu)),
        calendrierProvider.overrideWith(
          (ref, demande) => selon(() => <DateTime, EtatJour>{}),
        ),
        acompteProvider.overrideWith((ref, id) => selon(acompteNu)),
        mesReservationsProvider.overrideWith(
          () => _MesReservationsSelonLEtat(() => selon(() => <Reservation>[])),
        ),
      ],
    );
  }

  /// Une seconde en cinq images — voir l'en-tête.
  Future<void> avance(WidgetTester tester) async {
    await tester.pump();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  /// Monte [ecran] en arabe, PAR-DESSUS UNE PREMIÈRE PAGE.
  ///
  /// Le `push` donne à l'`AppBar` sa flèche de retour : un écran monté en
  /// `home` n'a rien derrière lui, et le contrôle des icônes n'aurait rien à
  /// regarder.
  Future<void> monte(
    WidgetTester tester,
    Widget ecran,
    Etat etat, {
    required ThemeData theme,
    bool connecte = false,
  }) async {
    tester.view.physicalSize = telephoneDesMaquettes;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final cle = GlobalKey<NavigatorState>();
    final conteneur = conteneurPour(etat, connecte: connecte);
    addTearDown(conteneur.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: conteneur,
        child: MaterialApp(
          navigatorKey: cle,
          locale: const Locale('ar'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: ferhaSupportedLocales,
          theme: theme,
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      ),
    );

    // Sans `await` sur le push : la Future d'une route ne se termine qu'au POP.
    unawaited(
      cle.currentState!.push(MaterialPageRoute<void>(builder: (_) => ecran)),
    );
    await avance(tester);

    // L'ÉCRAN EST-IL SEULEMENT LÀ ? Un `Scaffold` vide passe les quatre
    // contrôles sans rien dire : pas de débordement, pas de français, pas de
    // chiffre, pas d'icône. Si un fournisseur manquant faisait échouer la
    // construction, le banc se féliciterait de trente images blanches.
    expect(
      find.byWidget(ecran),
      findsOneWidget,
      reason:
          'L’écran ne s’est pas monté. Ce n’est pas un défaut de traduction : '
          'regardez d’abord ce qu’il lui manque pour se construire.',
    );

    // ET EST-CE BIEN LE THÈME DEMANDÉ ? Monter deux fois le thème clair
    // passerait les soixante images sans qu'une seule ne dise quoi que ce soit
    // du sombre. La luminosité est ce qui les distingue : on la lit là où
    // l'écran la lit, sous lui.
    expect(
      Theme.of(tester.element(find.byWidget(ecran))).brightness,
      theme.brightness,
      reason: 'Le thème posé n’est pas celui que le banc croit mesurer.',
    );
  }

  // ===========================================================================
  // LES DIX ÉCRANS
  //
  // Sept du parcours client, trois de compte. `connecte` ne vaut que pour le
  // profil : les sept autres se parcourent sans compte (§3), et c'est l'état
  // qu'il faut vérifier — celui d'un visiteur.
  // ===========================================================================

  final ecrans = <String, ({Widget widget, bool connecte})>{
    'accueil': (widget: const AccueilScreen(), connecte: false),
    'résultats': (
      widget: ResultatsScreen(
        filtres: SearchFilters(wilayaCode: '31', date: date, invites: 200),
      ),
      connecte: false,
    ),
    'fiche salle': (
      widget: const VenueScreen(venueId: venueId),
      connecte: false,
    ),
    'calendrier': (
      widget: const CalendrierScreen(venueId: venueId),
      connecte: false,
    ),
    'demande': (
      widget: DemandeScreen(
        venueId: venueId,
        date: date,
        creneau: Creneau.soir,
        invites: 200,
      ),
      connecte: false,
    ),
    'confirmation': (
      widget: const DemandeEnvoyeeScreen(reference: refDemande),
      connecte: false,
    ),
    'acompte': (
      widget: const AcompteScreen(bookingId: bookingId),
      connecte: false,
    ),
    'connexion': (widget: const ConnexionScreen(), connecte: false),
    'inscription': (widget: const InscriptionScreen(), connecte: false),
    'profil': (widget: const ProfilScreen(), connecte: true),
  };

  // LES DEUX THÈMES, ET LES QUATRE CONTRÔLES SUR CHACUN.
  //
  // C'est la règle du projet — clair ET sombre pour chaque écran — et ce n'est
  // pas une formalité ici : un thème ne change pas la longueur d'un mot, mais
  // il change les graisses et les contrastes, et `FerhaTheme` ne se contente
  // pas d'échanger des couleurs. Une rangée qui tenait de justesse dans l'un
  // peut céder dans l'autre, et l'état vide comme l'état d'erreur sont
  // justement ceux où une phrase longue se retrouve seule dans sa colonne.
  //
  // Les trois autres contrôles ne devraient rien voir de nouveau : un thème ne
  // traduit pas un texte et ne retourne pas une icône. On les passe quand même
  // — ils coûtent une lecture d'arbre déjà monté, et le jour où un écran
  // choisira un libellé ou un glyphe selon la luminosité, personne n'aura à y
  // penser.
  final themes = <String, ThemeData Function()>{
    'clair': FerhaTheme.light,
    'sombre': FerhaTheme.dark,
  };

  themes.forEach((nomDuTheme, theme) {
    for (final etat in Etat.values) {
      group('En arabe et en thème $nomDuTheme, ${etat.libelle}', () {
        ecrans.forEach((nom, cas) {
          testWidgets(nom, (tester) async {
            final ou = '$nom — ${etat.libelle}, thème $nomDuTheme';
            await monte(
              tester,
              cas.widget,
              etat,
              theme: theme(),
              connecte: cas.connecte,
            );

            // L'ORDRE COMPTE : `takeException` vide la file, donc le contrôle
            // du débordement passe en premier. Les trois autres lisent
            // l'arbre, et un arbre qui a levé n'est pas lisible.
            aucunDebordement(tester, ou);
            aucunTexteFrancais(tester, ou);
            aucunChiffreArabeIndien(tester, ou);
            lesIconesSuiventLaDirection(tester, ou);
          });
        });
      });
    }
  });

  // ===========================================================================
  // CE QUE LE BANC NE VOIT PAS TOUT SEUL
  //
  // Trois des quatre contrôles cherchent quelque chose qui ne devrait pas être
  // là. Un contrôle qui cherche mal ne dit rien, et surtout ne dit pas qu'il
  // cherche mal : il passe au vert, et l'écran part en production.
  //
  // On lui donne donc des chaînes dont on SAIT ce qu'il doit en faire.
  // ===========================================================================

  group('Le détecteur de français voit encore', () {
    test('il attrape un mot français resté à l’écran', () {
      expect(
        motsLatinsRestants(<String>['Réserver cette salle']),
        containsAll(<String>['Réserver', 'cette', 'salle']),
      );
    });

    test('il laisse passer l’arabe et les chiffres latins', () {
      expect(
        motsLatinsRestants(<String>['احجز هذه القاعة', '343 200 دج', '2027']),
        isEmpty,
      );
    });

    test('il laisse passer les noms propres de la base', () {
      expect(
        motsLatinsRestants(<String>['Salle El Bahia', 'Bir El Djir, Oran']),
        isEmpty,
      );
    });

    test('mais il ne laisse pas passer un mot qui leur ressemble', () {
      // « Salles » n'est pas « Salle El Bahia ». Une tolérance qui déborderait
      // sur les mots voisins cacherait précisément ce qu'on cherche.
      expect(motsLatinsRestants(<String>['Salles à Oran']), <String>['Salles']);
    });

    test('une lettre isolée ne compte pas pour un mot', () {
      expect(motsLatinsRestants(<String>['A 3 دج']), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // LES DEUX AUTRES CONTRÔLES NE SE VÉRIFIENT PAS SUR DES CHAÎNES : ils lisent
  // un arbre. On leur en donne donc un, fabriqué faux exprès.
  // ---------------------------------------------------------------------------

  /// Monte [corps] en arabe, sans fournisseur ni écran.
  Future<void> monteBrut(WidgetTester tester, Widget corps) async {
    tester.view.physicalSize = telephoneDesMaquettes;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: ferhaSupportedLocales,
        theme: FerhaTheme.light(),
        home: Scaffold(body: corps),
      ),
    );
    await tester.pump();
  }

  group('Les contrôles de mise en page savent échouer', () {
    testWidgets('une rangée de 500 px dans 390 est signalée', (tester) async {
      await monteBrut(
        tester,
        const Row(children: <Widget>[SizedBox(width: 500, height: 20)]),
      );

      expect(
        () => aucunDebordement(tester, 'une rangée de 500 px'),
        throwsA(isA<TestFailure>()),
        reason:
            'Si ce test passe au vert, le contrôle du débordement ne voit plus '
            'rien — et les trente images qu’il déclare saines ne prouvent rien.',
      );
    });

    testWidgets('une flèche de retour figée en LTR est signalée', (
      tester,
    ) async {
      // LE DÉFAUT QUE CE CONTRÔLE ATTRAPE VRAIMENT. `Icon` accepte une
      // `textDirection` qui l’emporte sur celle de la page : une flèche qui la
      // reçoit reste tournée vers la gauche au milieu d’un écran arabe, et rien
      // dans le code ne le dit.
      await monteBrut(
        tester,
        const Icon(Icons.arrow_back, textDirection: TextDirection.ltr),
      );

      expect(
        () => lesIconesSuiventLaDirection(tester, 'une flèche figée en LTR'),
        throwsA(isA<TestFailure>()),
      );
    });

    testWidgets('une loupe retournée à la main est signalée', (tester) async {
      // L’AUTRE MOITIÉ DU CONTRÔLE. Une icône non directionnelle ne se retourne
      // jamais seule ; celle-ci ne peut l’être que par un `Transform` posé
      // au-dessus, et c’est pour l’attraper qu’on compte aussi les ancêtres.
      await monteBrut(
        tester,
        Transform(
          alignment: Alignment.center,
          transform: Matrix4.diagonal3Values(-1, 1, 1),
          child: const Icon(Icons.search),
        ),
      );

      expect(
        () => lesIconesSuiventLaDirection(tester, 'une loupe retournée'),
        throwsA(isA<TestFailure>()),
      );
    });

    testWidgets('mais une loupe ordinaire ne l’est pas', (tester) async {
      // LE CONTRE-EXEMPLE, sans lequel les trois précédents ne diraient que la
      // moitié : un contrôle qui accuse tout le monde attrape tout, et ne sert
      // à rien.
      await monteBrut(tester, const Icon(Icons.search));
      lesIconesSuiventLaDirection(tester, 'une loupe ordinaire');
    });
  });

  group('Le détecteur de chiffres arabes-indiens voit encore', () {
    test('il attrape ٣٤٣ et ۳۴۳', () {
      expect(chiffresArabesIndiens.hasMatch('٣٤٣'), isTrue);
      expect(chiffresArabesIndiens.hasMatch('۳۴۳'), isTrue);
    });

    test('il laisse passer 343', () {
      expect(chiffresArabesIndiens.hasMatch('343'), isFalse);
    });
  });

  // ===========================================================================
  // LES DEUX EXCEPTIONS CONNUES — signalées une fois, et non comptées.
  // ===========================================================================

  group('Ce qui reste en français à dessein', () {
    test('les libellés qui viennent de la base ne sont pas des oublis', () {
      // LES OPTIONS viennent de `venue_options.label_fr` : `client_bookings()`
      // les remonte ainsi depuis la migration 033, et `venue_detail.dart` les
      // lit de la même colonne. `label_ar` existe et personne ne l'écrit.
      //
      // LES ÉQUIPEMENTS, LES TYPES D'ÉVÉNEMENT ET LES WILAYAS de même :
      // `amenities.label_fr`, `event_types.label_fr`, `wilayas.name_fr` — les
      // trois `select` de `search_providers.dart` le disent.
      //
      // Leurs 73 traductions arabes attendent une relecture humaine dans
      // `docs/libelles-arabes-a-relire.md`. Le jour où elles seront relues, ce
      // sont les `select` qui changeront — pas les écrans.
      //
      // CE TEST NE VÉRIFIE RIEN DE L'APPLICATION. Il tient la liste à jour et
      // la fait apparaître dans la sortie du banc, pour qu'elle ne devienne pas
      // une tolérance qu'on aurait oublié d'avoir accordée.
      expect(
        donneesDeLaBase,
        containsAll(<String>['Climatisation', 'Mariage', 'Oran']),
      );
      expect(donneesDeLaBase, contains('Chambre de la mariée'));
    });
  });
}

/// Les trois états d'un écran qui lit quelque chose.
enum Etat {
  /// Le fournisseur est parti, il n'est pas revenu.
  chargement('le chargement'),

  /// Il est revenu les mains vides.
  vide('le vide'),

  /// Il n'a pas pu partir.
  erreurReseau('l’erreur de réseau');

  const Etat(this.libelle);

  /// Ce que le banc écrit dans ses noms de tests.
  final String libelle;
}

/// « Mes réservations », soumis au même interrupteur que les autres.
class _MesReservationsSelonLEtat extends MesReservations {
  _MesReservationsSelonLEtat(this._selon);

  final Future<List<Reservation>> Function() _selon;

  @override
  Future<List<Reservation>> build() => _selon();
}
