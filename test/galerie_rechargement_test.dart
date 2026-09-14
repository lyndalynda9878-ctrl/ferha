import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:ferha/core/l10n/generated/app_localizations.dart';
import 'package:ferha/core/l10n/locale_controller.dart';
import 'package:ferha/core/router/app_router.dart';
import 'package:ferha/core/router/routes.dart';
import 'package:ferha/core/theme/ferha_theme.dart';
import 'package:ferha/features/venue/venue_detail.dart';
import 'package:ferha/features/venue/venue_providers.dart';

/// LA GALERIE DOIT SURVIVRE À UN RECHARGEMENT.
///
/// C'est la règle du README, section « La recherche » : une page se partage et
/// se recharge. Une galerie qui dépend de ce que l'écran précédent lui a tendu
/// ne le peut pas — et elle ne s'en tirait pas par un affichage dégradé, elle
/// plantait.
///
/// =============================================================================
/// CE QUI REVIENT DE L'HISTORIQUE DU NAVIGATEUR, ET POURQUOI CE N'EST PAS CE
/// QU'ON Y AVAIT MIS
///
/// `go_router` range l'état de navigation dans l'historique du navigateur, et
/// `extra` avec. La sérialisation est dans `RouteMatchListCodec`
/// (go_router 17.2.3, `lib/src/match.dart`) : sans `extraCodec` — Ferha n'en
/// fournit pas —, `_RouteMatchListEncoder` appelle `json.encoder.convert(extra)`
/// et `_RouteMatchListDecoder` relit avec `json.decoder.convert(...)`.
///
/// Un décodeur JSON ne rend que des `List<dynamic>`, des `Map<String, dynamic>`
/// et des primitives. Une `List<String>` n'en ressort donc JAMAIS — pas
/// « parfois », jamais. Au retour d'un rechargement ou du bouton Précédent, un
/// `as List<String>?` sur cet `extra` ne peut que lever.
///
/// CE TEST NE DEVINE PAS CE TYPE, IL LE FABRIQUE PAR LE MÊME CHEMIN : l'aller-
/// retour `json.decode(json.encode(...))` est exactement celui du codec. Si
/// go_router change de sérialisation un jour, ce test changera avec lui sans
/// qu'on ait à le réécrire.
void main() {
  const venueId = '5a11e000-0000-4000-a000-000000000001';

  /// Les photos que la BASE porte — trois.
  ///
  /// DES URL COMPLÈTES, ET C'EST NÉCESSAIRE ICI : `photo_salle.dart` rend telle
  /// quelle une valeur qui commence par `http`, et ne résout par le bucket
  /// `venue-photos` que les chemins. Un chemin ferait lire
  /// `supabaseClientProvider`, que rien n'initialise dans un test — et la
  /// galerie échouerait pour une raison qui n'a aucun rapport avec ce qu'on
  /// vérifie.
  const photosDeLaBase = <String>[
    'https://exemple.test/bahia/1.jpg',
    'https://exemple.test/bahia/2.jpg',
    'https://exemple.test/bahia/3.jpg',
  ];

  /// Les photos que la fiche avait tendues — DEUX, et volontairement
  /// différentes.
  ///
  /// C'est ce qui rend le test lisible une fois le bug parti : la galerie doit
  /// montrer les TROIS de la base, et non les deux de l'écran précédent. Un
  /// compte identique des deux côtés ne prouverait rien.
  const photosTendues = <String>[
    'https://exemple.test/ancienne/1.jpg',
    'https://exemple.test/ancienne/2.jpg',
  ];

  VenueDetail salle() => VenueDetail(
    id: venueId,
    nom: 'Salle El Bahia',
    commune: 'Oran',
    wilayaCode: '31',
    wilayaNom: 'Oran',
    capacite: 450,
    photos: photosDeLaBase,
    equipements: const <EquipementSalle>[],
    typesEvenement: const <TypeEvenement>[],
    tarifs: const <LigneTarif>[],
    options: const <OptionSalle>[],
    dateEstimation: DateTime(2027, 8, 14),
  );

  /// L'`extra` tel qu'il REVIENT de l'historique, et non tel qu'on l'y a mis.
  Object? extraRestaure(List<String> photos) =>
      json.decode(json.encode(photos));

  Future<GoRouter> ouvre(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final conteneur = ProviderContainer(
      overrides: [ficheProvider.overrideWith((ref, demande) async => salle())],
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

  testWidgets('la galerie s’ouvre avec un extra revenu de l’historique', (
    tester,
  ) async {
    final routeur = await ouvre(tester);

    routeur.push(
      FerhaRoutes.galerieDe(venueId),
      extra: extraRestaure(photosTendues),
    );
    await tester.pumpAndSettle();

    expect(
      tester.takeException(),
      isNull,
      reason:
          'La galerie a levé en s’ouvrant. Au retour de l’historique, `extra` '
          'est ce que json.decode en a fait — jamais une List<String>. Une '
          'page qui ne survit pas à un rechargement ne se partage pas, et '
          'c’est la règle du README.',
    );
  });

  testWidgets('elle montre les photos de la BASE, pas celles qu’on lui tend', (
    tester,
  ) async {
    final routeur = await ouvre(tester);

    routeur.push(
      FerhaRoutes.galerieDe(venueId),
      extra: extraRestaure(photosTendues),
    );
    await tester.pumpAndSettle();

    // Le titre de la galerie est « 1 / N ». Trois, celles de la base — et non
    // deux, celles que la fiche avait tendues.
    expect(
      find.text('1 / ${photosDeLaBase.length}'),
      findsOneWidget,
      reason:
          'La galerie devrait compter les ${photosDeLaBase.length} photos de '
          'la base. Si elle en compte ${photosTendues.length}, elle lit encore '
          'ce que l’écran précédent lui a tendu — ce qu’un rechargement ne lui '
          'tendra pas.',
    );
  });

  testWidgets('elle s’ouvre aussi sans rien du tout — le lien profond', (
    tester,
  ) async {
    final routeur = await ouvre(tester);

    // Le cas d'une adresse collée : aucun `extra`, personne devant.
    routeur.push(FerhaRoutes.galerieDe(venueId));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('1 / ${photosDeLaBase.length}'), findsOneWidget);
  });
}
