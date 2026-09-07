/// Chemins de navigation de l'application.
///
/// Un seul endroit où les chaînes de route sont écrites : les écrans appellent
/// `context.go(FerhaRoutes.favoris)`, jamais une chaîne littérale.
abstract final class FerhaRoutes {
  /// Onglet 1 — accueil / découverte.
  static const String accueil = '/accueil';

  /// Onglet 2 — assistant de recherche.
  static const String assistant = '/assistant';

  /// Onglet 3 — favoris.
  static const String favoris = '/favoris';

  /// Onglet 4 — profil et réglages.
  static const String profil = '/profil';

  /// Route cachée : galerie de contrôle de l'identité visuelle.
  ///
  /// Volontairement absente de la barre d'onglets. On y accède par lien
  /// profond (`/_design` dans la barre d'adresse en web) ou par
  /// `context.go(FerhaRoutes.design)` depuis le code.
  static const String design = '/_design';
}
