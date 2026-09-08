-- =============================================================================
-- Ferha — 006_rls_bookings.sql
-- Politiques Row Level Security des réservations (cahier des charges §9).
--
-- L'application Flutter parle directement à la base : la sécurité est ici, pas
-- dans le code Dart. Le tableau du §9, ligne par ligne :
--
--   bookings       lecture : le client concerné OU le propriétaire de la salle
--                  écriture : client, création seulement — les transitions
--                  d'état passent par les fonctions SECURITY DEFINER de 004
--   payments       lecture : client et propriétaire concernés
--                  écriture : AUCUNE écriture cliente, service role uniquement
--   reviews        lecture : public
--                  écriture : client, si booking.status = 'completed',
--                  booking.client_id = auth.uid() et J+1 ≤ maintenant ≤ J+30
--
-- Et l'autre point du §9 : « les numéros de téléphone ne sont révélés qu'après
-- passage à accepted ». C'est booking_contact(), tout en bas, qui le tient.
--
-- Les tables du prix (high_season_periods, venue_options) portent leurs propres
-- politiques dans 005 : le prix se lit d'un seul endroit.
--
-- Rejouable : chaque politique est supprimée avant d'être recréée.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Activation — chaque table, sans exception
-- -----------------------------------------------------------------------------

alter table public.bookings      enable row level security;
alter table public.payments      enable row level security;
alter table public.reviews       enable row level security;
alter table public.notifications enable row level security;

-- -----------------------------------------------------------------------------
-- bookings
--
-- Lecture : les deux parties, et personne d'autre. Pas d'exception « salle
-- publiée » : qui a réservé le 14 août ne regarde ni les curieux ni les
-- concurrents.
--
-- Écriture : création seulement. Il n'y a volontairement AUCUNE politique
-- UPDATE ni DELETE sur cette table — ni pour le client, ni pour le
-- propriétaire. Tout changement d'état passe par accept_booking(),
-- refuse_booking(), confirm_booking(), complete_booking(), cancel_booking() ou
-- expire_options() (004), qui vérifient chacune qui appelle et d'où l'on part.
-- Une réservation ne s'efface pas : elle s'annule.
-- -----------------------------------------------------------------------------

drop policy if exists bookings_select_parties on public.bookings;
create policy bookings_select_parties
  on public.bookings for select
  to authenticated
  using (
    client_id = auth.uid()
    or public.owns_venue(venue_id)
    or public.is_admin()
  );

drop policy if exists bookings_insert_client on public.bookings;
create policy bookings_insert_client
  on public.bookings for insert
  to authenticated
  with check (
    -- On ne réserve que pour soi.
    client_id = auth.uid()
    -- Une réservation naît en attente, jamais ailleurs. Le reste du cycle de
    -- vie appartient aux fonctions de transition.
    and status = 'pending'
    -- Ni acompte ni option de 72 h à la création : c'est le propriétaire qui
    -- les pose en acceptant.
    and deposit_amount is null
    and option_expires_at is null
    -- Seule une salle publiée est en vente, et on ne réserve pas la sienne.
    and exists (
      select 1 from public.venues v
      where v.id = venue_id
        and v.status = 'published'
        and v.owner_id <> auth.uid()
    )
  );

-- quoted_amount n'apparaît nulle part dans ce WITH CHECK : une politique RLS ne
-- sait pas calculer un prix. C'est le trigger bookings_set_price (005) qui jette
-- le montant reçu et le remplace par estimate_price(). Un client qui insérerait
-- « quoted_amount = 1 » obtiendrait quand même le vrai prix.

-- -----------------------------------------------------------------------------
-- payments
--
-- §9 : « Aucune écriture cliente. Service role via webhook uniquement. »
-- L'absence de politique INSERT, UPDATE et DELETE n'est pas un oubli : c'est la
-- règle. RLS étant activé, la table est fermée en écriture à tout ce qui n'est
-- pas service_role. Ne rien ajouter ici.
-- -----------------------------------------------------------------------------

drop policy if exists payments_select_parties on public.payments;
create policy payments_select_parties
  on public.payments for select
  to authenticated
  using (
    public.books_booking(booking_id)
    or public.owns_booking(booking_id)
    or public.is_admin()
  );

-- -----------------------------------------------------------------------------
-- reviews
--
-- Lecture publique : un avis sert à celui qui n'a pas encore réservé.
--
-- Écriture : les trois conditions du §9 réunies — réservation honorée,
-- réservation de l'auteur, et fenêtre J+1 → J+30 (§5.4). La quatrième condition,
-- « un seul avis par réservation », est portée par le schéma lui-même
-- (booking_id UNIQUE) : elle ne dépend d'aucune politique.
-- -----------------------------------------------------------------------------

drop policy if exists reviews_select_public on public.reviews;
create policy reviews_select_public
  on public.reviews for select
  to anon, authenticated
  using (true);

drop policy if exists reviews_insert_client on public.reviews;
create policy reviews_insert_client
  on public.reviews for insert
  to authenticated
  with check (
    exists (
      select 1 from public.bookings b
      where b.id          = booking_id
        and b.client_id   = auth.uid()
        and b.status      = 'completed'
        -- Fenêtre de dépôt du §5.4 : de J+1 à J+30 après l'événement. Avant,
        -- l'avis est prématuré ; après, il n'est plus de première main.
        and current_date >= b.event_date + 1
        and current_date <= b.event_date + 30
    )
  );

-- Deux acteurs modifient un avis, et pas les mêmes colonnes : l'auteur corrige
-- son texte tant que le propriétaire n'a pas répondu (§5.4), le propriétaire
-- écrit sa réponse (§4.3, OWN-06). Les politiques disent qui peut toucher la
-- ligne ; le trigger reviews_guard_actor, plus bas, dit à quoi.
drop policy if exists reviews_update_author on public.reviews;
create policy reviews_update_author
  on public.reviews for update
  to authenticated
  using (public.books_booking(booking_id))
  with check (public.books_booking(booking_id));

drop policy if exists reviews_update_owner_reply on public.reviews;
create policy reviews_update_owner_reply
  on public.reviews for update
  to authenticated
  using (public.owns_venue(venue_id))
  with check (public.owns_venue(venue_id));

-- Pas de politique DELETE : la modération d'un avis (§4.4, ADM-02) relève du
-- back-office, donc du rôle de service.

-- Qui a le droit de changer quoi. Un WITH CHECK ne sait pas comparer la ligne
-- d'arrivée à la ligne de départ ; sans ce trigger, le propriétaire pourrait
-- relever la note de son propre avis en même temps qu'il y répond.
create or replace function public.reviews_guard_actor()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_is_author boolean;
  v_is_owner  boolean;
begin
  -- Le rôle de service (modération, migrations) passe.
  if auth.uid() is null then
    return new;
  end if;

  v_is_author := public.books_booking(new.booking_id);
  v_is_owner  := public.owns_venue(new.venue_id);

  -- La note et le texte appartiennent à l'auteur.
  if not v_is_author
     and (new.rating, new.rating_cleanliness, new.rating_service,
          new.rating_value, new.rating_accuracy, new.body)
         is distinct from
         (old.rating, old.rating_cleanliness, old.rating_service,
          old.rating_value, old.rating_accuracy, old.body) then
    raise exception 'Seul l''auteur de l''avis peut en modifier le contenu.'
      using errcode = 'insufficient_privilege';
  end if;

  -- Et la réponse appartient au propriétaire.
  if not v_is_owner and new.owner_reply is distinct from old.owner_reply then
    raise exception 'Seul le propriétaire de la salle peut répondre à un avis.'
      using errcode = 'insufficient_privilege';
  end if;

  -- Ni l'un ni l'autre ne rattache l'avis à une autre réservation.
  if (new.booking_id, new.venue_id) is distinct from (old.booking_id, old.venue_id) then
    raise exception 'Un avis ne change pas de réservation.'
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

comment on function public.reviews_guard_actor() is
  'L''auteur écrit la note et le texte, le propriétaire écrit la réponse. Personne ne fait les deux (§5.4, §4.3).';

drop trigger if exists reviews_guard_actor on public.reviews;
create trigger reviews_guard_actor
  before update on public.reviews
  for each row execute function public.reviews_guard_actor();

-- -----------------------------------------------------------------------------
-- notifications
--
-- Chacun lit les siennes et les marque lues. Rien d'autre : une notification
-- naît de notify_user() (004), appelée par les fonctions de transition.
-- -----------------------------------------------------------------------------

drop policy if exists notifications_select_own on public.notifications;
create policy notifications_select_own
  on public.notifications for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists notifications_update_own on public.notifications;
create policy notifications_update_own
  on public.notifications for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists notifications_delete_own on public.notifications;
create policy notifications_delete_own
  on public.notifications for delete
  to authenticated
  using (user_id = auth.uid());

-- Marquer lu, et seulement cela. Sans ce trigger, la politique UPDATE
-- ci-dessus laisserait un utilisateur réécrire le type et la charge utile de sa
-- propre notification — donc l'écran vers lequel elle renvoie.
create or replace function public.notifications_guard_update()
returns trigger
language plpgsql
as $$
begin
  if (new.id, new.user_id, new.type, new.payload, new.created_at)
     is distinct from
     (old.id, old.user_id, old.type, old.payload, old.created_at) then
    raise exception 'Une notification ne se modifie pas : elle se marque lue.'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

comment on function public.notifications_guard_update() is
  'Seul read_at est modifiable par son destinataire.';

drop trigger if exists notifications_guard_update on public.notifications;
create trigger notifications_guard_update
  before update on public.notifications
  for each row execute function public.notifications_guard_update();

-- =============================================================================
-- LE TÉLÉPHONE
--
-- §9 : « Les numéros de téléphone ne sont révélés qu'après passage à accepted —
-- sinon la plateforme se fait contourner dès la première recherche. »
--
-- Ce n'est pas une règle d'affichage. Elle tient parce que profiles n'est
-- lisible que par son titulaire (002) : aucune requête cliente, aucune jointure,
-- aucune vue ne ramène le téléphone d'un tiers. La fonction ci-dessous est le
-- SEUL chemin, et elle ne s'ouvre qu'à partir de « accepted ».
--
-- Elle sert les deux sens : le client obtient le propriétaire, le propriétaire
-- obtient le client. Une seule fonction, une seule condition à maintenir.
--
-- Si un jour un écran doit afficher le nom d'un propriétaire avant réservation,
-- ce sera par une autre fonction, qui ne renverra pas le téléphone. Ne pas
-- élargir celle-ci.
-- =============================================================================

create or replace function public.booking_contact(p_booking_id uuid)
returns table (
  full_name        text,
  phone            text,
  phone_available  boolean,
  party            text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_booking  public.bookings%rowtype;
  v_owner_id uuid;
  v_is_owner boolean;
  v_other    uuid;
  v_open     boolean;
begin
  select b.* into v_booking from public.bookings b where b.id = p_booking_id;

  if v_booking.id is null then
    raise exception 'Réservation inconnue.' using errcode = 'no_data_found';
  end if;

  select v.owner_id into v_owner_id from public.venues v where v.id = v_booking.venue_id;

  v_is_owner := (v_owner_id = auth.uid());

  -- Un tiers n'apprend rien, pas même l'existence des deux parties.
  if not v_is_owner and v_booking.client_id <> auth.uid() then
    raise exception 'Cette réservation ne vous concerne pas.'
      using errcode = 'insufficient_privilege';
  end if;

  v_other := case when v_is_owner then v_booking.client_id else v_owner_id end;

  -- LA condition du §9. « pending » et « refused » n'ouvrent rien : c'est
  -- exactement le moment où la plateforme se ferait contourner.
  v_open := v_booking.status in ('accepted', 'confirmed', 'completed');

  return query
  select
    p.full_name,
    case when v_open then p.phone else null end,
    v_open,
    case when v_is_owner then 'client' else 'owner' end
  from public.profiles p
  where p.id = v_other;
end;
$$;

comment on function public.booking_contact(uuid) is
  'Coordonnées de l''autre partie d''une réservation. Le téléphone n''est révélé qu''à partir de « accepted » (§9). '
  'Seul chemin vers le téléphone d''un tiers : profiles reste fermée.';

revoke execute on function public.booking_contact(uuid) from public, anon;
grant execute on function public.booking_contact(uuid) to authenticated;
