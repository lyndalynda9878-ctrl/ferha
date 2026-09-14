import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ferha/core/l10n/generated/app_localizations.dart';
import 'package:ferha/core/l10n/locale_controller.dart';
import 'package:ferha/core/preferences/preferences_affichage.dart';
import 'package:ferha/core/supabase/supabase_providers.dart';
import 'package:ferha/core/theme/ferha_theme.dart';
import 'package:ferha/features/assistant/assistant_repository.dart';
import 'package:ferha/features/assistant/assistant_screen.dart';
import 'package:ferha/features/auth/auth_providers.dart';
import 'package:ferha/features/booking/mes_reservations_providers.dart';
import 'package:ferha/features/booking/mes_reservations_screen.dart';
import 'package:ferha/features/booking/reservation.dart';
import 'package:ferha/features/notifications/notification_ferha.dart';
import 'package:ferha/features/notifications/notifications_providers.dart';
import 'package:ferha/features/notifications/notifications_repository.dart';
import 'package:ferha/features/notifications/notifications_screen.dart';
import 'package:ferha/features/owner/agenda_screen.dart';
import 'package:ferha/features/owner/compression_photo.dart';
import 'package:ferha/features/owner/creneau_agenda.dart';
import 'package:ferha/features/owner/demande_detail.dart';
import 'package:ferha/features/owner/demande_en_attente.dart';
import 'package:ferha/features/owner/indicateurs_salle.dart';
import 'package:ferha/features/owner/detail_demande_screen.dart';
import 'package:ferha/features/owner/owner_repository.dart';
import 'package:ferha/features/owner/photos_salle_screen.dart';
import 'package:ferha/features/owner/publier_salle_screen.dart';
import 'package:ferha/features/owner/recapitulatif_salle_screen.dart';
import 'package:ferha/features/owner/salle_du_proprietaire.dart';
import 'package:ferha/features/owner/tableau_de_bord_screen.dart';
import 'package:ferha/features/reviews/avis.dart';
import 'package:ferha/features/reviews/avis_repository.dart';
import 'package:ferha/features/reviews/avis_screen.dart';
import 'package:ferha/features/reviews/deposer_avis_screen.dart';
import 'package:ferha/features/search/search_filters.dart';
import 'package:ferha/features/search/search_providers.dart' hide TypeEvenement;
import 'package:ferha/features/venue/galerie_screen.dart';
import 'package:ferha/features/venue/venue_detail.dart';
import 'package:ferha/features/venue/venue_providers.dart';

import 'assistant_fakes.dart';
import 'avis_fakes.dart';
import 'controles_arabe.dart';
import 'owner_fakes.dart';

/// LES ÉCRANS QUI SONT RESTÉS EN FRANÇAIS, MONTÉS EN ARABE.
///
/// L'espace propriétaire, l'assistant et les avis ne sont pas traduits, et ce
/// n'est pas un oubli : le J22 s'arrêtait au parcours client, et les traduire à
/// moitié serait pire que pas du tout.
///
/// MAIS LA LANGUE DE L'APPLICATION N'EST PAS CELLE D'UN ÉCRAN. Un propriétaire
/// qui met Ferha en arabe emporte l'arabe partout : `MaterialApp.locale` pose
/// `TextDirection.rtl` à la racine, et ces écrans-là se retournent avec le
/// reste — colonnes inversées, `AppBar` à droite, flèches miroir — tout en
/// gardant leurs phrases françaises. C'est laid et c'est assumé ; ce qui ne
/// l'est pas, c'est que ça tombe.
///
/// =============================================================================
/// DEUX CONTRÔLES SEULEMENT, ET C'EST VOLONTAIRE
///
/// On ne leur demande ni de parler arabe, ni d'avoir les bons chiffres : ils
/// n'ont pas été traduits. On leur demande de ne pas PLANTER et de ne pas
/// DÉBORDER — les deux seules choses qu'un renversement de direction casse tout
/// seul, parce qu'un `left` oublié ne se voit qu'en RTL.
///
/// Le jour où ces écrans seront traduits, ce fichier disparaîtra et ses écrans
/// rejoindront `relecture_arabe_test.dart`, qui leur appliquera les quatre.
void main() {
  setUpAll(chargeLaPoliceDeLaCharte);

  const bahia = '5a11e000-0000-4000-a000-000000000001';
  const demandeId = '024';
  const bookingId = 'bkg-$demandeId';
  final date = DateTime(2027, 8, 14);

  // UN CLIENT SUPABASE QUI N'OUVRE RIEN. `photos_salle_screen.dart` résout les
  // chemins du seau `venue-photos` par lui ; sans client, il échoue pour une
  // raison qui n'a rien à voir avec l'arabe.
  //
  // `autoRefreshToken: false` — GoTrue lance sinon, dès sa construction, un
  // `Timer.periodic` de dix secondes qui ne s'éteint jamais sous le temps
  // simulé. Et pas de `dispose()` : il attend la fermeture d'un canal temps
  // réel qui n'a jamais été ouvert.
  final clientDeTest = SupabaseClient(
    'https://exemple.supabase.co',
    'cle-de-test-sans-valeur',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );

  /// Tous les mois que l'agenda peut demander sans qu'on ait à deviner lequel.
  Map<String, AgendaDuMois> agendas() {
    final maintenant = DateTime.now();
    return <String, AgendaDuMois>{
      for (var d = -1; d <= 12; d++)
        cleDuMois(DateTime(maintenant.year, maintenant.month + d)):
            agendaDeTest(DateTime(maintenant.year, maintenant.month + d)),
    };
  }

  ProviderContainer conteneurDeTest() => ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      estConnecteProvider.overrideWithValue(true),
      preferencesAffichageProvider.overrideWithValue(
        PreferencesEnMemoire(bahia),
      ),
      supabaseClientProvider.overrideWithValue(clientDeTest),
      profilProvider.overrideWith(
        (ref) async => <String, dynamic>{
          'full_name': 'Karim Belkacem',
          'phone': '0770112233',
        },
      ),

      // L'espace propriétaire, chargé de ce que ses propres tests lui donnent.
      ownerRepositoryProvider.overrideWithValue(
        DepotDeTest(
          sallesRendues: <SalleDuProprietaire>[salleDeTest(id: bahia)],
          indicateursRendus: <String, IndicateursSalle>{
            bahia: indicateursDeTest(),
          },
          demandesRendues: <String, List<DemandeEnAttente>>{
            bahia: <DemandeEnAttente>[demandeDeTest(id: demandeId)],
          },
          detailsRendus: <String, DemandeDetail>{
            bookingId: detailDeTest(id: demandeId, venueId: bahia),
          },
          agendasRendus: agendas(),
        ),
      ),
      selecteurDePhotosProvider.overrideWithValue(SelecteurDeTest()),
      compresseurDePhotoProvider.overrideWithValue(CompresseurDeTest()),
      toutesLesWilayasProvider.overrideWith(
        (ref) async => <Wilaya>[
          (code: '31', nom: 'Oran'),
          (code: '16', nom: 'Alger'),
        ],
      ),
      equipementsParCategorieProvider.overrideWith(
        (ref) async => <String, List<Equipement>>{
          'confort': <Equipement>[
            (
              code: 'climatisation',
              libelle: 'Climatisation',
              categorie: 'confort',
            ),
          ],
        },
      ),
      typesEvenementProvider.overrideWith(
        (ref) async => <TypeEvenement>[(code: 'mariage', libelle: 'Mariage')],
      ),

      // L'assistant et les avis.
      assistantRepositoryProvider.overrideWithValue(DepotAssistantDeTest()),
      avisRepositoryProvider.overrideWithValue(
        DepotAvisDeTest(
          salles: <String, AvisDeLaSalle>{
            bahia: avisDeLaSalleDeTest(
              venueId: bahia,
              avis: <AvisPublie>[avisDeTest(id: 'avis-1')],
              synthese: syntheseDeTest(),
            ),
          },
          aDeposerRendus: <String, AvisADeposer>{
            bookingId: aDeposerDeTest(bookingId: bookingId, venueId: bahia),
          },
        ),
      ),

      // Les trois écrans que la liste ne nomme pas — voir le groupe du bas.
      ficheProvider.overrideWith(
        (ref, demande) async => VenueDetail(
          id: bahia,
          nom: 'Salle El Bahia',
          commune: 'Bir El Djir',
          wilayaCode: '31',
          wilayaNom: 'Oran',
          capacite: 450,
          photos: const <String>[
            'https://exemple.test/bahia/1.jpg',
            'https://exemple.test/bahia/2.jpg',
          ],
          equipements: const <EquipementSalle>[],
          typesEvenement: const <TypeEvenement>[],
          tarifs: const <LigneTarif>[],
          options: const <OptionSalle>[],
          dateEstimation: date,
        ),
      ),
      mesReservationsProvider.overrideWith(
        () => _MesReservationsDeTest(<Reservation>[
          Reservation(
            groupId: 'grp-$demandeId',
            bookingId: bookingId,
            venueId: bahia,
            salle: 'Salle El Bahia',
            commune: 'Bir El Djir',
            wilayaNom: 'Oran',
            date: date,
            creneau: Creneau.soir,
            invites: 350,
            typeEvenement: 'Mariage',
            etat: EtatReservation.enAttente,
            montant: 388200,
            creeLe: DateTime(2026, 9, 14),
            options: const <String>['Chambre de la mariée'],
          ),
        ]),
      ),
      notificationsProvider.overrideWith(
        () => _NotificationsDeTest(
          ListeNotifications(
            items: <NotificationFerha>[
              NotificationFerha(
                id: 'notif-1',
                type: TypeNotification.nouvelleDemande,
                role: RoleNotification.proprietaire,
                creeLe: DateTime(2026, 9, 14, 18, 30),
                bookingId: bookingId,
                salle: 'Salle El Bahia',
                commune: 'Bir El Djir',
                date: date,
                creneau: Creneau.soir,
                invites: 350,
              ),
            ],
            nonLues: 1,
          ),
        ),
      ),
    ],
  );

  /// Monte [ecran] en arabe, par-dessus une première page.
  ///
  /// Une seconde en cinq images plutôt que `pumpAndSettle` : plusieurs de ces
  /// écrans portent un squelette qui scintille ou un compte à rebours, et
  /// attendre le repos les attendrait pour toujours.
  Future<void> monte(
    WidgetTester tester,
    Widget ecran, {
    Locale locale = const Locale('ar'),
  }) async {
    tester.view.physicalSize = telephoneDesMaquettes;
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
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: ferhaSupportedLocales,
          theme: FerhaTheme.light(),
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      ),
    );

    unawaited(
      cle.currentState!.push(MaterialPageRoute<void>(builder: (_) => ecran)),
    );

    await tester.pump();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

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
  }

  /// Les écrans que la consigne nomme : propriétaire, assistant, avis.
  final restesEnFrancais = <String, Widget>{
    'propriétaire — tableau de bord': const TableauDeBordScreen(),
    'propriétaire — agenda': const AgendaScreen(),
    'propriétaire — publier une salle': const PublierSalleScreen(),
    'propriétaire — photos de la salle': const PhotosSalleScreen(
      venueId: bahia,
    ),
    'propriétaire — récapitulatif de la salle': const RecapitulatifSalleScreen(
      venueId: bahia,
    ),
    'propriétaire — détail d’une demande': const DetailDemandeScreen(
      bookingId: bookingId,
    ),
    'assistant': const AssistantScreen(),
    'avis — la page d’une salle': const AvisScreen(venueId: bahia),
    'avis — en déposer un': const DeposerAvisScreen(bookingId: bookingId),
  };

  /// Les trois autres — voir le commentaire du groupe.
  final nonNommes = <String, Widget>{
    'galerie de photos': const GalerieScreen(venueId: bahia),
    'mes réservations': const MesReservationsScreen(),
    'notifications': const NotificationsScreen(),
  };

  group('En arabe, les écrans restés en français', () {
    restesEnFrancais.forEach((nom, ecran) {
      testWidgets('$nom tient debout', (tester) async {
        await monte(tester, ecran);
        aucunDebordement(tester, '$nom, en locale ar');
      });
    });
  });

  group('En français, à la même taille — le témoin', () {
    // SANS CE GROUPE, UN ÉCHEC DU PRÉCÉDENT NE DIT PAS CE QU'IL A TROUVÉ.
    //
    // « L'assistant déborde en arabe » et « l'assistant déborde sur un
    // téléphone » sont deux défauts différents : le premier se répare dans le
    // sens de lecture, le second dans la largeur. Les tests propres à ces
    // écrans montent une fenêtre de 1000 × 2400, où rien ne déborde jamais ;
    // ils ne peuvent donc pas répondre.
    //
    // Le témoin monte les mêmes écrans, sur les mêmes 390 × 844, en français.
    // Ce qui échoue ici ET au-dessus n'a rien à voir avec l'arabe.
    restesEnFrancais.forEach((nom, ecran) {
      testWidgets('$nom tient debout', (tester) async {
        await monte(tester, ecran, locale: const Locale('fr'));
        aucunDebordement(tester, '$nom, en locale fr');
      });
    });
  });

  group('En arabe, les écrans que la consigne ne nomme pas', () {
    // LA CONSIGNE DIT « propriétaire, assistant, avis ». Ces trois-là ne sont
    // dans aucune des deux listes : ils ne font pas partie des dix écrans
    // traduits, et ils ne sont pas non plus de l'espace propriétaire.
    //
    // Ils tombent pourtant sous la même règle — ils s'affichent en arabe dès
    // que la langue change —, et les monter coûte deux lignes chacun. On les
    // met donc ici, à part, pour que personne ne croie qu'ils étaient couverts
    // par la liste du dessus.
    //
    // « Mes réservations » est un cas mixte : il passe déjà par l'ARB pour une
    // partie de ses textes, sans être l'un des dix. Il n'est pas jugé sur le
    // français qu'il affiche encore.
    nonNommes.forEach((nom, ecran) {
      testWidgets('$nom tient debout', (tester) async {
        await monte(tester, ecran);
        aucunDebordement(tester, '$nom, en locale ar');
      });
    });
  });
}

/// « Mes réservations », remplacé par une liste fixe.
class _MesReservationsDeTest extends MesReservations {
  _MesReservationsDeTest(this._reservations);

  final List<Reservation> _reservations;

  @override
  Future<List<Reservation>> build() async => _reservations;
}

/// La cloche, remplacée par une liste fixe.
class _NotificationsDeTest extends Notifications {
  _NotificationsDeTest(this._depart);

  final ListeNotifications _depart;

  @override
  Future<ListeNotifications> build() async => _depart;
}
