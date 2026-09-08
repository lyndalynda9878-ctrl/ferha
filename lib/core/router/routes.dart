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

  /// Résultats de recherche.
  ///
  /// Hors de la barre d'onglets : les résultats s'ouvrent par-dessus l'accueil
  /// et se referment dessus, avec les critères intacts.
  ///
  /// Les critères voyagent en paramètres de requête et non par `extra` :
  /// sur le web, une recherche doit pouvoir se copier, se partager et survivre
  /// à un rechargement de page.
  static const String resultats = '/resultats';

  /// Connexion par e-mail et mot de passe.
  ///
  /// Hors de la barre d'onglets : on y entre par-dessus l'écran en cours, et
  /// on en revient exactement là où l'on était.
  static const String connexion = '/connexion';

  /// Création de compte.
  static const String inscription = '/inscription';

  /// Paramètre de requête de [connexion] : la route à rejoindre une fois
  /// connecté.
  ///
  /// `/connexion?retour=/salle/123` ramène le client sur la fiche qu'il
  /// consultait, et non sur un accueil qui lui ferait tout recommencer.
  static const String parametreRetour = 'retour';

  /// Route cachée : galerie de contrôle de l'identité visuelle.
  ///
  /// Volontairement absente de la barre d'onglets. On y accède par lien
  /// profond (`/_design` dans la barre d'adresse en web) ou par
  /// `context.go(FerhaRoutes.design)` depuis le code.
  static const String design = '/_design';
}
