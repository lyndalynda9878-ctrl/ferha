-- =============================================================================
-- Ferha — 001_schema.sql
-- Catalogue : profils, salles, photos, équipements, tarifs, dates bloquées.
--
-- Contrat : cahier des charges §6. Les tables de réservation et de paiement
-- (bookings, payments, reviews, messages…) arrivent à l'étape suivante.
--
-- Rejouable : chaque objet est créé sous condition d'absence.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Outillage commun
-- -----------------------------------------------------------------------------

-- Tient à jour la colonne updated_at. Un seul exemplaire pour toutes les tables.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

comment on function public.set_updated_at() is
  'Trigger BEFORE UPDATE : repositionne updated_at à l''instant de la modification.';

-- -----------------------------------------------------------------------------
-- profiles — utilisateur, tous rôles confondus (§6)
-- -----------------------------------------------------------------------------

create table if not exists public.profiles (
  -- Même identifiant que auth.users : un seul utilisateur, un seul profil.
  id              uuid primary key references auth.users (id) on delete cascade,
  full_name       text        not null check (length(btrim(full_name)) > 0),
  -- v2.0 : l'inscription se fait par e-mail, il est donc obligatoire.
  email           text        not null check (email like '%_@_%.__%'),
  -- v2.0 : le téléphone n'est plus vérifié à l'inscription, donc nullable.
  phone           text,
  -- Passe à vrai seulement après une vérification hors inscription.
  phone_verified  boolean     not null default false,
  -- Débloque l'espace propriétaire. Un même compte peut être client ET
  -- propriétaire : pas de seconde table d'utilisateurs.
  is_owner        boolean     not null default false,
  is_admin        boolean     not null default false,
  -- Langue d'interface préférée, reprise par l'application au démarrage.
  locale          text        not null default 'fr' check (locale in ('fr', 'ar')),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  -- Un téléphone ne peut pas être marqué vérifié s'il n'y a pas de téléphone.
  constraint profiles_phone_verified_requires_phone
    check (not phone_verified or phone is not null)
);

comment on table  public.profiles is 'Utilisateur, tous rôles confondus (§6).';
comment on column public.profiles.id is 'Égal à auth.uid().';
comment on column public.profiles.phone_verified is
  'Vérification différée : en v2.0 l''inscription se fait par e-mail, pas par SMS.';
comment on column public.profiles.is_owner is
  'Débloque l''espace propriétaire. Un propriétaire reste un client par ailleurs.';

create unique index if not exists profiles_email_key
  on public.profiles (lower(email));

create index if not exists profiles_is_owner_idx
  on public.profiles (is_owner) where is_owner;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- Vrai si l'utilisateur courant est administrateur.
-- SECURITY DEFINER : la fonction lit profiles sans être bloquée par les
-- politiques RLS de cette même table, ce qui éviterait une récursion.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select p.is_admin from public.profiles p where p.id = auth.uid()),
    false
  );
$$;

comment on function public.is_admin() is
  'Vrai si le profil authentifié porte is_admin. Faux pour un visiteur anonyme.';

-- -----------------------------------------------------------------------------
-- venues — la salle (§6)
-- -----------------------------------------------------------------------------

create table if not exists public.venues (
  id               uuid primary key default gen_random_uuid(),
  owner_id         uuid        not null references public.profiles (id) on delete cascade,
  name             text        not null check (length(btrim(name)) > 0),
  -- Code de wilaya sur deux chiffres, « 01 » à « 58 ». Texte et non entier :
  -- le zéro de tête fait partie du code tel qu'il est écrit partout en Algérie.
  wilaya_code      text        not null check (wilaya_code ~ '^(0[1-9]|[1-4][0-9]|5[0-8])$'),
  commune          text        not null check (length(btrim(commune)) > 0),
  lat              double precision check (lat between -90 and 90),
  lng              double precision check (lng between -180 and 180),
  -- Capacité assise, en couverts. C'est le nombre que cherche le client.
  capacity_seated  integer     not null check (capacity_seated > 0),
  -- Superficie en mètres carrés. Nullable : tous les propriétaires ne la
  -- connaissent pas, et une salle reste publiable sans elle.
  area_sqm         integer     check (area_sqm > 0),
  -- Nombre de places de parking. NULL veut dire « non renseigné », 0 veut dire
  -- « pas de parking » : les deux se distinguent. C'est de ce nombre que se
  -- fabrique la puce « Parking 60 » des maquettes — il n'existe volontairement
  -- pas d'équipement « parking » dans le référentiel, pour qu'une seule colonne
  -- porte l'information.
  parking_spaces   integer     check (parking_spaces >= 0),
  description      text,
  -- Cycle de vie : brouillon → en attente de validation → publiée.
  -- « suspended » est une décision d'administration, jamais du propriétaire.
  status           text        not null default 'draft'
                     check (status in ('draft', 'pending', 'published', 'suspended')),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),

  -- Une salle est localisée entièrement, ou pas du tout.
  constraint venues_coordinates_complete
    check (num_nulls(lat, lng) <> 1)
);

comment on table  public.venues is 'La salle des fêtes (§6).';
comment on column public.venues.wilaya_code is
  'Code wilaya sur deux chiffres, « 01 » à « 58 ».';
comment on column public.venues.capacity_seated is 'Capacité assise, en couverts.';
comment on column public.venues.area_sqm is 'Superficie en mètres carrés.';
comment on column public.venues.parking_spaces is
  'Places de parking. NULL = non renseigné, 0 = pas de parking. Remplace l''équipement « parking ».';
comment on column public.venues.status is
  'draft → pending par le propriétaire ; published et suspended relèvent de l''administration.';

create index if not exists venues_owner_id_idx    on public.venues (owner_id);
create index if not exists venues_wilaya_idx      on public.venues (wilaya_code);
create index if not exists venues_capacity_idx    on public.venues (capacity_seated);
-- Index partiel : la recherche publique ne lit que les salles publiées.
create index if not exists venues_published_idx
  on public.venues (wilaya_code, capacity_seated) where status = 'published';

drop trigger if exists venues_set_updated_at on public.venues;
create trigger venues_set_updated_at
  before update on public.venues
  for each row execute function public.set_updated_at();

-- Le propriétaire ne peut pas se publier lui-même, ni céder sa salle en douce.
-- La règle vit dans un trigger et non dans une politique RLS : un WITH CHECK ne
-- voit que la ligne d'arrivée, jamais celle de départ — il ne peut donc pas
-- distinguer « la salle était déjà publiée » de « le propriétaire la publie ».
create or replace function public.venues_guard_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Le rôle de service (migrations, webhooks) et les administrateurs passent.
  if auth.uid() is null or public.is_admin() then
    return new;
  end if;

  if new.owner_id is distinct from old.owner_id then
    raise exception 'Le propriétaire d''une salle ne peut pas être changé par son propriétaire.'
      using errcode = 'check_violation';
  end if;

  if new.status is distinct from old.status
     and new.status not in ('draft', 'pending') then
    raise exception 'Une salle ne peut pas être passée à « % » par son propriétaire.', new.status
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

comment on function public.venues_guard_status() is
  'Interdit au propriétaire de dépasser « pending » et de céder sa salle (§9).';

drop trigger if exists venues_guard_status on public.venues;
create trigger venues_guard_status
  before update on public.venues
  for each row execute function public.venues_guard_status();

-- -----------------------------------------------------------------------------
-- venue_photos — galerie (§6)
-- -----------------------------------------------------------------------------

create table if not exists public.venue_photos (
  id           uuid primary key default gen_random_uuid(),
  venue_id     uuid        not null references public.venues (id) on delete cascade,
  -- Chemin dans le bucket Supabase Storage, pas une URL : l'URL se signe à la
  -- lecture et n'a donc pas à être stockée.
  storage_path text        not null check (length(btrim(storage_path)) > 0),
  -- Rang d'affichage dans la galerie, croissant.
  position     integer     not null default 0 check ("position" >= 0),
  is_cover     boolean     not null default false,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

comment on table  public.venue_photos is 'Galerie d''une salle (§6).';
comment on column public.venue_photos.storage_path is
  'Chemin dans le bucket Storage. L''URL est signée à la lecture.';
comment on column public.venue_photos.position is 'Rang d''affichage, croissant.';

create index if not exists venue_photos_venue_id_idx
  on public.venue_photos (venue_id, position);

-- Une seule photo de couverture par salle.
create unique index if not exists venue_photos_one_cover_per_venue
  on public.venue_photos (venue_id) where is_cover;

drop trigger if exists venue_photos_set_updated_at on public.venue_photos;
create trigger venue_photos_set_updated_at
  before update on public.venue_photos
  for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- amenities — référentiel des équipements (§6)
-- -----------------------------------------------------------------------------

create table if not exists public.amenities (
  -- Code stable, en minuscules : c'est lui que manipule l'application, jamais
  -- le libellé, qui dépend de la langue.
  code       text primary key check (code ~ '^[a-z][a-z0-9_]*$'),
  label_fr   text        not null check (length(btrim(label_fr)) > 0),
  label_ar   text        not null check (length(btrim(label_ar)) > 0),
  -- Nom d'icône Material, tel qu'il s'écrit dans Flutter (Icons.ac_unit).
  icon       text,
  -- Regroupement d'affichage dans la fiche salle et la feuille de filtres.
  category   text        not null
               check (category in ('confort', 'espaces', 'services', 'logistique')),
  -- Rang d'affichage à l'intérieur d'une catégorie.
  position   integer     not null default 0 check ("position" >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table  public.amenities is 'Référentiel des équipements (§6).';
comment on column public.amenities.code is
  'Code stable manipulé par l''application ; le libellé dépend de la langue.';
comment on column public.amenities.icon is
  'Nom d''icône Material tel qu''il s''écrit dans Flutter (Icons.ac_unit).';

create index if not exists amenities_category_idx
  on public.amenities (category, position);

drop trigger if exists amenities_set_updated_at on public.amenities;
create trigger amenities_set_updated_at
  before update on public.amenities
  for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- venue_amenities — équipements d'une salle, n↔n (§6)
-- -----------------------------------------------------------------------------

create table if not exists public.venue_amenities (
  venue_id     uuid        not null references public.venues (id) on delete cascade,
  -- RESTRICT : on ne retire pas du référentiel un équipement encore posé sur
  -- des salles sans s'en apercevoir.
  amenity_code text        not null references public.amenities (code)
                 on update cascade on delete restrict,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  primary key (venue_id, amenity_code)
);

comment on table public.venue_amenities is 'Équipements d''une salle, n↔n (§6).';

create index if not exists venue_amenities_amenity_idx
  on public.venue_amenities (amenity_code);

drop trigger if exists venue_amenities_set_updated_at on public.venue_amenities;
create trigger venue_amenities_set_updated_at
  before update on public.venue_amenities
  for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- venue_pricing — grille tarifaire (§6)
-- -----------------------------------------------------------------------------

create table if not exists public.venue_pricing (
  venue_id          uuid    not null references public.venues (id) on delete cascade,
  -- Créneau tarifé. « journee » est une ligne à part entière : une journée
  -- entière se vend rarement au prix de midi + soir.
  slot              text    not null check (slot in ('midi', 'soir', 'journee')),
  -- Prix de base en dinars, hors majorations.
  base_price        numeric(12, 2) not null check (base_price >= 0),
  -- Coefficients multiplicateurs appliqués par la fonction de calcul du prix,
  -- côté base de données. Jamais en Dart.
  weekend_coef      numeric(4, 2)  not null default 1 check (weekend_coef > 0),
  high_season_coef  numeric(4, 2)  not null default 1 check (high_season_coef > 0),
  -- Couverts compris dans le prix de base.
  included_seats    integer        not null default 0 check (included_seats >= 0),
  -- Prix du couvert au-delà de included_seats.
  extra_seat_price  numeric(12, 2) not null default 0 check (extra_seat_price >= 0),
  created_at        timestamptz    not null default now(),
  updated_at        timestamptz    not null default now(),
  primary key (venue_id, slot)
);

comment on table  public.venue_pricing is 'Grille tarifaire d''une salle (§6).';
comment on column public.venue_pricing.slot is
  'midi, soir, ou journee — la journée entière est tarifée à part.';
comment on column public.venue_pricing.base_price is 'Prix de base en dinars, hors majorations.';
comment on column public.venue_pricing.weekend_coef is
  'Multiplicateur week-end, appliqué par la fonction de calcul du prix en base.';
comment on column public.venue_pricing.high_season_coef is
  'Multiplicateur haute saison, appliqué par la fonction de calcul du prix en base.';
comment on column public.venue_pricing.included_seats is 'Couverts compris dans base_price.';
comment on column public.venue_pricing.extra_seat_price is
  'Prix du couvert au-delà de included_seats.';

drop trigger if exists venue_pricing_set_updated_at on public.venue_pricing;
create trigger venue_pricing_set_updated_at
  before update on public.venue_pricing
  for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- venue_blackouts — dates bloquées par le propriétaire (§6)
-- -----------------------------------------------------------------------------

create table if not exists public.venue_blackouts (
  id         uuid        primary key default gen_random_uuid(),
  venue_id   uuid        not null references public.venues (id) on delete cascade,
  date       date        not null,
  -- Créneaux atomiques seulement. Une journée entière se bloque en deux lignes,
  -- midi et soir — même découpage que les réservations (§6.1), pour que la
  -- requête de disponibilité lise les deux tables de la même façon.
  slot       text        not null check (slot in ('midi', 'soir')),
  -- Motif interne du propriétaire (travaux, fête de famille…).
  reason     text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (venue_id, date, slot)
);

comment on table  public.venue_blackouts is 'Dates bloquées par le propriétaire (§6).';
comment on column public.venue_blackouts.slot is
  'midi ou soir. Une journée entière se bloque en deux lignes, comme une réservation (§6.1).';
comment on column public.venue_blackouts.reason is
  'Motif interne du propriétaire. Non destiné à l''affichage public.';

create index if not exists venue_blackouts_venue_date_idx
  on public.venue_blackouts (venue_id, date);

drop trigger if exists venue_blackouts_set_updated_at on public.venue_blackouts;
create trigger venue_blackouts_set_updated_at
  before update on public.venue_blackouts
  for each row execute function public.set_updated_at();
