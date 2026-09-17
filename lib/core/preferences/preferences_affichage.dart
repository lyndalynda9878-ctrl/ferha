import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ce que l'appareil retient d'une ouverture à l'autre.
///
/// N'Y METTRE QUE DES PRÉFÉRENCES D'AFFICHAGE — la salle choisie dans l'espace
/// propriétaire, la langue, le thème clair ou sombre. C'est une règle du
/// projet, elle est écrite dans CLAUDE.md, et elle tient à ce qu'est ce
/// stockage : un fichier en clair sur l'appareil, `localStorage` sur le web,
/// que n'importe quelle extension de navigateur peut lire. Aucune donnée
/// métier, aucun jeton, aucun identifiant sensible n'y entre. Un numéro de
/// téléphone rangé ici échapperait à la règle du §9, qui ne le révèle qu'après
/// acceptation ; un prix rangé ici deviendrait une seconde source à côté
/// d'`estimate_price()`.
///
/// La session, elle, n'est pas notre affaire : `supabase_flutter` range son
/// jeton lui-même, chiffré ou non selon la plateforme, et c'est son problème.
///
/// SharedPreferencesAsync plutôt que l'ancienne API à cache : on lit une clé au
/// moment d'en avoir besoin, sans instance à construire au démarrage, donc sans
/// rien à attendre avant la première image.
abstract interface class PreferencesAffichage {
  /// La dernière salle ouverte dans l'espace propriétaire, ou `null`.
  Future<String?> salleChoisie();

  /// Retient la salle ouverte. `null` oublie le choix.
  Future<void> retenirSalle(String? venueId);

  /// Le code de langue retenu — `fr`, `ar` — ou `null` si personne n'a choisi.
  ///
  /// UNE LANGUE EST UNE PRÉFÉRENCE D'AFFICHAGE, et c'est ce qui lui donne le
  /// droit d'être ici : elle ne dit rien de qui vous êtes, elle dit comment
  /// vous voulez lire. Elle est aussi la seule chose qu'il faut connaître AVANT
  /// la première image — avant la session, avant le réseau, avant le profil.
  /// Une langue qui attendrait une réponse de Supabase ferait clignoter
  /// l'application en français chez quelqu'un qui l'a mise en arabe.
  ///
  /// `profiles.locale` reste la trace durable, celle qui suit le compte d'un
  /// appareil à l'autre ; les deux s'écrivent ensemble.
  Future<String?> langue();

  /// Retient la langue choisie.
  Future<void> retenirLangue(String codeLangue);

  /// Le mode de thème retenu — `system`, `light`, `dark` — ou `null` si
  /// personne n'a encore touché le bouton.
  ///
  /// `null` N'EST PAS `system`, ET LA DIFFÉRENCE EST TOUT L'INTÉRÊT DE CETTE
  /// CLÉ. Les deux donnent le même écran — celui que le téléphone demande —
  /// mais `null` dit « on ne m'a jamais rien demandé », là où `system` dirait
  /// « on m'a demandé de suivre le téléphone ». Le premier lancement est le
  /// premier cas, et c'est lui qui fait arriver en sombre quelqu'un dont
  /// l'appareil est en sombre.
  ///
  /// Comme la langue, c'est une préférence d'affichage, et pour la même
  /// raison : elle ne dit rien de qui vous êtes, elle dit comment vous voulez
  /// lire. Elle n'a en revanche PAS de jumelle en base — il n'existe pas de
  /// `profiles.theme`, et il n'en faut pas : un thème n'a aucune raison de
  /// suivre un compte d'un appareil à l'autre, puisqu'il répond d'abord à
  /// l'écran qu'on a sous les yeux et à la lumière de la pièce.
  Future<String?> modeTheme();

  /// Retient le mode de thème choisi.
  Future<void> retenirModeTheme(String nomDuMode);
}

/// L'implémentation qui écrit vraiment sur l'appareil.
class PreferencesAffichagePartagees implements PreferencesAffichage {
  /// Crée le service.
  PreferencesAffichagePartagees([SharedPreferencesAsync? stockage])
    : _stockage = stockage ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _stockage;

  /// Préfixée par `ferha.` : sur le web, l'application partage `localStorage`
  /// avec tout ce qui tourne sur le même domaine, la session Supabase comprise.
  static const String _cleSalle = 'ferha.owner.venue';

  /// Préfixée comme la précédente, et pour la même raison.
  static const String _cleLangue = 'ferha.langue';

  /// Préfixée comme les deux précédentes, et pour la même raison.
  static const String _cleTheme = 'ferha.theme';

  @override
  Future<String?> salleChoisie() => _stockage.getString(_cleSalle);

  @override
  Future<void> retenirSalle(String? venueId) => venueId == null
      ? _stockage.remove(_cleSalle)
      : _stockage.setString(_cleSalle, venueId);

  @override
  Future<String?> langue() => _stockage.getString(_cleLangue);

  @override
  Future<void> retenirLangue(String codeLangue) =>
      _stockage.setString(_cleLangue, codeLangue);

  @override
  Future<String?> modeTheme() => _stockage.getString(_cleTheme);

  @override
  Future<void> retenirModeTheme(String nomDuMode) =>
      _stockage.setString(_cleTheme, nomDuMode);
}

/// Les préférences d'affichage de l'appareil.
///
/// Un fournisseur, et non un appel direct : les tests le remplacent par une
/// version en mémoire, sans plateforme à simuler.
final preferencesAffichageProvider = Provider<PreferencesAffichage>(
  (ref) => PreferencesAffichagePartagees(),
);
