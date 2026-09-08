# Ferha — règles du projet

Application Flutter de réservation de salles des fêtes en Algérie.
Références : docs/cahier-des-charges_1.html (produit, base de données,
palette en §10.1) et docs/maquettes.html (écrans).

## Avant d'écrire du code
- Relis la section concernée du cahier des charges. Ne devine jamais une
  règle métier.
- Consulte context7 dans ces trois cas, sans exception :
  * avant d'utiliser une fonction d'une librairie que tu n'as pas déjà
    utilisée dans ce projet ;
  * dès qu'une erreur de compilation mentionne une librairie — ta mémoire
    est probablement en retard sur sa version actuelle ;
  * avant de proposer une nouvelle dépendance, pour vérifier qu'elle est
    toujours maintenue.
  Ne devine jamais une API. Si context7 ne répond pas, dis-le-moi plutôt
  que d'inventer.
- Demande-moi avant d'ajouter une dépendance.

## Couleurs et mise en page
- Aucune valeur hexadécimale hors de lib/core/theme/ferha_colors.dart.
- Les couleurs passent par FerhaColors. Le fond est ivoire, jamais #FFFFFF.
- EdgeInsetsDirectional et start/end partout, jamais left/right :
  l'application est bilingue français / arabe.
- Thème clair ET sombre pour chaque nouvel écran.

## Règles métier non négociables
- Les prix sont calculés en base de données, jamais en Dart.
- Les changements d'état d'une réservation passent par des fonctions SQL
  sécurisées, jamais par le client.
- Aucune donnée de salle écrite en dur dans le code.
- Aucune clé ni secret dans le dépôt.
- Le prix vient d'estimate_price(), et de nulle part ailleurs. Pas une
  seconde formule, ni en Dart, ni en SQL.
- Un compte fermé s'anonymise, il ne se supprime pas. Voir ci-dessous.

## Fermer un compte, c'est anonymiser
La loi 18-07 demande de pouvoir fermer un compte. Une réservation passée
est une trace comptable : elle ne peut pas s'évaporer, et l'autre partie
a le droit de retrouver ce qu'elle a vendu ou acheté.

Fermer un compte remplace donc full_name, email et phone par des valeurs
neutres. Les bookings, payments et reviews restent en place, rattachés au
même identifiant.

C'est pourquoi bookings.client_id et bookings.venue_id sont en RESTRICT :
une suppression franche doit échouer plutôt que d'emporter l'historique
en silence. Ne passe jamais ces clés en CASCADE pour faire passer une
suppression — c'est le filet qui garantit qu'on écrira une anonymisation.

## Vues publiques sans RLS
Une vue exposée publiquement — venue_availability aujourd'hui — est sans RLS
à dessein : elle ne montre que des colonnes publiques par nature, et c'est son
propre WHERE qui borne les lignes qui sortent.

N'y ajoute aucune colonne sans avoir vérifié qu'un inconnu, non connecté, a le
droit de la lire. En cas de doute, la réponse est non : la colonne reste dans
la table, derrière sa politique. Ne remplace pas non plus ce filtrage par
security_invoker = true — la vue se viderait.

## Avant de me rendre la main
Utilise la skill « verification ». Systématiquement, après toute
modification.

## Lancer l'application
flutter run -d chrome --print-dtd
Page de contrôle visuel : /#/_design
