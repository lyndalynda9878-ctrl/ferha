import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// LE TEST QUI EMPÊCHE UN FICHIER TRADUIT DE SE FAIRE MANGER SON ENCODAGE.
///
/// Le 17 septembre 2026, les dix chaînes de l'onglet Favoris sont entrées dans
/// les deux ARB en passant par `str.encode().decode('unicode-escape')` — un
/// raccourci qui déplie bien les échappements Unicode, mais relit TOUT LE
/// RESTE en latin-1.
/// « Ce favori n'a pas pu être enregistré. » est devenu « Ce favori nâa pas
/// pu Ãªtre enregistrÃ©. », et les dix valeurs arabes sont devenues dix suites
/// de lettres latines sans aucun sens.
///
/// RIEN NE L'A VU PENDANT DEUX JOURS. L'analyse ne lit pas les valeurs d'un
/// ARB ; le JSON restait valide ; les quatre contrôles de relecture arabe
/// auraient attrapé les dix valeurs cassées — « Ø§ÙÙÙØ¶ÙÙØ© » est fait de
/// mots latins, et c'est exactement ce que cherche `aucunTexteFrancais` —, mais
/// ils montent DIX ÉCRANS NOMMÉS, et l'écran des favoris n'en fait pas partie.
/// Un contrôle qui suit la liste des écrans traduits arrive toujours après le
/// dernier écran écrit.
///
/// CELUI-CI NE SUIT AUCUNE LISTE. Il lit les deux fichiers comme du texte, du
/// premier octet au dernier, et il échoue au PREMIER caractère abîmé — dans une
/// clé, dans une valeur, dans une description, n'importe où. C'est ce qui le
/// rend utile : il n'a rien à apprendre quand un écran s'ajoute.
///
/// =============================================================================
/// LES DEUX SIGNATURES, ET POURQUOI ELLES NE PEUVENT PAS SE TROMPER
///
/// 1. UN CARACTÈRE DE COMMANDE C1 (U+0080 à U+009F). Aucun texte n'en contient
///    jamais — ni le français, ni l'arabe, ni le JSON. Il n'apparaît que comme
///    débris : l'apostrophe typographique U+2019 abîmée donne « â » suivi de
///    deux de ces caractères, invisibles à l'écran, et c'est ce qui rendait
///    « nâa » si difficile à lire dans un diff.
///
/// 2. UNE SUITE QUI SE RELIT EN UTF-8. C'est la définition exacte du double
///    encodage, et non une ressemblance : on prend chaque suite de caractères
///    compris entre U+0080 et U+00FF — les seuls que le latin-1 sait écrire —,
///    on les remet en octets, et on demande à UTF-8 de les lire. « Ã© » donne
///    les octets C3 A9, qu'UTF-8 lit « é » : ces deux caractères-là étaient un
///    « é » et on peut le prouver.
///
///    Un accent sain ne passe pas ce filtre. « é » seul donne l'octet E9, qui
///    n'est pas de l'UTF-8 valide ; « TÂCHES » donne C2 puis une lettre ASCII,
///    donc une amorce sans suite. Les deux sont refusés par le décodeur, et le
///    test se tait — c'est le bon sens de l'erreur : il ne peut crier que
///    lorsqu'il a de quoi montrer le texte d'origine.
void main() {
  /// Les deux fichiers traduits, en entier.
  ///
  /// Ce sont les seuls fichiers dont une valeur part à l'écran sans que
  /// personne la relise. Un README abîmé se voit en l'ouvrant ; une chaîne
  /// d'ARB abîmée ne se voit qu'en montant l'écran, dans la bonne langue.
  const arb = <String>['lib/core/l10n/app_fr.arb', 'lib/core/l10n/app_ar.arb'];

  for (final chemin in arb) {
    test('$chemin n’a pas un seul caractère abîmé', () {
      final fichier = File(chemin);
      expect(
        fichier.existsSync(),
        isTrue,
        reason:
            '$chemin est introuvable. Si le fichier a été déplacé, ce test '
            'doit suivre : sans lui, plus rien ne surveille l’encodage des '
            'traductions.',
      );

      final degats = degatsDe(fichier.readAsStringSync(encoding: utf8));

      expect(
        degats,
        isEmpty,
        reason:
            '$chemin porte ${degats.length} passage(s) abîmé(s). Le premier :\n'
            '${degats.isEmpty ? '' : degats.first}\n\n'
            'C’est un double encodage : du texte UTF-8 relu en latin-1, puis '
            'réécrit. Il vient presque toujours d’un script qui fabrique le '
            'fichier — `encode().decode(\'unicode-escape\')` en Python fait '
            'exactement cela, et il ne prévient pas. Écrivez les chaînes '
            'DIRECTEMENT dans l’ARB, ou n’ouvrez le fichier qu’avec un '
            'encodage nommé, en lecture comme en écriture.',
      );
    });
  }

  // ===========================================================================
  // LE DÉTECTEUR VOIT ENCORE
  //
  // Un contrôle qui balaye un fichier propre passe au vert, qu'il sache
  // chercher ou non. Celui-ci coûte quatre lignes et répond à la seule question
  // qui compte le jour où le fichier n'est plus propre : est-ce que la loupe
  // fonctionne toujours ? Les trois cas viennent du vrai dégât du 17 septembre.
  // ===========================================================================
  group('Le détecteur d’encodage voit encore', () {
    // LES EXEMPLES SE FABRIQUENT, ILS NE S'ÉCRIVENT PAS. Un dégât recopié à la
    // main dans la source est faux deux fois sur trois : il perd en chemin les
    // caractères invisibles, et la suite d'octets qui reste n'est plus de
    // l'UTF-8 valide — le détecteur se tait, à raison, et le banc accuse la
    // loupe au lieu d'accuser l'exemple. `latin1.decode(utf8.encode(...))` EST
    // le double encodage, exactement : c'est la panne, reproduite.
    String abime(String sain) => latin1.decode(utf8.encode(sain));

    test('il attrape une voyelle accentuée doublement encodée', () {
      final degats = degatsDe('"favorisErreurTitre": "${abime('chargés')}"');
      expect(degats, hasLength(1));
      expect(degats.first.lisait, 'é');
    });

    test(
      'il attrape l’apostrophe typographique, débris invisibles compris',
      () {
        final degats = degatsDe('"favoriNonEnregistre": "${abime('n’a')}"');
        expect(degats, isNotEmpty);
        expect(degats.first.ligne, 1);
      },
    );

    test('il attrape une valeur arabe entière, et sait la relire', () {
      const sain = 'المفضّلة';
      final degats = degatsDe('"favorisTitre": "${abime(sain)}"');
      expect(degats, isNotEmpty);
      expect(degats.map((d) => d.lisait).join(), sain);
    });

    test('il laisse passer du français et de l’arabe sains', () {
      expect(
        degatsDe(
          '"favorisVideTitre": "Rien de côté pour l’instant",\n'
          '"favorisVideTexte": "Touchez le cœur sur une salle.",\n'
          '"description": "L’etat vide NE DIT PAS « aucun favori »,\n'
          '   et les TÂCHES de fond n’y changent rien.",\n'
          '"favorisTitre": "المفضّلة"',
        ),
        isEmpty,
      );
    });
  });
}

/// Un passage abîmé, et de quoi aller le corriger sans le chercher.
class Degat {
  const Degat({
    required this.ligne,
    required this.colonne,
    required this.abime,
    required this.lisait,
  });

  /// Où, dans le fichier — numérotées comme un éditeur les numérote.
  final int ligne;
  final int colonne;

  /// Ce qui est écrit aujourd'hui.
  final String abime;

  /// Ce que c'était avant d'être abîmé, quand on sait le reconstituer.
  ///
  /// Nul pour un caractère de commande isolé : on sait qu'il est impossible,
  /// on ne sait pas de quoi il est le débris.
  final String? lisait;

  @override
  String toString() => lisait == null
      ? 'ligne $ligne, colonne $colonne : ${_nomme(abime)} — un caractère de '
            'commande, impossible dans du texte.'
      : 'ligne $ligne, colonne $colonne : « $abime » ${_nomme(abime)} '
            'devrait se lire « $lisait ».';

  static String _nomme(String s) =>
      '(${s.runes.map((r) => 'U+${r.toRadixString(16).toUpperCase().padLeft(4, '0')}').join(' ')})';
}

/// Tous les passages abîmés de [contenu], dans l'ordre où ils s'y trouvent.
///
/// PURE, ET C'EST VOULU — comme `motsLatinsRestants` de `controles_arabe.dart` :
/// elle ne touche à aucun fichier, donc le banc peut la nourrir de chaînes
/// connues pour vérifier qu'elle voit encore.
List<Degat> degatsDe(String contenu) {
  final runes = contenu.runes.toList();
  final degats = <Degat>[];

  // La position se tient à mesure : refaire le compte des retours à la ligne
  // pour chaque dégât coûterait un balayage par dégât.
  var ligne = 1;
  var colonne = 1;
  var i = 0;

  while (i < runes.length) {
    final r = runes[i];

    // Une suite latin-1 est une suite : elle s'arrête au premier caractère
    // ASCII ou au premier caractère hors de portée — un caractère arabe sain,
    // par exemple, qui ne peut pas faire partie du dégât.
    if (r < 0x80 || r > 0xFF) {
      if (r == 0x0A) {
        ligne++;
        colonne = 1;
      } else {
        colonne++;
      }
      i++;
      continue;
    }

    var fin = i;
    while (fin < runes.length && runes[fin] >= 0x80 && runes[fin] <= 0xFF) {
      fin++;
    }
    final serie = runes.sublist(i, fin);

    // LA RELECTURE D'ABORD, LE DÉBRIS ENSUITE — et l'ordre n'est pas
    // indifférent. Une valeur arabe doublement encodée est faite de suites
    // « Ø§ », « Ù„ » dont le SECOND caractère est justement un caractère de
    // commande : chercher le débris en premier ferait crier le test à la bonne
    // ligne, mais avec le mauvais message — « un caractère impossible » là où
    // il peut dire « ceci était المفضّلة ». Un test qui échoue doit rendre la
    // correction évidente, pas seulement signaler qu'il faut chercher.

    // SIGNATURE 2 — la série se relit en UTF-8. C'est la preuve, et elle porte
    // le texte d'origine avec elle. `allowMalformed: false` est le défaut et
    // c'est lui qui fait le tri : il LÈVE sur un accent sain, et ce refus est
    // la réponse qu'on attend.
    var vu = false;
    try {
      final relu = utf8.decode(serie, allowMalformed: false);
      if (relu != String.fromCharCodes(serie)) {
        degats.add(
          Degat(
            ligne: ligne,
            colonne: colonne,
            abime: String.fromCharCodes(serie),
            lisait: relu,
          ),
        );
        vu = true;
      }
    } on FormatException {
      // Du texte sain, ou un dégât trop mutilé pour se relire. La signature 1
      // ci-dessous répond du second cas.
    }

    // SIGNATURE 1 — un caractère de commande C1. Elle rattrape ce que la
    // relecture ne peut plus reconstituer : un dégât amputé — recopié à la
    // main, tronqué par un éditeur — n'est plus de l'UTF-8 valide, mais il
    // garde ses caractères impossibles, et ils suffisent à le condamner.
    if (!vu) {
      final commande = serie.indexWhere((c) => c >= 0x80 && c <= 0x9F);
      if (commande >= 0) {
        degats.add(
          Degat(
            ligne: ligne,
            colonne: colonne + commande,
            abime: String.fromCharCode(serie[commande]),
            lisait: null,
          ),
        );
      }
    }

    colonne += serie.length;
    i = fin;
  }

  return degats;
}
