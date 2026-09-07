# Base de données Ferha

PostgreSQL, hébergé par Supabase. Le schéma est le contrat entre l'application
Flutter et le backend — cahier des charges §6 pour les tables, §9 pour la
sécurité.

## Ordre d'application

Les fichiers s'appliquent dans l'ordre de leur numéro, et dans cet ordre
seulement :

| Ordre | Fichier | Contenu | Dépend de |
|---|---|---|---|
| 1 | `migrations/001_schema.sql` | Tables, contraintes, index, triggers | `auth.users` (fourni par Supabase) |
| 2 | `migrations/002_rls.sql` | Activation de RLS et politiques | 001 |
| 3 | `migrations/003_amenities.sql` | Référentiel des équipements | 001 |

`002` a besoin des tables de `001`. `003` a besoin de la table `amenities` de
`001`, mais pas de `002`. Appliquer `002` avant `003` reste le bon ordre : le
référentiel arrive alors dans une base déjà fermée.

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
```

Les trois fichiers sont **rejouables** : les relancer sur une base déjà à jour
ne produit ni erreur ni doublon. `003` va plus loin et met à jour les libellés
existants — c'est le moyen prévu pour corriger une traduction.

## Ce que couvre cette étape

Le catalogue, et lui seul :

`profiles`, `venues`, `venue_photos`, `amenities`, `venue_amenities`,
`venue_pricing`, `venue_blackouts`.

Les tables `bookings`, `payments`, `reviews`, `messages`, `venue_embeddings`,
`kb_documents`, `notifications`, `ai_cache` et `ai_conversations` du §6 ne sont
pas encore écrites.

## Règles portées par la base

- **Les prix se calculent en base**, jamais en Dart. `venue_pricing` stocke les
  coefficients ; la fonction de calcul arrivera avec les réservations.
- **Le propriétaire ne se publie pas lui-même.** Il mène sa salle de `draft` à
  `pending` ; `published` et `suspended` relèvent de l'administration. La règle
  est portée par le trigger `venues_guard_status`, et non par une politique RLS :
  un `WITH CHECK` ne voit que la ligne d'arrivée et ne peut donc pas distinguer
  une salle déjà publiée d'une salle que le propriétaire publierait lui-même.
- **RLS est activé sur les sept tables.** Une table sans politique d'écriture
  n'est pas un oubli : c'est une table réservée au rôle de service. C'est le cas
  d'`amenities`.
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

## Ce que lit le calendrier

| Objet | Qui lit | Contenu |
|---|---|---|
| `venue_availability` (vue) | tous, sur une salle publiée | `venue_id`, `date`, `slot` |
| `venue_blackouts` (table) | le propriétaire de la salle | tout, `reason` comprise |

La vue s'exécute avec les droits de son propriétaire : elle traverse donc la
politique de la table, et c'est son propre `WHERE` qui borne ce qui sort. Ne pas
la passer en `security_invoker = true` — elle ne renverrait plus rien.

## Points à reprendre plus tard

- `profiles` n'est lisible que par son titulaire. L'affichage public du nom d'un
  propriétaire, et la révélation de son téléphone après passage à `accepted`
  (§9), viendront avec les réservations.
- La suppression d'un profil supprime ses salles en cascade. À revoir quand
  `bookings` existera : une salle qui porte des réservations confirmées ne doit
  pas disparaître avec le compte de son propriétaire.
- Les libellés arabes du référentiel sont marqués `-- À RELIRE` dans
  `003_amenities.sql`, en attente d'une relecture.
