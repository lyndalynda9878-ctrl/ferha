# Ferha

Réservation de salles des fêtes en Algérie. Application Flutter, français et
arabe.

Ce dépôt contient pour l'instant **le socle** : thème, navigation,
internationalisation et intégration continue. Aucune fonctionnalité métier.

## Lancer

```bash
flutter pub get
flutter run
```

## Vérifier

```bash
flutter analyze
flutter test
```

## Structure

```
lib/
  core/
    l10n/       fichiers ARB (fr, ar) et langue active
    router/     go_router : 4 onglets + route cachée
    theme/      palette « Ambre & ivoire », rayons, galerie de contrôle
  features/     vide — les tranches métier arrivent ici
  main.dart
```

## Identité visuelle

La palette « Ambre & ivoire » du cahier des charges (§10.1) vit dans une seule
`ThemeExtension`, `FerhaColors` : c'est le seul fichier du projet où une valeur
hexadécimale est écrite. Un écran lit ses couleurs par `context.ferhaColors`.

Les deux thèmes, clair et sombre, sont livrés ensemble.

La police d'affichage, Bricolage Grotesque, est embarquée en un seul fichier
variable : `assets/fonts/BricolageGrotesque-Variable.ttf`. Les styles pilotent
ses axes `wght` et `opsz` — l'application n'a donc besoin d'aucun réseau pour
s'afficher correctement, dès le premier lancement.

## Galerie de contrôle

La route `/_design` affiche chaque couleur avec son code, l'échelle
typographique, les boutons, les puces, la carte de salle, les trois états du
calendrier, et une bascule fr / ar. Elle n'apparaît dans aucune barre d'onglets.

```bash
flutter run -d chrome   # puis /_design dans la barre d'adresse
```

Depuis le code : `context.go(FerhaRoutes.design)`.

## Documents

- `docs/cahier-des-charges_1.html` — cahier des charges v2.0
- `docs/maquettes.html` — maquettes des écrans

## Licence

Le code est sous licence MIT — voir [LICENSE](LICENSE).

Bricolage Grotesque est sous SIL Open Font License 1.1 — voir
[assets/fonts/OFL.txt](assets/fonts/OFL.txt).
