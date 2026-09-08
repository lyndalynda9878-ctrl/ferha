-- =============================================================================
-- Ferha — 010_event_types.sql
-- Les types d'événement, et le filtre qui devient vrai.
--
-- POURQUOI CE FICHIER EXISTE
--
-- Le §4.2 (CLI-01) liste le type d'événement parmi les filtres de recherche, et
-- les maquettes en montrent les puces sur l'écran d'accueil. Mais aucune table
-- du §6 ne disait quels événements une salle accueille : `search_venues()`
-- acceptait le critère et ne s'en servait pas.
--
-- Une puce qui ne filtre rien est pire qu'une puce absente : elle promet un
-- tri que personne ne fait, et le client croit avoir restreint sa recherche.
-- Ce fichier apporte la donnée qui manquait, et branche le filtre pour de bon.
--
-- DEUX TABLES, comme pour les équipements :
--   event_types        le référentiel — les codes et leurs libellés
--   venue_event_types  ce que chaque salle accepte, n↔n
--
-- Le code est stable et manipulé par l'application ; le libellé dépend de la
-- langue et n'est jamais comparé.
--
-- CE FICHIER REDÉFINIT search_venues(). La version de 008_search.sql est
-- dépassée : elle ne pouvait pas filtrer sur une table qui n'existait pas
-- encore. C'est la version d'ici qui fait foi.
--
-- Rejouable : chaque objet est créé sous condition d'absence, le référentiel
-- est posé en ON CONFLICT, et la fonction est remplacée.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- event_types — le référentiel
--
-- Les cinq types des maquettes, et eux seuls. Le cahier des charges ne fixe pas
-- la liste ; on n'en invente donc pas d'autres. En ajouter un se fait ici, et
-- nulle part ailleurs.
-- -----------------------------------------------------------------------------

create table if not exists public.event_types (
  code       text primary key check (code ~ '^[a-z][a-z0-9_]*$'),
  label_fr   text        not null check (length(btrim(label_fr)) > 0),
  label_ar   text        not null check (length(btrim(label_ar)) > 0),
  -- Nom d'icône Material, tel qu'il s'écrit dans Flutter.
  icon       text,
  -- Rang d'affichage des puces.
  position   integer     not null default 0 check ("position" >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table  public.event_types is
  'Référentiel des types d''événement (§4.2, CLI-01). Ajout au modèle du §6.';
comment on column public.event_types.code is
  'Code stable manipulé par l''application ; le libellé dépend de la langue.';

create index if not exists event_types_position_idx
  on public.event_types (position);

drop trigger if exists event_types_set_updated_at on public.event_types;
create trigger event_types_set_updated_at
  before update on public.event_types
  for each row execute function public.set_updated_at();

alter table public.event_types enable row level security;

drop policy if exists event_types_select_all on public.event_types;
create policy event_types_select_all
  on public.event_types for select
  to anon, authenticated
  using (true);

-- Libellés arabes marqués « À RELIRE », comme ceux des équipements et des
-- wilayas : ils attendent une relecture par un locuteur natif.
insert into public.event_types (code, label_fr, label_ar, icon, position) values
  ('mariage',      'Mariage',      'زفاف',      'favorite',        10),  -- À RELIRE
  ('fiancailles',  'Fiançailles',  'خطوبة',     'diamond',         20),  -- À RELIRE
  ('henne',        'Henné',        'حنة',       'spa',             30),  -- À RELIRE
  ('circoncision', 'Circoncision', 'ختان',      'child_care',      40),  -- À RELIRE
  ('anniversaire', 'Anniversaire', 'عيد ميلاد', 'cake',            50)   -- À RELIRE
on conflict (code) do update set
  label_fr = excluded.label_fr,
  label_ar = excluded.label_ar,
  icon     = excluded.icon,
  position = excluded.position;

-- -----------------------------------------------------------------------------
-- venue_event_types — ce que chaque salle accepte, n↔n
--
-- ABSENCE DE LIGNES = SALLE QUI ACCEPTE TOUT. C'est le choix qui compte ici, et
-- il mérite d'être expliqué.
--
-- Une salle qui n'a rien déclaré est une salle dont le propriétaire n'a pas
-- encore répondu à la question — pas une salle qui refuse tout. Traiter le vide
-- comme un refus ferait disparaître du catalogue toutes les salles existantes
-- au moment où ce fichier s'applique, et toute salle créée avant que le
-- formulaire ne pose la question.
--
-- Le filtre de search_venues() suit donc cette règle : il ne retient une salle
-- que si elle n'a rien déclaré, OU si elle a déclaré le type demandé.
-- -----------------------------------------------------------------------------

create table if not exists public.venue_event_types (
  venue_id   uuid        not null references public.venues (id) on delete cascade,
  -- RESTRICT : on ne retire pas du référentiel un type encore posé sur des
  -- salles sans s'en apercevoir.
  event_type text        not null references public.event_types (code)
                on update cascade on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (venue_id, event_type)
);

comment on table public.venue_event_types is
  'Types d''événement acceptés par une salle, n↔n. '
  'Aucune ligne = la salle accepte tout : le propriétaire n''a pas encore répondu.';

create index if not exists venue_event_types_type_idx
  on public.venue_event_types (event_type);

drop trigger if exists venue_event_types_set_updated_at on public.venue_event_types;
create trigger venue_event_types_set_updated_at
  before update on public.venue_event_types
  for each row execute function public.set_updated_at();

-- Même règle que venue_amenities (002) : lisible quand la salle est lisible,
-- modifiable par son seul propriétaire.
alter table public.venue_event_types enable row level security;

drop policy if exists venue_event_types_select on public.venue_event_types;
create policy venue_event_types_select
  on public.venue_event_types for select
  to anon, authenticated
  using (public.can_read_venue(venue_id));

drop policy if exists venue_event_types_write on public.venue_event_types;
create policy venue_event_types_write
  on public.venue_event_types for all
  to authenticated
  using (public.owns_venue(venue_id))
  with check (public.owns_venue(venue_id));

-- =============================================================================
-- search_venues — VERSION COURANTE
--
-- Identique à celle de 008_search.sql, à une chose près : p_event_type filtre
-- désormais. Le reste du commentaire de 008 reste valable, et notamment la
-- règle sur ce que cette fonction a le droit de renvoyer — uniquement des
-- colonnes publiques par nature d'une salle PUBLIÉE.
-- =============================================================================

create or replace function public.search_venues(
  p_query        text    default null,
  p_wilaya_code  text    default null,
  p_commune      text    default null,
  p_event_date   date    default null,
  p_slot         text    default 'soir',
  p_guest_count  integer default null,
  p_max_budget   numeric default null,
  p_event_type   text    default null,
  p_amenities    text[]  default null,
  p_order        text    default 'note',
  p_limit        integer default 50,
  p_offset       integer default 0
)
returns table (
  venue_id        uuid,
  name            text,
  wilaya_code     text,
  commune         text,
  capacity_seated integer,
  parking_spaces  integer,
  cover_photo     text,
  amenity_codes   text[],
  price           numeric,
  price_slot      text,
  rating          numeric,
  review_count    bigint,
  total_count     bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  v_date   date    := coalesce(p_event_date, current_date);
  v_slots  text[]  := case when p_slot = 'journee'
                           then array['midi', 'soir']
                           else array[coalesce(p_slot, 'soir')] end;
  v_slot   text    := coalesce(p_slot, 'soir');
  v_guests integer := greatest(coalesce(p_guest_count, 1), 1);
  v_texte  text    := nullif(btrim(coalesce(p_query, '')), '');
  v_type   text    := nullif(btrim(coalesce(p_event_type, '')), '');
begin
  if v_slot not in ('midi', 'soir', 'journee') then
    raise exception 'Créneau inconnu : %. Attendu midi, soir ou journee.', v_slot
      using errcode = 'invalid_parameter_value';
  end if;

  -- Un code inconnu se dit, il ne se tait pas : sans ce contrôle, une faute de
  -- frappe côté application renverrait zéro salle et passerait pour un
  -- catalogue vide.
  if v_type is not null
     and not exists (select 1 from public.event_types t where t.code = v_type) then
    raise exception 'Type d''événement inconnu : %.', v_type
      using errcode = 'invalid_parameter_value',
            hint    = 'Les codes valides sont dans la table event_types.';
  end if;

  return query
  select
    v.id,
    v.name,
    v.wilaya_code,
    v.commune,
    v.capacity_seated,
    v.parking_spaces,

    (select p.storage_path
       from public.venue_photos p
      where p.venue_id = v.id
      order by p.is_cover desc, p.position asc
      limit 1),

    (select array_agg(va.amenity_code order by va.amenity_code)
       from public.venue_amenities va
      where va.venue_id = v.id),

    e.total,
    v_slot,
    vr.bayesian_rating,
    coalesce(vr.review_count, 0),
    count(*) over ()
  from public.venues v

  join public.venue_pricing vp
    on vp.venue_id = v.id and vp.slot = v_slot

  cross join lateral public.estimate_price(
    v.id, v_date, v_slot, v_guests, '{}'::uuid[]
  ) e

  left join public.venue_ratings vr on vr.venue_id = v.id

  where
    v.status = 'published'

    and (v_texte is null
         or v.name    ilike '%' || v_texte || '%'
         or v.commune ilike '%' || v_texte || '%'
         or v.wilaya_code = v_texte)
    and (p_wilaya_code is null or v.wilaya_code = p_wilaya_code)
    and (p_commune is null or v.commune ilike p_commune)

    and (p_guest_count is null or v.capacity_seated >= p_guest_count)
    and (p_max_budget is null or e.total <= p_max_budget)

    -- LE FILTRE DU TYPE D'ÉVÉNEMENT.
    --
    -- Une salle passe si elle n'a rien déclaré — son propriétaire n'a pas
    -- encore répondu, et le silence ne vaut pas refus — ou si elle a déclaré
    -- accepter ce type-là.
    and (v_type is null
         or not exists (
              select 1 from public.venue_event_types vet
              where vet.venue_id = v.id
            )
         or exists (
              select 1 from public.venue_event_types vet
              where vet.venue_id = v.id and vet.event_type = v_type
            ))

    and (p_amenities is null or cardinality(p_amenities) = 0
         or not exists (
           select 1 from unnest(p_amenities) as souhait(code)
           where not exists (
             select 1 from public.venue_amenities va
             where va.venue_id = v.id and va.amenity_code = souhait.code
           )
         ))

    and (p_event_date is null or not exists (
          select 1 from public.venue_blackouts vb
          where vb.venue_id = v.id
            and vb.date     = p_event_date
            and vb.slot     = any (v_slots)
        ))
    and (p_event_date is null or not exists (
          select 1 from public.bookings b
          where b.venue_id   = v.id
            and b.event_date = p_event_date
            and b.slot       = any (v_slots)
            and b.status in ('confirmed', 'completed')
        ))

  order by
    case when p_order = 'note'     then vr.bayesian_rating end desc nulls last,
    case when p_order = 'note'     then vr.review_count    end desc nulls last,
    case when p_order = 'prix'     then e.total            end asc,
    case when p_order = 'capacite' then v.capacity_seated  end desc,
    v.name asc,
    v.id asc
  limit  greatest(coalesce(p_limit, 50), 1)
  offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

comment on function public.search_venues(
  text, text, text, date, text, integer, numeric, text, text[], text, integer, integer
) is
  'Recherche de salles (§4.2, CLI-01). Filtre et tarife en base : le prix vient '
  'd''estimate_price() pour la date demandée, majorations comprises. '
  'p_event_type filtre depuis 010. '
  'SECURITY DEFINER pour lire les disponibilités dans bookings — ne renvoyer que '
  'des colonnes publiques d''une salle publiée.';

grant execute on function public.search_venues(
  text, text, text, date, text, integer, numeric, text, text[], text, integer, integer
) to anon, authenticated;
