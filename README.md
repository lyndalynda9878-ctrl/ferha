# Ferha

Réservation de salles des fêtes en Algérie. Application Flutter, français et
arabe.

Ce dépôt contient pour l'instant **le socle** : thème, navigation,
internationalisation, schéma de base de données et branchement sur Supabase.
Aucun écran métier.

## Configuration

Les identifiants Supabase ne sont pas dans le dépôt. Avant le premier
lancement :

```bash
cp env.example.json env.json
```

Puis remplissez les deux valeurs, prises dans votre tableau de bord Supabase,
**Project Settings › API** :

| Clé | Où la trouver |
|---|---|
| `SUPABASE_URL` | l'URL du projet, `https://xxxx.supabase.co` |
| `SUPABASE_ANON_KEY` | la clé publique — `anon`, aussi appelée *publishable* |

`env.json` est dans `.gitignore` : il ne partira jamais dans un commit.
`env.example.json`, lui, est versionné et ne contient que des valeurs vides.

La clé publique est publique au sens strict — elle part dans le bundle web et
n'importe qui peut la lire. **Ce n'est pas elle qui protège les données**, ce
sont les politiques RLS (§9). Elle reste hors du dépôt parce qu'elle désigne un
projet précis, et que changer de projet ne doit pas demander de changer le
code. La clé `service_role`, elle, ne doit apparaître **nulle part** dans cette
application.

Sans configuration, l'application ne démarre pas : elle affiche un écran qui
dit quelle clé manque et quoi faire.

## Lancer

```bash
flutter pub get
flutter run -d chrome --dart-define-from-file=env.json --print-dtd
```

`--dart-define-from-file` est obligatoire : les valeurs sont lues par
`String.fromEnvironment`, à la compilation. Un `flutter run` nu compile une
application sans identifiants, qui s'arrêtera sur l'écran de configuration.

## Vérifier

```bash
flutter analyze
flutter test
```

## Structure

```
lib/
  core/
    env/        clés lues à la compilation (--dart-define-from-file)
    l10n/       fichiers ARB (fr, ar) et langue active
    router/     go_router : 4 onglets + route cachée
    supabase/   le client, exposé par un fournisseur Riverpod
    theme/      palette « Ambre & ivoire », rayons, galerie de contrôle
  features/     vide — les tranches métier arrivent ici
  main.dart
supabase/
  migrations/   le schéma : tables, RLS, prix
  seed/         15 salles de démonstration
  tests/        le test de double réservation
```

La base de données a son propre document : [supabase/README.md](supabase/README.md).

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
flutter run -d chrome --dart-define-from-file=env.json --print-dtd
# puis /_design dans la barre d'adresse
```

Depuis le code : `context.go(FerhaRoutes.design)`.

Elle porte aussi, **temporairement**, un encart « État de la connexion » qui
compte les salles publiées trouvées en base et nomme la première. C'est
l'instrument qui prouve que la chaîne complète fonctionne — clés, réseau, RLS,
données. Il est marqué `// TEMPORAIRE — retirer en J6` et part avec le premier
écran métier qui lit ces mêmes données.

## Documents

- `docs/cahier-des-charges_1.html` — cahier des charges v2.0
- `docs/maquettes.html` — maquettes des écrans

## Licence

Le code est sous licence MIT — voir [LICENSE](LICENSE).

Bricolage Grotesque est sous SIL Open Font License 1.1 — voir
[assets/fonts/OFL.txt](assets/fonts/OFL.txt).
