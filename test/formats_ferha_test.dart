import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ferha/core/l10n/formats_ferha.dart';

import 'textes_traduits.dart';

/// LES FORMATS QUI NE DOIVENT PAS CHANGER AVEC LA LANGUE — ET CEUX QUI DOIVENT.
///
/// Le §10 des maquettes tient en trois phrases, et deux d'entre elles se
/// vérifient ici sans dessiner un seul écran : les chiffres restent latins, et
/// le calendrier commence par dimanche. La troisième — la flèche retournée —
/// demande un rendu, et vit dans `six_ecrans_en_arabe_test.dart`.
void main() {
  final fr = FormatsFerha(textesFr);
  final ar = FormatsFerha(textesAr);

  /// L'espace fine insécable des milliers (U+202F).
  ///
  /// NOMMÉE PLUTÔT QU'ÉCRITE : dans une chaîne de test, elle est
  /// invisible — et une attente qui échoue sur un caractère qu'on ne
  /// voit pas coûte une demi-heure à comprendre.
  final fine = String.fromCharCode(0x202f);

  /// Les chiffres arabes-indiens, ceux qu'on ne veut nulle part.
  final chiffresArabes = RegExp(r'[٠-٩۰-۹]');

  group('Les nombres restent en chiffres latins', () {
    test(
      'un montant s’écrit avec les mêmes chiffres dans les deux langues',
      () {
        expect(fr.nombre(343200), '343${fine}200');
        expect(ar.nombre(343200), '343${fine}200');
      },
    );

    test('aucun montant ne porte de chiffre arabe-indien', () {
      for (final montant in <num>[0, 900, 12500, 343200, 1250000]) {
        expect(chiffresArabes.hasMatch(ar.montant(montant)), isFalse);
        expect(chiffresArabes.hasMatch(fr.montant(montant)), isFalse);
      }
    });

    test('aucune date ne porte de chiffre arabe-indien', () {
      final jour = DateTime(2027, 8, 14);
      expect(chiffresArabes.hasMatch(ar.date(jour)), isFalse);
      expect(chiffresArabes.hasMatch(ar.jourEtDate(jour)), isFalse);
      expect(chiffresArabes.hasMatch(ar.moisEtAnnee(jour)), isFalse);
    });

    test('le séparateur des milliers est une espace fine insécable', () {
      // U+202F, et non une espace ordinaire : elle ne coupe pas un montant en
      // bout de ligne, et elle ne se traduit pas — c'est une espace, pas un
      // signe.
      expect(fr.nombre(1250000), '1${fine}250${fine}000');
    });

    test('seule la devise change de langue', () {
      expect(fr.montant(343200), '343${fine}200 DA');
      expect(ar.montant(343200), contains('343${fine}200'));
      expect(ar.montant(343200), isNot(contains('DA')));
    });

    test('la devise seule et le montant complet disent la même chose', () {
      // DEUX CLÉS POUR UNE MÊME MONNAIE, parce que la carte de salle met le
      // nombre en gras et la devise en gris. Elles finiraient par diverger si
      // rien ne les tenait ensemble — c'est ce que fait ce test.
      expect(textesFr.montantEnDinars('1'), contains(textesFr.devise));
      expect(textesAr.montantEnDinars('1'), contains(textesAr.devise));
    });
  });

  group('Les dates', () {
    final quatorzeAout = DateTime(2027, 8, 14);

    test('se lisent dans chaque langue', () {
      expect(fr.date(quatorzeAout), '14 août 2027');
      expect(ar.date(quatorzeAout), '14 أوت 2027');
    });

    test('les mois arabes sont ceux de l’Algérie, pas ceux du Machrek', () {
      // « أوت » et non « أغسطس » : c'est le mois qu'on lit sur un calendrier
      // algérien, dans un journal algérien et sur un acte d'état civil.
      expect(ar.mois(8), 'أوت');
      expect(ar.mois(1), 'جانفي');
      expect(ar.mois(7), 'جويلية');
    });

    test('le titre d’un mois prend la capitale en français, rien en arabe', () {
      expect(fr.moisEnTitre(8), 'Août');
      expect(ar.moisEnTitre(8), 'أوت');
    });

    test('le nom du jour suit le calendrier', () {
      // Le 14 août 2027 est un samedi — et c'est la maquette qui se trompait
      // en le plaçant un jeudi, pas le calendrier.
      expect(fr.jour(quatorzeAout), 'samedi');
      expect(ar.jour(quatorzeAout), 'السبت');
    });
  });

  group('Le calendrier commence toujours par dimanche', () {
    test('en français comme en arabe', () {
      expect(fr.initialesDesJours.first, textesFr.initialeDimanche);
      expect(fr.initialesDesJours.last, textesFr.initialeSamedi);
      expect(ar.initialesDesJours.first, textesAr.initialeDimanche);
      expect(ar.initialesDesJours.last, textesAr.initialeSamedi);
    });

    test('sept colonnes, ni six ni huit', () {
      expect(ar.initialesDesJours, hasLength(7));
    });
  });

  group('L’espacement des capitales', () {
    testWidgets('vaut la charte en latin et zéro en arabe', (tester) async {
      // EN ARABE, LES LETTRES D'UN MOT SE LIENT. Les écarter ne donne pas un
      // titre aéré : cela casse les liaisons, et le mot devient méconnaissable.
      late double enLatin;
      late double enArabe;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) {
              enLatin = context.espacementDesCapitales();
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.rtl,
          child: Builder(
            builder: (context) {
              enArabe = context.espacementDesCapitales();
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(enLatin, 1.2);
      expect(enArabe, 0);
    });
  });
}
