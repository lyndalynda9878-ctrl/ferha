# Ferha — règles du projet

Application Flutter de réservation de salles des fêtes en Algérie.
Références : docs/cahier-des-charges_1.html (produit, base de données,
palette en §10.1) et docs/maquettes.html (écrans).

## Avant d'écrire du code
- Relis la section concernée du cahier des charges. Ne devine jamais une
  règle métier.
- Ne devine JAMAIS une API. Va lire la source du paquet installé, dans le
  cache pub — c'est la version que le projet compile, pas celle dont tu te
  souviens. Sur cette machine :
  `~/AppData/Local/Pub/Cache/hosted/pub.dev/<paquet>-<version>/lib/`,
  et pubspec.lock donne la version exacte.
  Dans ces trois cas, sans exception :
  * avant d'utiliser une fonction d'une librairie que tu n'as pas déjà
    utilisée dans ce projet ;
  * dès qu'une erreur de compilation mentionne une librairie ;
  * avant de proposer une nouvelle dépendance.
  (context7 remplissait ce rôle jusqu'à l'étape J9 ; il expirait à chaque
  connexion et a été retiré de .mcp.json. La source installée dit de toute
  façon la vérité de plus près : elle est ce qui compile.)
- Demande-moi avant d'ajouter une dépendance.

## Couleurs et mise en page
- Aucune valeur hexadécimale hors de lib/core/theme/ferha_colors.dart.
- Les couleurs passent par FerhaColors. Le fond est ivoire, jamais #FFFFFF.
- EdgeInsetsDirectional et start/end partout, jamais left/right :
  l'application est bilingue français / arabe.
- Thème clair ET sombre pour chaque nouvel écran.

## Maquettes et charte : qui dit quoi
Les maquettes donnent la STRUCTURE — ce qu'il y a sur l'écran, dans quel
ordre, quelle information à côté de quelle autre, quelle hiérarchie.
La section 10.1 donne les VALEURS — couleurs et rayons.

En cas de désaccord, la charte gagne. Les maquettes sont dessinées dans
un cadre de 256 px de large pour un téléphone de 390 : leurs mesures
remises à l'échelle ne retombent pas sur les valeurs de la charte, et
c'est normal. Un rayon de carte de 13 px dans le mockup ne veut pas dire
20 px dans l'application — il veut dire FerhaRadii.card.

Les rayons passent donc par FerhaRadii, comme les couleurs par
FerhaColors. Aucun rayon écrit à la main dans un écran.

## L'espace propriétaire et sa barre d'onglets

La maquette de l'écran 9 dessine une barre d'onglets propre au propriétaire —
Tableau, Agenda, Messages, Ma salle. Elle n'existe pas encore, et c'est
délibéré : au J10 un seul de ses quatre onglets mène quelque part, et trois
onglets morts disent que l'application est inachevée bien plus fort que leur
absence.

Elle arrivera le jour où un DEUXIÈME écran propriétaire existera, et elle
enveloppera `/proprietaire/*` — sans doute par un second `StatefulShellRoute`,
à côté de celui du client. C'est pour cela que le tableau de bord est déjà
rangé sous ce préfixe (`/proprietaire/tableau`) alors qu'il est seul : ce
jour-là, la barre sera un emballage à poser autour, pas un déménagement de
routes et de liens.

Tout l'espace propriétaire vit donc dans `lib/features/owner/`, et les routes
qu'on lui ajoute commencent par `/proprietaire/`.

## Règles métier non négociables
- Les prix sont calculés en base de données, jamais en Dart.
- Les changements d'état d'une réservation passent par des fonctions SQL
  sécurisées, jamais par le client.
- Aucune donnée de salle écrite en dur dans le code.
- Aucune clé ni secret dans le dépôt.
- Le prix vient d'estimate_price(), et de nulle part ailleurs. Pas une
  seconde formule, ni en Dart, ni en SQL.
- Un compte fermé s'anonymise, il ne se supprime pas. Voir ci-dessous.
- L'agent a un accès en ÉCRITURE à la base Supabase. C'est un choix assumé
  pendant le développement, parce que toutes les migrations sont
  versionnées et les données de démonstration recréables. Le jour où de
  vrais utilisateurs existeront, ce droit repasse en lecture seule.

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

## Déployer une Edge Function
Le serveur MCP de Supabase ne doit JAMAIS servir à déployer une Edge
Function. Il ne prend pas un chemin de fichier : il fait retaper le
fichier entier dans une charge JSON, et les antislashs n'y survivent
pas. Le 15 septembre 2026, ça a cassé `ai-chat` en ligne trois fois de
suite — une fois en changeant `̀` en caractère littéral, deux fois
en doublant tous les antislashs, ce qui a tué `/^\d{2}$/` et
`/^\d{4}-\d{2}-\d{2}$/` : plus aucune wilaya ni aucune date reconnue.

Le seul chemin est la CLI, qui lit le fichier sur le disque :

    npx supabase functions deploy ai-chat --project-ref <ref>

Elle demande `SUPABASE_ACCESS_TOKEN` dans l'environnement. Les autres
outils MCP de Supabase — lire le schéma, interroger, migrer, consulter
les journaux — restent parfaitement utilisables : c'est le déploiement,
et lui seul, qui passe par la CLI.

## Avant de me rendre la main
Utilise la skill « verification ». Systématiquement, après toute
modification.

## Lancer l'application
flutter run -d chrome --dart-define-from-file=env.json --print-dtd
Page de contrôle visuel : /#/_design

--dart-define-from-file n'est pas optionnel : SUPABASE_URL et
SUPABASE_ANON_KEY sont lues par String.fromEnvironment, donc à la
compilation. Sans lui, l'application s'arrête sur l'écran de
configuration.

env.json est à la racine et dans .gitignore. env.example.json, versionné,
en est le modèle. Ne me demande jamais de coller une clé dans la
conversation, et n'en écris aucune dans le dépôt — pas même en exemple.
La clé service_role n'a rien à faire dans l'application Flutter.
