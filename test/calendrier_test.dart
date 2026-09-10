import 'package:flutter_test/flutter_test.dart';

import 'package:ferha/core/widgets/grille_calendrier.dart';

/// La semaine du calendrier commence par DIMANCHE.
///
/// Règle du cahier des charges, énoncée deux fois : les maquettes de l'écran 4
/// affichent « D L M M J V S », et le paragraphe RTL précise que « le
/// calendrier commence toujours par dimanche mais se lit de droite à gauche ».
///
/// Je l'avais d'abord écrit en semaine commençant le lundi. Ce test est là pour
/// que la charte l'emporte sans qu'on ait à s'en souvenir.
void main() {
  test('dimanche ouvre la semaine, samedi la ferme', () {
    expect(colonneDuJour(DateTime(2027, 8, 8)), 0, reason: 'un dimanche');
    expect(colonneDuJour(DateTime(2027, 8, 9)), 1, reason: 'un lundi');
    expect(colonneDuJour(DateTime(2027, 8, 14)), 6, reason: 'un samedi');
  });

  test('le 1er août 2027 est un dimanche et ouvre la grille', () {
    expect(colonneDuJour(DateTime(2027, 8)), 0);
  });

  test('un mois décale sa première case selon le jour qui le commence', () {
    // Septembre 2026 commence un mardi, octobre un jeudi.
    expect(colonneDuJour(DateTime(2026, 9)), 2, reason: 'mardi');
    expect(colonneDuJour(DateTime(2026, 10)), 4, reason: 'jeudi');
  });
}
