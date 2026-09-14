/// La langue de l'application : qui la choisit, où elle est retenue, et quand
/// elle s'applique.
///
/// =============================================================================
/// ELLE S'APPLIQUE TOUT DE SUITE, ET C'EST LE POINT
///
/// `MaterialApp.locale` lit ce fournisseur ; changer son état reconstruit
/// l'arbre entier — barre d'onglets, titres, direction du texte. Il n'y a rien
/// à redémarrer, et il ne doit rien y avoir à redémarrer : une application
/// qu'on doit fermer pour changer de langue apprend à son utilisateur qu'il
/// s'est trompé de bouton.
///
/// =============================================================================
/// DEUX ÉCRITURES, ET ELLES NE DISENT PAS LA MÊME CHOSE
///
/// `profiles.locale` suit le COMPTE : c'est la langue qu'on retrouve en se
/// connectant depuis un autre téléphone, et c'est elle que lira un jour le
/// courriel de confirmation ou la notification poussée. Elle n'existe que pour
/// qui a un compte, et elle demande un aller-retour réseau.
///
/// La préférence d'appareil suit le TÉLÉPHONE : elle vaut pour un visiteur qui
/// n'a pas de compte — c'est-à-dire pour tout le parcours du §3 jusqu'à l'envoi
/// d'une demande — et surtout, elle est lisible AVANT la première image.
///
/// C'est pourquoi c'est elle qui décide au démarrage. Faire dépendre la langue
/// du profil ferait s'ouvrir l'application en français chez quelqu'un qui l'a
/// mise en arabe, le temps d'une requête — un clignotement, et dans le mauvais
/// sens de lecture.
///
/// =============================================================================
/// ÉCRIRE DANS LE PROFIL NE DOIT JAMAIS FAIRE ÉCHOUER LA BASCULE
///
/// Le réseau peut être tombé, la session avoir expiré. La langue a déjà changé
/// à l'écran quand la requête part : si elle échoue, on garde le choix sur
/// l'appareil et on se tait. Rendre une erreur ici reviendrait à refuser de
/// changer de langue parce qu'on n'a pas de réseau.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/auth_providers.dart';
import '../preferences/preferences_affichage.dart';
import '../supabase/supabase_providers.dart';

/// Les deux langues livrées : français et arabe (RTL).
const List<Locale> ferhaSupportedLocales = <Locale>[Locale('fr'), Locale('ar')];

/// Langue active de l'application.
class LocaleController extends Notifier<Locale> {
  @override
  Locale build() {
    // LA LECTURE EST ASYNCHRONE, L'ÉTAT DE DÉPART NE L'EST PAS. `build()` doit
    // rendre une langue tout de suite : c'est le français, et la préférence
    // retenue la remplace dès que l'appareil l'a rendue — au pire une image
    // plus tard, sans réseau à attendre.
    _relireLaPreference();
    return ferhaSupportedLocales.first;
  }

  Future<void> _relireLaPreference() async {
    final code = await ref.read(preferencesAffichageProvider).langue();
    final retenue = _localeDepuisCode(code);
    // `ref.mounted` : l'application peut s'être fermée entre-temps, et un
    // fournisseur jeté n'accepte plus d'état.
    if (retenue != null && ref.mounted) state = retenue;
  }

  /// Fixe la langue active, la retient sur l'appareil et l'écrit dans le profil.
  ///
  /// L'ORDRE COMPTE : l'écran change d'abord, le stockage ensuite. Ce qui est
  /// long ou faillible vient après ce qui est instantané et sûr.
  Future<void> choisir(Locale locale) async {
    if (!ferhaSupportedLocales.contains(locale)) return;
    state = locale;

    await ref
        .read(preferencesAffichageProvider)
        .retenirLangue(locale.languageCode);
    await _ecrireDansLeProfil(locale.languageCode);
  }

  /// Bascule entre le français et l'arabe.
  Future<void> toggle() {
    final index = ferhaSupportedLocales.indexOf(state);
    final suivante =
        ferhaSupportedLocales[(index + 1) % ferhaSupportedLocales.length];
    return choisir(suivante);
  }

  /// Écrit `profiles.locale`, sans jamais faire échouer la bascule.
  Future<void> _ecrireDansLeProfil(String code) async {
    // ON DEMANDE D'ABORD S'IL Y A QUELQU'UN, ET ON LE DEMANDE À L'APPLICATION.
    //
    // Personne n'est connecté : il n'y a pas de profil où écrire, et ce n'est
    // pas une erreur — le parcours du §3 se fait sans compte. Passer par
    // `estConnecteProvider` plutôt que par le client a une seconde vertu : la
    // langue d'un visiteur se change sans que Supabase soit même touché.
    if (!ref.read(estConnecteProvider)) return;

    final client = ref.read(supabaseClientProvider);
    final utilisateur = client.auth.currentUser;
    if (utilisateur == null) return;

    try {
      await client
          .from('profiles')
          .update(<String, dynamic>{'locale': code})
          .eq('id', utilisateur.id);
    } on Object catch (erreur) {
      // Voir l'en-tête : la langue a déjà changé, et elle est retenue sur
      // l'appareil. On note, on ne dérange pas.
      debugPrint('Langue non écrite dans le profil : $erreur');
    }
  }
}

/// La `Locale` d'un code de langue, ou `null` s'il n'est pas des nôtres.
Locale? _localeDepuisCode(String? code) {
  if (code == null) return null;
  for (final locale in ferhaSupportedLocales) {
    if (locale.languageCode == code) return locale;
  }
  return null;
}

/// La langue active de l'application.
final localeProvider = NotifierProvider<LocaleController, Locale>(
  LocaleController.new,
);
