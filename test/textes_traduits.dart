import 'package:ferha/core/l10n/generated/app_localizations.dart';
import 'package:ferha/core/l10n/generated/app_localizations_ar.dart';
import 'package:ferha/core/l10n/generated/app_localizations_fr.dart';

/// Les textes traduits, hors de tout arbre de widgets.
///
/// POUR LES TESTS QUI APPELLENT UNE FONCTION, ET NON UN ÉCRAN. `refusDemande`,
/// `refusAcompte` et `resteEnMots` prennent désormais les textes en premier
/// paramètre : ils traduisent, et une traduction a besoin d'une langue. Dans un
/// écran, elle vient du contexte ; ici, il n'y a pas de contexte, et construire
/// un `MaterialApp` autour d'une assertion sur une chaîne serait démesuré.
///
/// Les deux classes générées s'instancient directement — c'est ce que fait le
/// délégué lui-même, sans rien charger d'asynchrone pour ces deux langues.
final AppLocalizations textesFr = AppLocalizationsFr();

/// Les mêmes, en arabe. Voir [textesFr].
final AppLocalizations textesAr = AppLocalizationsAr();
