import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:ferha/core/l10n/formats_ferha.dart';
import 'package:ferha/core/l10n/generated/app_localizations.dart';
import 'package:ferha/core/l10n/locale_controller.dart';
import 'package:ferha/core/router/app_router.dart';
import 'package:ferha/core/router/routes.dart';
import 'package:ferha/core/theme/ferha_theme.dart';
import 'package:ferha/features/booking/mes_reservations_providers.dart';
import 'package:ferha/features/booking/reservation.dart';
import 'package:ferha/features/search/search_filters.dart';

import 'textes_traduits.dart';

/// LA CONFIRMATION DOIT SURVIVRE À UN RECHARGEMENT.
///
/// Même règle que la galerie, et même cause — `extra` de go_router ne franchit
/// pas l'historique du navigateur —, mais une conséquence différente, et c'est
/// ce qui la rendait invisible.
///
/// =============================================================================
/// ELLE NE PLANTAIT PAS, ELLE SE VIDAIT
///
/// `DemandeEnvoyee` n'a pas de `toJson()`. `json.encoder.convert` appelle donc
/// `toEncodable`, qui tente `.toJson()`, échoue, et `dart:convert` réemballe
/// l'échec en `JsonUnsupportedObjectError` (`json.dart`, `writeObject`). Or
/// `_RouteMatchListEncoder` attrape précisément cette erreur-là : il écrit
/// `null` dans l'historique et se contente d'un avertissement au journal.
///
/// Au retour, `extra` vaut donc `null`, le transtypage réussit, et l'écran
/// s'affiche — amputé. La galerie tombait bruyamment ; celle-ci disait « votre
/// demande est partie » sans dire LAQUELLE : plus de salle, plus de date, plus
/// de montant, plus d'options.
///
/// CE TEST NE DEVINE PAS CE COMPORTEMENT, IL LE REJOUE : `extra` y passe par
/// l'aller-retour `json.decode(json.encode(...))`, celui du codec, avec le
/// repli sur `null` que go_router applique quand l'objet n'est pas encodable.
void main() {
  const groupId = '7f3a91c2-0000-4000-a000-000000000001';
  final date = DateTime(2027, 8, 14);

  /// LES ATTENTES SE CALCULENT, ELLES NE SE TAPENT PAS. Un montant porte une
  /// espace fine insécable entre ses milliers, et une espace ordinaire écrite à
  /// la main ferait échouer le test pour une raison invisible à la lecture.
  final formats = FormatsFerha(textesFr);

  /// La réservation telle que `client_bookings()` la rend — options comprises
  /// depuis la migration 033.
  Reservation reservation() => Reservation(
    groupId: groupId,
    bookingId: 'bkg-023',
    venueId: '5a11e000-0000-4000-a000-000000000001',
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
    options: const <String>['Chambre de la mariée', 'Décoration florale'],
  );

  /// Ce que `extra` devient au retour de l'historique.
  ///
  /// go_router n'ayant pas su encoder `DemandeEnvoyee`, il a écrit `null` — et
  /// c'est `null` qui revient. L'aller-retour JSON est écrit ici pour dire d'où
  /// vient cette valeur, et non pour la calculer.
  Object? extraRestaure() => json.decode(json.encode(null));

  Future<GoRouter> ouvre(
    WidgetTester tester, {
    List<Reservation>? reservations,
    Object? erreur,
  }) async {
    // LARGEUR D'UN TÉLÉPHONE, HAUTEUR D'UNE AFFICHE. La largeur décide de la
    // mise en page et reste celle des maquettes ; la hauteur ne décide que de
    // ce que le `ListView` construit. À 844, la référence et le bouton du bas
    // tombent hors de la fenêtre, le sliver ne les crée pas, et `find.text` ne
    // trouve rien — un échec qui ne parle de rien.
    //
    // Le débordement se vérifie ailleurs, à 390 × 844 : c'est le travail de
    // `six_ecrans_en_arabe_test.dart`, et ce n'est pas celui-ci.
    tester.view.physicalSize = const Size(390, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final conteneur = ProviderContainer(
      // AUCUNE NOUVELLE TENTATIVE. Riverpod 3 replanifie de lui-même un
      // fournisseur qui a échoué — c'est très bien dans l'application, et c'est
      // une minuterie qui traîne à la fin d'un test : `pumpAndSettle` ne rend
      // jamais la main tant qu'elle bat. On teste ici ce que l'écran AFFICHE
      // quand la lecture a échoué, pas la politique de reprise.
      retry: (_, _) => null,
      overrides: [
        mesReservationsProvider.overrideWith(
          () => _MesReservationsDeTest(
            reservations ?? <Reservation>[reservation()],
            erreur,
          ),
        ),
      ],
    );
    addTearDown(conteneur.dispose);

    final routeur = conteneur.read(routerProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: conteneur,
        child: MaterialApp.router(
          routerConfig: routeur,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: ferhaSupportedLocales,
          theme: FerhaTheme.light(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return routeur;
  }

  /// L'adresse telle que le navigateur la rouvre : la référence, et rien
  /// d'autre.
  String adresse() => Uri(
    path: FerhaRoutes.demandeEnvoyee,
    queryParameters: <String, String>{'ref': groupId},
  ).toString();

  testWidgets('elle nomme la salle après un rechargement', (tester) async {
    final routeur = await ouvre(tester);

    routeur.push(adresse(), extra: extraRestaure());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.text(textesFr.envoyeeRecueParSalle('Salle El Bahia')),
      findsOneWidget,
      reason:
          'Après un rechargement, l’écran retombait sur la phrase anonyme — '
          '« Le propriétaire l’a reçue » — parce qu’il n’avait plus la salle. '
          'La référence est pourtant dans l’adresse.',
    );
  });

  testWidgets('elle retrouve tout le récapitulatif', (tester) async {
    final routeur = await ouvre(tester);

    routeur.push(adresse(), extra: extraRestaure());
    await tester.pumpAndSettle();

    // Les sept lignes du récapitulatif, celles qui disaient LAQUELLE des
    // demandes on regarde.
    expect(find.text('Salle El Bahia'), findsWidgets);
    expect(find.text('Bir El Djir, Oran'), findsOneWidget);
    expect(
      find.text(
        textesFr.calendrierResumeJour(
          formats.date(date),
          Creneau.soir.auMilieuDUnePhrase(textesFr),
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('350'), findsOneWidget);
    expect(find.text('Mariage'), findsOneWidget);
    expect(
      find.text(
        <String>[
          'Chambre de la mariée',
          'Décoration florale',
        ].join(textesFr.separateurListe),
      ),
      findsOneWidget,
      reason:
          'Les options viennent de client_bookings() depuis la migration 033. '
          'Sans elles, le récapitulatif reste incomplet là où il comptait le '
          'plus : c’est la ligne qui dit ce qui a été ajouté au forfait.',
    );
    expect(find.text(formats.montant(388200)), findsOneWidget);
  });

  testWidgets('la référence affichée reste les huit premiers caractères', (
    tester,
  ) async {
    final routeur = await ouvre(tester);

    routeur.push(adresse(), extra: extraRestaure());
    await tester.pumpAndSettle();

    expect(
      find.text(textesFr.envoyeeReference('7F3A91C2')),
      findsOneWidget,
      reason:
          'De quoi citer la demande au téléphone sans réciter trente-six '
          'caractères.',
    );
  });

  testWidgets('une référence introuvable ne plante pas, elle se replie', (
    tester,
  ) async {
    // L'adresse d'une demande qui n'est pas la sienne, ou une référence
    // inventée. L'écran ne doit rien affirmer qu'il ne sait pas.
    final routeur = await ouvre(tester, reservations: <Reservation>[]);

    routeur.push(adresse(), extra: extraRestaure());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(textesFr.envoyeeRecue), findsOneWidget);
    expect(find.text(textesFr.envoyeeSuiteTitre), findsOneWidget);
  });

  testWidgets('une lecture qui échoue se replie de la même façon', (
    tester,
  ) async {
    // Session expirée, réseau tombé : on ne sait pas, et on ne prétend pas.
    final routeur = await ouvre(tester, erreur: Exception('reseau'));

    routeur.push(adresse(), extra: extraRestaure());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(textesFr.envoyeeRecue), findsOneWidget);
  });
}

/// Le fournisseur de « Mes réservations », remplacé par une liste fixe.
class _MesReservationsDeTest extends MesReservations {
  _MesReservationsDeTest(this._reservations, this._erreur);

  final List<Reservation> _reservations;
  final Object? _erreur;

  @override
  Future<List<Reservation>> build() async {
    if (_erreur != null) throw _erreur;
    return _reservations;
  }
}
