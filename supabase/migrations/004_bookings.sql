-- =============================================================================
-- Ferha — 004_bookings.sql
-- Réservations, paiements, avis, notifications.
--
-- Contrat : cahier des charges §5 (règles métier), §6 (modèle de données) et
-- son §6.1 — la contrainte qui protège le produit.
--
-- Ce fichier ne contient AUCUNE règle de prix. Le calcul du prix vit dans
-- estimate_price() (005_pricing.sql), et nulle part ailleurs.
--
-- Rejouable : chaque objet est créé sous condition d'absence.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- bookings — la table pivot du produit (§6)
--
-- Une ligne = un créneau atomique occupé. Une réservation « journee » s'écrit
-- donc en DEUX lignes, midi et soir, liées par le même group_id (§6.1). C'est
-- ce découpage qui permet à l'index unique partiel plus bas de porter sur un
-- créneau réel, et à venue_blackouts (001) de se lire de la même façon.
-- -----------------------------------------------------------------------------

create table if not exists public.bookings (
  id               uuid primary key default gen_random_uuid(),

  -- Lie les lignes d'une même réservation. Une demande midi ou soir est un
  -- groupe d'une ligne ; une journée entière, un groupe de deux. Toutes les
  -- fonctions de transition d'état travaillent sur le groupe, jamais sur la
  -- ligne : accepter la moitié d'une journée n'aurait pas de sens.
  group_id         uuid        not null default gen_random_uuid(),

  -- RESTRICT et non CASCADE : une salle qui porte des réservations ne doit pas
  -- disparaître en silence avec le compte de son propriétaire. La suppression
  -- échoue, et c'est le comportement voulu — c'est le point laissé ouvert dans
  -- supabase/README.md à l'étape du catalogue.
  venue_id         uuid        not null references public.venues (id)   on delete restrict,
  client_id        uuid        not null references public.profiles (id) on delete restrict,

  event_date       date        not null,

  -- Créneau réellement occupé. Atomique, toujours : c'est la colonne que lit
  -- l'index unique partiel du §6.1.
  slot             text        not null check (slot in ('midi', 'soir')),

  -- Ce que le client a demandé, et donc la ligne de venue_pricing qui tarife la
  -- réservation. Une journée entière ne se vend pas au prix de midi + soir :
  -- sans cette colonne, le prix serait indérivable après coup.
  requested_slot   text        not null check (requested_slot in ('midi', 'soir', 'journee')),

  guest_count      integer     not null check (guest_count > 0),

  -- Vocabulaire libre : le cahier des charges cite « type d'événement » (§4.2,
  -- CLI-01) sans en fixer la liste. Pas de CHECK inventé ici ; un référentiel
  -- viendra quand la liste sera arrêtée.
  event_type       text,

  -- Message libre de la demande (§4.2, CLI-05).
  client_message   text,

  -- Options choisies, telles qu'elles existent dans venue_options (005). Le
  -- tableau porte les mêmes valeurs sur les deux lignes d'une journée : les
  -- options se paient une fois par réservation, pas une fois par créneau.
  -- L'intégrité référentielle est vérifiée par request_booking() (005), un
  -- tableau ne pouvant pas porter de clé étrangère.
  option_ids       uuid[]      not null default '{}',

  -- Montant du devis, pour le GROUPE entier, en dinars. Écrit par
  -- estimate_price() à la demande, puis éventuellement corrigé par le
  -- propriétaire au moment d'accepter (§5.2 : « une estimation engageante à
  -- ±10 %, pas un contrat »).
  --
  -- ATTENTION : la valeur est répétée à l'identique sur les deux lignes d'une
  -- journée. Ne jamais faire sum(quoted_amount) sur bookings — lire la vue
  -- booking_groups, plus bas, qui compte chaque réservation une fois.
  quoted_amount    numeric(12, 2) not null check (quoted_amount >= 0),

  -- Acompte attendu, pour le groupe entier. NULL tant que le propriétaire n'a
  -- pas répondu : c'est lui qui le fixe en acceptant (§3, étape 4).
  deposit_amount   numeric(12, 2) check (deposit_amount >= 0),

  -- États possibles, en contrainte CHECK :
  --   pending    la demande est posée et ne bloque rien (§5.1)
  --   accepted   le propriétaire a dit oui : option de 72 h (§5.1)
  --   confirmed  l'acompte est réglé — la date est prise (§3, étape 5)
  --   completed  l'événement a eu lieu (§3, étape 6)
  --   refused    le propriétaire a dit non
  --   cancelled  annulation par le client ou le propriétaire (§5.3)
  --   expired    option de 72 h échue sans acompte (§5.1)
  status           text        not null default 'pending'
                     check (status in ('pending', 'accepted', 'confirmed',
                                       'completed', 'refused', 'cancelled', 'expired')),

  -- Échéance de l'option de 72 h. Posée au passage à « accepted », relue par le
  -- cron expire-options (§7.2).
  option_expires_at timestamptz,

  -- Traces des transitions. Renseignées par les fonctions SECURITY DEFINER
  -- plus bas, jamais par le client.
  accepted_at      timestamptz,
  confirmed_at     timestamptz,
  completed_at     timestamptz,
  cancelled_at     timestamptz,
  cancelled_by     uuid references public.profiles (id) on delete set null,
  -- Motif d'un refus ou d'une annulation. Interne aux deux parties.
  status_reason    text,

  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),

  -- Une demande simple occupe le créneau qu'elle demande.
  constraint bookings_slot_matches_request
    check (requested_slot = 'journee' or slot = requested_slot),

  -- L'option de 72 h n'a de sens qu'une fois la demande acceptée.
  constraint bookings_option_expiry_requires_accepted
    check (option_expires_at is null or status in ('accepted', 'confirmed',
                                                   'completed', 'expired', 'cancelled')),

  -- On ne confirme pas une réservation dont l'acompte n'a pas été chiffré.
  constraint bookings_confirmed_requires_deposit
    check (status not in ('confirmed', 'completed') or deposit_amount is not null)
);

comment on table  public.bookings is
  'Réservation — table pivot du produit (§6). Une ligne = un créneau atomique occupé.';
comment on column public.bookings.group_id is
  'Lie les deux lignes d''une journée entière (§6.1). Les transitions d''état portent sur le groupe.';
comment on column public.bookings.slot is
  'Créneau réellement occupé, midi ou soir. Colonne de l''index unique partiel du §6.1.';
comment on column public.bookings.requested_slot is
  'Ce que le client a demandé — midi, soir ou journee. Désigne la ligne de venue_pricing qui tarife.';
comment on column public.bookings.option_ids is
  'Options choisies (venue_options, 005). Mêmes valeurs sur les deux lignes d''une journée.';
comment on column public.bookings.quoted_amount is
  'Devis du GROUPE entier, en dinars, calculé par estimate_price(). Répété sur les deux lignes d''une journée : ne jamais en faire la somme, lire booking_groups.';
comment on column public.bookings.deposit_amount is
  'Acompte attendu pour le groupe entier. NULL tant que le propriétaire n''a pas accepté.';
comment on column public.bookings.status is
  'pending, accepted, confirmed, completed, refused, cancelled, expired (§3, §5.1).';
comment on column public.bookings.option_expires_at is
  'Échéance de l''option de 72 h posée à l''acceptation (§5.1). Relue par le cron expire-options.';

-- -----------------------------------------------------------------------------
-- §6.1 — LA CONTRAINTE QUI PROTÈGE LE PRODUIT
--
-- Empêcher la double réservation ne se fait pas avec un SELECT suivi d'un
-- INSERT : deux clients qui paient à la même seconde passeraient tous les deux.
-- L'index ci-dessous fait refuser le second enregistrement par la base
-- elle-même, quelle que soit la logique applicative, quel que soit le rôle,
-- même en service_role, même depuis psql.
--
-- Ne pas y toucher. Le test supabase/tests/001_double_booking.sql existe pour
-- vérifier qu'il tient.
-- -----------------------------------------------------------------------------

create unique index if not exists uniq_booking_slot
  on public.bookings (venue_id, event_date, slot)
  where status in ('confirmed', 'completed');

comment on index public.uniq_booking_slot is
  'Une date+créneau ne porte qu''une seule réservation confirmée ou honorée (§6.1). '
  'Partiel : pending et accepted ne bloquent pas la date (§5.1).';

-- Une journée entière, c'est midi ET soir — jamais deux fois le même créneau.
create unique index if not exists uniq_booking_group_slot
  on public.bookings (group_id, slot);

create index if not exists bookings_venue_date_idx  on public.bookings (venue_id, event_date);
create index if not exists bookings_client_idx      on public.bookings (client_id, created_at desc);
create index if not exists bookings_group_idx       on public.bookings (group_id);
-- Le cron expire-options (§7.2) ne lit que les options en cours.
create index if not exists bookings_option_expiry_idx
  on public.bookings (option_expires_at) where status = 'accepted';

drop trigger if exists bookings_set_updated_at on public.bookings;
create trigger bookings_set_updated_at
  before update on public.bookings
  for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- booking_groups — une réservation, une ligne
--
-- bookings compte les créneaux ; cette vue compte les réservations. C'est elle
-- que lisent « Mes réservations », l'agenda du propriétaire et tout calcul de
-- revenu : quoted_amount y apparaît une seule fois par groupe, alors qu'il est
-- répété sur les deux lignes d'une journée entière.
--
-- security_invoker = true : contrairement à venue_availability (002), cette vue
-- n'a rien à contourner. Elle doit au contraire hériter des politiques de
-- bookings, pour qu'un lecteur n'y voie que ses propres réservations.
-- -----------------------------------------------------------------------------

-- DISTINCT ON plutôt que GROUP BY : les deux lignes d'un groupe portent les
-- mêmes valeurs partout sauf sur slot — les transitions d'état travaillent
-- toujours sur le groupe entier. On prend donc une ligne, la première par ordre
-- de créneau, et le montant se trouve compté une seule fois sans avoir à
-- l'agréger.
create or replace view public.booking_groups
  with (security_invoker = true) as
  select distinct on (b.group_id)
    b.group_id,
    b.venue_id,
    b.client_id,
    b.event_date,
    b.requested_slot,
    -- Les créneaux réellement occupés : {midi} , {soir} ou {midi,soir}.
    (select array_agg(g.slot order by g.slot)
       from public.bookings g
      where g.group_id = b.group_id)     as slots,
    b.guest_count,
    b.event_type,
    b.status,
    b.quoted_amount,
    b.deposit_amount,
    b.option_expires_at,
    b.created_at
  from public.bookings b
  order by b.group_id, b.slot;

comment on view public.booking_groups is
  'Une ligne par réservation, créneaux agrégés et devis compté une seule fois. '
  'À lire partout où bookings compterait double une journée entière.';

grant select on public.booking_groups to authenticated;

-- -----------------------------------------------------------------------------
-- payments — trace Chargily (§6)
--
-- Aucune écriture cliente (§9). Cette table est remplie par la Edge Function
-- chargily-webhook, en service_role, et par elle seule.
-- -----------------------------------------------------------------------------

create table if not exists public.payments (
  id           uuid primary key default gen_random_uuid(),
  booking_id   uuid        not null references public.bookings (id) on delete restrict,

  -- Identifiant du checkout côté Chargily. NULL pour un règlement en espèces,
  -- qui n'en a pas.
  checkout_id  text,

  amount       numeric(12, 2) not null check (amount >= 0),

  -- cash : la variante « acompte en main propre » du §3, indispensable à
  -- l'adoption. Le propriétaire confirme alors la réservation dans
  -- l'application.
  method       text        not null check (method in ('cib', 'edahabia', 'cash')),

  status       text        not null default 'pending'
                 check (status in ('pending', 'paid', 'failed', 'refunded')),

  -- v2.0 : Chargily tourne en mode test. Mêmes appels, autres clés (§4.2,
  -- CLI-06). La colonne évite qu'un paiement de démonstration soit un jour
  -- compté comme un vrai encaissement.
  is_test      boolean     not null default true,

  -- Corps brut du webhook, conservé tel quel pour le rapprochement comptable
  -- (§4.4, ADM-03).
  raw_webhook  jsonb,

  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

comment on table  public.payments is 'Trace des paiements Chargily (§6). Aucune écriture cliente (§9).';
comment on column public.payments.checkout_id is
  'Identifiant du checkout Chargily. NULL pour un règlement en espèces.';
comment on column public.payments.method is
  'cib, edahabia, ou cash — l''acompte en main propre du §3.';
comment on column public.payments.is_test is
  'v2.0 : Chargily est en mode test. Distingue un paiement de démonstration d''un vrai encaissement.';
comment on column public.payments.raw_webhook is
  'Corps brut du webhook, pour le rapprochement comptable (§4.4, ADM-03).';

-- Idempotence du webhook (§9) : rejouer un appel ne crée pas un second
-- paiement. Partiel, parce qu'un règlement en espèces n'a pas de checkout_id.
create unique index if not exists payments_checkout_id_key
  on public.payments (checkout_id) where checkout_id is not null;

create index if not exists payments_booking_idx on public.payments (booking_id);

drop trigger if exists payments_set_updated_at on public.payments;
create trigger payments_set_updated_at
  before update on public.payments
  for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- reviews — avis vérifié (§6, §5.4)
--
-- booking_id UNIQUE NOT NULL : pas de réservation, pas d'avis ; et pas deux
-- avis sur la même. C'est la règle anti-faux-avis, et elle est structurelle —
-- aucune politique RLS ne peut la remplacer.
-- -----------------------------------------------------------------------------

create table if not exists public.reviews (
  id                  uuid primary key default gen_random_uuid(),

  -- UNIQUE NOT NULL : la règle du §5.4, portée par le schéma lui-même.
  -- RESTRICT : un avis publié ne s'efface pas en supprimant la réservation.
  booking_id          uuid unique not null references public.bookings (id) on delete restrict,

  -- Une journée entière, ce sont DEUX lignes de bookings (§6.1) — donc deux
  -- booking_id, donc deux avis possibles sur un seul mariage si l'on s'arrêtait
  -- à la contrainte du §5.4. Cette colonne, unique elle aussi, ferme la brèche :
  -- un événement, un avis. Elle est renseignée par le trigger, jamais par
  -- l'appelant.
  booking_group_id    uuid unique not null,

  -- Dénormalisé depuis la réservation pour que la fiche salle lise ses avis
  -- sans traverser bookings, qui est privée (§9). Le trigger plus bas garantit
  -- que cette colonne ne peut pas mentir.
  venue_id            uuid        not null references public.venues (id) on delete cascade,

  rating              smallint    not null check (rating between 1 and 5),
  -- Les quatre sous-notes du §4.2, CLI-08. Facultatives : un avis reste
  -- publiable avec la seule note globale.
  rating_cleanliness  smallint    check (rating_cleanliness between 1 and 5),
  rating_service      smallint    check (rating_service    between 1 and 5),
  rating_value        smallint    check (rating_value      between 1 and 5),
  rating_accuracy     smallint    check (rating_accuracy   between 1 and 5),

  body                text,

  -- Droit de réponse du propriétaire, une seule fois (§4.3, OWN-06).
  owner_reply         text,
  owner_replied_at    timestamptz,

  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),

  constraint reviews_reply_timestamp_consistent
    check (num_nulls(owner_reply, owner_replied_at) <> 1)
);

comment on table  public.reviews is 'Avis vérifié (§6). Un avis exige une réservation honorée (§5.4).';
comment on column public.reviews.booking_id is
  'UNIQUE NOT NULL : pas de réservation, pas d''avis, et jamais deux avis sur la même (§5.4).';
comment on column public.reviews.booking_group_id is
  'UNIQUE : un événement, un avis. Ferme la brèche des journées entières, qui portent deux booking_id (§6.1).';
comment on column public.reviews.venue_id is
  'Dénormalisé depuis la réservation : la fiche salle lit ses avis sans traverser bookings, qui est privée.';
comment on column public.reviews.owner_reply is
  'Droit de réponse du propriétaire, une seule fois (§4.3, OWN-06). Fige l''avis (§5.4).';

create index if not exists reviews_venue_idx on public.reviews (venue_id, created_at desc);

drop trigger if exists reviews_set_updated_at on public.reviews;
create trigger reviews_set_updated_at
  before update on public.reviews
  for each row execute function public.set_updated_at();

-- venue_id doit désigner la salle de la réservation, et pas une autre : sans ce
-- garde-fou, un client pourrait déposer sur une salle concurrente l'avis d'une
-- réservation honorée ailleurs. Un WITH CHECK ne suffirait pas — il vérifierait
-- la ligne, pas la cohérence entre deux tables au fil des mises à jour.
create or replace function public.reviews_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_venue_id uuid;
  v_group_id uuid;
begin
  select b.venue_id, b.group_id into v_venue_id, v_group_id
  from public.bookings b
  where b.id = new.booking_id;

  if new.venue_id is distinct from v_venue_id then
    raise exception 'L''avis doit porter sur la salle de sa réservation.'
      using errcode = 'check_violation';
  end if;

  -- Renseignée ici et pas par l'appelant : c'est elle qui garantit un seul avis
  -- par événement, y compris pour une journée entière écrite en deux lignes.
  new.booking_group_id := v_group_id;

  -- §5.4 : un avis n'est plus modifiable après la réponse du propriétaire,
  -- sinon la réponse devient incompréhensible. Seule la réponse elle-même
  -- reste modifiable par son auteur.
  if tg_op = 'UPDATE'
     and old.owner_reply is not null
     and (new.rating, new.rating_cleanliness, new.rating_service,
          new.rating_value, new.rating_accuracy, new.body)
         is distinct from
         (old.rating, old.rating_cleanliness, old.rating_service,
          old.rating_value, old.rating_accuracy, old.body) then
    raise exception 'Un avis n''est plus modifiable après la réponse du propriétaire (§5.4).'
      using errcode = 'check_violation';
  end if;

  -- La réponse du propriétaire s'horodate toute seule.
  if new.owner_reply is not null
     and (tg_op = 'INSERT' or old.owner_reply is null or old.owner_reply <> new.owner_reply) then
    new.owner_replied_at = now();
  end if;

  return new;
end;
$$;

comment on function public.reviews_guard() is
  'Aligne reviews.venue_id sur sa réservation et fige l''avis après la réponse du propriétaire (§5.4).';

drop trigger if exists reviews_guard on public.reviews;
create trigger reviews_guard
  before insert or update on public.reviews
  for each row execute function public.reviews_guard();

-- -----------------------------------------------------------------------------
-- venue_ratings — la note affichée (§5.4)
--
-- Moyenne bayésienne, pas moyenne simple : une salle avec un seul 5/5 ne doit
-- pas dépasser une salle avec quarante 4,6/5.
--
--   note_affichee = (m × C + Σ notes) / (m + n)
--   n = nombre d'avis, m = 5 (poids de l'a priori), C = 4.0 (moyenne plateforme)
--
-- Écrit ici et nulle part ailleurs, pour la même raison que le prix : une
-- formule recopiée en Dart finit par diverger.
-- -----------------------------------------------------------------------------

create or replace view public.venue_ratings
  with (security_invoker = true) as
  select
    r.venue_id,
    count(*)                                                   as review_count,
    round(avg(r.rating)::numeric, 2)                           as raw_rating,
    round(((5 * 4.0) + sum(r.rating)) / (5 + count(*)), 2)     as bayesian_rating,
    round(avg(r.rating_cleanliness)::numeric, 2)               as rating_cleanliness,
    round(avg(r.rating_service)::numeric, 2)                   as rating_service,
    round(avg(r.rating_value)::numeric, 2)                     as rating_value,
    round(avg(r.rating_accuracy)::numeric, 2)                  as rating_accuracy
  from public.reviews r
  group by r.venue_id;

comment on view public.venue_ratings is
  'Note affichée d''une salle : moyenne bayésienne du §5.4 (m = 5, C = 4.0). Seule source de cette note.';

grant select on public.venue_ratings to anon, authenticated;

-- -----------------------------------------------------------------------------
-- notifications — v2.0, remplace le push au MVP (§6, §4.1 CORE-04)
-- -----------------------------------------------------------------------------

create table if not exists public.notifications (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid        not null references public.profiles (id) on delete cascade,

  -- Les événements du §4.1, CORE-04.
  type       text        not null
               check (type in ('booking_requested',   -- nouvelle demande, côté propriétaire
                               'booking_answered',    -- réponse du propriétaire, côté client
                               'booking_confirmed',   -- acompte reçu, les deux parties
                               'booking_cancelled',
                               'reminder_j7',
                               'reminder_j1',
                               'review_invitation')),

  -- Charge utile libre : identifiants et libellés de l'écran d'arrivée. jsonb
  -- et non des colonnes, parce que la forme dépend du type.
  payload    jsonb       not null default '{}'::jsonb,

  read_at    timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table  public.notifications is
  'Notifications dans l''application (§6, v2.0). Realtime au MVP ; le push FCM s''ajoute par-dessus en V1.';
comment on column public.notifications.payload is
  'Charge utile libre : la forme dépend du type, d''où le jsonb.';

-- Le badge « non lues » ne lit que les non lues.
create index if not exists notifications_unread_idx
  on public.notifications (user_id, created_at desc) where read_at is null;

drop trigger if exists notifications_set_updated_at on public.notifications;
create trigger notifications_set_updated_at
  before update on public.notifications
  for each row execute function public.set_updated_at();

-- =============================================================================
-- Transitions d'état
--
-- §9 : « Transitions d'état par fonction SECURITY DEFINER ». Le client n'a
-- aucune politique UPDATE sur bookings, le propriétaire non plus — ces
-- fonctions sont le seul chemin. Chacune :
--   * vérifie qui appelle,
--   * vérifie l'état de départ,
--   * travaille sur le GROUPE, jamais sur une ligne isolée,
--   * et notifie la partie concernée.
-- =============================================================================

-- Vrai si l'utilisateur courant est le propriétaire de la salle réservée.
create or replace function public.owns_booking(p_booking_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.bookings b
    join public.venues   v on v.id = b.venue_id
    where b.id = p_booking_id
      and v.owner_id = auth.uid()
  );
$$;

comment on function public.owns_booking(uuid) is
  'Vrai si la réservation porte sur une salle de l''utilisateur courant.';

-- Vrai si l'utilisateur courant est le client de la réservation.
create or replace function public.books_booking(p_booking_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.bookings b
    where b.id = p_booking_id and b.client_id = auth.uid()
  );
$$;

comment on function public.books_booking(uuid) is
  'Vrai si l''utilisateur courant est le client de la réservation.';

-- Dépose une notification. Interne aux fonctions de transition.
create or replace function public.notify_user(
  p_user_id uuid,
  p_type    text,
  p_payload jsonb default '{}'::jsonb
)
returns void
language sql
security definer
set search_path = public
as $$
  insert into public.notifications (user_id, type, payload)
  values (p_user_id, p_type, p_payload);
$$;

comment on function public.notify_user(uuid, text, jsonb) is
  'Dépose une notification (§4.1, CORE-04). Appelée par les fonctions de transition.';

revoke execute on function public.notify_user(uuid, text, jsonb) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- accept_booking — pending → accepted, et pose l'option de 72 h (§5.1)
--
-- Le propriétaire garde le droit de proposer un montant différent (§5.2) : c'est
-- le seul endroit du projet où un prix peut s'écarter d'estimate_price(), et
-- c'est une décision humaine, pas une règle de calcul.
-- -----------------------------------------------------------------------------
create or replace function public.accept_booking(
  p_booking_id     uuid,
  p_deposit_amount numeric,
  p_quoted_amount  numeric default null
)
returns setof public.bookings
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group   uuid;
  v_client  uuid;
  v_quoted  numeric;
begin
  if not public.owns_booking(p_booking_id) then
    raise exception 'Seul le propriétaire de la salle peut accepter cette demande.'
      using errcode = 'insufficient_privilege';
  end if;

  select b.group_id, b.client_id, coalesce(p_quoted_amount, b.quoted_amount)
    into v_group, v_client, v_quoted
  from public.bookings b
  where b.id = p_booking_id and b.status = 'pending';

  if v_group is null then
    raise exception 'Seule une demande en attente peut être acceptée.'
      using errcode = 'check_violation';
  end if;

  if p_deposit_amount is null or p_deposit_amount < 0 or p_deposit_amount > v_quoted then
    raise exception 'L''acompte doit être compris entre 0 et le montant du devis.'
      using errcode = 'check_violation';
  end if;

  perform public.notify_user(
    v_client, 'booking_answered',
    jsonb_build_object('booking_id', p_booking_id, 'group_id', v_group, 'status', 'accepted')
  );

  -- CTE : plpgsql ne sait pas renvoyer directement un UPDATE ... RETURNING.
  return query
  with touched as (
    update public.bookings b
       set status            = 'accepted',
           quoted_amount     = v_quoted,
           deposit_amount    = p_deposit_amount,
           -- L'option de 72 h du §5.1.
           option_expires_at = now() + interval '72 hours',
           accepted_at       = now()
     where b.group_id = v_group and b.status = 'pending'
    returning b.*
  )
  select t.* from touched t;
end;
$$;

comment on function public.accept_booking(uuid, numeric, numeric) is
  'Propriétaire : pending → accepted, pose l''option de 72 h (§5.1) et fixe l''acompte. '
  'p_quoted_amount permet la contre-proposition du §5.2.';

-- -----------------------------------------------------------------------------
-- refuse_booking — pending → refused
-- -----------------------------------------------------------------------------
create or replace function public.refuse_booking(
  p_booking_id uuid,
  p_reason     text default null
)
returns setof public.bookings
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group  uuid;
  v_client uuid;
begin
  if not public.owns_booking(p_booking_id) then
    raise exception 'Seul le propriétaire de la salle peut refuser cette demande.'
      using errcode = 'insufficient_privilege';
  end if;

  select b.group_id, b.client_id into v_group, v_client
  from public.bookings b
  where b.id = p_booking_id and b.status = 'pending';

  if v_group is null then
    raise exception 'Seule une demande en attente peut être refusée.'
      using errcode = 'check_violation';
  end if;

  perform public.notify_user(
    v_client, 'booking_answered',
    jsonb_build_object('booking_id', p_booking_id, 'group_id', v_group, 'status', 'refused')
  );

  return query
  with touched as (
    update public.bookings b
       set status = 'refused', status_reason = p_reason
     where b.group_id = v_group and b.status = 'pending'
    returning b.*
  )
  select t.* from touched t;
end;
$$;

comment on function public.refuse_booking(uuid, text) is
  'Propriétaire : pending → refused, avec motif (§4.3, OWN-05).';

-- -----------------------------------------------------------------------------
-- confirm_booking — accepted → confirmed. C'EST ICI QUE LA DATE SE PREND.
--
-- Deux appelants légitimes :
--   * la Edge Function chargily-webhook, en service_role, quand l'acompte est
--     encaissé (§3, étape 5) ;
--   * le propriétaire lui-même, pour la variante « acompte en main propre » du
--     §3 — sans elle, le produit retombe en simple annuaire.
--
-- L'index uniq_booking_slot (§6.1) se déclenche exactement ici. Deux
-- confirmations simultanées sur le même créneau : la base en refuse une, et le
-- message renvoyé est fait pour être montré tel quel au client.
-- -----------------------------------------------------------------------------
create or replace function public.confirm_booking(p_booking_id uuid)
returns setof public.bookings
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group  uuid;
  v_client uuid;
  v_owner  uuid;
begin
  -- auth.uid() vaut NULL en service_role : c'est le webhook Chargily.
  if auth.uid() is not null and not public.owns_booking(p_booking_id) then
    raise exception 'Seul le propriétaire de la salle peut confirmer un règlement en espèces.'
      using errcode = 'insufficient_privilege';
  end if;

  select b.group_id, b.client_id, v.owner_id into v_group, v_client, v_owner
  from public.bookings b
  join public.venues   v on v.id = b.venue_id
  where b.id = p_booking_id and b.status = 'accepted';

  if v_group is null then
    raise exception 'Seule une demande acceptée peut être confirmée.'
      using errcode = 'check_violation';
  end if;

  perform public.notify_user(
    v_client, 'booking_confirmed',
    jsonb_build_object('booking_id', p_booking_id, 'group_id', v_group)
  );
  perform public.notify_user(
    v_owner, 'booking_confirmed',
    jsonb_build_object('booking_id', p_booking_id, 'group_id', v_group)
  );

  begin
    return query
    with touched as (
      update public.bookings b
         set status = 'confirmed', confirmed_at = now()
       where b.group_id = v_group and b.status = 'accepted'
      returning b.*
    )
    select t.* from touched t;
  exception when unique_violation then
    -- L'index du §6.1 a parlé. Personne ne passe après lui.
    raise exception 'Ce créneau vient d''être réservé par quelqu''un d''autre.'
      using errcode = 'unique_violation',
            hint    = 'Proposez une autre date ou un autre créneau au client.';
  end;
end;
$$;

comment on function public.confirm_booking(uuid) is
  'accepted → confirmed. Webhook Chargily en service_role, ou propriétaire pour un acompte en espèces (§3). '
  'C''est ici que l''index uniq_booking_slot du §6.1 se déclenche.';

-- -----------------------------------------------------------------------------
-- complete_booking — confirmed → completed (§3, étape 6)
--
-- Débloque l'avis (§5.4). Pas avant l'événement : on ne marque pas honoré ce
-- qui n'a pas eu lieu.
-- -----------------------------------------------------------------------------
create or replace function public.complete_booking(p_booking_id uuid)
returns setof public.bookings
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group  uuid;
  v_client uuid;
  v_date   date;
begin
  if not public.owns_booking(p_booking_id) then
    raise exception 'Seul le propriétaire de la salle peut marquer la réservation comme honorée.'
      using errcode = 'insufficient_privilege';
  end if;

  select b.group_id, b.client_id, b.event_date into v_group, v_client, v_date
  from public.bookings b
  where b.id = p_booking_id and b.status = 'confirmed';

  if v_group is null then
    raise exception 'Seule une réservation confirmée peut être marquée comme honorée.'
      using errcode = 'check_violation';
  end if;

  if v_date > current_date then
    raise exception 'L''événement n''a pas encore eu lieu.'
      using errcode = 'check_violation';
  end if;

  -- L'avis se débloque à J+1 (§5.4) ; l'invitation part dès maintenant.
  perform public.notify_user(
    v_client, 'review_invitation',
    jsonb_build_object('booking_id', p_booking_id, 'group_id', v_group)
  );

  return query
  with touched as (
    update public.bookings b
       set status = 'completed', completed_at = now()
     where b.group_id = v_group and b.status = 'confirmed'
    returning b.*
  )
  select t.* from touched t;
end;
$$;

comment on function public.complete_booking(uuid) is
  'Propriétaire : confirmed → completed, jamais avant la date de l''événement (§3). Débloque l''avis (§5.4).';

-- -----------------------------------------------------------------------------
-- cancel_booking — annulation par l'une ou l'autre partie (§5.3)
--
-- Le barème de remboursement du §5.3 n'est PAS appliqué ici : il relève du
-- remboursement Chargily, qui n'est pas encore écrit. Cette fonction libère la
-- date et trace qui a annulé — rien de plus.
-- -----------------------------------------------------------------------------
create or replace function public.cancel_booking(
  p_booking_id uuid,
  p_reason     text default null
)
returns setof public.bookings
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group    uuid;
  v_client   uuid;
  v_owner    uuid;
  v_is_owner boolean;
begin
  v_is_owner := public.owns_booking(p_booking_id);

  if not v_is_owner and not public.books_booking(p_booking_id) then
    raise exception 'Seules les deux parties de la réservation peuvent l''annuler.'
      using errcode = 'insufficient_privilege';
  end if;

  select b.group_id, b.client_id, v.owner_id into v_group, v_client, v_owner
  from public.bookings b
  join public.venues   v on v.id = b.venue_id
  where b.id = p_booking_id
    and b.status in ('pending', 'accepted', 'confirmed');

  if v_group is null then
    raise exception 'Cette réservation n''est plus annulable.'
      using errcode = 'check_violation';
  end if;

  -- On prévient l'autre partie, pas celle qui vient de cliquer.
  perform public.notify_user(
    case when v_is_owner then v_client else v_owner end,
    'booking_cancelled',
    jsonb_build_object('booking_id', p_booking_id, 'group_id', v_group)
  );

  return query
  with touched as (
    update public.bookings b
       set status        = 'cancelled',
           cancelled_at  = now(),
           cancelled_by  = auth.uid(),
           status_reason = p_reason
     where b.group_id = v_group
       and b.status in ('pending', 'accepted', 'confirmed')
    returning b.*
  )
  select t.* from touched t;
end;
$$;

comment on function public.cancel_booking(uuid, text) is
  'Annulation par le client ou le propriétaire (§5.3). Le barème de remboursement relève du remboursement Chargily, pas d''ici.';

-- -----------------------------------------------------------------------------
-- expire_options — le cron horaire du §7.2
--
-- Une demande acceptée non payée à l'échéance des 72 h libère la date (§5.1).
-- Réservée au rôle de service : c'est une opération de maintenance, pas un
-- geste d'utilisateur.
-- -----------------------------------------------------------------------------
create or replace function public.expire_options()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer := 0;
  v_row   record;
begin
  -- L'UPDATE est enveloppé dans une CTE : plpgsql ne sait pas boucler
  -- directement sur un UPDATE ... RETURNING.
  for v_row in
    with expired as (
      update public.bookings b
         set status = 'expired', status_reason = 'Option de 72 h échue sans acompte.'
       where b.status = 'accepted'
         and b.option_expires_at is not null
         and b.option_expires_at < now()
      returning b.id, b.group_id, b.client_id
    )
    select e.id, e.group_id, e.client_id from expired e
  loop
    v_count := v_count + 1;
    perform public.notify_user(
      v_row.client_id, 'booking_cancelled',
      jsonb_build_object('booking_id', v_row.id, 'group_id', v_row.group_id,
                         'reason', 'option_expired')
    );
  end loop;

  return v_count;
end;
$$;

comment on function public.expire_options() is
  'Cron horaire (§7.2) : libère les demandes acceptées non payées après 72 h (§5.1). Rôle de service uniquement.';

-- Le rôle de service ignore ces révocations ; les clients, non.
revoke execute on function public.expire_options() from public, anon, authenticated;

revoke execute on function public.accept_booking(uuid, numeric, numeric)  from public, anon;
revoke execute on function public.refuse_booking(uuid, text)              from public, anon;
revoke execute on function public.confirm_booking(uuid)                   from public, anon;
revoke execute on function public.complete_booking(uuid)                  from public, anon;
revoke execute on function public.cancel_booking(uuid, text)              from public, anon;

grant execute on function public.accept_booking(uuid, numeric, numeric)   to authenticated;
grant execute on function public.refuse_booking(uuid, text)               to authenticated;
grant execute on function public.confirm_booking(uuid)                    to authenticated;
grant execute on function public.complete_booking(uuid)                   to authenticated;
grant execute on function public.cancel_booking(uuid, text)               to authenticated;
