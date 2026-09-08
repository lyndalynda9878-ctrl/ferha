-- =============================================================================
-- Ferha — 005_pricing.sql
-- Le prix. Toute la formule du §5.2, et rien qu'elle.
--
--   prix = prix_base(creneau)
--        × coef_jour     -- jeu / ven / sam : 1.0 → 1.4
--        × coef_saison   -- juin–sept et vacances scolaires : 1.0 → 1.3
--        + max(0, invites − couverts_inclus) × prix_couvert_sup
--        + Σ options_choisies
--
-- RÈGLE DU PROJET : estimate_price() est la SEULE source du prix. Pas une ligne
-- de calcul en Dart, pas une seconde formule ailleurs en SQL. Un trigger, plus
-- bas, garantit qu'aucune réservation ne peut naître avec un montant qui ne
-- vienne pas d'ici — même si quelqu'un insère directement dans la table.
--
-- Ce fichier porte aussi ses propres tables et ses propres politiques RLS
-- (high_season_periods, venue_options) : le prix se lit d'un seul endroit, y
-- compris quand on cherche qui a le droit de le lire.
--
-- Rejouable : chaque objet est créé sous condition d'absence.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- high_season_periods — les vacances scolaires du §5.2
--
-- Le cahier des charges donne deux sources de haute saison : « juin–sept » et
-- « vacances scolaires ». La première est une règle de calendrier, écrite dans
-- estimate_price(). La seconde est une donnée : elle change chaque année et ne
-- se devine pas. Elle vit donc ici, et la table arrive VIDE — à charge de
-- l'administration d'y déposer les périodes officielles.
--
-- Table vide = seuls juin–septembre majorent. C'est un défaut sûr : on ne
-- surfacture jamais par accident.
-- -----------------------------------------------------------------------------

create table if not exists public.high_season_periods (
  id         uuid primary key default gen_random_uuid(),
  starts_on  date        not null,
  ends_on    date        not null,
  -- « Vacances de printemps 2027 », « Aïd el-Fitr 2027 »…
  label      text        not null check (length(btrim(label)) > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint high_season_periods_ordered check (ends_on >= starts_on)
);

comment on table public.high_season_periods is
  'Périodes de haute saison hors juin–septembre : vacances scolaires (§5.2). '
  'Vide par défaut — la règle des mois suffit alors, et rien n''est surfacturé par accident.';
comment on column public.high_season_periods.ends_on is 'Borne incluse.';

create index if not exists high_season_periods_range_idx
  on public.high_season_periods (starts_on, ends_on);

drop trigger if exists high_season_periods_set_updated_at on public.high_season_periods;
create trigger high_season_periods_set_updated_at
  before update on public.high_season_periods
  for each row execute function public.set_updated_at();

-- Calendrier public : tout le monde le lit, le seul rôle de service l'écrit.
-- L'absence de politique d'écriture ferme la table, comme pour amenities (002).
alter table public.high_season_periods enable row level security;

drop policy if exists high_season_periods_select_all on public.high_season_periods;
create policy high_season_periods_select_all
  on public.high_season_periods for select
  to anon, authenticated
  using (true);

-- -----------------------------------------------------------------------------
-- venue_options — le « Σ options_choisies » du §5.2
--
-- Le §6 ne liste pas de table d'options, mais le §5.2 en additionne le prix et
-- le §4.2 (CLI-05) en fait choisir au client. Sans cette table, le dernier
-- terme de la formule n'aurait aucune source — et un prix d'option finirait
-- écrit en dur dans l'application. C'est un ajout au modèle du §6, à confirmer.
-- -----------------------------------------------------------------------------

create table if not exists public.venue_options (
  id         uuid primary key default gen_random_uuid(),
  venue_id   uuid        not null references public.venues (id) on delete cascade,
  -- Code stable propre à la salle : c'est lui qu'affiche l'application, jamais
  -- le libellé, qui dépend de la langue.
  code       text        not null check (code ~ '^[a-z][a-z0-9_]*$'),
  label_fr   text        not null check (length(btrim(label_fr)) > 0),
  label_ar   text        not null check (length(btrim(label_ar)) > 0),
  -- Prix forfaitaire de l'option, en dinars, pour la réservation entière.
  price      numeric(12, 2) not null check (price >= 0),
  -- Une option retirée du catalogue reste lisible : les réservations passées la
  -- citent encore.
  is_active  boolean     not null default true,
  position   integer     not null default 0 check ("position" >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (venue_id, code)
);

comment on table public.venue_options is
  'Options payantes d''une salle — le « Σ options_choisies » du §5.2. '
  'Ajout au modèle du §6, qui ne listait pas cette table.';
comment on column public.venue_options.price is
  'Forfait en dinars pour la réservation entière, et non par créneau ni par couvert.';
comment on column public.venue_options.is_active is
  'Une option désactivée n''est plus proposée, mais reste lisible : les réservations passées la citent.';

create index if not exists venue_options_venue_idx
  on public.venue_options (venue_id, position);

drop trigger if exists venue_options_set_updated_at on public.venue_options;
create trigger venue_options_set_updated_at
  before update on public.venue_options
  for each row execute function public.set_updated_at();

-- Même règle que venue_pricing (002) : lisible quand la salle est lisible,
-- modifiable par son seul propriétaire.
alter table public.venue_options enable row level security;

drop policy if exists venue_options_select on public.venue_options;
create policy venue_options_select
  on public.venue_options for select
  to anon, authenticated
  using (public.can_read_venue(venue_id));

drop policy if exists venue_options_write on public.venue_options;
create policy venue_options_write
  on public.venue_options for all
  to authenticated
  using (public.owns_venue(venue_id))
  with check (public.owns_venue(venue_id));

-- =============================================================================
-- estimate_price — la formule du §5.2, et la seule
-- =============================================================================

-- -----------------------------------------------------------------------------
-- is_high_season — le coef_saison s'applique-t-il à cette date ?
--
-- Deux sources, comme le dit le §5.2 : les mois de juin à septembre (règle de
-- calendrier), et les vacances scolaires (donnée, dans high_season_periods).
-- -----------------------------------------------------------------------------
create or replace function public.is_high_season(p_date date)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select extract(month from p_date) between 6 and 9
      or exists (
        select 1 from public.high_season_periods h
        where p_date between h.starts_on and h.ends_on
      );
$$;

comment on function public.is_high_season(date) is
  'Vrai de juin à septembre, ou pendant une période de high_season_periods (§5.2).';

-- -----------------------------------------------------------------------------
-- is_peak_day — le coef_jour s'applique-t-il à ce jour ?
--
-- Jeudi, vendredi, samedi (§5.2). isodow : 1 = lundi … 7 = dimanche.
-- -----------------------------------------------------------------------------
create or replace function public.is_peak_day(p_date date)
returns boolean
language sql
immutable
as $$
  select extract(isodow from p_date) in (4, 5, 6);
$$;

comment on function public.is_peak_day(date) is
  'Vrai les jeudi, vendredi et samedi — les jours majorés du §5.2.';

-- -----------------------------------------------------------------------------
-- estimate_price — le prix, décomposé
--
-- Renvoie le détail et pas seulement un total : la fiche salle doit pouvoir
-- montrer d'où vient le montant, et le §5.2 en fait « une estimation engageante
-- à ±10 % ». Un client qui voit la décomposition ne se sent pas grugé.
--
-- p_slot vaut midi, soir ou journee. Une journée entière est tarifée par SA
-- ligne de venue_pricing — jamais comme midi + soir : le §6 lui donne une ligne
-- à elle, et une salle ne la vend presque jamais à la somme des deux.
--
-- Droits de l'appelant (pas SECURITY DEFINER) : la fonction ne lit que ce que
-- l'appelant a déjà le droit de lire — la grille tarifaire d'une salle publiée,
-- ou de son propre brouillon. Rien à contourner ici.
-- -----------------------------------------------------------------------------
create or replace function public.estimate_price(
  p_venue_id    uuid,
  p_event_date  date,
  p_slot        text,
  p_guest_count integer,
  p_option_ids  uuid[] default '{}'::uuid[]
)
returns table (
  base_price          numeric,
  day_coef            numeric,
  season_coef         numeric,
  slot_price          numeric,
  included_seats      integer,
  extra_seats         integer,
  extra_seats_amount  numeric,
  options_amount      numeric,
  total               numeric
)
language plpgsql
stable
set search_path = public
as $$
declare
  v_pricing public.venue_pricing%rowtype;
begin
  if p_slot is null or p_slot not in ('midi', 'soir', 'journee') then
    raise exception 'Créneau inconnu : %. Attendu midi, soir ou journee.', p_slot
      using errcode = 'invalid_parameter_value';
  end if;

  if p_guest_count is null or p_guest_count <= 0 then
    raise exception 'Le nombre d''invités doit être supérieur à zéro.'
      using errcode = 'invalid_parameter_value';
  end if;

  select * into v_pricing
  from public.venue_pricing vp
  where vp.venue_id = p_venue_id and vp.slot = p_slot;

  -- Pas de repli inventé : si le propriétaire n'a pas tarifé ce créneau, la
  -- salle ne se vend pas sur ce créneau, et on le dit. Additionner midi et soir
  -- pour fabriquer un prix de journée serait une règle que personne n'a écrite.
  if v_pricing.venue_id is null then
    raise exception 'Aucune grille tarifaire pour le créneau « % » de cette salle.', p_slot
      using errcode    = 'no_data_found',
            hint       = 'Le propriétaire doit renseigner venue_pricing pour ce créneau.';
  end if;

  base_price     := v_pricing.base_price;
  day_coef       := case when public.is_peak_day(p_event_date)    then v_pricing.weekend_coef     else 1 end;
  season_coef    := case when public.is_high_season(p_event_date) then v_pricing.high_season_coef else 1 end;

  -- prix_base × coef_jour × coef_saison
  slot_price     := round(base_price * day_coef * season_coef, 2);

  -- + max(0, invites − couverts_inclus) × prix_couvert_sup
  included_seats     := v_pricing.included_seats;
  extra_seats        := greatest(0, p_guest_count - v_pricing.included_seats);
  extra_seats_amount := round(extra_seats * v_pricing.extra_seat_price, 2);

  -- + Σ options_choisies. Seules comptent les options de CETTE salle : un
  -- identifiant emprunté à une autre salle ne rapporte rien à personne.
  select coalesce(round(sum(vo.price), 2), 0)
    into options_amount
  from public.venue_options vo
  where vo.venue_id = p_venue_id
    and vo.id = any (coalesce(p_option_ids, '{}'::uuid[]));

  total := slot_price + extra_seats_amount + options_amount;

  return next;
end;
$$;

comment on function public.estimate_price(uuid, date, text, integer, uuid[]) is
  'LA formule de prix du §5.2, et la seule du projet. Renvoie le détail, pas seulement le total. '
  'Une journée entière est tarifée par sa propre ligne de venue_pricing, jamais comme midi + soir.';

-- Le prix d'une salle publiée s'affiche avant même de se connecter.
grant execute on function public.estimate_price(uuid, date, text, integer, uuid[])
  to anon, authenticated;

-- =============================================================================
-- Ce qui empêche un prix de venir d'ailleurs
-- =============================================================================

-- -----------------------------------------------------------------------------
-- bookings_set_price — recalcule quoted_amount à chaque insertion
--
-- Sans ce trigger, la politique d'INSERT de 006 laisserait un client poser
-- lui-même quoted_amount = 1 DZD : un WITH CHECK ne sait pas calculer un prix.
-- Ici, la valeur reçue est simplement JETÉE et remplacée par celle
-- d'estimate_price(). Le chemin d'écriture n'a plus d'importance — Flutter,
-- psql ou une Edge Function, le montant vient du même endroit.
--
-- SECURITY DEFINER : le trigger doit pouvoir lire venue_pricing et
-- venue_options quel que soit l'appelant. Il ne fait rien d'autre.
--
-- Le devis du propriétaire (§5.2) n'est pas concerné : il passe par
-- accept_booking(), qui est un UPDATE.
-- -----------------------------------------------------------------------------
create or replace function public.bookings_set_price()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total   numeric;
  v_unknown integer;
begin
  -- Un identifiant d'option qui n'appartient pas à la salle est une erreur, pas
  -- une option à zéro dinar : on refuse plutôt que de facturer autre chose que
  -- ce que le client croit avoir choisi.
  select count(*) into v_unknown
  from unnest(new.option_ids) as requested(id)
  where not exists (
    select 1 from public.venue_options vo
    where vo.id = requested.id and vo.venue_id = new.venue_id
  );

  if v_unknown > 0 then
    raise exception 'Option inconnue pour cette salle.'
      using errcode = 'foreign_key_violation';
  end if;

  select e.total into v_total
  from public.estimate_price(new.venue_id, new.event_date, new.requested_slot,
                             new.guest_count, new.option_ids) e;

  -- Sur une journée entière, les deux lignes portent le prix du GROUPE, pas la
  -- moitié chacune : la vue booking_groups le compte une seule fois.
  new.quoted_amount := v_total;
  return new;
end;
$$;

comment on function public.bookings_set_price() is
  'Écrase quoted_amount par estimate_price() à chaque insertion : aucun prix ne peut entrer par un autre chemin (§5.2).';

drop trigger if exists bookings_set_price on public.bookings;
create trigger bookings_set_price
  before insert on public.bookings
  for each row execute function public.bookings_set_price();

-- -----------------------------------------------------------------------------
-- bookings_check_journee — une journée entière, c'est deux lignes (§6.1)
--
-- Trigger d'instruction, et non de ligne : la règle porte sur le groupe, qui
-- n'existe qu'une fois les deux lignes insérées. Une insertion directe d'une
-- seule ligne « journee » est refusée — sinon le client croirait avoir la
-- journée en n'ayant réservé que le midi, et le soir resterait à vendre.
-- -----------------------------------------------------------------------------
create or replace function public.bookings_check_journee()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group uuid;
begin
  select i.group_id into v_group
  from inserted i
  where i.requested_slot = 'journee'
  group by i.group_id
  having count(*) <> 2 or count(distinct i.slot) <> 2
  limit 1;

  if v_group is not null then
    raise exception 'Une réservation « journee » s''écrit en deux lignes, midi et soir (§6.1).'
      using errcode = 'check_violation',
            hint    = 'Passez par request_booking(), qui insère les deux lignes en une seule instruction.';
  end if;

  return null;
end;
$$;

comment on function public.bookings_check_journee() is
  'Refuse une journée entière écrite en une seule ligne (§6.1).';

drop trigger if exists bookings_check_journee on public.bookings;
create trigger bookings_check_journee
  after insert on public.bookings
  referencing new table as inserted
  for each statement execute function public.bookings_check_journee();

-- =============================================================================
-- request_booking — poser une demande, prix compris
--
-- Le seul chemin recommandé pour créer une réservation : il insère les deux
-- lignes d'une journée entière en UNE instruction, ce que la politique d'INSERT
-- de 006 ne saurait pas faire à elle seule.
--
-- Elle n'écrit aucune règle de prix : le montant lui arrive du trigger
-- ci-dessus, donc d'estimate_price().
-- =============================================================================
create or replace function public.request_booking(
  p_venue_id     uuid,
  p_event_date   date,
  p_slot         text,
  p_guest_count  integer,
  p_event_type   text    default null,
  p_message      text    default null,
  p_option_ids   uuid[]  default '{}'::uuid[]
)
returns setof public.bookings
language plpgsql
security definer
set search_path = public
as $$
declare
  v_client uuid := auth.uid();
  v_owner  uuid;
  v_group  uuid := gen_random_uuid();
  v_slots  text[];
begin
  if v_client is null then
    raise exception 'Il faut être connecté pour demander une réservation.'
      using errcode = 'insufficient_privilege';
  end if;

  if p_slot not in ('midi', 'soir', 'journee') then
    raise exception 'Créneau inconnu : %. Attendu midi, soir ou journee.', p_slot
      using errcode = 'invalid_parameter_value';
  end if;

  if p_event_date < current_date then
    raise exception 'On ne réserve pas une date passée.'
      using errcode = 'check_violation';
  end if;

  -- Une demande ne se pose que sur une salle publiée : un brouillon n'est pas
  -- en vente, même si son propriétaire en connaît l'identifiant.
  select v.owner_id into v_owner
  from public.venues v
  where v.id = p_venue_id and v.status = 'published';

  if v_owner is null then
    raise exception 'Cette salle n''est pas ouverte à la réservation.'
      using errcode = 'check_violation';
  end if;

  if v_owner = v_client then
    raise exception 'On ne réserve pas sa propre salle.'
      using errcode = 'check_violation';
  end if;

  -- Une journée entière occupe midi ET soir (§6.1).
  v_slots := case when p_slot = 'journee' then array['midi', 'soir'] else array[p_slot] end;

  -- Le propriétaire a bloqué le créneau (travaux, fête de famille) : inutile de
  -- lui envoyer une demande qu'il refusera.
  if exists (
    select 1 from public.venue_blackouts vb
    where vb.venue_id = p_venue_id
      and vb.date     = p_event_date
      and vb.slot     = any (v_slots)
  ) then
    raise exception 'Ce créneau est bloqué par le propriétaire.'
      using errcode = 'check_violation';
  end if;

  -- Le créneau est déjà pris. Ce contrôle est un CONFORT, pas la garantie : une
  -- demande pending ne bloque rien (§5.1), et c'est l'index uniq_booking_slot
  -- (§6.1) qui arbitre pour de bon, au moment de la confirmation.
  if exists (
    select 1 from public.bookings b
    where b.venue_id   = p_venue_id
      and b.event_date = p_event_date
      and b.slot       = any (v_slots)
      and b.status in ('confirmed', 'completed')
  ) then
    raise exception 'Ce créneau est déjà réservé.'
      using errcode = 'check_violation';
  end if;

  perform public.notify_user(
    v_owner, 'booking_requested',
    jsonb_build_object('venue_id', p_venue_id, 'group_id', v_group,
                       'event_date', p_event_date, 'slot', p_slot)
  );

  -- CTE : plpgsql ne sait pas renvoyer directement un INSERT ... RETURNING.
  -- Les deux lignes d'une journée entière partent dans UNE seule instruction —
  -- c'est ce que vérifie le trigger bookings_check_journee (§6.1).
  return query
  with created as (
    insert into public.bookings (
      group_id, venue_id, client_id, event_date, slot, requested_slot,
      guest_count, event_type, client_message, option_ids,
      -- Valeur de façade : le trigger bookings_set_price l'écrase par
      -- estimate_price(). Elle n'est là que parce que la colonne est NOT NULL.
      quoted_amount, status
    )
    select
      v_group, p_venue_id, v_client, p_event_date, s, p_slot,
      p_guest_count, p_event_type, p_message, coalesce(p_option_ids, '{}'::uuid[]),
      0, 'pending'
    from unnest(v_slots) as s
    returning public.bookings.*
  )
  select c.* from created c;
end;
$$;

comment on function public.request_booking(uuid, date, text, integer, text, text, uuid[]) is
  'Pose une demande (§3, étape 3). Insère les deux lignes d''une journée entière en une instruction (§6.1). '
  'Le montant vient du trigger bookings_set_price, donc d''estimate_price() — aucune règle de prix ici.';

revoke execute on function public.request_booking(uuid, date, text, integer, text, text, uuid[])
  from public, anon;
grant execute on function public.request_booking(uuid, date, text, integer, text, text, uuid[])
  to authenticated;
