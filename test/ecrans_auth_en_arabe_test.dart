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
import 'package:ferha/features/owner/owner_repository.dart';
import 'package:ferha/features/auth/connexion_screen.dart';
import 'package:ferha/features/auth/inscription_screen.dart';
import 'package:ferha/features/auth/profil_screen.dart';

import 'owner_fakes.dart';
import 'textes_traduits.dart';

/// LES TROIS ÉCRANS D'AUTHENTIFICATION, CONSTRUITS EN ARABE.
///
/// Le même banc que `six_ecrans_en_arabe_test.dart`, sur le même modèle et pour
/// les mêmes raisons : un écran traduit peut être faux de quatre façons, et
/// aucune des quatre ne se voit dans une revue de code française.
///
///   1. il DÉBORDE — les mots arabes n'ont pas la longueur des mots français ;
///   2. il se lit dans le MAUVAIS SENS ;
///   3. sa flèche de retour pointe encore vers l'avant ;
///   4. ses nombres passent en chiffres arabes-indiens.
///
/// CES ÉCRANS-CI PORTENT PLUS DE CHAMPS QUE DE CHIFFRES, et c'est ce qui rend
/// le premier contrôle le plus utile des quatre : un libellé de champ, un texte
/// d'aide et un message de validation se superposent dans la même colonne, et
/// trois lignes arabes plus longues que leurs équivalents français suffisent à
/// faire déborder un formulaire qui tenait.
///
/// LA TAILLE EST CELLE D'UN TÉLÉPHONE — 390 × 844, celle des maquettes. Sur une
/// fenêtre géante, aucun débordement ne se produirait jamais.
void main() {
  /// Le téléphone des maquettes.
  const telephone = Size(390, 844);

  /// Les chiffres arabes-indiens — ceux qu'on ne veut nulle part (§10).
  final chiffresArabes = RegExp(r'[٠-٩۰-۹]');

  /// Un conteneur chargé de ce que les trois écrans lisent.
  ///
  /// PERSONNE N'EST CONNECTÉ PAR DÉFAUT : c'est l'état dans lequel on arrive
  /// sur la connexion et sur l'inscription, et c'est aussi ce qui garde
  /// Supabase hors de ce test — `LocaleController` n'écrit dans `profiles` que
  /// s'il y a quelqu'un, et ne touche pas au client sinon.
  ProviderContainer conteneurDeTest({
    bool connecte = false,
    Map<String, dynamic>? profil,
    Object? erreurDeProfil,
    PreferencesAffichage? preferences,
  }) => ProviderContainer(
    overrides: [
      estConnecteProvider.overrideWithValue(connecte),
      preferencesAffichageProvider.overrideWithValue(
        preferences ?? PreferencesEnMemoire(),
      ),
      ownerRepositoryProvider.overrideWithValue(DepotDeTest()),
      profilProvider.overrideWith((ref) async {
        if (erreurDeProfil != null) throw erreurDeProfil;
        return profil;
      }),
    ],
  );

  /// Un profil complet, tel que `profiles` le rend.
  Map<String, dynamic> profilDe({
    bool proprietaire = false,
    bool admin = false,
    String? telephone = '0770112233',
  }) => <String, dynamic>{
    'id': 'u-023',
    'full_name': 'Amina Benali',
    'email': 'amina@demo.ferha.dz',
    'phone': telephone,
    'is_owner': proprietaire,
    'is_admin': admin,
    'locale': 'ar',
  };

  /// Monte [ecran] en arabe, PAR-DESSUS UNE PREMIÈRE PAGE.
  ///
  /// Le `push` donne à l'`AppBar` sa flèche de retour : un écran monté en
  /// `home` n'a rien derrière lui, et le troisième contrôle n'aurait rien à
  /// regarder.
  Future<void> pompe(
    WidgetTester tester,
    Widget ecran, {
    ProviderContainer? conteneur,
    ThemeData? theme,
    Locale locale = const Locale('ar'),
  }) async {
    tester.view.physicalSize = telephone;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final cle = GlobalKey<NavigatorState>();
    final c = conteneur ?? conteneurDeTest();
    addTearDown(c.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          navigatorKey: cle,
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: ferhaSupportedLocales,
          theme: theme ?? FerhaTheme.light(),
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      ),
    );

    // Sans `await` sur le push : la Future d'une route ne se termine qu'au POP.
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

  final ecrans = <String, Widget>{
    'connexion': const ConnexionScreen(),
    'inscription': const InscriptionScreen(),
    'profil — visiteur': const ProfilScreen(),
  };

  group('En arabe, les écrans d’authentification', () {
    ecrans.forEach((nom, ecran) {
      testWidgets('$nom se construit sans déborder', (tester) async {
        await pompe(tester, ecran);

        expect(
          tester.takeException(),
          isNull,
          reason:
              '$nom déborde en arabe. Laissez le texte se replier — Expanded, '
              'Flexible, ou deux lignes — plutôt que de raccourcir la '
              'traduction.',
        );
      });

      testWidgets('$nom se lit de droite à gauche', (tester) async {
        await pompe(tester, ecran);
        expect(directionDe(tester), TextDirection.rtl);
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
              'En Algérie, les numéros et les dates s’écrivent en chiffres '
              'latins, en arabe comme en français (§10).',
        );
      });

      testWidgets('$nom tient aussi en thème sombre', (tester) async {
        await pompe(tester, ecran, theme: FerhaTheme.dark());

        expect(tester.takeException(), isNull);
        expect(directionDe(tester), TextDirection.rtl);
      });
    });
  });

  group('Le profil d’un compte connecté', () {
    testWidgets('se construit sans déborder, et garde son numéro en latin', (
      tester,
    ) async {
      await pompe(
        tester,
        const ProfilScreen(),
        conteneur: conteneurDeTest(connecte: true, profil: profilDe()),
      );

      expect(tester.takeException(), isNull);
      expect(directionDe(tester), TextDirection.rtl);

      // LE NUMÉRO S'AFFICHE TEL QUE LA BASE LE PORTE : c'est celui qu'on
      // compose, et il ne change pas de chiffres avec la langue.
      expect(find.text('0770112233'), findsOneWidget);
    });

    testWidgets('le badge de rôle est traduit — propriétaire', (tester) async {
      await pompe(
        tester,
        const ProfilScreen(),
        conteneur: conteneurDeTest(
          connecte: true,
          profil: profilDe(proprietaire: true),
        ),
      );

      expect(find.text(textesAr.profilRoleProprietaire), findsOneWidget);
      expect(find.text(textesAr.profilRoleClient), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('le badge de rôle est traduit — cliente, et l’admin avec', (
      tester,
    ) async {
      await pompe(
        tester,
        const ProfilScreen(),
        conteneur: conteneurDeTest(
          connecte: true,
          profil: profilDe(admin: true),
        ),
      );

      expect(find.text(textesAr.profilRoleClient), findsOneWidget);
      expect(find.text(textesAr.profilRoleAdministration), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('un numéro absent le dit dans la langue de l’écran', (
      tester,
    ) async {
      await pompe(
        tester,
        const ProfilScreen(),
        conteneur: conteneurDeTest(
          connecte: true,
          profil: profilDe(telephone: null),
        ),
      );

      expect(find.text(textesAr.profilNonRenseigne), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('La bascule de langue du profil', () {
    testWidgets('annonce toujours la langue vers laquelle elle mène', (
      tester,
    ) async {
      // EN FRANÇAIS ELLE DIT « العربية », EN ARABE ELLE DIT « Français ».
      // C'est l'inverse de ce qu'on écrirait d'instinct, et c'est le point : un
      // bouton « Français » sur une page française ne dit pas s'il change
      // quelque chose.
      await pompe(tester, const ProfilScreen(), locale: const Locale('fr'));
      expect(find.text(textesFr.switchLanguage), findsOneWidget);
      expect(textesFr.switchLanguage, textesFr.langueArabe);

      await pompe(tester, const ProfilScreen());
      expect(find.text(textesAr.switchLanguage), findsOneWidget);
      expect(textesAr.switchLanguage, textesAr.langueFrancais);
    });
  });

  group('Les refus de GoTrue', () {
    testWidgets('s’affichent dans la langue de l’écran', (tester) async {
      // On fait échouer la lecture du profil : c'est le seul chemin par lequel
      // un refus traduit arrive à l'écran sans réseau ni session.
      await pompe(
        tester,
        const ProfilScreen(),
        conteneur: conteneurDeTest(
          connecte: true,
          erreurDeProfil: const AuthException(
            'Invalid login credentials',
            code: 'invalid_credentials',
          ),
        ),
      );

      expect(find.text(textesAr.authIdentifiantsInvalides), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('un code inconnu se nomme, et montre le message d’origine', (
      tester,
    ) async {
      // LE REPLI N'INVENTE RIEN. Le message est en anglais, et c'est mieux
      // qu'un « une erreur est survenue » : celui qui devra corriger le voit.
      const brut = 'Something unexpected';
      await pompe(
        tester,
        const ProfilScreen(),
        conteneur: conteneurDeTest(
          connecte: true,
          erreurDeProfil: const AuthException(brut, code: 'lune_bleue'),
        ),
      );

      expect(
        find.text(textesAr.authRefusNonTraduit('lune_bleue', brut)),
        findsOneWidget,
      );
    });
  });
}
