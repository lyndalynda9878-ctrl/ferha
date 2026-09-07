import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Les deux langues livrées : français et arabe (RTL).
const List<Locale> ferhaSupportedLocales = <Locale>[Locale('fr'), Locale('ar')];

/// Langue active de l'application.
///
/// Le socle garde le choix en mémoire uniquement ; la persistance dans le
/// profil arrivera avec l'écran « Choix de la langue ».
class LocaleController extends Notifier<Locale> {
  @override
  Locale build() => ferhaSupportedLocales.first;

  /// Fixe la langue active.
  void set(Locale locale) => state = locale;

  /// Bascule entre le français et l'arabe.
  void toggle() {
    final index = ferhaSupportedLocales.indexOf(state);
    final next = (index + 1) % ferhaSupportedLocales.length;
    state = ferhaSupportedLocales[next];
  }
}

/// La langue active de l'application.
final localeProvider = NotifierProvider<LocaleController, Locale>(
  LocaleController.new,
);
