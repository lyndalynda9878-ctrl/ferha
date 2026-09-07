# Ferha — règles du projet

Application Flutter de réservation de salles des fêtes en Algérie.
Références : docs/cahier-des-charges.html (produit, base de données,
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

## Avant de me rendre la main
Utilise la skill « verification ». Systématiquement, après toute
modification.

## Lancer l'application
flutter run -d chrome --print-dtd
Page de contrôle visuel : /#/_design
