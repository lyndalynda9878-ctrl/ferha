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

## Points à reprendre plus tard

- `venue_blackouts.reason` est un motif interne du propriétaire, mais la table
  est lisible publiquement parce que le calendrier l'est. Avant que l'écran
  calendrier ne lise cette table directement, poser une vue qui n'expose que
  `venue_id`, `date` et `slot`.
- `profiles` n'est lisible que par son titulaire. L'affichage public du nom d'un
  propriétaire, et la révélation de son téléphone après passage à `accepted`
  (§9), viendront avec les réservations.
- La suppression d'un profil supprime ses salles en cascade. À revoir quand
  `bookings` existera : une salle qui porte des réservations confirmées ne doit
  pas disparaître avec le compte de son propriétaire.
- Les maquettes affichent « Parking 60 » et « Superficie 620 m² ». Ni la valeur
  numérique d'un équipement ni la superficie ne figurent au §6 : elles ne sont
  donc pas dans le schéma.
- Les libellés arabes du référentiel sont à faire relire.
