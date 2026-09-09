import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ce que l'appareil retient d'une ouverture à l'autre.
///
/// N'Y METTRE QUE DES PRÉFÉRENCES D'AFFICHAGE — la salle choisie dans l'espace
/// propriétaire, la langue. C'est une règle du projet, elle est écrite dans
/// CLAUDE.md, et elle tient à ce qu'est ce stockage : un fichier en clair sur
/// l'appareil, `localStorage` sur le web, que n'importe quelle extension de
/// navigateur peut lire. Aucune donnée métier, aucun jeton, aucun identifiant
/// sensible n'y entre. Un numéro de téléphone rangé ici échapperait à la règle
/// du §9, qui ne le révèle qu'après acceptation ; un prix rangé ici deviendrait
/// une seconde source à côté d'`estimate_price()`.
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

  @override
  Future<String?> salleChoisie() => _stockage.getString(_cleSalle);

  @override
  Future<void> retenirSalle(String? venueId) => venueId == null
      ? _stockage.remove(_cleSalle)
      : _stockage.setString(_cleSalle, venueId);
}

/// Les préférences d'affichage de l'appareil.
///
/// Un fournisseur, et non un appel direct : les tests le remplacent par une
/// version en mémoire, sans plateforme à simuler.
final preferencesAffichageProvider = Provider<PreferencesAffichage>(
  (ref) => PreferencesAffichagePartagees(),
);
