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

  /// Fiche d'une salle. `/salle/:id`
  ///
  /// Les critères de recherche la suivent en paramètres de requête — date,
  /// créneau, invités — parce que c'est d'eux que dépend le prix affiché en bas
  /// de l'écran. Une fiche ouverte sans critères tarife pour aujourd'hui.
  static const String salle = '/salle/:id';

  /// Chemin de la fiche d'une salle donnée.
  static String salleDe(String id) => '/salle/$id';

  /// Galerie plein écran d'une salle. `/salle/:id/galerie`
  static const String galerie = '/salle/:id/galerie';

  /// Chemin de la galerie d'une salle donnée.
  static String galerieDe(String id) => '/salle/$id/galerie';

  /// Calendrier de disponibilité d'une salle. `/salle/:id/calendrier`
  static const String calendrier = '/salle/:id/calendrier';

  /// Chemin du calendrier d'une salle donnée.
  static String calendrierDe(String id) => '/salle/$id/calendrier';

  /// Demande de réservation d'une salle. `/salle/:id/demande`
  ///
  /// On y arrive depuis le bouton du calendrier, une date et un créneau
  /// choisis. Les deux voyagent en paramètres de requête, comme partout
  /// ailleurs : c'est de la date et du créneau que dépend le devis, et une
  /// demande en cours doit survivre à un rechargement de page sur le web.
  ///
  /// Ce qui NE voyage PAS dans l'adresse : les options cochées et le type
  /// d'événement. Ils sont l'état de l'écran, et cet écran ne se quitte que
  /// d'une seule façon — l'écran de connexion, qui s'ouvre PAR-DESSUS et se
  /// referme dessus sans le démonter.
  static const String demande = '/salle/:id/demande';

  /// Chemin de la demande pour une salle donnée.
  static String demandeDe(String id) => '/salle/$id/demande';

  /// Confirmation d'une demande envoyée. `/demande-envoyee`
  ///
  /// Hors de l'arborescence de la salle : on n'y revient pas, on en sort. Le
  /// récapitulatif voyage par `extra` ; l'adresse ne porte que la référence du
  /// groupe, seul survivant d'un rechargement de page.
  static const String demandeEnvoyee = '/demande-envoyee';

  /// Suivi des réservations du client. `/mes-reservations`
  ///
  /// Hors de la barre d'onglets : on y entre depuis le profil et on en revient
  /// dessus. Aucun paramètre — la liste est celle de l'utilisateur connecté, et
  /// personne d'autre ne peut la demander : `client_bookings()` ne connaît que
  /// `auth.uid()`.
  static const String mesReservations = '/mes-reservations';

  /// Tableau de bord du propriétaire. `/proprietaire/tableau`
  ///
  /// SOUS UN PRÉFIXE DÈS AUJOURD'HUI, ALORS QU'IL N'Y A QU'UN ÉCRAN. C'est le
  /// seul travail que cette étape fait pour la suivante : l'espace propriétaire
  /// aura sa propre barre d'onglets — Tableau, Agenda, Messages, Ma salle
  /// (écran 9) —, et elle enveloppera `/proprietaire/*`. Poser cet écran à la
  /// racine aujourd'hui obligerait à le déménager ce jour-là, avec les liens
  /// qui pointent dessus et les adresses que Karim aura mises en favori. Le
  /// préfixe coûte huit caractères maintenant et évite tout cela.
  ///
  /// LA BARRE, ELLE, N'ARRIVE PAS TOUT DE SUITE, et c'est délibéré : trois
  /// onglets morts sur quatre disent au propriétaire que l'application est
  /// inachevée bien plus fort que leur absence.
  ///
  /// Aucun paramètre : la salle regardée n'est pas dans l'adresse, elle est
  /// dans les préférences de l'appareil. Un tableau de bord n'est ni partageable
  /// ni copiable — le contraire d'une recherche, dont les critères voyagent
  /// justement pour cela.
  static const String proprietaireTableau = '/proprietaire/tableau';

  /// Détail d'une demande, côté propriétaire. `/proprietaire/demande/:id`
  ///
  /// Sous le même préfixe que le tableau de bord, et pour la même raison : la
  /// barre d'onglets propriétaire enveloppera `/proprietaire/*` quand elle
  /// viendra.
  ///
  /// L'identifiant est celui de la LIGNE représentative du groupe, pas celui du
  /// groupe : c'est ce qu'attendent `owner_request_detail()`,
  /// `accepter_demande()` et `refuser_demande()`, qui remontent au groupe
  /// elles-mêmes. Une journée entière s'ouvre donc par l'un de ses deux
  /// créneaux, et se répond d'un bloc.
  static const String proprietaireDemande = '/proprietaire/demande/:id';

  /// Chemin du détail d'une demande donnée.
  static String proprietaireDemandeDe(String bookingId) =>
      '/proprietaire/demande/$bookingId';

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
