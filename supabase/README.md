# Base de données Ferha

PostgreSQL, hébergé par Supabase. Le schéma est le contrat entre l'application
Flutter et le backend — cahier des charges §6 pour les tables, §9 pour la
sécurité.

## Ordre d'application

Les fichiers s'appliquent dans l'ordre de leur numéro, et dans cet ordre
seulement :

| Ordre | Fichier | Contenu | Dépend de |
|---|---|---|---|
| 1 | `migrations/001_schema.sql` | Catalogue : tables, contraintes, index, triggers | `auth.users` (fourni par Supabase) |
| 2 | `migrations/002_rls.sql` | RLS du catalogue | 001 |
| 3 | `migrations/003_amenities.sql` | Référentiel des équipements | 001 |
| 4 | `migrations/004_bookings.sql` | Réservations, paiements, avis, notifications | 001, 002 |
| 5 | `migrations/005_pricing.sql` | `estimate_price()` et ses tables | 002, 004 |
| 6 | `migrations/006_rls_bookings.sql` | RLS des réservations | 004 |
| 7 | `migrations/007_auth.sql` | Un compte créé, un profil créé | 001 |
| 8 | `migrations/008_search.sql` | `search_venues()` — la recherche | 004, 005 |
| 9 | `migrations/009_wilayas.sql` | Référentiel des 58 wilayas | 001 |
| 10 | `migrations/010_event_types.sql` | Types d'événement — **redéfinit `search_venues()`** | 002, 008 |
| 11 | `migrations/011_venue_detail.sql` | `venue_detail()` et `venue_calendar()` — la fiche et le calendrier | 002, 005, 010 |
| 12 | `migrations/012_booking_request.sql` | La demande de réservation — **redéfinit `venue_detail()` et `request_booking()`** | 005, 010, 011 |
| 13 | `migrations/013_mes_reservations.sql` | `client_bookings()` et `bookings` en temps réel | 004, 006 |
| 14 | `migrations/014_espace_proprietaire.sql` | `owner_venues()`, `owner_dashboard()`, la file des demandes | 002, 004, 006 |
| 15 | `migrations/015_repondre_a_une_demande.sql` | `accepter_demande()` et `refuser_demande()` | 004, 012 |
| 16 | `migrations/016_agenda_proprietaire.sql` | `owner_agenda()`, `bloquer_date()`, `debloquer_date()` | 001, 002, 004, 014 |
| 17 | `migrations/017_publier_une_salle.sql` | `creer_salle()` et `envoyer_salle_en_validation()` | 001, 002, 009, 010 |
| 18 | `migrations/018_garde_privileges_profil.sql` | un compte ne se donne pas `is_admin` ni `is_owner` | 001, 002, 017 |
| 19 | `migrations/019_adresse_de_la_salle.sql` | `venues.address` — **redéfinit `creer_salle()`**, et retire `address` du SELECT public | 001, 002, 017 |
| 20 | `migrations/020_telephone_joignable.sql` | la règle du téléphone — **redéfinit `handle_new_user()`, `envoyer_salle_en_validation()` et `request_booking()`** | 001, 004, 006, 007, 012, 019 |

`002` a besoin des tables de `001`. `003` a besoin de la table `amenities` de
`001`, mais pas de `002`. Appliquer `002` avant `003` reste le bon ordre : le
référentiel arrive alors dans une base déjà fermée.

`005` pose des triggers sur `bookings` : il vient donc après `004`. Il porte
aussi ses propres politiques RLS, contrairement aux autres fichiers de schéma —
le prix se lit d'un seul endroit, y compris quand on cherche qui a le droit de
le lire.

## Comment les appliquer

Avec la CLI Supabase, depuis la racine du dépôt :

```bash
supabase db push
```

Ou fichier par fichier, sur n'importe quelle base PostgreSQL :

```bash
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/001_schema.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/002_rls.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/003_amenities.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/004_bookings.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/005_pricing.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/006_rls_bookings.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/007_auth.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/008_search.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/009_wilayas.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/010_event_types.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/011_venue_detail.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/012_booking_request.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/013_mes_reservations.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/014_espace_proprietaire.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/015_repondre_a_une_demande.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/016_agenda_proprietaire.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/017_publier_une_salle.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/018_garde_privileges_profil.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/019_adresse_de_la_salle.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/020_telephone_joignable.sql
```

Les vingt fichiers sont **rejouables** : les relancer sur une base déjà à jour
ne produit ni erreur ni doublon. `003` va plus loin et met à jour les libellés
existants — c'est le moyen prévu pour corriger une traduction.

## Ce que couvre le schéma

Le catalogue :

`profiles`, `venues`, `venue_photos`, `amenities`, `venue_amenities`,
`venue_pricing`, `venue_blackouts`.

Les réservations :

`bookings`, `payments`, `reviews`, `notifications`, plus `venue_options` et
`high_season_periods`, qui servent la formule de prix — ces deux dernières ont
été ajoutées au §6 du cahier des charges, le document est à jour.

Les tables `messages`, `venue_embeddings`, `kb_documents`, `ai_cache` et
`ai_conversations` du §6 ne sont pas encore écrites.

Les fonctions appelées en RPC depuis Flutter :

| Fonction | Écran | Droits |
|---|---|---|
| `search_venues()` (010) | résultats de recherche | `SECURITY DEFINER` |
| `venue_detail()` (**012**) | fiche salle, et demande | droits de l'appelant |
| `venue_calendar()` (011) | calendrier | `SECURITY DEFINER` |
| `booking_quote()` (012) | demande — le devis | droits de l'appelant, ouvert à `anon` |
| `request_booking()` (**020**) | demande — l'envoi | `SECURITY DEFINER`, fermée à `anon` |
| `client_bookings()` (013) | mes réservations | `SECURITY DEFINER`, fermée à `anon` |

`booking_quote()` est ouverte aux visiteurs et `request_booking()` ne l'est pas :
c'est toute la règle du parcours (§3). On montre un prix à qui le demande ; on ne
demande son identité qu'à celui qui engage quelque chose.

## Le cycle de vie d'une réservation

Les états sont ceux du §3, en contrainte `CHECK` sur `bookings.status` :

```
pending ──accept_booking()──> accepted ──confirm_booking()──> confirmed
   │                             │                                │
   │ refuse_booking()            │ expire_options() (72 h)        │ complete_booking()
   ▼                             ▼                                ▼
refused                       expired                         completed ──> avis
```

`cancel_booking()` mène à `cancelled` depuis `pending`, `accepted` ou
`confirmed`. **Aucune de ces transitions n'est faisable par une requête
cliente** : il n'existe volontairement aucune politique `UPDATE` ni `DELETE` sur
`bookings`. Les six fonctions sont `SECURITY DEFINER` et vérifient chacune qui
appelle et d'où l'on part (§9).

## Règles portées par la base

- **Un compte créé, un profil créé.** Le déclencheur `on_auth_user_created`
  (migration 007) écrit la ligne `profiles` dans la transaction de GoTrue.
  L'application n'insère pas le profil elle-même : ce second appel pourrait se
  perdre — réseau coupé, onglet fermé — et laisser un compte sans profil,
  c'est-à-dire un utilisateur connecté à qui plus rien ne répond, puisque
  toutes les clés étrangères du projet pointent vers `profiles`. La fonction
  n'avale jamais ses erreurs : elle normalise ses valeurs pour ne pas pouvoir
  échouer, plutôt que d'échouer en silence.
- **La recherche filtre et tarife en base.** `search_venues()` (008) prend les
  critères, écarte les salles et calcule le prix ; le Dart affiche des lignes.
  C'est ce qui garantit que le montant d'une carte de résultat est le même que
  celui de la fiche et que celui du devis — il vient d'`estimate_price()`, pour
  la date demandée, majorations comprises. **Pas un « à partir de ».**
  S'il devient tentant d'écarter une salle côté Flutter, c'est que la fonction
  SQL est incomplète.
- **`search_venues()` est `SECURITY DEFINER`**, comme la vue
  `venue_availability` et pour la même raison : elle doit lire `bookings` pour
  savoir si un créneau est pris, alors que cette table est fermée aux visiteurs
  (§9). Elle ne renvoie que des colonnes publiques d'une salle **publiée** —
  jamais le téléphone d'un propriétaire, jamais le motif d'un blocage, jamais
  rien de `bookings`. N'y ajoutez aucune colonne sans avoir vérifié qu'un
  inconnu a le droit de la lire.
- **Le filtre « type d'événement » est vrai.** `venue_event_types` (010) dit ce
  qu'une salle accepte, et `search_venues()` s'en sert. **Aucune ligne = la
  salle accepte tout** : un propriétaire qui n'a pas encore répondu à la
  question ne doit pas disparaître du catalogue. Traiter le vide comme un refus
  aurait fait s'évanouir toutes les salles existantes le jour où la migration
  s'applique.
- **`search_venues()` vit dans `010`, pas dans `008`.** La version de `008` ne
  pouvait pas filtrer sur une table qui n'existait pas encore. On ne réécrit
  pas une migration déjà appliquée : `008` reste tel quel avec un renvoi en
  tête, et c'est `010` qu'il faut modifier.
- **Une salle sans avis n'a pas de note.** `search_venues()` renvoie `NULL`, pas
  `0.0` : l'écran n'affiche alors aucune étoile. « 0,0 (0) » ferait passer une
  salle neuve pour une salle mal notée.
- **Le prix se calcule dans `estimate_price()`, et nulle part ailleurs.** Ni en
  Dart, ni dans une seconde fonction SQL. Le trigger `bookings_set_price` jette
  le `quoted_amount` reçu à l'insertion et le remplace par celui
  d'`estimate_price()` : le chemin d'écriture n'a plus d'importance. La seule
  valeur qui peut s'en écarter est la contre-proposition du propriétaire au
  moment d'accepter (§5.2), qui est une décision humaine et non un calcul.
- **Le devis de l'écran de demande ne calcule rien non plus.** `booking_quote()`
  (012) appelle `estimate_price()` et rhabille son résultat : elle n'a pas une
  ligne de formule. Elle y ajoute l'acompte, qui n'est pas un prix mais une
  fraction du devis, et cette fraction vit dans `deposit_rate()` — **une
  fonction d'une ligne, et le seul endroit où le taux est écrit.**
- **Le taux d'acompte est de 25 %** (§5.3), et il vit dans `deposit_rate()`. Le
  §5.3 borne l'acompte à **20–30 %** du montant convenu et fixe à 25 % le taux
  que la plateforme propose ; les maquettes disent la même chose, écrans 5 et 6,
  où 51 250 DA valent bien 25 % de 205 000 DA. Ce montant reste
  **indicatif** : c'est `accept_booking()` qui fixe l'acompte réellement dû, et
  le §5.2 laisse expressément le propriétaire s'écarter de l'estimation.
- **Les refus de `request_booking()` portent un code Ferha dans leur `hint`**
  (012) : `FE001` créneau déjà pris, `FE002` bloqué, `FE003` date passée,
  `FE004` salle fermée, `FE005` sa propre salle, `FE006` non connecté. Leur
  SQLSTATE, lui, est un `PTxxx` : chez PostgREST le SQLSTATE ne nomme pas
  l'erreur, il **choisit le code HTTP**. Un code inventé retomberait sur un 500,
  et « ce créneau vient d'être pris » n'est pas une panne de serveur — c'est un
  409. Le Dart lit le `hint` (`lib/features/booking/booking_messages.dart`) et
  n'a donc jamais à comparer un message français.
- **Le propriétaire ne dépasse jamais `pending`.** ADM-01 : « aucune salle n'est
  visible avant contrôle humain ». Deux portes tiennent cette règle, et il faut
  les deux : `envoyer_salle_en_validation()` (017) écrit `pending` **en dur** —
  il n'y a pas de paramètre de statut par lequel glisser `published` —, et le
  trigger `venues_guard_status` (001) refuse l'écriture directe. Être `SECURITY
  DEFINER` n'endort pas le trigger : il lit `auth.uid()`, qui reste celui du
  propriétaire.
- **Le propriétaire d'une salle vient d'`auth.uid()`, jamais d'un paramètre.**
  `creer_salle()` (017) ne demande pas à qui appartient la salle. « Créer une
  salle au nom d'un autre » n'est donc pas interdit : c'est **inexprimable**, il
  n'y a aucun argument par lequel le mentir. Même chose pour le statut, écrit
  `draft` en dur.
- **Créer sa première salle lève `profiles.is_owner`**, dans la même
  transaction (017). Le drapeau suit le fait au lieu de le précéder : sans lui,
  une cliente qui inscrit une salle n'aurait plus aucun chemin pour la
  retrouver — c'est `is_owner` qui ouvre l'entrée de l'espace propriétaire.
- **Une salle neuve a une adresse, et personne ne la lit** (019). ADM-01 demande
  de contrôler une « adresse plausible » : `creer_salle()` l'exige donc (FE036).
  La colonne reste nullable en table — les quinze salles de démonstration n'en
  ont pas, et inventer quinze rues fausses serait la pire des réponses.
  **RLS ne suffisait pas à la garder privée** : `venues_select_published_or_own`
  (002) laisse un inconnu lire la LIGNE d'une salle publiée, et RLS borne les
  lignes, jamais les colonnes — un `GET /rest/v1/venues?select=address` aurait
  tout rendu. Le droit de SELECT est donc repris sur la table et redonné
  **colonne par colonne**, `address` exclue. Une colonne ajoutée à `venues` sera
  invisible tant qu'on ne l'aura pas ajoutée à cette liste : c'est un oubli qui
  se voit, plutôt qu'un oubli qui ne se voit jamais.
- **Le numéro de téléphone suit UNE règle, écrite une fois** (020) :
  `telephone_valide()` — mobile 0 + 5/6/7 + 8 chiffres (10 en tout), ou fixe
  0 + 2/3/4 + 7 chiffres (9 en tout), espaces tolérés à la saisie, chiffres
  seuls en base. **C'est le deuxième chiffre qui fait le travail** : une règle
  plus large — « 0 et huit chiffres » pour un fixe — prenait un mobile amputé
  d'un chiffre (`077011223`) pour un fixe et le rangeait sans broncher. Elle
  borne la forme, pas l'annuaire : aucune liste d'indicatifs de wilaya, ici
  comme côté Flutter. La contrainte de table,
  le trigger de normalisation et les deux fonctions RPC l'appellent tous ; côté
  Flutter, `lib/core/validation/telephone.dart` en porte le seul autre
  exemplaire, et `tests/007` compare les deux listes d'exemples.
  **Il se demande là où quelqu'un devra décrocher**, et nulle part ailleurs :
  `envoyer_salle_en_validation()` (ADM-01, « propriétaire joignable », FE037) et
  `request_booking()` (FE007) le reçoivent et l'écrivent dans `profiles.phone`.
  Avant cela, aucun écran ne remplissait cette colonne : `booking_contact()`
  ouvrait fidèlement… rien, des deux côtés. Un numéro qui change fait retomber
  `phone_verified` — un drapeau de vérification ne suit pas un numéro jusqu'au
  suivant.
- **Un compte ne se donne pas de droits à lui-même** (018). `is_admin` et
  `is_owner` sont dans `profiles`, mais ce ne sont pas des données : ce sont des
  droits. `profiles_update_self` (002) borne la LIGNE qu'on écrit, pas les
  COLONNES — n'importe quel compte connecté pouvait donc faire
  `update profiles set is_admin = true where id = auth.uid()`, et lire ensuite
  le nom, l'e-mail et le téléphone de **tous** les utilisateurs (la politique de
  lecture s'élargit à `or is_admin()`) puis publier n'importe quelle salle
  (`venues_guard_status` laisse passer les administrateurs). Le trou est fermé
  par le trigger `profiles_guard_privileges` — un `WITH CHECK` ne voit que la
  ligne d'arrivée et ne peut pas distinguer « était déjà administrateur » de
  « vient de se déclarer administrateur », exactement comme en 001.
  Passent encore : le rôle de service — c'est par lui, et par lui seul, que
  naît le premier administrateur — et un administrateur déjà en place.
  `is_owner`, lui, **se constate au lieu de se déclarer** : il ne se lève que
  sur un compte qui possède réellement une salle, ce qui laisse passer
  `creer_salle()` sans une ligne de changement.
- **On ne ferme pas une date sur la tête d'un client.** `bloquer_date()` (016)
  refuse un créneau qui porte une option de 72 h ou une réservation confirmée
  (`FE022`). Fermer la date n'annulerait pas la réservation — elle laisserait
  deux vérités contradictoires dans la base, et un client devant une salle
  fermée. Une demande **en attente**, elle, n'empêche rien : elle n'a bloqué
  aucune date (§5.1), et le propriétaire y répondra depuis sa file. Une
  `journee` dont un seul créneau est vendu ne se ferme pas non plus, et surtout
  pas à moitié : la fonction vérifie avant d'écrire.
- **La double réservation est refusée par la base.** `uniq_booking_slot`, index
  unique partiel sur `(venue_id, event_date, slot) WHERE status IN ('confirmed',
  'completed')` (§6.1). Il est partiel exprès : une demande `pending` ne bloque
  pas la date, plusieurs familles peuvent demander le même 14 août et le
  propriétaire arbitre (§5.1). `supabase/tests/001_double_booking.sql` le
  vérifie.
- **Une réservation `journee` s'écrit en deux lignes**, `midi` et `soir`, liées
  par `group_id` (§6.1). `request_booking()` les insère en une seule
  instruction ; le trigger `bookings_check_journee` refuse toute journée écrite
  en une seule ligne. Le devis est celui du **groupe** et se trouve répété sur
  les deux lignes : lire la vue `booking_groups`, jamais `sum(quoted_amount)`.
- **Pas de réservation honorée, pas d'avis.** `reviews.booking_id` est `UNIQUE
  NOT NULL` (§5.4) — la règle est dans le schéma, pas dans une politique.
  `reviews.booking_group_id`, unique lui aussi, ferme la brèche des journées
  entières, qui portent deux `booking_id` pour un seul événement.
- **La note affichée est bayésienne**, pas une moyenne simple (§5.4). Vue
  `venue_ratings`, seule source de cette note.
- **Aucune écriture cliente sur `payments`** (§9). L'absence de politique
  `INSERT` / `UPDATE` / `DELETE` est la règle, pas un oubli : seul le
  `service_role` du webhook Chargily écrit. L'index partiel
  `payments_checkout_id_key` rend le webhook idempotent.
- **Le téléphone ne sort qu'à partir de `accepted`** (§9). `profiles` reste
  fermée à son seul titulaire ; `booking_contact()` est le seul chemin vers le
  numéro d'un tiers, et il ne s'ouvre pas avant. « sinon la plateforme se fait
  contourner dès la première recherche. »
  **`client_bookings()` (013) ne recopie pas cette règle, elle l'appelle** :
  une jointure latérale sur `booking_contact()`, ligne par ligne. Écrire un
  second `case when status in (…)` aurait fait deux endroits à tenir d'accord,
  et c'est ainsi qu'un numéro finit par fuiter — pas par une faille, par une
  divergence. Si un jour l'écran du propriétaire a besoin de la même liste, il
  passera par la même fonction.
- **`bookings` est publiée en temps réel** (013), et c'est sa politique RLS qui
  la protège : Realtime évalue `bookings_select_parties` pour chaque abonné
  avant de lui livrer une ligne. Ouvrir la publication n'ouvre donc pas la
  table, et si la politique de `SELECT` s'élargit un jour, elle s'élargit ici
  aussi — un seul endroit à surveiller. Le filtre `client_id=eq.<uid>` posé par
  Flutter ne remplace pas la politique : il évite seulement au serveur
  d'examiner des lignes qui ne partiraient pas.
  Le service Realtime **démarre à froid** quand le projet a dormi : un
  changement survenu pendant ces deux secondes-là n'est annoncé à personne.
  C'est pourquoi l'écran charge aussi la liste à l'ouverture, et ne se contente
  jamais des événements.
- **Le propriétaire ne se publie pas lui-même.** Il mène sa salle de `draft` à
  `pending` ; `published` et `suspended` relèvent de l'administration. La règle
  est portée par le trigger `venues_guard_status`, et non par une politique RLS :
  un `WITH CHECK` ne voit que la ligne d'arrivée et ne peut donc pas distinguer
  une salle déjà publiée d'une salle que le propriétaire publierait lui-même.
- **RLS est activé sur toutes les tables.** Une table sans politique d'écriture
  n'est pas un oubli : c'est une table réservée au rôle de service. C'est le cas
  d'`amenities`, de `high_season_periods` et de `payments`.
- **Une journée entière se stocke en deux lignes**, `midi` et `soir`. Même
  découpage que les réservations (§6.1), pour que la requête de disponibilité
  lise `venue_blackouts` et `bookings` de la même façon.
- **Le motif d'un blocage ne sort pas.** `venue_blackouts` n'est lisible que par
  le propriétaire de la salle, parce que `reason` y figure. Le calendrier lit la
  vue `venue_availability`, qui expose `venue_id`, `date` et `slot` — et rien
  d'autre.
- **Le parking est une colonne, pas un équipement.** `venues.parking_spaces`
  porte le nombre de places, et c'est de lui que se fabrique la puce
  « Parking 60 » des maquettes. `NULL` veut dire « non renseigné », `0` veut
  dire « pas de parking ». Deux endroits pour dire la même chose finissent
  toujours par se contredire.

## Les photos : chemin de Storage, ou URL complète

`venue_photos.storage_path` porte normalement un **chemin dans le bucket**
`venue-photos`, de la forme `{venue_id}/{uuid}.webp` (§7.3). C'est ce que
produira l'application quand un propriétaire téléversera ses photos.

Les salles de démonstration, elles, portent une **URL Unsplash complète** :
nous n'avons pas encore de photos réelles, et une application de salles des
fêtes sans images ne se juge pas.

**La règle, côté Flutter :**

> Si `storage_path` commence par `http`, on l'affiche tel quel.
> Sinon, on le résout dans le Storage.

Deux lignes de code, un seul endroit. Le jour où les vraies photos arrivent,
rien à changer : les nouvelles lignes porteront un chemin, les anciennes
partiront avec `seed/002_reset_demo.sql`.

**N'écrivez pas d'URL externe dans `venue_photos` en dehors de
`seed/001_demo_venues.sql`.** C'est une exception de démonstration, pas une
seconde façon de stocker une photo.

## Données de démonstration

Ce ne sont **pas** des migrations : elles ne créent aucune table et ne touchent
à aucune contrainte. Elles vivent dans `seed/` pour qu'on puisse les lancer,
les effacer et les relancer sans que le schéma bouge.

| Fichier | Rôle |
|---|---|
| `seed/001_demo_venues.sql` | 4 propriétaires, 15 salles, 5 wilayas, types d'événement, options payantes |
| `seed/003_demo_accounts.sql` | 2 comptes qui se connectent — **après 001 et 007** |
| `seed/002_reset_demo.sql` | efface tout cela, et rien d'autre |

```bash
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/seed/001_demo_venues.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/seed/003_demo_accounts.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/seed/002_reset_demo.sql   # pour tout retirer
```

`003` vient après `001` — il donne un mot de passe au compte de Karim créé
là-bas — et après la migration `007`, qui pose le déclencheur de profil. Il
s'arrête avec un message clair si l'un des deux manque.

`001` est **rejouable** : comptes et salles sont posés en `ON CONFLICT`, les
tables filles sont effacées puis réécrites. Le relancer ne crée aucun doublon
et ramène les quinze salles à l'état décrit dans le fichier.

Les identifiants portent une marque, et c'est par elle que `002` reconnaît ses
données — pas par le nom, pas par la wilaya : un vrai propriétaire peut
s'appeler Karim et tenir une salle à Oran.

| Préfixe | Quoi |
|---|---|
| `d0000000-0000-4000-a000-…` | les quatre propriétaires de démonstration |
| `5a11e000-0000-4000-a000-…` | les quinze salles |

Treize salles sont `published`, **deux sont `pending`** — de quoi alimenter
l'écran de validation du §4.4 (ADM-01). Une recherche cliente doit en trouver
treize, jamais quinze.

`002` **s'arrête net** si des réservations portent sur ces salles :
`bookings.venue_id` est en `RESTRICT`, et une réservation est une trace
comptable. Il vous dit lesquelles et vous laisse décider.

### Les deux comptes de démonstration

Le §4.1 (CORE-01) les exige : « Deux comptes de démonstration sont proposés en
un tap sur l'écran de connexion. »

| Compte | Adresse | Rôle |
|---|---|---|
| Amina Haddad | `amina@demo.ferha.dz` | cliente, aucune salle |
| Karim Belhadj | `karim.belhadj@demo.ferha.dz` | propriétaire de **4 salles** |

Mot de passe des deux : **`demo1234`**, en clair dans le fichier de seed et
dans `lib/features/auth/demo_accounts.dart`. C'est assumé : ce sont des comptes
publics, sur une base de démonstration, sans aucune donnée réelle. Les cacher
ne protégerait rien.

**Karim est le même compte que le propriétaire de `001`** — même UUID. En se
connectant, il voit ses quatre salles, pas un espace vide. C'est pourquoi `003`
*met à jour* son mot de passe au lieu de recréer le compte : une nouvelle ligne
aurait un nouvel UUID, et les quatre salles se retrouveraient orphelines.

`003` écrit dans `auth.users`, un schéma interne à Supabase dont les colonnes
changent d'une version de GoTrue à l'autre. **C'est la partie la plus fragile du
dépôt.** Une solution de repli, qui ne demande pas de déboguer GoTrue, est
écrite en bas du fichier.

**Aucune de ces données ne doit apparaître dans le code Flutter.** Il ne
connaît que des requêtes — à la seule exception de `demo_accounts.dart`, qui
porte les deux adresses parce que le cahier des charges demande un accès en un
tap.

## Ce que lit le calendrier

| Objet | Qui lit | Contenu |
|---|---|---|
| `venue_availability` (vue) | tous, sur une salle publiée | `venue_id`, `date`, `slot` |
| `venue_blackouts` (table) | le propriétaire de la salle | tout, `reason` comprise |

La vue s'exécute avec les droits de son propriétaire : elle traverse donc la
politique de la table, et c'est son propre `WHERE` qui borne ce qui sort. Ne pas
la passer en `security_invoker = true` — elle ne renverrait plus rien.

**Le motif d'un blocage ne sort que par l'agenda du propriétaire.**
`venue_blackouts.reason` — « travaux », « mariage de ma fille » — n'a aucun
chemin vers un client : la vue ne porte pas la colonne, `venue_calendar()` (011)
ne rend que `(day, state)`, et `owner_agenda()` (016) ne répond qu'au
propriétaire de la salle. `tests/004_agenda_proprietaire.sql` le vérifie de
quatre façons plutôt que de le supposer : les colonnes de la vue, la lecture par
un client connecté, la lecture par un inconnu, et la signature de
`venue_calendar()`.

## Ce qui manque encore

- **UNE SALLE NE PEUT PAS ÊTRE PUBLIÉE SANS GRILLE TARIFAIRE, ET RIEN NE
  L'EMPÊCHE ENCORE.** C'est le trou ouvert par l'étape J12, et il est écrit ici
  pour qu'on ne le découvre pas par un propriétaire qui attend des demandes.

  `search_venues()` (010) fait une jointure **interne** sur `venue_pricing` pour
  le créneau cherché : une salle sans ligne de tarif ne sort d'**aucune**
  recherche, même publiée. Et `estimate_price()` (005) lève `P0002` sur elle, ce
  qui rend sa fiche et son calendrier inutilisables. Autrement dit, une salle
  passée en `published` sans tarifs est visible de personne et réservable par
  personne — sans qu'aucune erreur ne le signale.

  Aujourd'hui, `creer_salle()` (017) n'écrit aucun tarif : l'écran de la grille
  tarifaire (OWN-03) n'existe pas. Deux choses restent donc à faire, et dans cet
  ordre :

  1. l'écran OWN-03, pour que le propriétaire puisse saisir ses prix ;
  2. **un garde-fou dans le passage à `published`** — celui qui valide une salle
     doit se voir refuser une salle sans tarifs, plutôt que de publier une fiche
     morte. Le contrôle humain d'ADM-01 ne suffit pas : c'est exactement le
     genre d'absence qu'un œil ne voit pas.

  En attendant, le récapitulatif de l'inscription le dit au propriétaire en
  toutes lettres — « il vous restera à saisir vos tarifs par créneau ». Une
  phrase n'est pas une contrainte, mais elle vaut mieux qu'un silence.

- **LA CARTE ET LES COORDONNÉES (CLI-02) NE SONT PAS FAITES.** `venues.lat` et
  `venues.lng` existent depuis `001`, avec une contrainte qui interdit d'en
  renseigner une seule (`venues_coordinates_complete`) — mais **aucune salle
  n'en porte**, et aucun écran ne les saisit. La fiche salle n'a donc pas de
  carte, et « les 5 salles les plus proches » du §4.2 n'a rien pour se calculer.

  Ce qui reste à faire, et dans cet ordre :

  1. la saisie, à l'étape 2 du formulaire d'inscription — un point qu'on pose
     sur une carte vaut mieux qu'une latitude tapée à la main ;
  2. la sortie publique. `venues.address` (019) est **privée** : elle sert au
     contrôle humain d'ADM-01 et le droit de SELECT lui a été retiré. `lat` et
     `lng` sont d'une autre nature — une carte est faite pour être vue — mais
     elles restent à décider : montrer le point exact d'une salle avant
     réservation revient à donner son adresse, et c'est précisément ce que le §9
     évite pour les téléphones. Un cercle approximatif avant « accepted », le
     point exact après, est la piste ; elle n'est pas tranchée.

  La question de ce qui s'affiche AVANT réservation se pose donc à trois
  endroits maintenant — téléphone (§9, tranché), adresse (019, tranché : rien),
  coordonnées (à trancher). La réponse devrait être la même partout.

## Points à reprendre plus tard

- **Le nom public d'un propriétaire n'a pas encore de chemin.** `profiles` reste
  lisible par son seul titulaire, et `booking_contact()` ne doit pas être
  élargi pour ça — il porte le téléphone. Ce sera traité à l'étape de la fiche
  salle, par une **vue distincte n'exposant que le prénom** des propriétaires
  ayant au moins une salle publiée. Prénom seul, pas de nom de famille, pas
  d'e-mail, pas de numéro.
- **`bookings` a la `REPLICA IDENTITY` par défaut**, c'est-à-dire la clé
  primaire. Les événements Realtime portent donc la nouvelle ligne entière mais
  un `old_record` réduit à l'identifiant. Cela suffit ici — l'écran recharge par
  `client_bookings()` et ne lit pas l'ancienne ligne. Passer la table en
  `REPLICA IDENTITY FULL` serait à faire seulement si un écran avait besoin de
  savoir *ce qui a changé*, et cela grossirait chaque enregistrement WAL.
- **`accept_booking()` ne vérifie pas les bornes de 20–30 % du §5.3.** Elle
  n'exige aujourd'hui qu'un acompte compris entre 0 et le montant du devis. Le
  §5.3 est plus étroit depuis qu'il fixe la fourchette ; resserrer la contrainte
  demande d'abord de vérifier qu'aucune réservation acceptée n'en sort.
- `high_season_periods` arrive **vide**. Tant qu'elle l'est, seuls juin à
  septembre majorent ; les vacances scolaires du §5.2 doivent y être déposées
  année par année.
- Le **barème de remboursement du §5.3** (100 % / 50 % / 0 % selon la date)
  n'est écrit nulle part : `cancel_booking()` libère la date et trace qui a
  annulé, sans calculer de remboursement. Il viendra avec le remboursement
  Chargily.
- `bookings.event_type` n'a **pas de contrainte** : le §4.2 cite « type
  d'événement » sans en fixer la liste. Un référentiel viendra.
- **`bookings.event_type` n'a pas de clé étrangère vers `event_types`.** La
  colonne est du texte libre depuis `004`, écrite avant que le référentiel
  existe. L'ajouter demande d'abord de vérifier qu'aucune réservation ne porte
  une valeur hors référentiel.
- **`venues.wilaya_code` n'a pas de clé étrangère vers `wilayas`.** Le
  référentiel arrive en 009, la colonne existe depuis 001 : ajouter la
  contrainte demande de vérifier d'abord qu'aucune salle ne porte un code
  inconnu.
- `search_venues()` appelle `estimate_price()` **une fois par salle**. Sans
  incidence sur quinze salles ; à revoir si le catalogue grandit beaucoup.
- Les libellés arabes des référentiels sont marqués `-- À RELIRE` dans
  `003_amenities.sql` et `009_wilayas.sql`, en attente d'une relecture.

## Fermeture de compte : on anonymise, on ne supprime pas

**Décision prise, pas encore écrite en SQL.**

La loi 18-07 demande de pouvoir fermer un compte (§9). Mais une réservation
passée est une **trace comptable** : elle ne peut pas s'évaporer, et l'autre
partie a le droit de retrouver ce qu'elle a vendu ou acheté.

Fermer un compte remplacera donc son `full_name`, son `email` et son `phone`
par des valeurs neutres. Les `bookings`, `payments` et `reviews` restent en
place, rattachés au même identifiant.

C'est aussi pourquoi `bookings.client_id` et `bookings.venue_id` sont en
`RESTRICT` et non en `CASCADE` : une suppression franche doit **échouer**
plutôt que d'emporter l'historique en silence. Le `RESTRICT` n'est pas un
obstacle à contourner le jour où l'on écrira la fermeture de compte — c'est le
filet qui garantit qu'on l'écrira comme une anonymisation.

Reste à décider au moment de l'écrire : ce que devient le `full_name` affiché
sur un avis déjà publié.

## Tests

Deux fichiers, qui se collent tels quels dans l'éditeur SQL de Supabase et
annulent tout par un `ROLLBACK` final. Une erreur rouge commençant par « ÉCHEC »
signale la règle qui ne tient plus.

| Fichier | Ce qu'il vérifie |
|---|---|
| `tests/001_double_booking.sql` | le prix vient d'`estimate_price()`, et la base refuse la seconde réservation confirmée sur un créneau pris |
| `tests/002_devis_demande.sql` | `booking_quote()` ne s'écarte jamais d'`estimate_price()`, l'acompte vient de `deposit_rate()`, et chaque refus de `request_booking()` porte son code Ferha |
| `tests/003_reponse_proprietaire.sql` | un propriétaire ne répond qu'à SES demandes, et accepter un créneau déjà vendu échoue proprement |
| `tests/004_agenda_proprietaire.sql` | la propriété de l'agenda, le refus de fermer une date vendue, et **le motif d'un blocage qui ne sort pas** |
| `tests/005_publier_une_salle.sql` | on n'inscrit pas une salle sans session ni au nom d'un autre, le propriétaire ne se publie pas lui-même, et une salle `pending` n'est pas au catalogue |
| `tests/006_garde_privileges_profil.sql` | un compte connecté ne se fait pas administrateur, ne se déclare pas propriétaire sans salle — et `creer_salle()` marche toujours |
| `tests/007_adresse_et_telephone.sql` | une salle sans adresse est refusée, le numéro est exigé aux deux endroits où quelqu'un décrochera, **l'adresse ne se lit pas même en interrogeant la table**, et un inconnu ne lit toujours aucun numéro |

Le quatrième change de rôle SQL en cours de route (`set local role
authenticated`, puis `anon`). C'est nécessaire : ses trois derniers tests
interrogent une table et une vue, et ce qui les protège est RLS — laquelle ne
s'applique pas au rôle avec lequel on colle le fichier. Sans ce changement, le
test lirait tout et passerait toujours.

`supabase/tests/001_double_booking.sql` se colle tel quel dans l'éditeur SQL de
Supabase. Il crée ses propres données, vérifie que la base refuse la seconde
réservation confirmée sur un créneau déjà pris, et annule tout par un `ROLLBACK`
final. Une erreur rouge commençant par « ÉCHEC » signale la règle qui ne tient
plus.
