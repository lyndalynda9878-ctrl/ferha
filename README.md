# Ferha

Réservation de salles des fêtes en Algérie. Application Flutter, français et
arabe.

Ce dépôt contient pour l'instant **le socle** : thème, navigation,
internationalisation, schéma de base de données, branchement sur Supabase,
comptes utilisateurs et **la recherche de salles**.

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
    auth/          connexion, inscription, profil, session
    booking/       demande, devis, suivi des réservations
    notifications/ la cloche, l'écran, et le temps réel
    owner/         espace propriétaire : tableau de bord, agenda, publication
    search/        accueil (= recherche) et résultats
    venue/         fiche salle, galerie, calendrier
  main.dart
supabase/
  functions/    les Edge Functions (Deno) — create-checkout aujourd'hui
  migrations/   le schéma : tables, RLS, prix
  seed/         15 salles de démonstration
  tests/        le test de double réservation
```

La base de données a son propre document : [supabase/README.md](supabase/README.md).

## La recherche

L'accueil **est** la recherche (maquettes, écran 1) : où, quand, combien, et le
bouton part. Les résultats (écran 2) gardent les filtres actifs en tête, chacun
retirable d'un tap.

**Rien n'est filtré ni calculé en Dart.** Une seule fonction SQL,
`search_venues()`, prend les critères et renvoie des lignes déjà triées, déjà
tarifées. Le prix d'une carte est celui de la **date choisie**, majorations du
§5.2 comprises — pas un « à partir de », et pas un montant qui changerait entre
la liste et la fiche.

Le nombre d'invités sert deux fois : il écarte les salles trop petites, et il
entre dans le calcul du prix comme nombre de couverts. « 300 invités » affiche
donc le prix pour 300 couverts, supplément compris.

Les critères voyagent dans l'URL (`/resultats?wilaya=31&date=…`) et non dans
l'état : sur le web, une recherche se copie, se partage et survit à un
rechargement.

Le filtre **type d'événement** retire vraiment des salles : `venue_event_types`
dit ce que chaque salle accepte. Trois salles de démonstration refusent quelque
chose, pour que le filtre se voie à l'usage — le grand palais de Zéralda ne
fait que mariages et fiançailles, la petite salle d'Ouled Yaïch ne fait pas de
mariage. Une salle qui n'a **rien déclaré accepte tout** : le silence d'un
propriétaire ne vaut pas refus.

### Ce qui ne s'affiche pas

Une salle **sans avis n'a pas d'étoiles**. Pas « 0,0 (0) » : une salle neuve
n'est pas une salle mal notée. La base renvoie `NULL` plutôt que zéro, et
l'écran d'accueil intitule sa liste « Salles à découvrir » tant qu'aucune note
n'existe, « Les mieux notées » ensuite.

### Les trois états

| État | Ce qu'on voit |
|---|---|
| Chargement | des cartes squelettes, à la forme de ce qui arrive |
| Vide | ce qui bloque, **nommé**, et un bouton par critère à retirer |
| Erreur | le message traduit, un bouton Réessayer, et le détail technique repliable |

L'état vide ne dit jamais « aucun résultat » tout court : il nomme le critère le
plus probablement responsable — une date déjà prise, un budget sous le prix réel
d'un vendredi d'été — et chaque piste proposée est un bouton qui retire
vraiment ce critère.

### Sans compte

Chercher et consulter ne demandent **aucune connexion**. Voir la règle de
navigation plus bas.

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

## Les délais et les alertes

### L'option de 72 h s'éteint toute seule

Une demande acceptée pose une option de 72 h (§5.1). Sans acompte à l'échéance,
elle expire et **rend la date** — sans que personne n'appuie sur rien. C'est
`pg_cron` qui porte ce « sans personne » : `expire_options()` passe **toutes les
quinze minutes**, et une seconde tâche purge chaque nuit l'historique
d'exécutions de plus de sept jours. Les deux sont posées par une migration, pas
à la main dans le tableau de bord Supabase : un projet recréé repartirait sans
elles, avec des options qui n'expirent plus et personne pour s'en apercevoir.

**Une journée entière expire d'un bloc.** Elle occupe deux lignes de `bookings`
et n'est qu'une seule réservation : le midi libéré et le soir tenu ferait une
date invendable. Les deux parties sont prévenues — c'est aussi la date du
propriétaire qui vient de repartir à la vente — et chacune **une seule fois**.

Le détail est dans [supabase/README.md](supabase/README.md).

### La cloche, et l'écran

Une cloche en haut de l'accueil (écran 1 des maquettes) et dans la barre du
tableau de bord propriétaire. **La même cloche**, et pas une par espace : Karim
reçoit ses demandes sur ses salles, mais il peut aussi avoir réservé ailleurs —
deux compteurs qui se partageraient les notifications donneraient deux nombres,
et aucun des deux ne serait le bon.

La pastille ne montre jamais « 0 » : elle apparaît à un, et dit « 99+ » au-delà.
Le nombre vient de la base et porte sur **toutes** les non lues, pas sur les
cinquante lignes affichées — sinon le badge rétrécirait à mesure qu'on remonte
dans l'historique.

L'écran charge la liste à l'ouverture **et** écoute le temps réel. Les deux, pas
l'un ou l'autre : le service Realtime de Supabase démarre à froid quand le
projet a dormi, et une notification déposée pendant ces deux secondes-là ne
serait annoncée à personne.

Toucher une notification fait deux choses, dans cet ordre : elle s'éteint, puis
l'écran s'ouvre — le suivi des réservations pour la famille, le détail de la
demande pour le propriétaire. L'inverse laisserait la pastille allumée le temps
de la transition, et on croirait avoir mal appuyé.

**Aucun texte de notification n'est écrit en dur.** Le titre vient du type, la
ligne de détail du payload — nom de la salle, date, créneau, invités —, et le
payload est rempli par la base au moment où la notification naît. Il est donc
aussi **figé** : une salle renommée demain ne réécrit pas l'annonce d'hier.

### Ce qui manque encore

Le push téléphone (FCM), les e-mails, les rappels J-7 et J-1, l'écran qui
recevra l'invitation à laisser un avis (J17) et le bouton WhatsApp ne sont pas
faits. Les deux types `reminder_j7` et `reminder_j1` existent en base et
personne ne les dépose encore ; `review_invitation`, elle, est déjà déposée par
`complete_booking()` et mène au suivi des réservations faute d'écran dédié.

## Le paiement de l'acompte

Une demande acceptée propose « Verser l'acompte » dans « Mes réservations ». On
arrive sur l'écran 6 des maquettes : le compte à rebours des 72 h, le
récapitulatif, le montant, CIB ou Edahabia, et un bouton qui ouvre la vraie page
de paiement Chargily.

**En mode test, et seulement en mode test.** L'URL est celle du mode test de
Chargily Pay v2, `payments.is_test` vaut `true` sur chaque ligne écrite, et
l'écran le dit au client plutôt que de le cacher : « aucune somme n'est
réellement débitée ». Mieux vaut qu'il l'apprenne là que devant son relevé.

### La clé secrète ne quitte jamais le serveur

Elle vit dans les secrets de la Edge Function `create-checkout`, sous le nom
**`CHARGILY_SECRET_KEY`**, et nulle part ailleurs — ni dans `env.json`, ni dans
le dépôt, ni dans l'application. Flutter appelle la fonction avec **le jeton de
l'utilisateur** et n'apprend jamais qu'une clé existe. Le §9.4 du cahier des
charges le demande en toutes lettres : « un APK se décompile en quelques
minutes ».

Sans ce secret, la fonction répond `FE058` et l'écran dit que le paiement en
ligne n'est pas encore ouvert — sans nommer aucune clé.

Une seconde variable, **`APP_ORIGIN`**, est facultative. Posée, elle restreint
les adresses de retour à celles de ce domaine (les origines locales restent
acceptées, pour le développement). Le jour où l'application aura un domaine,
elle se remplit sans qu'une ligne de code change.

### Le montant vient de la base, et d'un seul arrondi

Chargily encaisse des **dinars entiers** ; `bookings.deposit_amount` est un
`numeric(12,2)`, parce que 25 % d'un devis tombe rarement rond. Il faut donc
arrondir, et **une seule fois** : c'est `montant_acompte()` (migration 024), au
dinar **supérieur** — l'acompte est un minimum convenu, et le solde du jour J
absorbe la différence au centime.

Trois endroits annoncent ce montant, et les trois lisent cette même fonction :
le bouton de « Mes réservations », l'écran 6, et la ligne `payments`. Sans cela,
le bouton dirait « 51 333 DA » et la caisse en demanderait 51 334.

Flutter n'envoie **aucun montant** : la Edge Function le lit dans la base pour
créer le checkout, et la base le relit une seconde fois au moment d'écrire.

### Une seule page de paiement par réservation

Un second « Payer » — double tap, retour arrière, page rechargée — ne crée pas
un second checkout. La fonction retrouve celui qui est déjà ouvert chez
Chargily et rend **la même URL**, tant qu'il est encore en attente et toujours
du bon montant. Une page neuve éteint la précédente : jamais deux paiements
« en cours » sur la même date.

### Revenir de Chargily ne confirme rien

C'est le point le plus important de cette étape. `success_url` ramène sur « Mes
réservations » avec un bandeau **« Paiement en cours de vérification »**, et la
réservation reste **acceptée**. Seul le webhook signé — le J16 — la fera passer
en « confirmée ». Le paramètre de retour s'appelle d'ailleurs `verification` et
non `succes` : le nom dit déjà qu'on ne sait pas encore.

### Ce qui confirme vraiment : le webhook

`chargily-webhook` est la seule chose qui fasse passer une réservation en
**confirmée**. Il tourne sans jeton Supabase — Chargily n'en a pas — et ce qui
le protège est **la signature**, vérifiée sur le corps brut avant tout décodage,
en HMAC-SHA256 avec la clé secrète. Signature fausse ou absente : 401, et rien
n'est écrit.

Il ne décide de rien d'autre. Le montant, l'option, le créneau, l'idempotence :
tout se joue en SQL, en une transaction, sur une ligne verrouillée. Recevoir
deux fois le même événement ne confirme pas deux fois.

**Un paiement encaissé ne confirme pas toujours.** Quand l'option a expiré
pendant le trajet, quand un autre a pris le créneau, ou quand la réservation
était déjà réglée, l'argent est arrivé et la date n'est pas prise. La base
marque la ligne « à rembourser », prévient les deux parties et
l'administration — et **ne rembourse rien toute seule**. Le détail est dans
[supabase/README.md](supabase/README.md).

### L'acompte en espèces

Le troisième choix de l'écran 6, et il marche maintenant. La légende de la
maquette dit pourquoi il compte : « elle sauve les utilisateurs réticents au
paiement en ligne ».

**Annoncer n'est pas payer.** Le client dit qu'il apportera les billets ; la
réservation reste acceptée, l'option de 72 h continue de courir, et le
propriétaire est prévenu. C'est lui qui confirme, depuis le détail de la
demande, une fois l'argent compté — et ce bouton demande confirmation, parce
qu'il prend la date pour de bon.

Le propriétaire lit le **même montant** que sa cliente : l'entier de
`montant_acompte()`, et non les centimes du montant convenu.

### Tester le paiement sans la page Chargily

La page de paiement n'est pas joignable depuis toutes les connexions
algériennes. Le webhook, lui, se teste entièrement sans elle :

```powershell
$env:CHARGILY_SECRET_KEY = 'test_sk_...'
.\supabase\tests\webhook_chargily.ps1 -Cas tout
```

Le script signe avec la vraie clé et vise la fonction déployée ; le décor se
pose et s'efface par `supabase/tests/013_webhook_bac_a_sable.sql`. La clé est
lue dans une variable d'environnement et n'entre dans aucun fichier.

### Ce qui manque encore

Sur téléphone, le paiement par carte renvoie à un navigateur — le lien
d'application Android n'est pas déclaré, et une page de paiement dont on ne
revient pas vaut moins qu'un refus qui le dit. Le parcours espèces, lui, marche
partout : il ne quitte jamais l'application.

Il n'y a pas encore d'écran d'administration pour les paiements à rembourser :
la vue `paiements_a_examiner` existe, et se lit pour l'instant dans l'éditeur
SQL.

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

Elle a porté un temps un encart « État de la connexion », le temps de brancher
l'application sur la base. Il a été retiré : l'écran de recherche lit désormais
les mêmes données pour de bon, et une panne s'y verra sans instrument dédié.

## Documents

- `docs/cahier-des-charges_1.html` — cahier des charges v2.0
- `docs/maquettes.html` — maquettes des écrans

## Licence

Le code est sous licence MIT — voir [LICENSE](LICENSE).

Bricolage Grotesque est sous SIL Open Font License 1.1 — voir
[assets/fonts/OFL.txt](assets/fonts/OFL.txt).
