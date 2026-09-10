import 'package:flutter_test/flutter_test.dart';

import 'package:ferha/core/validation/telephone.dart';

/// La règle du numéro de téléphone, côté Flutter.
///
/// CE FICHIER ET `supabase/tests/007_adresse_et_telephone.sql` PORTENT LES MÊMES
/// NUMÉROS, et c'est tout leur intérêt. La règle est écrite deux fois — une fois
/// ici, une fois dans `telephone_valide()` (migration 020) — parce qu'elle sert
/// deux fois : celle-ci éteint le bouton avant qu'on appuie, celle de la base
/// refuse et a le dernier mot. Deux exemplaires d'une règle finissent toujours
/// par diverger ; deux listes d'exemples identiques, elles, le font savoir.
///
/// Si vous ajoutez un numéro ici, ajoutez-le là-bas.
void main() {
  group('Ce que la règle accepte', () {
    const bons = <String>[
      '0770112233', // mobile Mobilis
      '0661445566', // mobile Djezzy
      '0555778899', // mobile Ooredoo
      '0770 11 22 33', // le même, comme on l'écrit sur une carte de visite
      ' 0661445566 ', // des blancs autour
      '041234567', // fixe, Oran
      '021 23 45 67', // fixe, Alger
    ];

    for (final numero in bons) {
      test('« $numero » est accepté', () {
        expect(TelephoneAlgerien.estValide(numero), isTrue);
        expect(TelephoneAlgerien.ceQuiManque(numero), isNull);
      });
    }
  });

  group('Ce que la règle refuse', () {
    const mauvais = <String>[
      '', // vide
      '   ', // des blancs
      '07701122', // huit chiffres : ni un mobile, ni un fixe
      '07701122334', // un chiffre de trop
      '1770112233', // ne commence pas par zéro
      '+213770112233', // l'indicatif international n'est pas de la mise en forme
      '0770-11-22-33', // les tirets non plus
      '0770.11.22.33',
      '0770AB2233', // des lettres
    ];

    for (final numero in mauvais) {
      test('« $numero » est refusé', () {
        expect(TelephoneAlgerien.estValide(numero), isFalse);
        expect(TelephoneAlgerien.ceQuiManque(numero), isNotNull);
      });
    }

    test('un numéro absent n’est pas valide', () {
      expect(TelephoneAlgerien.estValide(null), isFalse);
    });
  });

  group('Ce qu’on garde de ce qui a été tapé', () {
    test('les espaces disparaissent, les chiffres restent', () {
      expect(TelephoneAlgerien.normalise('0770 11 22 33'), '0770112233');
      expect(TelephoneAlgerien.normalise(' 0661445566 '), '0661445566');
    });

    test('ce qui n’est pas de la mise en forme reste, et sera refusé', () {
      // On ne rattrape PAS les tirets : les retirer en silence reviendrait à
      // deviner ce que quelqu'un a voulu écrire. Le refus est plus honnête, et
      // l'écran dit la forme attendue.
      expect(TelephoneAlgerien.normalise('0770-11-22-33'), '0770-11-22-33');
      expect(TelephoneAlgerien.estValide('0770-11-22-33'), isFalse);
    });
  });

  group('Ce qui manque, et la phrase qu’on en fait', () {
    test('un champ vide ne gronde personne', () {
      // Il n'y a pas de faute à ne pas avoir encore rempli un champ : la phrase
      // demande, elle ne reproche pas.
      expect(
        TelephoneAlgerien.ceQuiManque(''),
        'Indiquez un numéro de téléphone.',
      );
    });

    test('un numéro à moitié tapé reçoit un exemple, pas une règle', () {
      // « Format : 0[567]\\d{8} » ne se lit pas. Un exemple se recopie.
      final phrase = TelephoneAlgerien.ceQuiManque('0770 11')!;
      expect(phrase, contains('0770 11 22 33'));
      expect(phrase, contains('041 23 45 67'));
    });
  });
}
