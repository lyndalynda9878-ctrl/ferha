# Ferha

Réservation de salles des fêtes en Algérie. Application Flutter, français et
arabe.

Ce dépôt contient pour l'instant **le socle** : thème, navigation,
internationalisation, schéma de base de données, branchement sur Supabase et
comptes utilisateurs. Aucun écran métier.

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
    router/     go_router : 4 onglets, routes d'authentification, route cachée
    supabase/   le client, exposé par un fournisseur Riverpod
    theme/      palette « Ambre & ivoire », rayons, galerie de contrôle
  features/
    auth/       connexion, inscription, profil, session
  main.dart
supabase/
  migrations/   le schéma : tables, RLS, prix
  seed/         15 salles de démonstration
  tests/        le test de double réservation
```

La base de données a son propre document : [supabase/README.md](supabase/README.md).

## Comptes et connexion

Trois écrans : connexion, création de compte, profil. L'écran de connexion
porte les deux comptes de démonstration du cahier des charges (§4.1, CORE-01),
accessibles **en un tap** :

| Bouton | Compte | Ce qu'on voit |
|---|---|---|
| Entrer comme Amina | cliente | le point de vue par défaut, aucune salle |
| Entrer comme Karim | propriétaire | ses **4 salles** du catalogue de démonstration |

Ils supposent que `supabase/seed/003_demo_accounts.sql` a été lancé. Les
identifiants vivent dans `lib/features/auth/demo_accounts.dart`, et nulle part
ailleurs.

Le seed remplit `email_confirmed_at` sur ces comptes : ils fonctionnent donc
**même si « Confirm email » est actif** sur le projet Supabase. C'est
indispensable — personne ne recevra jamais de message à une adresse
`@demo.ferha.dz`.

En revanche, quand ce réglage est actif, une **inscription normale** depuis
l'application n'ouvre pas de session : l'écran affiche « Vérifiez votre boîte
mail », parce que c'est ce que le serveur a répondu. L'application ne fait rien
de plus — le parcours de confirmation n'est pas traité.

**La session survit à la fermeture de l'application** : le jeton est rangé dans
`localStorage` sur le web, dans `SharedPreferences` sur mobile, et restauré par
`Supabase.initialize()` avant la première image.

### La règle de navigation

> Un visiteur non connecté peut chercher une salle et consulter une fiche.
> La connexion n'est demandée qu'**au moment d'agir**.

C'est le parcours du §3, dont les deux premières étapes se font sans compte.
Le routeur n'a donc **aucune redirection globale** vers la connexion : une
redirection posée sur des routes de consultation transformerait l'application
en annuaire fermé.

Les écrans qui portent un geste — envoyer une demande, écrire à un
propriétaire, déposer un avis — appellent `exigerConnexion` :

```dart
if (!await exigerConnexion(context, ref)) return;
// ici, la session existe
```

Gratuit si la session existe déjà. Sinon l'écran de connexion s'ouvre
par-dessus, et se referme sur le geste interrompu.

### Messages d'erreur

`lib/features/auth/auth_messages.dart` traduit les erreurs de GoTrue en
français, à partir du **code** d'erreur — stable et documenté — et non du texte
anglais du serveur, qui change de version en version. Un code inconnu n'est pas
masqué : il est nommé, avec le message d'origine. « Une erreur est survenue »
fait perdre le temps qu'il prétend faire gagner.

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

Elle porte aussi, **temporairement**, un encart « État de la connexion » en
deux lignes, parce que deux pannes différentes s'y distinguent :

1. **la base** — nombre de salles publiées et nom de la première ;
2. **l'authentification** — session ouverte ou non, et profil lu ou non.

Une seule ligne pour les deux obligerait à deviner laquelle est tombée.
Marqué `// TEMPORAIRE — retirer en J6`, il part avec le premier écran métier
qui lit ces mêmes données.

## Documents

- `docs/cahier-des-charges_1.html` — cahier des charges v2.0
- `docs/maquettes.html` — maquettes des écrans

## Licence

Le code est sous licence MIT — voir [LICENSE](LICENSE).

Bricolage Grotesque est sous SIL Open Font License 1.1 — voir
[assets/fonts/OFL.txt](assets/fonts/OFL.txt).
