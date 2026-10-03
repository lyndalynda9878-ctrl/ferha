# Le paiement de l'acompte

Retour au [README](../README.md).

Une demande acceptée propose « Verser l'acompte » dans « Mes réservations ». On
arrive sur l'écran de l'acompte : le compte à rebours des 72 h, le
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
l'utilisateur** et n'apprend jamais qu'une clé existe. Le cahier des charges le
demande en toutes lettres : « un APK se décompile en quelques
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
le bouton de « Mes réservations », l'écran de l'acompte, et la ligne `payments`. Sans cela,
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
réservation reste **acceptée**. Seul le webhook signé la fera passer
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
[supabase/README.md](../supabase/README.md).

### L'acompte en espèces

Le troisième choix de l'écran de l'acompte, et il marche. La légende de la
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

