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
| 21 | `migrations/021_photos_de_la_salle.sql` | le bucket `venue-photos`, ses politiques, `ajouter_photo()`, `supprimer_photo()`, `reordonner_photos()` — **redéfinit `envoyer_salle_en_validation()`** | 001, 002, 017, 020 |
| 22 | `migrations/022_delais_et_alertes.sql` | pg_cron, les notifications lisibles et le temps réel — **redéfinit `notify_user()`, `request_booking()` et `expire_options()`** | 004, 006, 012, 020 |
| 23 | `migrations/023_une_option_tient_la_date.sql` | `tient_la_date()` — LA règle de disponibilité, écrite une seule fois — **redéfinit `search_venues()`, `venue_calendar()`, `request_booking()`, `accepter_demande()`, `owner_agenda()` et `bloquer_date()`** | 004, 008, 010, 011, 012, 014, 015, 016 |
| 24 | `migrations/024_acompte_chargily.sql` | `montant_acompte()`, `acompte_a_verser()`, `enregistrer_checkout()` — le versement de l'acompte — **redéfinit `client_bookings()`** | 004, 006, 013, 015, 023 |
| 25 | `migrations/025_paiement_confirme.sql` | `confirmer_paiement_chargily()`, le parcours espèces, `payments.anomalie` et la vue `paiements_a_examiner` — **redéfinit `owner_request_detail()` et `acompte_a_verser()`** | 004, 006, 014, 022, 023, 024 |
| 26 | `migrations/026_les_avis.sql` | `complete_booking()`, `deposer_avis()`, `repondre_a_un_avis()`, `avis_de_la_salle()` — l'écran 7 | 004, 006, 013, 022 |
| 27 | `migrations/027_index_semantique.sql` | `venue_embeddings`, `document_salle()`, `salles_a_indexer()`, `recherche_semantique()` (§8.3, §8.4) | 001, 003, 004, 010, 011 |
| 28 | `migrations/028_agent.sql` | `salles_pour_agent()` et `journaliser_conversation()` (§8.1, §8.5) | 010, 023, 027 |
| 29 | `migrations/029_agent_parking_et_prix.sql` | le parking et le prix deviennent filtres et tris — **redéfinit `salles_pour_agent()`** | 028 |
| 30 | `migrations/030_agent_nom_arabe_wilaya.sql` | `wilaya_name_ar` remonte dans le contexte — **redéfinit `salles_pour_agent()`** | 009, 029 |
| 31 | `migrations/031_agent_photo_de_la_salle.sql` | `cover_photo` remonte pour les cartes de l'écran 8 — **redéfinit `salles_pour_agent()`** | 023, 030 |
| 32 | `migrations/032_synthese_des_avis.sql` | `venue_review_summaries`, `synthese_avis_minimum()`, `avis_pour_synthese()`, `enregistrer_synthese_avis()`, le cron `ferha-synthese-avis` — **redéfinit `avis_de_la_salle()`** | 001, 002, 004, 022, 026 |
| 33 | `migrations/033_options_dans_mes_reservations.sql` | `option_labels` — les libellés des options retenues, pour que la confirmation d'une demande survive à un rechargement — **redéfinit `client_bookings()`** | 004, 005, 006, 024, 026 |
| 34 | `migrations/034_gardien_des_empreintes.sql` | `gardien_empreintes`, `reveiller_empreintes()`, la vue `etat_du_gardien`, le cron `ferha-reveil-empreintes` — le service d'empreintes ne s'endort plus | pg_cron, pg_net |
| 35 | `migrations/035_le_decor_se_remet_en_place.sql` | `decor_bookings`, `decor_reviews`, `decor_blackouts`, `capturer_le_decor()`, `vider_le_decor()`, `menage_du_decor()`, la vue `etat_du_decor`, le cron `ferha-menage-du-decor` — la démonstration se répare entre deux visiteurs | 001, 004, 005, 012, et les seeds 001, 003, 004 |
| 36 | `migrations/036_les_personnes_du_decor.sql` | `decor_profiles`, `roles_detournes` — l'empreinte tient aussi les personnes ; le rôle se remet sans délai, les saisies attendent — **élargit `capturer_le_decor()`, `vider_le_decor()`, `menage_du_decor()` et `etat_du_decor`** | 001, 018, 035 |
| 37 | `migrations/037_les_dates_bloquees_manquantes.sql` | les 50 dates bloquées du second bloc de `seed/001`, que la base n'avait jamais reçues — additive, rejouable, et elle reprend l'empreinte APRÈS l'insertion | 001, 035, 036, seed/001 |
| 38 | `migrations/038_pas_de_telephone_en_demonstration.sql` | `profiles_pas_de_telephone_en_demonstration` — un compte `d0000000-…` ne PEUT PAS porter de numéro : le déclencheur force `phone` à NULL et `phone_verified` à false, sous toutes les portes. Il force, il ne refuse pas | 001, 018, 020 |
| 39 | `migrations/039_les_favoris.sql` | `favorites` (clé primaire composite), sa RLS, `mes_favoris()`, `decor_favorites` et les trois favoris d'Amina — **élargit `capturer_le_decor()`, `vider_le_decor()`, `menage_du_decor()` et `etat_du_decor`** ; additive et rejouable, elle reprend l'empreinte APRÈS l'insertion | 001, 002, 005, 035, 036, seed/001 |

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
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/021_photos_de_la_salle.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/022_delais_et_alertes.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/023_une_option_tient_la_date.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/024_acompte_chargily.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/025_paiement_confirme.sql
```

Les trente-deux fichiers sont **rejouables** : les relancer sur une base déjà à jour
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

`venue_embeddings` (027), `ai_conversations` (028) et `venue_review_summaries`
(032, hors §6 : la synthèse d'avis n'y avait pas de table) existent désormais.
Les tables `messages`, `kb_documents` et `ai_cache` du §6 ne sont pas encore
écrites.

Les fonctions appelées en RPC depuis Flutter :

| Fonction | Écran | Droits |
|---|---|---|
| `search_venues()` (010) | résultats de recherche | `SECURITY DEFINER` |
| `venue_detail()` (**012**) | fiche salle, et demande | droits de l'appelant |
| `venue_calendar()` (011) | calendrier | `SECURITY DEFINER` |
| `booking_quote()` (012) | demande — le devis | droits de l'appelant, ouvert à `anon` |
| `request_booking()` (**020**) | demande — l'envoi | `SECURITY DEFINER`, fermée à `anon` |
| `client_bookings()` (**033**) | mes réservations, et la confirmation d'une demande | `SECURITY DEFINER`, fermée à `anon` |
| `acompte_a_verser()` (**025**) | verser l'acompte — l'écran 6 | `SECURITY DEFINER`, fermée à `anon` |
| `payer_en_especes()` (025) | écran 6 — « espèces sur place » | `SECURITY DEFINER`, fermée à `anon` |
| `confirmer_encaissement_especes()` (025) | détail d'une demande — « j'ai reçu l'acompte » | `SECURITY DEFINER`, fermée à `anon` |
| `mes_notifications()` (022) | notifications, et le badge de la cloche | droits de l'appelant, fermée à `anon` |
| `marquer_notifications_lues()` (022) | notifications — une, ou toutes | droits de l'appelant, fermée à `anon` |

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

**Une seule de ces flèches ne part de personne** : `expire_options()`. Voir
ci-dessous.

## L'option de 72 h s'éteint toute seule (022)

Le §5.1 pose une option de 72 h sur une demande acceptée, et dit qu'elle expire
« automatiquement » sans acompte. Deux tâches **pg_cron**, posées par la
migration 022, portent ce mot :

| Tâche | Quand | Ce qu'elle fait |
|---|---|---|
| `ferha-expire-options` | toutes les 15 min | `select public.expire_options();` |
| `ferha-purge-cron-history` | tous les jours à 3 h 20 | efface les exécutions de plus de 7 jours dans `cron.job_run_details` |
| `ferha-synthese-avis` (032) | tous les jours à 3 h 50 | `select public.declencher_synthese_avis();` — réveille l'Edge Function « summarize-reviews » par pg_net |
| `ferha-reveil-empreintes` (034) | toutes les 5 min | `select public.reveiller_empreintes();` — tient le service d'empreintes éveillé |
| `ferha-menage-du-decor` (035) | toutes les heures, à la minute 10 | `select public.menage_du_decor();` — efface ce qu'un visiteur a fait sur la démonstration et remet le décor en place |

### La démonstration se répare entre deux visiteurs (035)

Les visiteurs entrent en un tap, comme Amina ou comme Karim. Tout ce qu'ils font
est donc fait au nom des comptes de démonstration, et reste après eux — y
compris ce qu'ils DÉFONT : un visiteur entré comme Karim qui refuse une demande
vide la file d'attente de l'écran 9 sans rien créer. Mesuré le 16 septembre
2026, avant la migration : 19 réservations de visiteurs, 45 notifications, 4
dates bloquées de trop, et **plus une seule demande en attente**.

Le ménage distingue le DÉCOR de ce qui est arrivé après, par les préfixes
d'identifiant déjà posés par les seeds (`b0000000-`, `5a11e000-`, `d0000000-`).
Il efface les réservations de visiteurs sur les salles de démonstration, puis
remet le décor tel qu'une empreinte le décrit. Rien n'est touché avant deux
heures : un visiteur qui teste dix minutes garde ce qu'il vient de faire.

**Sans empreinte, il ne fait rien.** L'empreinte se prend par
`capturer_le_decor()`, que `seed/004_demo_bookings.sql` appelle en dernière
instruction — et à ce moment-là seulement, parce que capturer un décor déjà
abîmé fige le dégât.

```sql
select * from public.etat_du_decor;   -- ce qui est sale en ce moment
```

`demandes_en_attente` est la ligne qui compte : le tableau de bord n'a plus rien
à montrer quand elle tombe à zéro. Banc d'essai :
`tests/018_le_decor_se_remet_en_place.sql`.

**Un trou connu, documenté dans l'en-tête de la migration :** une vraie
réservation prise sur une salle de démonstration serait effacée, son identifiant
étant aléatoire comme celui d'un visiteur. Toutes les salles du catalogue sont
aujourd'hui de démonstration, donc le risque est maximal — mais ce dépôt est une
pièce de portfolio et il n'y a pas de vraies réservations. À revoir le jour où il
y en aurait.

**Le second trou a été bouché le 16 septembre 2026**, et la première version de
cette section le décrivait de travers : elle disait qu'une salle publiée par un
visiteur ferait « échouer » `seed/002_reset_demo.sql`. C'est l'inverse.
`venues.owner_id` référence `profiles` en **CASCADE** : 002 n'échouait pas, il
emportait ces salles **sans les nommer**, et son bloc de preuve n'en disait rien
puisqu'il ne comptait que les salles en `5a11e000-`. Une cascade muette, pas un
échec bruyant — donc précisément ce que la règle RESTRICT du projet cherche à
empêcher. `002` reconnaît désormais une salle à son **propriétaire** autant qu'à
son identifiant, et son bloc de preuve les compte.

**Les fichiers du bucket ne suivent pas.** Rien ne relie `storage.objects` à
`venues` : le SQL efface la ligne d'index d'une photo, jamais le fichier. Le bloc
de preuve de `002` compte désormais `fichiers_orphelins` — le seul de ses
compteurs qui a le droit de ne pas être nul. Les retirer se fait par l'API
Storage, **avant** de supprimer la salle : après, la politique
`venue_photos_storage_delete` (021) exige `owns_venue()` et plus personne n'y a
droit.

### Les personnes aussi (036)

L'empreinte de 035 tient les réservations, les avis et les dates bloquées. Elle ne
voyait pas les **personnes**, et deux dérives vivaient en base le 16 septembre
2026 : Amina portait `is_owner = true` alors que son seed la déclare cliente — «
Entrer comme Amina (cliente) » ouvrait l'espace propriétaire — et `locale = 'ar'`,
si bien que l'application s'ouvrait **en arabe**, de droite à gauche, pour tout
visiteur entrant comme elle. Les deux ont été remises à la main avant la première
empreinte.

**Deux horloges, et c'est la décision du fichier.** `is_owner` se remet **sans
délai** : l'application n'écrit jamais ce champ — aucun écran ne le touche, 018
l'interdit dans les deux sens, et seule `creer_salle()` (017) le lève en même
temps qu'elle insère une salle. Il n'y a donc aucune saisie en cours à protéger,
et tant qu'il est faux la promesse de l'écran d'accueil est fausse pour tout le
monde. Le nom, l'e-mail, le téléphone et la langue, eux, sont des **saisies** et
gardent le délai de deux heures : un visiteur qui bascule en arabe pour regarder
la mise en page doit la garder le temps de sa visite.

L'objection — « la salle du visiteur attend deux heures, remettre le drapeau tout
de suite laisserait une salle dont le propriétaire n'est plus déclaré
propriétaire » — reposait sur une prémisse fausse : **le ménage n'efface jamais
les salles publiées par un visiteur**, ni au bout de deux heures, ni jamais. Cet
état est donc définitif quelle que soit la durée. Et ce qu'il casse est petit :
côté base **rien** — `owns_venue()` lit `owner_id`, jamais `is_owner` — côté
application, le bouton « Mes salles » disparaît de l'écran profil.

**La restauration se fait par `UPDATE`, jamais par delete-insert** :
`profiles.id` est référencé par `bookings.client_id` en RESTRICT, par
`venues.owner_id` et `notifications.user_id` en CASCADE. Un profil absent n'est
pas recréé — seul `seed/003` sait reposer un compte avec son identité GoTrue, et
036 n'approche pas `auth.users`.

```sql
select roles_detournes, profils_detournes from public.etat_du_decor;
```

`roles_detournes` a sa propre ligne parce qu'elle ne dit pas la même chose que
`profils_detournes` : un nom changé est une salissure, un rôle changé modifie ce
qu'un visiteur **voit** en entrant.

### Le gardien des empreintes (034), et comment voir qu'il est mort

Render endort l'offre gratuite. Mesuré au J25 : **62 s** pour le premier appel
après deux heures de silence, contre **85 à 573 ms** à chaud. Une tâche pg_cron
frappe donc `/health` toutes les 5 minutes — 288 appels par jour, qui ne se
paient nulle part, et **aucune dépendance nouvelle** : pg_cron et pg_net étaient
déjà là.

**`cron.job_run_details` ne suffit pas à surveiller ce gardien.** Il dit que la
tâche a tourné, jamais que le service a répondu : une tâche qui dépose une
requête vers une adresse morte est enregistrée « succeeded ». Un voyant vert
au-dessus d'un service éteint est exactement ce qu'on veut éviter.

C'est pourquoi `public.gardien_empreintes` garde le **code HTTP et le corps
réels**, relevés de `net._http_response` à la passe suivante — pg_net est
asynchrone, la réponse n'existe pas encore quand la fonction rend la main. Une
seule requête à retenir :

```sql
select * from public.etat_du_gardien;
```

| ce qu'on lit | ce que ça veut dire |
|---|---|
| `derniere_reussite` il y a moins de 10 min | tout va bien |
| `derniere_reussite` vieille, `derniere_frappe` récente | **le gardien tourne, le service est mort** — c'est le cas qu'aucun voyant vert ne montre |
| `derniere_frappe` vieille aussi | la tâche pg_cron ne tourne plus : regarder `cron.job` et `cron.job_run_details` |
| `dernier_corps` vide et `derniere_erreur` remplie | le service répond mais mal — l'erreur vient de pg_net, telle quelle |
| `echecs_24h` qui monte | à regarder avant une démonstration |

`dernier_corps` doit contenir le modèle chargé :
`{"etat":"ok","modele":"intfloat/multilingual-e5-small","dimensions":384,"charge":true}`.
Ce corps ne peut venir que de Render : c'est lui la preuve, pas l'état du job.

L'adresse se lit dans le Vault sous `ferha_embeddings_url`, et à défaut retombe
sur celle du dépôt — un projet recréé repart donc avec son gardien sans qu'on
ait rien à poser. `/health` ne demande aucun jeton.

### Empêcher la base de se mettre en pause — et comment voir que ça a lâché

Un projet gratuit se met en pause après une semaine sans activité. **Le gardien
ci-dessus n'y peut rien** : il vit dans la base, et un pg_cron ne tourne pas
dans un projet en pause. Le réveil doit venir de dehors, d'où le workflow
`.github/workflows/maintien-supabase.yml`, toutes les 48 h à 4 h UTC.

**C'est une prophylaxie, pas un remède.** Une fois le projet effectivement en
pause, aucune requête API ne le relance : il faut le restaurer à la main depuis
le tableau de bord Supabase. Ce workflow sert à ce que ce moment n'arrive
jamais ; il ne sait pas en sortir.

**Il fait une vraie requête, et il en vérifie la réponse.** Il lit les salles
publiées par PostgREST, avec la clé publiable — la même requête que le banc des
37 questions. Trois conditions, chacune capable de faire échouer le travail à
elle seule : code **200**, corps qui est un **tableau JSON** (une page d'erreur
n'en est pas un), et **au moins une salle**. Les noms lus sont écrits dans le
résumé du travail : c'est la preuve qu'un humain peut regarder.

| ce qui a lâché | comment ça se voit |
|---|---|
| la base ne répond plus, ou plus 200 | **travail rouge**, et GitHub envoie un courriel au propriétaire du dépôt |
| la base répond mais le catalogue est vide | **travail rouge** — `AUCUNE salle publiée` |
| un secret a disparu ou changé | **travail rouge** dès la première étape |
| **le dépôt est resté 60 jours sans activité** | **le travail ne devient PAS rouge : il cesse d'être planifié.** GitHub désactive les tâches planifiées des dépôts dormants, après un courriel d'avertissement |

Cette dernière ligne est la panne sournoise de ce dispositif, et la seule qu'un
vert ne montrera jamais. Le repère à regarder est la **date de la dernière
exécution** dans l'onglet Actions : si elle a plus de 48 h, la planification est
tombée, quoi qu'en dise la dernière exécution connue.

On peut le lancer à la main à tout moment : onglet **Actions** → *Maintien de la
base* → **Run workflow**.

La troisième est la seule à **sortir de la base**, et c'est assumé : elle a
besoin de parler à un modèle de langage, donc d'une clé d'API, qui n'a rien à
faire dans PostgreSQL (§7.1). Elle lit l'URL et la clé de service dans le
**Vault**, par leur nom — `ferha_functions_url` et `ferha_service_role_key` —,
et tant que l'un des deux manque elle rend `NULL` après un avertissement, sans
échouer. Voir `supabase/functions/summarize-reviews/README.md`.

```sql
-- Ce que fait le cron, à la main :
select public.expire_options();      -- rend le nombre de RÉSERVATIONS expirées

-- Les deux tâches, et leurs dernières exécutions :
select jobname, schedule, active from cron.job;
select j.jobname, d.status, d.start_time, d.return_message
from cron.job_run_details d join cron.job j using (jobid)
order by d.start_time desc limit 10;
```

**Pas d'Edge Function**, alors que le §7.2 en dessine une (`expire-options`,
cron horaire). Elle n'aurait fait qu'appeler par HTTP une fonction SQL qui
existe déjà : un secret de plus à garder, et une panne possible entre deux
morceaux qui vivent dans la même base.

**Toutes les 15 minutes et non toutes les heures.** Une heure de retard sur une
option échue, c'est une heure pendant laquelle une date libre se lit « prise »
dans `owner_agenda()` — et c'est justement le moment où une autre famille
regarde.

**Les demandes `pending` n'expirent pas**, et ce n'est pas un oubli : le §5.1
n'y pose aucune échéance, et une demande en attente ne coûte la date à
personne. Un propriétaire parti en voyage retrouve ses demandes au retour
plutôt qu'un écran vide.

## Les favoris (039)

Une salle mise de côté, et rien d'autre : `favorites` porte **la personne, la
salle, la date**. Pas de dossier, pas de note, pas de partage, pas de compteur.

**La clé primaire porte les deux colonnes ensemble.** Aimer deux fois la même
salle ne crée pas deux lignes, et ce n'est pas un `if` en Dart qui l'empêche —
c'est `primary key (user_id, venue_id)`. Même doctrine que l'index partiel qui
rend la double réservation impossible (004) : un double tap, deux onglets
ouverts, une reprise de réseau qui rejoue la requête, aucun de ces trois chemins
ne passe.

**RLS : je lis, j'ajoute et je retire MES lignes, et rien d'autre.** Trois
politiques, et **aucune d'`UPDATE`** — un favori n'a rien à modifier, il existe
ou il n'existe pas, et ses deux seules colonnes sont sa clé. L'insertion vérifie
en plus `can_read_venue()` : sans ce contrôle, la table accepterait
l'identifiant de n'importe quelle salle, et un inconnu pourrait y ranger des
identifiants au hasard pour apprendre lesquels existent. Le retrait, lui, ne
vérifie pas la salle — une salle dépubliée après coup laisserait sinon son
favori collé pour toujours.

`mes_favoris()` rend **les douze colonnes de `search_venues()`, dans le même
ordre** : l'onglet réutilise la carte de l'accueil et des résultats sans en
redessiner une. Le prix vient d'`estimate_price()` comme partout ailleurs, pour
aujourd'hui, le soir, une personne — l'onglet ne porte aucune date.

### À la suppression : CASCADE des deux côtés, et pourquoi la règle tient toujours

`CLAUDE.md` interdit de passer une clé en `CASCADE` pour faire passer une
suppression, parce que c'est le filet qui garantit qu'on écrira une
anonymisation. Les deux clés de `favorites` sont pourtant en `CASCADE`. La règle
n'est pas contournée : **elle ne s'applique pas ici**, et voici les trois
raisons.

1. **Un favori n'a qu'une seule partie.** Une réservation est un échange : il y
   a un vendeur et un acheteur, et chacun peut venir demander ce qu'il a fait.
   Un favori n'est connu que de la personne qui l'a posé — le propriétaire de la
   salle ne le voit pas, la RLS le lui interdit, et on a refusé exprès le
   compteur « 12 personnes aiment cette salle ». Il n'existe **aucun tiers** qui
   pourrait un jour venir réclamer cette ligne.

2. **Anonymiser un favori ne conserverait rien.** C'est le test décisif, et il
   se pose ainsi : que reste-t-il de lisible après l'anonymisation ? Pour une
   réservation, beaucoup — « cette salle a été louée ce jour-là, pour ce
   montant » reste vrai, reste utile, et reste dû au propriétaire. Pour un
   favori, il reste « quelqu'un, un jour, a aimé cette salle » : une phrase que
   **personne** ne peut lire, puisque le seul lecteur que la RLS désigne jamais
   est le propriétaire de la ligne, et qu'il n'existe plus. Ce n'est pas une
   trace préservée, c'est une ligne orpheline — et la garder serait conserver
   une donnée personnelle au-delà de la finalité qui la justifiait, l'inverse de
   ce que demande la loi 18-07.

3. **Cette cascade ne desserre pas le filet d'un millimètre.** Le filet, c'est
   `bookings.client_id` en `RESTRICT`, et il ne bouge pas. Une suppression
   franche d'un profil qui a déjà réservé échoue toujours, et elle échoue
   **avant** que la cascade des favoris ait la moindre occasion de partir. Cette
   cascade ne peut donc s'exécuter que pour un profil sans aucune réservation —
   exactement le cas où il n'y a aucun historique comptable à protéger. On ne
   fait pas passer une suppression qui était bloquée : on choisit le
   comportement d'une table neuve que rien n'a jamais bloquée.

**La salle qui disparaît** : même raisonnement, plus court. Le contenu entier
d'un favori EST la salle ; sans elle il ne désigne plus rien, et l'onglet
afficherait une carte vide. Toutes les tables qui dépendent d'une salle
cascadent déjà — photos, tarifs, dates bloquées, équipements, avis ; la seule
qui résiste est `bookings.venue_id`, et elle résiste parce qu'elle enregistre
une **vente**. Un favori n'enregistre aucune vente.

### Ce que le décor garantit

Les favoris sont la **première donnée qu'un visiteur crée sans formulaire**.
Envoyer une demande prend six écrans ; toucher un cœur prend un doigt. Le chemin
d'entrée de la démonstration est « Entrer comme Amina », en un tap, sur un
compte partagé : sans ce qui suit, dans une semaine l'onglet Favoris d'Amina
montrerait les salles de trente inconnus — et le gardien du décor n'en saurait
rien, parce qu'il ne connaissait pas cette table.

Trois gestes, donc, et ce sont ceux de 035 appliqués à une table de plus :

* **le décor porte trois favoris pour Amina** — Salle El Bahia (Oran), Palais
  Dar El Feth (Zéralda), Salle Les Ponts (Constantine). Trois wilayas, trois
  propriétaires, trois capacités éloignées : ce qu'une famille met de côté, pas
  trois variantes de la même salle. El Bahia est celle qui porte les trois avis
  du décor, donc la seule dont la carte montre une note ;
* **`decor_favorites` capture ces trois lignes**, `created_at` compris — c'est
  l'ordre de l'onglet, et un favori reposé à `now()` remonterait en tête de
  liste à chaque ménage, faisant changer l'écran tout seul dans la nuit ;
* **`menage_du_decor()` les remet** : exactement trois, ni plus ni moins. Le
  critère est **la personne** (`user_id like 'd0000000-%'`) et non la salle : un
  favori n'appartient pas à une salle, il appartient à quelqu'un. Un favori posé
  par une vraie personne sur une salle de démonstration n'est jamais touché.

Les favoris du décor se reposent **sans délai**, comme les dates bloquées : un
favori du décor qu'un visiteur a retiré est une absence, pas une saisie en
cours, et l'onglet d'Amina doit cesser d'être vide à la première heure ronde. Ce
qu'un visiteur a ajouté en trop attend, lui, `p_delai` — celui qui pose cinq
cœurs en voit cinq pendant toute sa visite.

`etat_du_decor` gagne trois colonnes, et **elles disent la conformité, pas
l'exécution** — une tâche cron qui tourne à vide s'exécute parfaitement :

| Colonne | Ce qu'elle dit | Valeur attendue |
|---|---|---|
| `empreinte_favoris` | combien de favoris l'empreinte porte | `3` |
| `favoris_de_visiteurs_en_trop` | les favoris posés par un visiteur sur un compte de démonstration | `0` |
| `favoris_du_decor_manquants` | les favoris du décor qu'un visiteur a retirés | `0` |

**L'ordre est un garde-fou, pas une préférence.** `menage_du_decor()` efface les
favoris de comptes de démonstration absents de l'empreinte : insérer les trois
lignes sans reprendre l'empreinte derrière, c'est les voir disparaître à la
première heure ronde passé le délai — sans message et sans erreur. **Insertion
d'abord, empreinte ensuite**, dans `seed/004` comme dans la migration 039.

## Les notifications (§4.1, CORE-04)

`notify_user()` est le **seul** chemin vers `notifications` : la table n'a
aucune politique `INSERT`. Depuis 022, la fonction ne se contente plus de
déposer deux identifiants — elle **remplit le payload** à partir de
`booking_groups` :

```json
{
  "booking_id": "…", "group_id": "…", "venue_id": "…",
  "venue_name": "Salle El Bahia", "commune": "Oran",
  "event_date": "2027-08-14", "requested_slot": "journee",
  "slots": ["midi", "soir"], "guest_count": 400,
  "role": "client"
}
```

Trois conséquences, et elles se voient toutes à l'écran :

- **Le texte ne demande aucune seconde requête.** L'écran écrit « Salle El
  Bahia · 14 août 2027, journée · 400 invités » avec ce qu'il a reçu — pas une
  requête par ligne, et pas un nom de salle écrit en dur côté Flutter.
- **Le texte est figé.** Une salle renommée demain ne réécrit pas l'annonce
  d'hier. C'est la différence entre une notification et une vue.
- **`role` décide de l'écran d'arrivée.** `booking_confirmed` part aux deux
  parties, avec le même type et le même identifiant de demande ; seul le rôle
  distingue « Mes réservations » du détail de la demande côté propriétaire.

`booking_id` est toujours **normalisé** vers la ligne représentative du groupe
(`slots[1]`), celle qu'attendent `owner_request_detail()`, `accepter_demande()`
et `refuser_demande()`. Une journée entière s'ouvre donc toujours par la même
de ses deux lignes.

### Qui est prévenu, et une seule fois

| Changement d'état | Qui reçoit | Type |
|---|---|---|
| nouvelle demande | le propriétaire | `booking_requested` |
| acceptation, contre-proposition | le client | `booking_answered` (`status: accepted`) |
| refus | le client | `booking_answered` (`status: refused`) |
| acompte reçu | **les deux** | `booking_confirmed` |
| annulation | **l'autre** partie, pas celle qui a cliqué | `booking_cancelled` |
| option de 72 h échue | **les deux** | `booking_expired` |
| événement honoré | le client | `review_invitation` |

**Une réservation, une notification — jamais une par ligne.** Une journée
entière occupe deux lignes de `bookings` ; elle ne s'annonce, ne s'accepte et
n'expire qu'une fois. `tests/009_delais_et_alertes.sql` compte chacun de ces
sept gestes, et c'est le seul test qui attrape la notification **en trop** —
celle qu'on ajoute « pour être sûr » et qui ne casse rien en apparence.

`booking_expired` est un type à part et non un `booking_cancelled` portant un
motif : « votre réservation a été annulée » laisse croire que quelqu'un l'a
annulée, alors que personne n'a rien fait — et que c'est justement le problème.

### `notifications` en temps réel

La table est dans la publication `supabase_realtime` depuis 022, comme
`bookings` depuis 013. **La politique `notifications_select_own` (006) est le
seul garde-fou** : Realtime l'évalue pour chaque abonné avant de lui livrer une
ligne. Ouvrir la publication n'ouvre donc pas la table.

C'est le point que `tests/009` vérifie le plus sérieusement : une politique
relâchée ne se verrait nulle part dans l'application — chacun continuerait de
voir sa liste — et enverrait pourtant les demandes des uns sur le téléphone des
autres.

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
  **Et sur un compte de démonstration, il n'y a rien à sortir** : depuis 038,
  le déclencheur `profiles_pas_de_telephone_en_demonstration` remet `phone` à
  NULL et `phone_verified` à false sur tout profil `d0000000-…`, avant
  écriture. Le §9 n'est pas modifié — il s'ouvre toujours à `accepted`, et
  `phone_available` reste vrai ; il n'a simplement plus de numéro à révéler.
  Le déclencheur FORCE au lieu de REFUSER, sans quoi `request_booking()`
  lèverait une exception et le parcours du testeur s'arrêterait sur l'écran 5.
  Les deux colonnes partent ensemble parce que
  `profiles_phone_verified_requires_phone` interdit un numéro vérifié sans
  numéro. Il est nommé pour passer APRÈS `profiles_normalise_telephone` dans
  l'ordre alphabétique des déclencheurs : rien ne repose de valeur derrière lui.
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
l'application écrit depuis le J13, quand un propriétaire téléverse ses photos.

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

### Le bucket, et ses trois politiques (021)

`venue-photos` est **public**, borné à **2 Mo par fichier** et aux types
`image/webp` et `image/jpeg`. Public veut dire que `/object/public/...` sert les
fichiers sans consulter aucune politique — c'est ce qui fait qu'une photo
s'affiche chez un visiteur non connecté, et c'est voulu : une photo de salle est
faite pour être vue.

Ce qui est gardé, c'est l'**écriture**, par trois politiques sur
`storage.objects` qui portent toutes le même prédicat — `owns_venue()` sur la
salle que nomme le premier segment du chemin :

| Politique | Ce qu'elle ouvre |
|---|---|
| `venue_photos_storage_insert` | déposer un fichier dans le dossier de SA salle |
| `venue_photos_storage_select` | **retrouver** ses propres fichiers |
| `venue_photos_storage_delete` | les effacer |

La politique de lecture n'est pas décorative sur un bucket public, et l'oublier
casse la suppression : PostgreSQL applique les politiques `select` à un
`DELETE ... WHERE`, et l'API Storage cherche l'objet avant de l'effacer. Sans
elle, une suppression ne trouve rien, n'efface rien, et ne se plaint de rien —
le fichier resterait dans le bucket après que sa ligne a disparu de la galerie.

### Pas de transformations d'image, et donc une seule taille

Le §7.3 annonce « miniatures générées à la volée par les transformations d'image
du Storage ». **On ne s'en sert pas** : elles sont réservées aux offres payantes
de Supabase, et le projet coûte 0 DA.

Conséquence assumée : **un seul fichier par photo**, réduit à 1600 px de large et
réencodé à 80 % côté appareil (`lib/features/owner/compression_photo.dart`), et
les vignettes des cartes affichent ce même fichier. Une photo pèse alors 150 à
400 Ko — dix fois moins qu'un original de téléphone, ce qui est le point du
§7.3. Le jour où le projet passerait à une offre payante, les miniatures
s'ajouteraient sans rien changer en base : elles ne sont qu'un paramètre d'URL.

### Le format est RENIFLÉ, jamais supposé

Sur le web, `canvas.toDataURL('image/webp')` retombe **silencieusement** sur du
PNG quand le navigateur ne sait pas encoder du WebP, et `flutter_image_compress`
jette le préfixe qui l'aurait dit. L'application lit donc les premiers octets du
résultat et nomme le fichier d'après ce qu'il EST — `.webp`, ou `.jpg` pour le
repli du §7.3. La liste `allowed_mime_types` du bucket est le filet sous ce
reniflement : un PNG déguisé serait refusé à l'entrée.

### De 5 à 20 photos

`photos_min()` et `photos_max()` (021) portent les deux bornes, et sont le seul
endroit où ces nombres sont écrits en SQL. Le trigger
`venue_photos_guard_count` refuse la 21e (FE038) ; `envoyer_salle_en_validation()`
refuse une salle qui en a moins de cinq (FE041), parce qu'ADM-01 demande « des
photos réelles » avant toute publication.

### La couverture EST la première photo

`check (is_cover = ("position" = 0))`, plus une unicité de `(venue_id, position)`.
Les deux colonnes ne peuvent donc plus se contredire : `is_cover` n'a pas de
valeur propre, il redit le rang. Il n'existe pas de geste « faire de celle-ci la
couverture » — on réordonne, et la première l'est.

L'unicité du rang est **`DEFERRABLE`**, et c'est nécessaire : réordonner est une
permutation, qui traverse des collisions de rang n'existant plus à la fin de
l'instruction. `supprimer_photo()` et `reordonner_photos()` la diffèrent le temps
de leur `UPDATE`. L'index `venue_photos_one_cover_per_venue` de 001 a été
**supprimé** par 021 : la paire ci-dessus dit strictement plus que lui, et un
index unique non différable aurait refait échouer la permutation.

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

## Le versement de l'acompte (024)

### Un seul arrondi, trois lecteurs

Chargily encaisse des **dinars entiers**. `bookings.deposit_amount` est un
`numeric(12,2)` : 25 % d'un devis de 205 333 DA font 51 333,25 DA. Il faut donc
choisir un entier, et le choisir **une seule fois**.

C'est `montant_acompte(group_id)`, et elle arrondit au dinar **supérieur** :
l'acompte est un minimum convenu, et le rogner de 99 centimes ferait verser au
client moins que ce que le propriétaire a accepté. Le solde affiché — montant
convenu moins acompte — absorbe la différence et reste exact au centime.

Trois lecteurs, une seule fonction :

| Qui | Pourquoi |
|---|---|
| `acompte_a_verser()` | le « Payer X DA » de l'écran 6 |
| `client_bookings()` | le « Verser l'acompte — X DA » de la liste |
| `enregistrer_checkout()` | `payments.amount`, la trace comptable |

Sans cela, le bouton de la liste dirait 51 333 et la caisse en demanderait
51 334 — un dinar d'écart, au pire moment du parcours.

`montant_acompte()` **ne calcule aucun prix** : `deposit_amount` est déjà en
base, posée par `accepter_demande()` (015) depuis `deposit_rate()`. Elle n'en
change que l'unité. Il n'y a toujours qu'une seule formule de prix, et c'est
`estimate_price()`.

### Les refus, et pourquoi il y en a cinq

`acompte_a_verser()` demande à `tient_la_date()` (023) ce qu'elle doit penser du
statut — elle ne le relit pas elle-même.

| Code | HTTP | Ce qu'il refuse |
|---|---|---|
| `FE050` | 401 | aucune session |
| `FE051` | 403 | la réservation d'un autre — **ou une réservation inconnue** |
| `FE052` | 409 | le propriétaire n'a pas encore répondu |
| `FE053` | 409 | l'option est échue, ou la demande n'est plus en course |
| `FE054` | 409 | l'acompte est déjà réglé |
| `FE055` | 400 | moyen de paiement inattendu |

`FE051` ne distingue pas « inconnue » de « pas la vôtre », à dessein : deux
phrases différentes diraient à un curieux quels identifiants existent.

`FE052`, `FE053` et `FE054` refusent la même chose, mais la **suite à faire**
diffère — attendre, refaire une demande, ou ne rien faire du tout. Trois
phrases à l'écran, donc trois codes.

### `payments` reste fermée en écriture au client

Le §9 dit « aucune écriture cliente », et la table n'a **aucune politique
d'INSERT** : ce n'est pas un oubli. `enregistrer_checkout()` est
`SECURITY DEFINER` et n'est donnée **qu'au `service_role`** — celui de la Edge
Function. L'application Flutter ne peut pas l'appeler.

Elle ne prend **pas de montant en paramètre** : elle relit `montant_acompte()`
au moment d'écrire. Elle revérifie aussi l'option — entre la lecture par la Edge
Function et son écriture, il s'est écoulé un aller-retour chez Chargily, et une
option peut s'éteindre pendant ce temps-là.

Elle est **idempotente** sur `checkout_id` (l'index partiel de `004`), comme le
webhook du J16 devra l'être, et elle éteint les pages abandonnées du même
groupe : jamais deux paiements « pending » sur une même réservation.

## Les Edge Functions

| Fonction | Appelée par | Ce qu'elle fait | `verify_jwt` |
|---|---|---|---|
| `create-checkout` | l'application, avec le jeton de l'utilisateur | ouvre la page de paiement Chargily de l'acompte et range sa trace dans `payments` | oui |
| `chargily-webhook` | Chargily | vérifie la signature du corps brut, puis laisse la base trancher | **non** — voir ci-dessous |

Le code est versionné dans `supabase/functions/`. Elle se déploie avec la CLI :

```bash
supabase functions deploy create-checkout
```

### Le secret, et lui seul

**`CHARGILY_SECRET_KEY`** se pose à la main dans le tableau de bord Supabase —
*Edge Functions › Secrets* —, jamais dans le dépôt, jamais dans `env.json`,
jamais dans l'application. `SUPABASE_URL`, `SUPABASE_ANON_KEY` et
`SUPABASE_SERVICE_ROLE_KEY` sont fournies d'office par la plateforme.

**`APP_ORIGIN`** est facultative : posée, elle restreint les adresses de retour
à ce domaine (les origines locales restent acceptées pour le développement).

Sans `CHARGILY_SECRET_KEY`, la fonction répond `FE058` et l'application dit que
le paiement en ligne n'est pas encore ouvert — sans nommer aucune clé.

### Mode test, et rien d'autre

L'URL de base est `https://pay.chargily.net/test/api/v2`, et `payments.is_test`
vaut `true` sur chaque ligne écrite. Le passage en réel changera cette constante
et la clé du secret, pas le reste du fichier.

### Le webhook, et ce qui le protège

`chargily-webhook` tourne avec **`verify_jwt = false`**, et il le faut :
Chargily n'a aucun jeton Supabase et n'en aura jamais. La fonction est donc
ouverte sur Internet, et ce qui la protège est **la signature, et elle seule**.

En-tête `signature`, **HMAC-SHA256 du corps avec la clé secrète d'API**, en
hexadécimal minuscule — c'est la documentation de Chargily, pas un choix. Ce
n'est pas le format de Stripe : ni horodatage, ni préfixe, ni version.

**La signature se vérifie sur le CORPS BRUT, avant tout décodage.** Un
`JSON.parse` puis `JSON.stringify` rendrait un texte différent de celui qui a
été signé. La comparaison se fait en **temps constant** : une comparaison
ordinaire s'arrête au premier caractère qui diffère, et le temps qu'elle met à
répondre dit combien de caractères étaient justes.

La fonction ne décide de rien d'autre. Tout ce qui compte — le montant,
l'option, le créneau, l'idempotence — se joue dans
`confirmer_paiement_chargily()` (025), **en une seule transaction, sur une ligne
`payments` verrouillée** (`for update`). C'est ce verrou qui rend l'idempotence
vraie : deux livraisons simultanées du même événement ne confirment pas deux
fois, la seconde attend et lit un état déjà réglé.

L'adresse du webhook part avec **chaque checkout** (`webhook_endpoint`), plutôt
que d'être réglée à la main dans le tableau de bord Chargily. Le guide
« Webhooks » de Chargily appelle ce champ `webhook_url` ; la **référence API**
l'appelle `webhook_endpoint`, et l'objet Checkout qu'elle rend porte un attribut
de ce nom. C'est la référence qui fait foi.

### Les quatre façons de mal finir

Un paiement encaissé ne confirme pas toujours. Quatre fois sur cinq il confirme ;
la cinquième, `payments.anomalie` dit pourquoi.

| `anomalie` | `suite` | Ce qui s'est passé |
|---|---|---|
| `montant_different` | `a_examiner` | Chargily annonce un montant qui n'est pas le nôtre |
| `option_expiree` | `a_rembourser` | l'argent est arrivé après les 72 h |
| `creneau_pris` | `a_rembourser` | un autre a confirmé le même créneau entre-temps |
| `deja_paye` | `a_rembourser` | la réservation était déjà réglée — en espèces, ou par une autre page |
| `confirmation_impossible` | `a_examiner` | la base a refusé pour une autre raison |

Les trois `a_rembourser` veulent dire la même chose pour le client : **son argent
est parti et sa date n'est pas prise**. Les deux parties ET l'administration sont
prévenues, et la vue `paiements_a_examiner` les rassemble.

**Aucun remboursement automatique.** La base marque, notifie, et s'arrête. Un
remboursement se décide en regardant, depuis le tableau de bord Chargily.

**Le paiement est marqué `paid` même quand la réservation ne l'est pas**, et
c'est délibéré : Chargily affirme que l'argent a bougé, et l'écrire `pending`
parce que la suite nous déplaît serait tenir une comptabilité fausse. C'est
`anomalie` qui porte le « mais ».

**La fonction SQL ne lève jamais sur un cas métier.** Un webhook qui échoue est
un webhook que Chargily renvoie ; redemander indéfiniment un événement dont le
problème est « cette date est déjà vendue » ne réglerait rien. Chaque issue a un
nom, rendu en texte : `confirme`, `echec`, `deja_traite`, `inconnu`, et les cinq
anomalies.

### L'acompte en espèces

Deux fonctions, et la première ne confirme rien.

`payer_en_especes()` — le client annonce qu'il apportera les billets. La
réservation **reste `accepted`**, l'option de 72 h **continue de courir**, une
ligne `payments` `method = 'cash'` en `pending` est créée (sans `checkout_id` :
l'index partiel de `004` le permet expressément), et le propriétaire est
prévenu. Idempotente : rappuyer rend l'intention déjà posée, sans renotifier.

`confirmer_encaissement_especes()` — le propriétaire a compté l'argent. Elle
vérifie `owns_booking()`, passe le paiement en `paid`, puis appelle
`confirm_booking()`. **Le même chemin que Chargily**, et donc le même index du
§6.1 pour dernier mot : il n'y a qu'une porte vers `confirmed`.

Elle n'éteint pas une page Chargily ouverte — on ne peut pas empêcher Chargily
d'encaisser. Si la carte aboutit après coup, le webhook voit la réservation déjà
réglée et marque `deja_paye` : à rembourser.

### Tester sans la page de paiement

La page Chargily n'est pas joignable depuis toutes les connexions algériennes.
Le webhook, lui, se teste entièrement sans elle : il ne demande qu'un corps JSON
et une signature, et la signature se calcule avec la même clé, où qu'on soit.

```powershell
$env:CHARGILY_SECRET_KEY = 'test_sk_...'
.\supabase\tests\webhook_chargily.ps1 -Cas tout
```

Le décor se pose par la **section 1** de `tests/013_webhook_bac_a_sable.sql`, se
lit par la **section 2**, et s'efface par la **section 3**. Le script signe avec
la vraie clé et vise la fonction déployée : seul le formulaire de carte manque.

### Revenir sur `success_url` ne confirme rien

C'est la règle de cette étape. La fonction écrit une ligne `pending`, et **rien
de plus** : la réservation reste `accepted`. Seul le webhook signé — le J16 —
la fera passer en `confirmed`. Tant qu'il n'a pas parlé, l'application dit
« paiement en cours de vérification ».

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

- **LE WEBHOOK CHARGILY N'EXISTE PAS ENCORE, ET DONC RIEN NE PASSE EN
  `confirmed`.** L'étape J15 a posé la caisse : `create-checkout` ouvre la page
  de paiement et écrit une ligne `payments` en `pending`. Personne ne la fait
  avancer. Concrètement, une cliente peut payer et voir sa réservation rester
  « acceptée » jusqu'à l'expiration de son option.

  Le J16 apportera `chargily-webhook` : signature vérifiée à chaque appel,
  endpoint **idempotent** (§9), passage par `confirm_booking()` (004) — jamais
  un `UPDATE` direct sur `bookings` —, et les deux parties prévenues. Il devra
  aussi traiter les paiements **échoués**, que rien ne range aujourd'hui :
  `enregistrer_checkout()` n'éteint une ligne `pending` que lorsqu'une page
  neuve s'ouvre.

- **LE RÈGLEMENT EN ESPÈCES (`payments.method = 'cash'`) N'A PAS DE PARCOURS.**
  La colonne l'accepte depuis `004` et la maquette de l'écran 6 le dessine en
  troisième choix ; `enregistrer_checkout()` le **refuse** explicitement, parce
  qu'un règlement en espèces n'a pas de checkout. Il lui faudra sa propre
  fonction et une confirmation par le propriétaire.

- **LES ALERTES QUI SORTENT DE L'APPLICATION N'EXISTENT PAS.** L'étape J14 a
  posé les notifications *dans* l'application — table, temps réel, cloche, écran
  — et rien au-delà. Le §4.1 (CORE-04) et le §6 en prévoient plus :

  1. **le push téléphone (FCM)**, prévu en V1 « par-dessus le reste sans rien
     changer » : il lira la même table `notifications`, et c'est pour cela que
     le payload s'y suffit à lui-même depuis 022 ;
  2. **les e-mails**, pour ce qui doit survivre à une application désinstallée ;
  3. **les rappels J-7 et J-1** : les deux types `reminder_j7` et `reminder_j1`
     existent dans la contrainte `CHECK` depuis `004`, et **personne ne les
     dépose**. Ce sera une troisième tâche pg_cron, quotidienne, à côté des deux
     de 022 — et elle devra retenir ce qu'elle a déjà envoyé, sans quoi elle
     rappellera le même mariage chaque jour ;
  4. **l'invitation à laisser un avis** : `complete_booking()` dépose déjà
     `review_invitation`, mais l'écran qui la reçoit n'existe pas encore (J17).
     La notification s'affiche et mène au suivi des réservations, faute de
     mieux ;
  5. **le bouton WhatsApp**, qui n'est écrit nulle part encore.

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
- **`notifications` n'est jamais purgée.** Rien n'efface une notification lue de
  2026, et la table grossira d'autant. Elle est petite et indexée sur
  `(user_id, created_at desc) where read_at is null` — le badge ne lit que les
  non lues —, mais une purge des lues de plus de six mois fera une troisième
  tâche pg_cron le jour où cela se verra. Il n'y a rien à décider avant.
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

**Les favoris, eux, devront être supprimés explicitement.** La cascade de
`favorites.user_id` ne part **jamais** lors d'une fermeture de compte, puisqu'on
n'y supprime pas la ligne `profiles` — on la neutralise. Sans une suppression
écrite noir sur blanc dans la fonction d'anonymisation, un compte fermé
garderait une liste de goûts attachée à une personne qu'on peut encore
identifier par ailleurs. Les favoris sont l'une des rares choses de ce schéma
qu'une fermeture de compte doit vraiment **effacer**, et non conserver.

**La conséquence, en clair, aujourd'hui : un compte fermé garderait ses
favoris.** Il n'y a encore aucun compte fermé, puisque la fonction
d'anonymisation n'est pas écrite — mais c'est précisément pour cela que la dette
se note ici et pas ailleurs. Le jour où quelqu'un écrira
`fermer_le_compte(uuid)`, la ligne

```sql
delete from public.favorites where user_id = p_compte;
```

devra s'y trouver, **à l'intérieur de la fonction** et non dans une tâche
voisine qui passerait après. Rien dans le schéma ne la réclamera : les deux
clés de `favorites` sont en `CASCADE`, et une cascade ne se déclenche que sur
une suppression — or on ne supprime pas, on neutralise. C'est le seul endroit de
ce schéma où la base ne rattrapera pas un oubli du code, et c'est pour cela
qu'il est écrit.

## Tests

Quatorze fichiers, qui se collent tels quels dans l'éditeur SQL de Supabase et
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
| `tests/008_photos_de_la_salle.sql` | la couverture EST la première photo, réordonner la déplace, **un autre compte n'écrit ni ligne ni fichier dans mon dossier**, la 21e est refusée et une salle de moins de 5 photos ne part pas en validation |
| `tests/009_delais_et_alertes.sql` | une option échue s'éteint et rend la date, une option vivante et une réservation confirmée ne bougent pas, une journée entière expire d'un bloc, relancer le cron ne notifie pas deux fois, le payload se suffit à lui-même, **un compte ne lit jamais les notifications d'un autre**, et chacun des six changements d'état prévient la bonne personne une seule fois |
| `tests/010_une_option_tient_la_date.sql` | une option en cours ferme la date partout, une option échue la rouvre à la minute sans attendre le cron, et les demandes `pending` ne bloquent toujours rien |
| `tests/011_acompte_chargily.sql` | la caisse ne s'ouvre que pour son client et tant que l'option tient, **le montant est celui de la base arrondi une seule fois**, une seule page de paiement court par réservation, et **aucune écriture cliente n'atteint `payments`** |
| `tests/012_especes_sur_place.sql` | annoncer n'est pas payer, **un autre compte ne confirme pas un encaissement** — ni la cliente, ni une inconnue, ni un propriétaire d'une AUTRE salle —, et une réservation confirmée ne se reconfirme pas |
| `tests/013_webhook_bac_a_sable.sql` | le décor du test de bout en bout, sa lecture et son nettoyage — **il ne fait pas de ROLLBACK**, voir en tête du fichier |
| `tests/014_webhook_confirme.sql` | les huit situations d'un webhook : confirmation, rejeu, montant faux, option échue, créneau pris, carte refusée, checkout inconnu, double paiement — **et aucune ne lève** |
| `tests/015_les_avis.sql` | un avis exige une réservation honorée, la fenêtre de J+1 à J+30, la réponse du propriétaire qui fige l'avis, la moyenne bayésienne, et **aucun nom entier ni téléphone dans ce que lit un inconnu** |
| `tests/016_index_semantique.sql` | le document porte tout ce qu'on peut demander, le hachage ne bouge qu'avec le contenu, **une salle non publiée n'est jamais indexée**, et `venue_embeddings` est close |
| `tests/017_synthese_des_avis.sql` | **pas de synthèse sous trois avis porteurs de texte**, **une salle dont les avis n'ont pas bougé n'est pas retraitée**, aucun nom de client n'atteint le modèle, un brouillon n'est jamais résumé, et la table est close |
| `tests/019_pas_de_telephone_en_demonstration.sql` | un numéro ne se dépose pas sur un compte de démonstration — ni par un `update` direct, ni avec `phone_verified = true`, ni par `request_booking()` — **et il se dépose toujours chez un vrai client** ; `booking_contact()` ouvre le contact sans rien révéler |
| `tests/020_les_favoris.sql` | **la clé primaire composite rend le doublon impossible** — une seconde insertion ne crée pas une seconde ligne —, deux personnes aiment la même salle chacune sa ligne, une salle supprimée emporte ses favoris, **B ne voit AUCUN favori de A**, ne peut ni en retirer un ni en poser un au nom de A, `mes_favoris()` ne rend que les siens, et un inconnu non connecté ne lit ni n'écrit rien |

Le huitième va plus loin encore : pour mesurer les politiques du bucket, il
lève au passage `storage.allow_delete_query`, le verrou de Supabase qui refuse
tout `DELETE` direct sur `storage.objects`. Ce verrou-là protège des fichiers
orphelins, pas des intrus — il refuserait le propriétaire comme l'intrus, et
laisserait le test vert sans avoir rien prouvé. Chacun de ses refus est d'ailleurs
doublé d'un **contrôle positif** : on montre d'abord que le propriétaire PEUT
faire le geste, sans quoi « permission refusée » ne distinguerait pas une
politique qui travaille d'un `GRANT` manquant qui bloque tout le monde.

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
