import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ferha/features/booking/widgets/compte_a_rebours.dart';

/// Le compte à rebours des 72 h, testé là où il vit.
///
/// « Il doit se mettre à jour tout seul, sans quitter l'écran » : c'est un
/// comportement, pas un rendu, et il se vérifie sur le widget seul plutôt qu'à
/// travers l'écran entier. Le faire passer par « Mes réservations » obligerait
/// à faire descendre une horloge de test à travers trois widgets privés —
/// c'est-à-dire à abîmer le code pour le tester.
///
/// DEUX HORLOGES, ET C'EST TOUT LE PIÈGE. `tester.pump(durée)` avance celle des
/// minuteries et des animations ; `DateTime.now()` continue de lire la vraie.
/// Sans horloge injectée, la minuterie battrait bien soixante fois, et le texte
/// ne bougerait pas d'un pouce — un test vert sur un compteur figé.
void main() {
  /// L'instant que le widget croira être « maintenant ».
  late DateTime maintenant;

  Future<void> pose(WidgetTester tester, DateTime echeance) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompteARebours(
            echeance: echeance,
            style: const TextStyle(),
            maintenant: () => maintenant,
          ),
        ),
      ),
    );
  }

  setUp(() => maintenant = DateTime(2026, 9, 9, 20));

  testWidgets('il descend tout seul, sans que personne ne touche à rien', (
    tester,
  ) async {
    await pose(tester, maintenant.add(const Duration(hours: 2, seconds: 30)));
    expect(find.text('2 h 00 min'), findsOneWidget);

    // Le temps passe. L'écran, lui, ne bouge pas.
    maintenant = maintenant.add(const Duration(seconds: 31));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('2 h 00 min'), findsNothing);
    expect(find.text('1 h 59 min'), findsOneWidget);
  });

  testWidgets('il ne se redessine pas soixante fois par minute', (
    tester,
  ) async {
    // Trois heures et trente secondes : dix secondes plus tard, on est encore
    // dans la même minute affichée. Poser l'échéance à trois heures pile
    // ferait basculer le texte dès la première seconde, et ce test ne
    // vérifierait plus rien.
    await pose(tester, maintenant.add(const Duration(hours: 3, seconds: 30)));
    expect(find.text('3 h 00 min'), findsOneWidget);

    // Dix secondes plus tard, la minuterie a battu dix fois et le texte est le
    // même : il ne doit pas y avoir eu de reconstruction. On le vérifie par
    // l'élément, qui serait remplacé si le widget avait été rebâti autrement.
    final avant = tester.element(find.text('3 h 00 min'));
    for (var i = 0; i < 10; i++) {
      maintenant = maintenant.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    }

    expect(find.text('3 h 00 min'), findsOneWidget);
    expect(tester.element(find.text('3 h 00 min')), same(avant));
  });

  testWidgets('passé l’échéance, il dit « délai écoulé »', (tester) async {
    await pose(tester, maintenant.add(const Duration(minutes: 1)));
    expect(find.text('1 min'), findsOneWidget);

    // expire_options() ne tourne qu'à l'heure (§7.2) : entre l'échéance et son
    // passage, l'écran doit dire que le délai est écoulé plutôt que d'afficher
    // un compteur négatif.
    maintenant = maintenant.add(const Duration(minutes: 2));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('délai écoulé'), findsOneWidget);
  });

  testWidgets('changer d’échéance repart du bon compte, sans attendre', (
    tester,
  ) async {
    await pose(tester, maintenant.add(const Duration(hours: 5)));
    expect(find.text('5 h 00 min'), findsOneWidget);

    // Le temps réel fait sa liste des réservations : une autre échéance peut
    // prendre la place de celle-ci dans le même élément.
    await pose(tester, maintenant.add(const Duration(hours: 12)));

    expect(find.text('12 h 00 min'), findsOneWidget);
  });
}
