import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ferha/core/l10n/generated/app_localizations.dart';
import 'package:ferha/core/l10n/locale_controller.dart';
import 'package:ferha/core/theme/ferha_theme.dart';
import 'package:ferha/features/search/search_filters.dart';
import 'package:ferha/features/venue/calendrier_screen.dart';
import 'package:ferha/features/venue/venue_detail.dart';
import 'package:ferha/features/venue/venue_providers.dart';

/// Changer de créneau ne doit pas renvoyer la liste en haut.
///
/// Le calendrier fait dix-huit mois : quelqu'un qui regarde mars 2027 et compare
/// midi et soir ne peut pas redescendre toute la liste à chaque puce touchée.
///
/// Le piège est discret. Chaque créneau a son propre fournisseur dans la
/// famille : passer de midi à soir en vise un autre, qui commence par
/// `AsyncLoading` sans valeur précédente. Rendre le squelette à ce moment-là
/// démonte le `ListView` des mois, et un `ListView` démonté emporte sa position.
/// Le test regarde donc la position, pas les couleurs.
void main() {
  const venueId = '6f1a2b3c-0000-4000-8000-000000000001';

  /// Le soir se fait attendre : c'est cette attente qui, avant, remettait la
  /// liste en haut.
  late Completer<Map<DateTime, EtatJour>> soir;

  setUp(() => soir = Completer<Map<DateTime, EtatJour>>());

  Future<void> ouvre(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          calendrierProvider.overrideWith((ref, demande) {
            if (demande.creneau == Creneau.soir) return soir.future;
            return Future<Map<DateTime, EtatJour>>.value(
              <DateTime, EtatJour>{},
            );
          }),
          // La fiche ne sert qu'au prix du bandeau du bas : on la laisse en
          // attente pour ne rien appeler.
          ficheProvider.overrideWith(
            (ref, demande) => Completer<VenueDetail>().future,
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: ferhaSupportedLocales,
          theme: FerhaTheme.light(),
          home: const CalendrierScreen(venueId: venueId, creneau: Creneau.midi),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  ScrollableState liste(WidgetTester tester) => tester.state<ScrollableState>(
    find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first,
  );

  testWidgets('le changement de créneau garde la position de défilement', (
    tester,
  ) async {
    await ouvre(tester);

    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();

    final avant = liste(tester).position.pixels;
    expect(avant, greaterThan(0), reason: 'la liste a bien défilé');

    await tester.tap(find.text('Soir'));
    await tester.pump();

    expect(
      liste(tester).position.pixels,
      avant,
      reason: 'pendant que le soir se charge, la liste ne bouge pas',
    );

    soir.complete(<DateTime, EtatJour>{});
    await tester.pumpAndSettle();

    expect(
      liste(tester).position.pixels,
      avant,
      reason: 'les états arrivés, la liste est toujours au même endroit',
    );
  });
}
