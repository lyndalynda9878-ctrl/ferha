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
```

Les six fichiers sont **rejouables** : les relancer sur une base déjà à jour
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

- **Le prix se calcule dans `estimate_price()`, et nulle part ailleurs.** Ni en
  Dart, ni dans une seconde fonction SQL. Le trigger `bookings_set_price` jette
  le `quoted_amount` reçu à l'insertion et le remplace par celui
  d'`estimate_price()` : le chemin d'écriture n'a plus d'importance. La seule
  valeur qui peut s'en écarter est la contre-proposition du propriétaire au
  moment d'accepter (§5.2), qui est une décision humaine et non un calcul.
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
| `seed/001_demo_venues.sql` | 4 propriétaires, 15 salles, 5 wilayas |
| `seed/002_reset_demo.sql` | efface tout cela, et rien d'autre |

```bash
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/seed/001_demo_venues.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/seed/002_reset_demo.sql   # pour tout retirer
```

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

**Aucune de ces données ne doit apparaître dans le code Flutter.** Il ne
connaît que des requêtes.

## Ce que lit le calendrier

| Objet | Qui lit | Contenu |
|---|---|---|
| `venue_availability` (vue) | tous, sur une salle publiée | `venue_id`, `date`, `slot` |
| `venue_blackouts` (table) | le propriétaire de la salle | tout, `reason` comprise |

La vue s'exécute avec les droits de son propriétaire : elle traverse donc la
politique de la table, et c'est son propre `WHERE` qui borne ce qui sort. Ne pas
la passer en `security_invoker = true` — elle ne renverrait plus rien.

## Points à reprendre plus tard

- **Le nom public d'un propriétaire n'a pas encore de chemin.** `profiles` reste
  lisible par son seul titulaire, et `booking_contact()` ne doit pas être
  élargi pour ça — il porte le téléphone. Ce sera traité à l'étape de la fiche
  salle, par une **vue distincte n'exposant que le prénom** des propriétaires
  ayant au moins une salle publiée. Prénom seul, pas de nom de famille, pas
  d'e-mail, pas de numéro.
- `high_season_periods` arrive **vide**. Tant qu'elle l'est, seuls juin à
  septembre majorent ; les vacances scolaires du §5.2 doivent y être déposées
  année par année.
- Le **barème de remboursement du §5.3** (100 % / 50 % / 0 % selon la date)
  n'est écrit nulle part : `cancel_booking()` libère la date et trace qui a
  annulé, sans calculer de remboursement. Il viendra avec le remboursement
  Chargily.
- `bookings.event_type` n'a **pas de contrainte** : le §4.2 cite « type
  d'événement » sans en fixer la liste. Un référentiel viendra.
- Les libellés arabes du référentiel sont marqués `-- À RELIRE` dans
  `003_amenities.sql`, en attente d'une relecture.

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

`supabase/tests/001_double_booking.sql` se colle tel quel dans l'éditeur SQL de
Supabase. Il crée ses propres données, vérifie que la base refuse la seconde
réservation confirmée sur un créneau déjà pris, et annule tout par un `ROLLBACK`
final. Une erreur rouge commençant par « ÉCHEC » signale la règle qui ne tient
plus.
