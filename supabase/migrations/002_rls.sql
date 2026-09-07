-- =============================================================================
-- Ferha — 002_rls.sql
-- Politiques Row Level Security du catalogue (cahier des charges §9).
--
-- L'application Flutter parle directement à la base : la sécurité est ici, pas
-- dans le code Dart. Toute table du catalogue a RLS activé, sans exception —
-- une table sans politique de lecture est simplement fermée, ce qui est le bon
-- défaut.
--
-- Rejouable : chaque politique est supprimée avant d'être recréée.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Activation — chaque table, sans exception
-- -----------------------------------------------------------------------------

alter table public.profiles        enable row level security;
alter table public.venues          enable row level security;
alter table public.venue_photos    enable row level security;
alter table public.amenities       enable row level security;
alter table public.venue_amenities enable row level security;
alter table public.venue_pricing   enable row level security;
alter table public.venue_blackouts enable row level security;

-- -----------------------------------------------------------------------------
-- Fonctions d'aide
-- -----------------------------------------------------------------------------

-- Vrai si la salle est visible par l'utilisateur courant : publiée pour tout le
-- monde, ou brouillon de son propre propriétaire.
create or replace function public.can_read_venue(p_venue_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.venues v
    where v.id = p_venue_id
      and (v.status = 'published' or v.owner_id = auth.uid())
  );
$$;

comment on function public.can_read_venue(uuid) is
  'Vrai si la salle est publiée, ou si elle appartient à l''utilisateur courant (§9).';

-- Vrai si l'utilisateur courant est le propriétaire de la salle.
create or replace function public.owns_venue(p_venue_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.venues v
    where v.id = p_venue_id
      and v.owner_id = auth.uid()
  );
$$;

comment on function public.owns_venue(uuid) is
  'Vrai si la salle appartient à l''utilisateur courant.';

-- -----------------------------------------------------------------------------
-- profiles
-- Chacun lit et modifie son propre profil, rien d'autre. L'exposition publique
-- du nom d'un propriétaire, et la révélation du téléphone après passage à
-- « accepted » (§9), relèvent des tables de réservation : étape suivante.
-- -----------------------------------------------------------------------------

drop policy if exists profiles_select_self on public.profiles;
create policy profiles_select_self
  on public.profiles for select
  to authenticated
  using (id = auth.uid() or public.is_admin());

drop policy if exists profiles_insert_self on public.profiles;
create policy profiles_insert_self
  on public.profiles for insert
  to authenticated
  with check (id = auth.uid());

drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self
  on public.profiles for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- Pas de politique DELETE : la suppression de compte passe par auth.users, qui
-- cascade jusqu'ici.

-- -----------------------------------------------------------------------------
-- venues
-- Lecture : tous si published ; le propriétaire voit aussi ses brouillons.
-- Écriture : propriétaire uniquement, et il ne dépasse pas « pending ».
-- -----------------------------------------------------------------------------

drop policy if exists venues_select_published_or_own on public.venues;
create policy venues_select_published_or_own
  on public.venues for select
  to anon, authenticated
  using (status = 'published' or owner_id = auth.uid());

drop policy if exists venues_insert_own on public.venues;
create policy venues_insert_own
  on public.venues for insert
  to authenticated
  -- Une salle naît en brouillon ou en attente de validation, jamais publiée.
  with check (owner_id = auth.uid() and status in ('draft', 'pending'));

drop policy if exists venues_update_own on public.venues;
create policy venues_update_own
  on public.venues for update
  to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());
-- La borne « pas au-delà de pending » est portée par le trigger
-- venues_guard_status (001_schema.sql) : un WITH CHECK ne voit pas la ligne de
-- départ et ne peut donc pas distinguer une salle déjà publiée d'une salle que
-- le propriétaire publierait lui-même.

drop policy if exists venues_delete_own on public.venues;
create policy venues_delete_own
  on public.venues for delete
  to authenticated
  using (owner_id = auth.uid());

-- -----------------------------------------------------------------------------
-- venue_photos, venue_amenities, venue_pricing, venue_blackouts
-- Ces quatre tables suivent leur salle : lisibles quand la salle est lisible,
-- modifiables par son seul propriétaire.
-- -----------------------------------------------------------------------------

drop policy if exists venue_photos_select on public.venue_photos;
create policy venue_photos_select
  on public.venue_photos for select
  to anon, authenticated
  using (public.can_read_venue(venue_id));

drop policy if exists venue_photos_write on public.venue_photos;
create policy venue_photos_write
  on public.venue_photos for all
  to authenticated
  using (public.owns_venue(venue_id))
  with check (public.owns_venue(venue_id));

drop policy if exists venue_amenities_select on public.venue_amenities;
create policy venue_amenities_select
  on public.venue_amenities for select
  to anon, authenticated
  using (public.can_read_venue(venue_id));

drop policy if exists venue_amenities_write on public.venue_amenities;
create policy venue_amenities_write
  on public.venue_amenities for all
  to authenticated
  using (public.owns_venue(venue_id))
  with check (public.owns_venue(venue_id));

drop policy if exists venue_pricing_select on public.venue_pricing;
create policy venue_pricing_select
  on public.venue_pricing for select
  to anon, authenticated
  using (public.can_read_venue(venue_id));

drop policy if exists venue_pricing_write on public.venue_pricing;
create policy venue_pricing_write
  on public.venue_pricing for all
  to authenticated
  using (public.owns_venue(venue_id))
  with check (public.owns_venue(venue_id));

-- venue_blackouts porte reason, le motif interne du propriétaire (travaux, fête
-- de famille). La table n'est donc lisible que par lui. Le public passe par la
-- vue venue_availability, plus bas, qui n'expose pas cette colonne.
drop policy if exists venue_blackouts_select on public.venue_blackouts;
create policy venue_blackouts_select
  on public.venue_blackouts for select
  to authenticated
  using (public.owns_venue(venue_id));

drop policy if exists venue_blackouts_write on public.venue_blackouts;
create policy venue_blackouts_write
  on public.venue_blackouts for all
  to authenticated
  using (public.owns_venue(venue_id))
  with check (public.owns_venue(venue_id));

-- -----------------------------------------------------------------------------
-- venue_availability — ce que le calendrier a le droit de voir
--
-- CETTE VUE EST VOLONTAIREMENT SANS RLS.
--
-- Ce n'est pas un oubli, et il n'y a pas de politique à lui ajouter. Elle est
-- ouverte parce que les trois colonnes qu'elle expose — venue_id, date, slot —
-- sont publiques par nature : savoir qu'une salle publiée est prise le 14 août
-- au soir, c'est précisément ce que le client vient chercher. Ce qui est
-- confidentiel, c'est le motif du blocage, et il reste dans la table.
--
-- RÈGLE : n'ajouter aucune colonne à cette vue sans avoir vérifié qu'un
-- inconnu, non connecté, a le droit de la lire. En cas de doute, la réponse est
-- non — la colonne reste dans venue_blackouts, que seul le propriétaire lit.
-- Ajouter reason ici annulerait tout l'intérêt de la vue.
--
-- Comment elle tient : elle s'exécute avec les droits de son propriétaire
-- (security_invoker = false, le défaut, écrit ici explicitement parce que c'est
-- tout l'argument). Elle traverse donc la politique de venue_blackouts, et
-- c'est son propre WHERE qui borne ce qui sort — les salles publiées, plus les
-- brouillons de celui qui regarde. La passer en security_invoker = true la
-- viderait entièrement.
--
-- C'est cette vue que lit l'écran calendrier, jamais la table.
--
-- Le linter Supabase la signale comme « security definer view ». C'est un faux
-- positif : la vue filtre elle-même, et n'expose que du public.
-- -----------------------------------------------------------------------------

create or replace view public.venue_availability
  with (security_invoker = false) as
  select
    b.venue_id,
    b.date,
    b.slot
  from public.venue_blackouts b
  where public.can_read_venue(b.venue_id);

comment on view public.venue_availability is
  'Créneaux bloqués, sans le motif. Seule lecture publique de venue_blackouts (§9). '
  'Sans RLS à dessein : n''y ajouter aucune colonne qui ne soit lisible par un inconnu.';

grant select on public.venue_availability to anon, authenticated;

-- -----------------------------------------------------------------------------
-- amenities
-- Référentiel : lisible par tous, écrit par le seul rôle de service. L'absence
-- volontaire de politique d'écriture suffit à fermer la table.
-- -----------------------------------------------------------------------------

drop policy if exists amenities_select_all on public.amenities;
create policy amenities_select_all
  on public.amenities for select
  to anon, authenticated
  using (true);
