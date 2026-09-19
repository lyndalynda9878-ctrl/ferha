/// LES QUATRE CONTRÔLES D'UNE RELECTURE EN ARABE.
///
/// Ce fichier ne se termine pas par `_test.dart` : `flutter test` ne le lance
/// pas, il l'importe. Deux bancs s'en servent — la relecture des dix écrans
/// traduits, et celle des écrans restés en français.
///
/// Un écran monté en arabe peut être faux de quatre façons, et aucune des
/// quatre ne se voit dans une revue de code française :
///
///   1. il DÉBORDE — les mots arabes n'ont pas la longueur des mots français ;
///   2. il garde du FRANÇAIS À L'ÉCRAN — une chaîne oubliée en dur, un libellé
///      qui n'est jamais passé par l'ARB ;
///   3. il écrit ses nombres en CHIFFRES ARABES-INDIENS — illisibles pour qui
///      achète en Algérie (§10) ;
///   4. ses ICÔNES suivent mal la direction — la flèche de retour pointe encore
///      vers l'avant, ou bien une loupe s'est retournée avec elle.
///
/// =============================================================================
/// CHAQUE CONTRÔLE DIT OÙ, ET IL DIT QUOI
///
/// Tous prennent [ou] — le nom de l'écran et de l'état sous lesquels il a été
/// monté. Un banc qui monte trente fois un widget doit nommer laquelle de ses
/// trente images a échoué, sinon il fait perdre le temps qu'il fait gagner.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ferha/core/theme/display_font.dart';

/// =============================================================================
/// CHARGER LA VRAIE POLICE, SANS QUOI LE PREMIER CONTRÔLE MENT
///
/// `flutter test` ne charge aucune police : il rend chaque signe dans un CARRÉ
/// de la taille du corps. « Assistant Ferha » en corps 20 mesure alors 297 px
/// là où Bricolage Grotesque en donne environ 150 — et une barre de titre
/// parfaitement saine se met à déborder de 69 px.
///
/// Sur une fenêtre de 1000 px, comme dans les autres bancs, cela ne se voyait
/// pas. Sur les 390 px des maquettes, cela invente des défauts.
///
/// LA POLICE DE LA CHARTE EST DANS LE DÉPÔT — `assets/fonts/`, déclarée au
/// `pubspec` —, donc on la charge et on mesure pour de vrai. Elle habille les
/// TITRES ; le texte courant prend la police système, que le test ne peut pas
/// charger et qui reste donc en carrés. Le contrôle du débordement continue
/// d'exagérer la largeur du texte courant : il peut crier pour rien, il ne peut
/// pas se taire à tort. C'est le bon sens de l'erreur.
Future<void> chargeLaPoliceDeLaCharte() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final chargeur = FontLoader(ferhaDisplayFontFamily)
    ..addFont(rootBundle.load('assets/fonts/BricolageGrotesque-Variable.ttf'));
  await chargeur.load();
}

/// Le téléphone des maquettes.
///
/// C'est la seule taille sous laquelle un débordement veut dire quelque chose :
/// sur une fenêtre géante, aucun ne se produit jamais.
const telephoneDesMaquettes = Size(390, 844);

/// Les chiffres arabes-indiens et persans — ceux qu'on ne veut nulle part.
final chiffresArabesIndiens = RegExp(r'[٠-٩۰-۹]');

/// Une suite d'au moins deux lettres latines, accents compris.
///
/// DEUX, ET PAS UNE : un « L » isolé peut être une initiale, un sigle, une
/// unité. Deux lettres à la file, c'est un mot — et dans un écran arabe, un mot
/// latin est un mot oublié, sauf s'il vient de la base (voir
/// [donneesDeLaBase]).
final motsLatins = RegExp(r'[A-Za-zÀ-ÖØ-öø-ÿ]{2,}');

/// =============================================================================
/// LES DEUX EXCEPTIONS CONNUES — ce qui reste en français À DESSEIN.
///
/// Le contrôle 2 ne peut pas les distinguer d'un oubli : ce sont des chaînes
/// comme les autres, affichées comme les autres. On les lui nomme donc une
/// fois, ici, et le banc les reprend dans une rubrique à part.
///
///   * LES LIBELLÉS D'OPTIONS viennent de `venue_options.label_fr`. La colonne
///     `label_ar` existe et personne ne l'écrit encore.
///   * LES ÉQUIPEMENTS, LES TYPES D'ÉVÉNEMENT ET LES WILAYAS viennent
///     respectivement d'`amenities.label_fr`, d'`event_types.label_fr` et de
///     `wilayas.name_fr` — les trois fournisseurs de `search_providers.dart` le
///     disent dans leur `select`. Leurs 73 traductions arabes attendent une
///     relecture humaine dans `docs/libelles-arabes-a-relire.md`.
///
/// S'Y AJOUTENT LES NOMS PROPRES DU JEU D'ESSAI — la salle, la commune, le
/// propriétaire, la cliente. Une salle s'appelle comme elle s'appelle, dans
/// toutes les langues.
///
/// CE N'EST PAS UNE LISTE DE MOTS TOLÉRÉS EN GÉNÉRAL : ce sont les valeurs
/// EXACTES que le jeu d'essai fait descendre de la base. Un mot français qui
/// n'y figure pas ressort, même s'il ressemble à l'un d'eux.
const donneesDeLaBase = <String>{
  // Les noms propres du jeu d'essai.
  //
  // ILS SE RELISENT CONTRE LA BASE, PAS CONTRE LA MÉMOIRE. « Amina Benali » et
  // « Karim Belkacem » ont figuré ici pendant des semaines : la base dit
  // « Amina Haddad » et « Karim Belhadj », et « Benali » est le nom d'une
  // TROISIÈME personne du décor, Sofia. Une tolérance qui protège un nom
  // inexistant ne protège rien — elle laisse le vrai nom se faire accuser par
  // le premier écran arabe qui l'affichera, avec un message qui désignera la
  // traduction au lieu de désigner cette liste.
  'Salle El Bahia',
  'Bir El Djir',
  'Oran',
  'Alger',
  'Karim Belhadj',
  'Amina Haddad',
  'amina@demo.ferha.dz',
  // Les référentiels, en label_fr.
  'Climatisation',
  'Jardin',
  'Parking',
  'Mariage',
  'Henné',
  // Les options, en label_fr.
  'Chambre de la mariée',
  'Décoration florale',
};

/// =============================================================================
/// LA TROISIÈME CATÉGORIE — des mots latins DANS une phrase arabe, et traduits.
///
/// Celle-ci n'était pas prévue, et c'est le banc qui l'a trouvée : les quatre
/// entrées ci-dessous sont sorties des dix écrans à la première exécution. La
/// phrase qui les porte est bel et bien en arabe dans `app_ar.arb` ; c'est le
/// mot lui-même qui ne se traduit pas.
///
/// On ne les retire donc pas de l'écran — on les retire du CONTRÔLE, en disant
/// pourquoi. Chacune a été ouverte dans l'ARB avant d'arriver ici.
const motsQuiRestentLatins = <String>{
  // « بطاقة CIB » — la carte interbancaire algérienne. Une marque s'écrit
  // comme elle s'écrit ; Edahabia, elle, a un nom arabe et le porte (الذهبية).
  'CIB',
  // « الدخول بحساب Amina (زبونة) » — les deux comptes de démonstration de
  // l'écran de connexion. Ce sont des identifiants de comptes, pas des
  // personnages : les écrire أمينة et كريم en ferait deux autres comptes aux
  // yeux du lecteur.
  'Amina',
  'Karim',
  // « الترحيل 007_auth.sql غير مطبَّق على مشروع Supabase » — un nom de fichier
  // et un nom de produit. Cette phrase-là ne s'adresse pas au client mais à
  // celui qui installe, et elle doit nommer exactement ce qu'il doit ouvrir.
  '007_auth.sql',
  'Supabase',
  // LA BASCULE DE LANGUE ANNONCE LA LANGUE VERS LAQUELLE ELLE MÈNE : en arabe
  // elle dit « Français », en français elle dit « العربية ». C'est l'inverse de
  // ce qu'on écrirait d'instinct, et c'est le point — un bouton « العربية » sur
  // une page arabe ne dit pas s'il change quelque chose.
  'Français',
};

/// Tout ce que le contrôle 2 laisse passer, sauf mention contraire.
const tolerancesParDefaut = <String>{
  ...donneesDeLaBase,
  ...motsQuiRestentLatins,
};

/// Tout le texte réellement affiché, rassemblé.
List<String> textesAffiches(WidgetTester tester) => <String>[
  for (final t in tester.widgetList<Text>(find.byType(Text)))
    t.data ?? t.textSpan?.toPlainText() ?? '',
];

/// Les mots latins qui restent dans [textes] une fois [tolere] retiré.
///
/// PURE, ET C'EST VOULU : elle ne touche ni à l'arbre ni au testeur, donc le
/// banc peut la nourrir de chaînes connues pour vérifier qu'elle voit encore.
/// Un contrôle dont la loupe s'est cassée ne dit plus rien, et ne le dit pas.
///
/// Les chaînes tolérées sont retirées de la PLUS LONGUE à la plus courte :
/// « Salle El Bahia » doit partir avant « Oran », sans quoi un retrait partiel
/// laisserait des moitiés de noms propres derrière lui.
List<String> motsLatinsRestants(
  Iterable<String> textes, {
  Set<String> tolere = tolerancesParDefaut,
}) {
  final aRetirer = tolere.toList()
    ..sort((a, b) => b.length.compareTo(a.length));

  final restants = <String>[];
  for (final texte in textes) {
    var reste = texte;
    for (final connue in aRetirer) {
      reste = reste.replaceAll(connue, ' ');
    }
    restants.addAll(motsLatins.allMatches(reste).map((m) => m[0]!));
  }
  return restants;
}

/// CONTRÔLE 1 — aucun débordement.
///
/// Un débordement est une EXCEPTION, pas un avertissement : `RenderFlex
/// overflowed by N pixels` passe par `FlutterError`, et `takeException` la
/// ramasse. Rien à ramasser veut dire que tout tient dans 390 px.
///
/// `takeException` VIDE la file : ce contrôle passe donc en premier partout, et
/// une seule fois par image.
void aucunDebordement(WidgetTester tester, String ou) {
  expect(
    tester.takeException(),
    isNull,
    reason:
        '$ou : la mise en page a levé. Le plus souvent c’est un débordement — '
        'les mots arabes n’ont pas la longueur des mots français, et une '
        'rangée qui tenait de justesse ne tient plus. Laissez le texte se '
        'replier — Expanded, Flexible, ou deux lignes — plutôt que de '
        'raccourcir la traduction.',
  );
}

/// CONTRÔLE 2 — aucun texte français resté affiché.
void aucunTexteFrancais(
  WidgetTester tester,
  String ou, {
  Set<String> tolere = tolerancesParDefaut,
}) {
  final restants = motsLatinsRestants(textesAffiches(tester), tolere: tolere);

  expect(
    restants,
    isEmpty,
    reason:
        '$ou affiche encore des mots latins : ${restants.join(' | ')}\n'
        'Soit la chaîne est écrite en dur dans l’écran, soit elle manque à '
        'app_ar.arb. Si elle vient de la base — un libellé label_fr, un nom '
        'propre —, ajoutez-la à « donneesDeLaBase » en disant d’où elle sort.',
  );
}

/// CONTRÔLE 3 — aucun chiffre arabe-indien.
void aucunChiffreArabeIndien(WidgetTester tester, String ou) {
  final fautifs = textesAffiches(
    tester,
  ).where(chiffresArabesIndiens.hasMatch).toList();

  expect(
    fautifs,
    isEmpty,
    reason:
        '$ou affiche des chiffres arabes-indiens : ${fautifs.join(' | ')}\n'
        'En Algérie, les prix, les dates et les numéros s’écrivent en chiffres '
        'latins, en arabe comme en français (§10). Passez par FormatsFerha, '
        'qui met en forme à la main et ne laisse jamais intl choisir.',
  );
}

/// CONTRÔLE 4 — les icônes directionnelles retournées, les autres non.
///
/// COMMENT FLUTTER RETOURNE UNE ICÔNE : quand `IconData.matchTextDirection` est
/// vrai ET que la direction est RTL, `Icon.build` enveloppe son glyphe dans un
/// `Transform` qui inverse l'axe des x. On ne lit donc pas un booléen de la
/// charte — on regarde la matrice réellement posée.
///
/// LE TRANSFORM EST DESSOUS, PAS AU-DESSUS : chercher un ancêtre ne trouverait
/// rien, et le contrôle passerait au vert sur une flèche jamais retournée.
///
/// LA DIRECTION SE LIT À L'ENDROIT DE L'ICÔNE, pas à la racine : un champ de
/// téléphone forcé en LTR contient des icônes qui ne doivent PAS se retourner,
/// et les accuser serait accuser le bon comportement.
///
/// ON COMPTE LES MIROIRS AU-DESSUS AUTANT QU'EN DESSOUS, et on regarde la
/// PARITÉ. Sans les ancêtres, la moitié de ce contrôle serait morte : une icône
/// non directionnelle ne se retourne jamais toute seule — `Icon` ne pose son
/// `Transform` que si `matchTextDirection` est vrai —, donc « retournée à
/// tort » ne peut venir que d'un `Transform` posé À LA MAIN plus haut. Ne
/// regarder que le sous-arbre revenait à écrire une branche qu'aucun défaut ne
/// pouvait jamais atteindre.
///
/// Deux miroirs se composent en identité, trois en un miroir : la parité est la
/// réponse exacte, et non une approximation.
void lesIconesSuiventLaDirection(WidgetTester tester, String ou) {
  final fautives = <String>[];

  for (final noeud in tester.elementList(find.byType(Icon))) {
    final glyphe = (noeud.widget as Icon).icon;
    if (glyphe == null) continue;

    final rtl = Directionality.of(noeud) == TextDirection.rtl;
    final devraitSeRetourner = glyphe.matchTextDirection && rtl;
    final seRetourne = _miroirs(noeud).isOdd;

    if (devraitSeRetourner && !seRetourne) {
      fautives.add('${_nomme(glyphe)} n’est pas retournée');
    } else if (!devraitSeRetourner && seRetourne) {
      fautives.add('${_nomme(glyphe)} est retournée à tort');
    }
  }

  expect(
    fautives,
    isEmpty,
    reason:
        '$ou : ${fautives.join(' ; ')}\n'
        'Seules les icônes qui montrent une DIRECTION se retournent en arabe : '
        'la flèche de retour montre d’où l’on vient, et l’on vient de la '
        'droite. Une loupe retournée n’est pas une loupe arabe, c’est une '
        'loupe à l’envers. Le choix se fait en prenant l’icône qui porte '
        '« matchTextDirection », jamais en posant un Transform à la main.',
  );
}

/// Le nombre de `Transform` qui inversent les x autour et sous [noeud].
///
/// STRICTEMENT UN MIROIR : x inversé ET y laissé tel quel. Une animation
/// d'échelle passe par des valeurs qui ne sont pas −1, et une rotation touche
/// les deux axes — ni l'une ni l'autre ne doit compter pour un retournement.
int _miroirs(Element noeud) {
  var compte = 0;

  bool estUnMiroir(Widget w) =>
      w is Transform &&
      w.transform.storage[0] == -1.0 &&
      w.transform.storage[5] == 1.0;

  void descend(Element e) {
    if (estUnMiroir(e.widget)) compte++;
    e.visitChildren(descend);
  }

  noeud.visitChildren(descend);
  noeud.visitAncestorElements((e) {
    if (estUnMiroir(e.widget)) compte++;
    return true;
  });

  return compte;
}

/// Les icônes directionnelles de Material, par point de code.
///
/// UNE ICÔNE FAUTIVE DOIT SE NOMMER. `IconData` ne connaît pas son nom — c'est
/// une constante, pas un objet —, et « U+E5C4 » n'aide personne à ouvrir le bon
/// fichier. Cette table couvre la famille qui se retourne, c'est-à-dire
/// exactement celle qui peut être prise en défaut.
const _nomsConnus = <int, String>{
  0xe5c4: 'Icons.arrow_back',
  0xe5c8: 'Icons.arrow_forward',
  0xe5e0: 'Icons.arrow_back_ios',
  0xe5e1: 'Icons.arrow_forward_ios',
  0xe5cb: 'Icons.chevron_left',
  0xe5cc: 'Icons.chevron_right',
  0xe163: 'Icons.send',
};

String _nomme(IconData glyphe) {
  final connu = _nomsConnus[glyphe.codePoint];
  final code = 'U+${glyphe.codePoint.toRadixString(16).toUpperCase()}';
  return connu == null ? 'l’icône $code' : '$connu ($code)';
}
