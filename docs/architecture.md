# Architecture

Comment le projet est rangé, comment il se configure et se lance, comment on se connecte, et comment il se dessine. Retour au [README](../README.md).

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
sont les politiques RLS. Elle reste hors du dépôt parce qu'elle désigne un
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
    supabase/   le client Riverpod, et la session — qui est connecté
    theme/      palette « Ambre & ivoire », rayons, galerie de contrôle
  features/
    auth/          connexion, inscription, profil
    booking/       demande, devis, suivi des réservations
    favorites/     le cœur sur la carte, et l'onglet qui les rassemble
    notifications/ la cloche, l'écran, et le temps réel
    owner/         espace propriétaire : tableau de bord, agenda, publication
    search/        accueil (= recherche) et résultats
    venue/         fiche salle, galerie, calendrier
    reviews/       avis : dépôt, lecture, droit de réponse
    assistant/     l'assistant et son fil de conversation
  main.dart
supabase/
  functions/    cinq Edge Functions (Deno) : create-checkout, chargily-webhook,
                embed-venue, summarize-reviews, ai-chat
  migrations/   42 fichiers : schéma, RLS, prix, recherche, avis, agent, gardiens
  seed/         15 salles, 8 comptes, 24 réservations et 3 favoris de démonstration
  tests/        22 bancs d'essai SQL, de la double réservation à la protection
                des comptes de démonstration
  outils/       scripts de mise au point
services/
  embeddings/   le service Python qui transforme le texte en vecteurs (Render)
docs/
  captures/     les six images du README
```

**Le socle ne dépend d'aucune fonctionnalité, et la frontière passe par la
session.** `core/supabase/session_providers.dart` dit s'il y a QUELQU'UN —
le routeur s'en sert pour rediriger, la langue pour savoir s'il existe un
profil où écrire. Savoir QUI c'est est autre chose : `profilProvider` lit la
table `profiles`, avec ses colonnes et ses droits, et il vit dans
`features/auth/`. La seule exception est `core/router/`, qui importe tous les
écrans : nommer chaque destination est le travail d'un routeur, pas une
dépendance de travers.

**Dette notée, pas urgente** : une trentaine de symboles de `lib/` sont
publics alors qu'ils ne servent que dans leur propre fichier. Les passer en
privé est un vrai nettoyage, qui se fait au calme et pas entre deux mises en
ligne.

La base de données a son propre document : [supabase/README.md](../supabase/README.md).

## Comptes et connexion

Trois écrans : connexion, création de compte, profil. L'écran de connexion
porte les deux comptes de démonstration que demande le cahier des charges,
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

C'est le parcours prévu par le cahier des charges, dont les deux premières
étapes — chercher, consulter — se font sans compte.
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

La palette « Ambre & ivoire » du cahier des charges vit dans une seule
`ThemeExtension`, `FerhaColors` : c'est le seul fichier du projet où une valeur
hexadécimale est écrite. Un écran lit ses couleurs par `context.ferhaColors`.

Les deux thèmes, clair et sombre, sont livrés ensemble, et un petit bouton rond
— soleil ou lune — les échange depuis la barre du haut, à côté de la cloche et
là où vit déjà la bascule de langue. Le choix est retenu par l'appareil et
survit au rechargement de la page.

Tant que personne n'y a touché, l'application suit le **réglage du système**, et
c'est délibéré : un téléphone en sombre doit ouvrir Ferha en sombre sans qu'on
ait rien à demander. Le modèle porte donc trois états — « système », « clair »,
« sombre » — là où le bouton n'en montre que deux : il annonce ce vers quoi il
mène, jamais l'état courant.

La police d'affichage, Bricolage Grotesque, est embarquée en un seul fichier
variable : `assets/fonts/BricolageGrotesque-Variable.ttf`. Les styles pilotent
ses axes `wght` et `opsz` — l'application n'a donc besoin d'aucun réseau pour
s'afficher correctement, dès le premier lancement.

## Galerie de contrôle

La route `/_design` affiche chaque couleur avec son code, l'échelle
typographique, les boutons, les puces, la carte de salle, les trois états du
calendrier, et les deux bascules d'affichage — fr / ar, clair / sombre. Elle n'apparaît dans aucune barre d'onglets.

```bash
flutter run -d chrome --dart-define-from-file=env.json --print-dtd
# puis /_design dans la barre d'adresse
```

Depuis le code : `context.go(FerhaRoutes.design)`.

Elle a porté un temps un encart « État de la connexion », le temps de brancher
l'application sur la base. Il a été retiré : l'écran de recherche lit désormais
les mêmes données pour de bon, et une panne s'y verra sans instrument dédié.

