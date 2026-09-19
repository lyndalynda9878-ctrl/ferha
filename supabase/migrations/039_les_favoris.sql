-- =============================================================================
-- Ferha — 039_les_favoris.sql
-- L'onglet Favoris a enfin quelque chose à montrer (J28).
--
-- CE QUE CE FICHIER APPORTE
--
--   favorites               la personne, la salle, la date — et rien d'autre
--   mes_favoris()           les salles aimées, dans la forme d'une carte
--   decor_favorites         l'empreinte des trois favoris d'Amina
--   capturer_le_decor()     une cinquième colonne
--   menage_du_decor()       deux gestes de plus
--   etat_du_decor           deux colonnes de plus
--
-- POURQUOI MAINTENANT. L'onglet existe dans la barre du bas depuis le J10, sa
-- page est un gabarit vide, et aucun écran de l'application ne permet d'ajouter
-- un favori. C'est le dernier onglet mort de la coque.
--
-- =============================================================================
-- LE COMPORTEMENT À LA SUPPRESSION — L'ARGUMENT AVANT LE SQL
--
-- CLAUDE.md interdit de passer une clé en CASCADE pour faire passer une
-- suppression, et c'est une bonne règle : `bookings.client_id` et
-- `bookings.venue_id` sont en RESTRICT parce qu'une réservation est une TRACE
-- COMPTABLE, et que l'autre partie a le droit de retrouver ce qu'elle a vendu
-- ou acheté. Le RESTRICT est le filet qui force à écrire une anonymisation
-- plutôt qu'une suppression.
--
-- Les deux clés de `favorites` sont pourtant en CASCADE. Voici pourquoi, et la
-- règle n'est pas contournée : elle ne s'applique pas ici.
--
-- 1. UN FAVORI N'A QU'UNE SEULE PARTIE. Une réservation est un échange : il y a
--    un vendeur et un acheteur, et chacun peut venir demander ce qu'il a fait.
--    Un favori n'est connu que de la personne qui l'a posé. Le propriétaire de
--    la salle ne le voit pas — la RLS le lui interdit, et on a refusé exprès le
--    compteur « 12 personnes aiment cette salle ». Il n'existe donc AUCUN tiers
--    qui pourrait un jour venir réclamer cette ligne.
--
-- 2. ANONYMISER UN FAVORI NE CONSERVERAIT RIEN. C'est le test décisif, et il se
--    pose ainsi : que reste-t-il de lisible après l'anonymisation ? Pour une
--    réservation, beaucoup — « cette salle a été louée ce jour-là, pour ce
--    montant » reste vrai, reste utile, et reste dû au propriétaire. Pour un
--    favori, il reste « quelqu'un, un jour, a aimé cette salle » : une phrase
--    que PERSONNE ne peut lire, puisque le seul lecteur que la RLS désigne
--    jamais est le propriétaire de la ligne, et qu'il n'existe plus. Ce n'est
--    pas une trace préservée, c'est une ligne orpheline. La garder serait
--    conserver une donnée personnelle au-delà de la finalité qui la justifiait
--    — l'inverse de ce que demande la loi 18-07.
--
-- 3. ET SURTOUT : CETTE CASCADE NE DESSERRE PAS LE FILET D'UN MILLIMÈTRE. Le
--    filet, c'est `bookings.client_id` en RESTRICT, et il ne bouge pas. Une
--    suppression franche d'un profil qui a déjà réservé échoue toujours, et
--    elle échoue AVANT que la cascade des favoris ait la moindre occasion de
--    partir. Cette cascade ne peut donc s'exécuter que pour un profil sans
--    aucune réservation — c'est-à-dire exactement le cas où il n'y a aucun
--    historique comptable à protéger. On ne fait pas passer une suppression qui
--    était bloquée : on choisit le comportement d'une table neuve que rien n'a
--    jamais bloquée.
--
-- 4. UNE OBLIGATION QUE CETTE TABLE CRÉE, ET QU'IL FAUT ÉCRIRE ICI. Fermer un
--    compte, dans ce projet, c'est ANONYMISER : on remplace full_name, email et
--    phone, on ne supprime pas la ligne `profiles`. La cascade ne part donc
--    JAMAIS lors d'une fermeture de compte. La fonction d'anonymisation, le
--    jour où elle sera écrite, devra supprimer les favoris EXPLICITEMENT —
--    sans quoi un compte neutralisé garderait une liste de goûts attachée à une
--    personne qu'on peut encore identifier par ailleurs. Les favoris sont l'une
--    des rares choses de ce schéma qu'une fermeture de compte doit vraiment
--    effacer. C'est noté dans supabase/README.md, section « Fermeture de
--    compte ».
--
-- LA SALLE QUI DISPARAÎT — même raisonnement, plus court. Le contenu entier
-- d'un favori EST la salle : sans elle, il ne désigne plus rien, et l'onglet
-- afficherait une carte vide. Toutes les tables qui dépendent d'une salle
-- cascadent déjà — photos, tarifs, dates bloquées, équipements, avis ; la seule
-- qui résiste est `bookings.venue_id`, et elle résiste parce qu'elle enregistre
-- une VENTE. Un favori n'enregistre aucune vente.
--
-- =============================================================================
-- LA CLÉ PRIMAIRE PORTE LES DEUX COLONNES, ET C'EST LA BASE QUI DIT NON
--
-- Aimer deux fois la même salle ne crée pas deux lignes, et ce n'est pas un
-- test en Dart qui l'empêche : c'est `primary key (user_id, venue_id)`. Même
-- doctrine que l'index partiel qui rend la double réservation impossible (004).
-- Un double tap, deux onglets ouverts, une reprise de réseau qui rejoue la
-- requête — aucun de ces trois chemins ne passe.
--
-- AUCUNE POLITIQUE D'UPDATE, ET C'EST VOLONTAIRE. Un favori n'a rien à
-- modifier : il existe, ou il n'existe pas. Les deux seules colonnes qui le
-- composent sont sa clé. Une table sans politique d'UPDATE est fermée en
-- écriture pour tout le monde, ce qui est ici le bon défaut.
--
-- Dépend de : 001 (venues, profiles), 002 (can_read_venue), 005 (estimate_price),
--             035 et 036 (l'empreinte et le ménage), seed/001 pour les salles.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- La table
-- -----------------------------------------------------------------------------

create table if not exists public.favorites (
  user_id    uuid        not null references public.profiles (id) on delete cascade,
  venue_id   uuid        not null references public.venues   (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, venue_id)
);

comment on table public.favorites is
  'Les salles qu''une personne a mises de côté (J28). La clé primaire porte les deux '
  'colonnes : c''est la base qui rend le doublon impossible. Les deux clés étrangères '
  'sont en CASCADE — un favori n''a qu''une partie, n''enregistre aucune vente, et '
  'anonymisé ne conserverait rien de lisible par personne ; voir l''en-tête de 039.';

comment on column public.favorites.created_at is
  'Quand le cœur a été touché. C''est l''ordre de l''onglet Favoris — le dernier aimé '
  'en premier — et la borne de délai du ménage du décor.';

-- L'INDEX SUR venue_id EXISTE POUR LA CASCADE, PAS POUR UNE REQUÊTE. La clé
-- primaire indexe déjà (user_id, venue_id), donc « mes favoris » est couvert.
-- Une suppression de salle, elle, cherche par venue_id : sans cet index,
-- PostgreSQL relit toute la table à chaque salle supprimée.
create index if not exists favorites_venue_id_idx
  on public.favorites (venue_id);

-- -----------------------------------------------------------------------------
-- RLS — je lis, j'ajoute et je retire MES lignes, rien d'autre
-- -----------------------------------------------------------------------------

alter table public.favorites enable row level security;

drop policy if exists favorites_select_self on public.favorites;
create policy favorites_select_self
  on public.favorites for select
  to authenticated
  using (user_id = auth.uid());

-- ON N'AIME QUE CE QU'ON PEUT VOIR. `can_read_venue` (002) dit si la salle est
-- publiée, ou si c'est le brouillon de son propre propriétaire. Sans ce
-- contrôle, la table accepterait l'identifiant de n'importe quelle salle : un
-- inconnu pourrait y ranger des identifiants au hasard et apprendre lesquels
-- existent, ce qu'aucun autre écran ne lui dit.
drop policy if exists favorites_insert_self on public.favorites;
create policy favorites_insert_self
  on public.favorites for insert
  to authenticated
  with check (user_id = auth.uid() and public.can_read_venue(venue_id));

-- LE RETRAIT NE VÉRIFIE PAS LA SALLE, et c'est délibéré : une salle dépubliée
-- après coup laisserait sinon son favori collé pour toujours.
drop policy if exists favorites_delete_self on public.favorites;
create policy favorites_delete_self
  on public.favorites for delete
  to authenticated
  using (user_id = auth.uid());

-- Aucune politique d'UPDATE : voir l'en-tête.

-- -----------------------------------------------------------------------------
-- mes_favoris — les salles aimées, dans la forme exacte d'une carte
--
-- LES MÊMES DOUZE COLONNES QUE search_venues, ET DANS LE MÊME ORDRE. L'écran
-- Favoris réutilise la carte de l'accueil et des résultats, sans en redessiner
-- une : pour cela il lui faut exactement la même ligne. `VenueSummary` la lit
-- avec son constructeur habituel, et rien dans le Dart ne sait d'où elle vient.
--
-- `total_count` n'y est pas : la pagination est ce qui le justifiait, et un
-- onglet Favoris n'en a pas.
--
-- LE PRIX VIENT D'estimate_price(), COMME PARTOUT. Pas une seconde formule —
-- c'est la règle du projet. Il est calculé pour aujourd'hui, le soir, une
-- personne : ce sont les mêmes valeurs d'attente que l'accueil, où aucune date
-- n'est encore choisie. L'onglet Favoris ne porte AUCUNE date, et c'est un
-- choix assumé (voir README, « ce qui manque encore »).
--
-- SEULES LES SALLES PUBLIÉES SORTENT. Une salle dépubliée reste dans la table —
-- son propriétaire peut la republier — mais elle quitte l'onglet, parce qu'on
-- ne peut plus la visiter.
-- -----------------------------------------------------------------------------

create or replace function public.mes_favoris()
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
  review_count    bigint
)
language sql
stable
security definer
set search_path = public
as $$
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
    'soir'::text,
    vr.bayesian_rating,
    coalesce(vr.review_count, 0)

  from public.favorites f
  join public.venues v on v.id = f.venue_id

  cross join lateral public.estimate_price(
    v.id, current_date, 'soir', 1, '{}'::uuid[]
  ) e

  left join public.venue_ratings vr on vr.venue_id = v.id

  -- SECURITY DEFINER, DONC LE FILTRE EST ICI ET IL EST TOUT. La fonction
  -- contourne la RLS de `favorites` : sans cette ligne, elle rendrait les
  -- favoris de tout le monde. `auth.uid()` est null pour un visiteur non
  -- connecté, et null n'est égal à rien — la fonction rend alors zéro ligne,
  -- ce qui est la bonne réponse.
  where f.user_id = auth.uid()
    and v.status  = 'published'

  order by f.created_at desc, v.name asc;
$$;

comment on function public.mes_favoris() is
  'Les salles mises de côté par l''utilisateur courant (J28), dans la forme exacte '
  'd''une ligne de search_venues — l''onglet réutilise la même carte. Le prix vient '
  'd''estimate_price() pour aujourd''hui, le soir, une personne : l''onglet ne porte '
  'aucune date. Dernier aimé en premier.';

revoke execute on function public.mes_favoris() from public, anon;
grant  execute on function public.mes_favoris() to authenticated;

-- =============================================================================
-- LE DÉCOR — LA PARTIE QUI SE FAIT OUBLIER
--
-- LES FAVORIS SONT LA PREMIÈRE DONNÉE QUE LES VISITEURS VONT CRÉER SANS
-- FORMULAIRE. Envoyer une demande prend six écrans ; toucher un cœur prend un
-- doigt. Le chemin d'entrée de la démonstration est « Entrer comme Amina », en
-- un tap, sur un compte partagé : sans ce qui suit, dans une semaine l'onglet
-- Favoris d'Amina montrerait les salles de trente inconnus, et le gardien du
-- décor n'en saurait rien — il ne connaît pas cette table.
--
-- Trois gestes, donc, et ce sont ceux de 035 appliqués à une table de plus :
-- l'empreinte capture, le ménage remet, `etat_du_decor` le prouve.
--
-- ET « PROUVER » VEUT DIRE QUELQUE CHOSE DE PRÉCIS. Les deux colonnes ajoutées
-- à la vue ne disent pas que le ménage s'est exécuté — une tâche cron qui
-- tourne à vide s'exécute parfaitement. Elles disent si le décor est CONFORME :
-- combien de favoris l'empreinte porte, et combien de favoris de visiteurs
-- traînent en trop. Les deux doivent valoir 3 et 0.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- L'empreinte des favoris
--
-- Aucune clé étrangère, pour la même raison qu'en 035 et 036 : une empreinte
-- doit survivre à ce qu'elle décrit.
--
-- `created_at` EST DANS L'EMPREINTE, et ce n'est pas décoratif : c'est l'ordre
-- de l'onglet. Un favori reposé avec `now()` remonterait en tête de liste à
-- chaque ménage, et l'écran changerait d'ordre tout seul dans la nuit.
-- -----------------------------------------------------------------------------

create table if not exists public.decor_favorites (
  user_id    uuid        not null,
  venue_id   uuid        not null,
  created_at timestamptz not null,
  capturee_a timestamptz not null default now(),
  primary key (user_id, venue_id)
);

comment on table public.decor_favorites is
  'Empreinte des favoris des comptes de démonstration (J28). created_at en fait '
  'partie : c''est l''ordre d''affichage de l''onglet, et le reposer à now() le '
  'ferait changer tout seul.';

alter table public.decor_favorites enable row level security;
revoke all on public.decor_favorites from anon, authenticated;

-- -----------------------------------------------------------------------------
-- capturer_le_decor — une cinquième colonne
--
-- La signature change, donc on remplace la fonction : `create or replace` ne
-- sait pas changer un type de retour.
-- -----------------------------------------------------------------------------

drop function if exists public.capturer_le_decor();

create function public.capturer_le_decor()
returns table (reservations integer, avis integer, dates_bloquees integer,
               personnes integer, favoris integer)
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.decor_reviews;
  delete from public.decor_bookings;
  delete from public.decor_blackouts;
  delete from public.decor_profiles;
  delete from public.decor_favorites;

  insert into public.decor_bookings (
    id, group_id, venue_id, client_id, event_date, slot, requested_slot,
    guest_count, event_type, client_message, option_ids, status,
    option_expires_at, accepted_at, confirmed_at, completed_at,
    cancelled_at, cancelled_by, status_reason, created_at)
  select
    b.id, b.group_id, b.venue_id, b.client_id, b.event_date, b.slot, b.requested_slot,
    b.guest_count, b.event_type, b.client_message, b.option_ids, b.status,
    b.option_expires_at, b.accepted_at, b.confirmed_at, b.completed_at,
    b.cancelled_at, b.cancelled_by, b.status_reason, b.created_at
  from public.bookings b
  where b.id::text like 'b0000000-%';

  insert into public.decor_reviews (
    booking_id, venue_id, rating, rating_cleanliness, rating_service,
    rating_value, rating_accuracy, body, owner_reply, owner_replied_at, created_at)
  select
    r.booking_id, r.venue_id, r.rating, r.rating_cleanliness, r.rating_service,
    r.rating_value, r.rating_accuracy, r.body, r.owner_reply, r.owner_replied_at, r.created_at
  from public.reviews r
  where r.booking_id::text like 'b0000000-%';

  insert into public.decor_blackouts (venue_id, date, slot, reason)
  select vb.venue_id, vb.date, vb.slot, vb.reason
  from public.venue_blackouts vb
  where vb.venue_id::text like '5a11e000-%';

  insert into public.decor_profiles (
    id, full_name, email, phone, phone_verified, is_owner, locale)
  select p.id, p.full_name, p.email, p.phone, p.phone_verified, p.is_owner, p.locale
  from public.profiles p
  where p.id::text like 'd0000000-%';

  -- LES FAVORIS DES COMPTES DE DÉMONSTRATION, et eux seuls. Le critère est la
  -- personne — voir l'étape 6 du ménage.
  insert into public.decor_favorites (user_id, venue_id, created_at)
  select f.user_id, f.venue_id, f.created_at
  from public.favorites f
  where f.user_id::text like 'd0000000-%';

  return query select
    (select count(*)::integer from public.decor_bookings),
    (select count(*)::integer from public.decor_reviews),
    (select count(*)::integer from public.decor_blackouts),
    (select count(*)::integer from public.decor_profiles),
    (select count(*)::integer from public.decor_favorites);
end;
$$;

comment on function public.capturer_le_decor() is
  'Fige le décor — réservations b0000000-…, leurs avis, les dates bloquées des salles '
  '5a11e000-…, les comptes d0000000-… et leurs favoris — dans les cinq tables '
  'd''empreinte. À appeler au sortir de seed/004, et à ce moment-là seulement. '
  'Rôle de service.';

revoke execute on function public.capturer_le_decor() from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- vider_le_decor — les favoris partent aussi
-- -----------------------------------------------------------------------------

create or replace function public.vider_le_decor()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.decor_reviews;
  delete from public.decor_bookings;
  delete from public.decor_blackouts;
  delete from public.decor_profiles;
  delete from public.decor_favorites;
end;
$$;

comment on function public.vider_le_decor() is
  'Efface l''empreinte, les cinq tables. Appelée par seed/002_reset_demo.sql. '
  'Rôle de service.';

revoke execute on function public.vider_le_decor() from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- menage_du_decor — une sixième étape
--
-- La signature gagne deux sorties, donc on remplace la fonction. La tâche
-- pg_cron n'a pas à être reposée : elle appelle `select public.menage_du_decor();`
-- et résout le nom à l'exécution.
--
-- LES CINQ PREMIÈRES ÉTAPES SONT CELLES DE 036, MOT POUR MOT. Seule la sixième
-- est neuve.
-- -----------------------------------------------------------------------------

drop function if exists public.menage_du_decor(interval);
create function public.menage_du_decor(
  p_delai                          interval default interval '2 hours',
  out reservations_de_visiteurs    integer,
  out avis_de_visiteurs            integer,
  out paiements_de_visiteurs       integer,
  out decor_remis                  boolean,
  out dates_bloquees_retirees      integer,
  out dates_bloquees_reposees      integer,
  out notifications_purgees        integer,
  out roles_remis                  integer,
  out profils_remis                integer,
  out favoris_de_visiteurs_retires integer,
  out favoris_du_decor_reposes     integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_groupes           uuid[];
  v_ecarts            integer;
  v_derniere_retouche timestamptz;
begin
  reservations_de_visiteurs    := 0;
  avis_de_visiteurs            := 0;
  paiements_de_visiteurs       := 0;
  decor_remis                  := false;
  dates_bloquees_retirees      := 0;
  dates_bloquees_reposees      := 0;
  notifications_purgees        := 0;
  roles_remis                  := 0;
  profils_remis                := 0;
  favoris_de_visiteurs_retires := 0;
  favoris_du_decor_reposes     := 0;

  if not exists (select 1 from public.decor_bookings) then
    raise notice 'Aucune empreinte du décor : rien n''est touché. Lancez seed/004, '
                 'qui appelle capturer_le_decor(), ou appelez-la à la main.';
    return;
  end if;

  if not exists (select 1 from public.venues where id::text like '5a11e000-%') then
    raise notice 'Plus aucune salle de démonstration : empreinte périmée, rien n''est touché.';
    return;
  end if;

  -- ---------------------------------------------------------------------------
  -- 1. CE QU'UN VISITEUR A CRÉÉ — par groupe, et en premier (voir 035).
  -- ---------------------------------------------------------------------------

  select coalesce(array_agg(g.group_id), '{}'::uuid[])
    into v_groupes
  from (
    select b.group_id
    from public.bookings b
    where b.venue_id::text like '5a11e000-%'
      and b.id::text not like 'b0000000-%'
    group by b.group_id
    having max(b.created_at) < now() - p_delai
  ) g;

  if array_length(v_groupes, 1) is not null then
    delete from public.payments p
     using public.bookings b
     where p.booking_id = b.id
       and b.group_id = any (v_groupes);
    get diagnostics paiements_de_visiteurs = row_count;

    delete from public.reviews r
     using public.bookings b
     where r.booking_id = b.id
       and b.group_id = any (v_groupes);
    get diagnostics avis_de_visiteurs = row_count;

    delete from public.bookings b
     where b.group_id = any (v_groupes);
    get diagnostics reservations_de_visiteurs = row_count;
  end if;

  -- ---------------------------------------------------------------------------
  -- 2. CE QU'UN VISITEUR A DÉFAIT — le décor, comme en 035.
  -- ---------------------------------------------------------------------------

  select count(*), max(d.quand)
    into v_ecarts, v_derniere_retouche
  from (
    select b.updated_at as quand
    from public.bookings b
    join public.decor_bookings e on e.id = b.id
    where (b.venue_id, b.client_id, b.event_date, b.slot, b.requested_slot,
           b.guest_count, b.event_type, b.client_message, b.option_ids,
           b.status, b.option_expires_at, b.accepted_at, b.confirmed_at,
           b.completed_at, b.cancelled_at, b.cancelled_by, b.status_reason,
           b.created_at)
          is distinct from
          (e.venue_id, e.client_id, e.event_date, e.slot, e.requested_slot,
           e.guest_count, e.event_type, e.client_message, e.option_ids,
           e.status, e.option_expires_at, e.accepted_at, e.confirmed_at,
           e.completed_at, e.cancelled_at, e.cancelled_by, e.status_reason,
           e.created_at)

    union all

    select b.updated_at
    from public.bookings b
    where b.id::text like 'b0000000-%'
      and not exists (select 1 from public.decor_bookings e where e.id = b.id)

    union all

    select r.updated_at
    from public.reviews r
    left join public.decor_reviews e on e.booking_id = r.booking_id
    where r.booking_id::text like 'b0000000-%'
      and (e.booking_id is null
           or (r.venue_id, r.rating, r.rating_cleanliness, r.rating_service,
               r.rating_value, r.rating_accuracy, r.body, r.owner_reply, r.created_at)
              is distinct from
              (e.venue_id, e.rating, e.rating_cleanliness, e.rating_service,
               e.rating_value, e.rating_accuracy, e.body, e.owner_reply, e.created_at))

    union all

    select '-infinity'::timestamptz
    from public.decor_bookings e
    where not exists (select 1 from public.bookings b where b.id = e.id)

    union all

    select '-infinity'::timestamptz
    from public.decor_reviews e
    where not exists (select 1 from public.reviews r where r.booking_id = e.booking_id)
  ) d;

  if v_ecarts > 0 and v_derniere_retouche < now() - p_delai then
    begin
      delete from public.reviews  where booking_id::text like 'b0000000-%';

      delete from public.payments p
       using public.bookings b
       where p.booking_id = b.id
         and b.id::text like 'b0000000-%';

      delete from public.bookings where id::text like 'b0000000-%';

      insert into public.bookings (
        id, group_id, venue_id, client_id, event_date, slot, requested_slot,
        guest_count, event_type, client_message, option_ids,
        quoted_amount, created_at)
      select
        e.id, e.group_id, e.venue_id, e.client_id, e.event_date, e.slot, e.requested_slot,
        e.guest_count, e.event_type, e.client_message, e.option_ids,
        0, e.created_at
      from public.decor_bookings e;

      update public.bookings b
         set status            = e.status,
             option_expires_at = e.option_expires_at,
             accepted_at       = e.accepted_at,
             confirmed_at      = e.confirmed_at,
             completed_at      = e.completed_at,
             cancelled_at      = e.cancelled_at,
             cancelled_by      = e.cancelled_by,
             status_reason     = e.status_reason,
             deposit_amount    = case
                                   when e.accepted_at is not null
                                     or e.status in ('confirmed', 'completed')
                                   then round(b.quoted_amount * public.deposit_rate(), 2)
                                 end
        from public.decor_bookings e
       where e.id = b.id;

      insert into public.reviews (
        booking_id, venue_id, rating, rating_cleanliness, rating_service,
        rating_value, rating_accuracy, body, owner_reply, created_at)
      select
        e.booking_id, e.venue_id, e.rating, e.rating_cleanliness, e.rating_service,
        e.rating_value, e.rating_accuracy, e.body, e.owner_reply, e.created_at
      from public.decor_reviews e;

      update public.reviews r
         set owner_replied_at = e.owner_replied_at
        from public.decor_reviews e
       where e.booking_id = r.booking_id
         and e.owner_reply is not null;

      decor_remis := true;

    exception when others then
      raise notice 'Décor non remis cette fois (%) — la passe suivante réessaiera.', sqlerrm;
      decor_remis := false;
    end;
  end if;

  -- ---------------------------------------------------------------------------
  -- 3. LES DATES BLOQUÉES — comme en 035.
  -- ---------------------------------------------------------------------------

  delete from public.venue_blackouts vb
   where vb.venue_id::text like '5a11e000-%'
     and vb.created_at < now() - p_delai
     and not exists (
       select 1 from public.decor_blackouts e
        where e.venue_id = vb.venue_id and e.date = vb.date and e.slot = vb.slot);
  get diagnostics dates_bloquees_retirees = row_count;

  insert into public.venue_blackouts (venue_id, date, slot, reason)
  select e.venue_id, e.date, e.slot, e.reason
  from public.decor_blackouts e
  where not exists (
    select 1 from public.venue_blackouts vb
     where vb.venue_id = e.venue_id and vb.date = e.date and vb.slot = e.slot);
  get diagnostics dates_bloquees_reposees = row_count;

  update public.venue_blackouts vb
     set reason = e.reason
    from public.decor_blackouts e
   where vb.venue_id = e.venue_id and vb.date = e.date and vb.slot = e.slot
     and vb.reason is distinct from e.reason
     and vb.updated_at < now() - p_delai;

  -- ---------------------------------------------------------------------------
  -- 4. LES NOTIFICATIONS DES COMPTES DE DÉMONSTRATION — comme en 035.
  -- ---------------------------------------------------------------------------

  delete from public.notifications
   where user_id::text like 'd0000000-%'
     and created_at < now() - p_delai;
  get diagnostics notifications_purgees = row_count;

  -- ---------------------------------------------------------------------------
  -- 5. LES PERSONNES — deux horloges, et l'ordre compte
  --
  -- LES SAISIES D'ABORD, LE RÔLE ENSUITE, et ce n'est pas cosmétique : le
  -- trigger profiles_set_updated_at repositionne updated_at à chaque écriture.
  -- Remettre le rôle en premier rajeunirait la ligne et ferait échouer la
  -- condition de délai de l'instruction suivante — les saisies ne seraient
  -- jamais remises. L'ordre est le garde-fou.
  --
  -- UN SEUL BLOC D'EXCEPTION pour les deux : une collision sur l'index unique
  -- de l'e-mail, ou n'importe quel refus de contrainte, doit laisser les profils
  -- tels quels et laisser la passe suivante réessayer — plutôt qu'une tâche
  -- cron en erreur toutes les heures.
  -- ---------------------------------------------------------------------------

  begin
    -- 5a. CE QUI SE SAISIT — nom, e-mail, téléphone, langue. Un visiteur les
    --     modifie délibérément depuis l'écran profil : on attend le délai.
    --     phone_verified suit phone, parce que la contrainte les lie.
    update public.profiles p
       set full_name      = e.full_name,
           email          = e.email,
           phone          = e.phone,
           phone_verified = e.phone_verified,
           locale         = e.locale
      from public.decor_profiles e
     where e.id = p.id
       and p.updated_at < now() - p_delai
       and (p.full_name, p.email, p.phone, p.phone_verified, p.locale)
           is distinct from
           (e.full_name, e.email, e.phone, e.phone_verified, e.locale);
    get diagnostics profils_remis = row_count;

    -- 5b. CE QUI SE CONSTATE — le rôle. SANS DÉLAI : voir l'en-tête. Aucun
    --     écran ne l'écrit, il n'y a donc aucune saisie en cours à protéger, et
    --     tant qu'il est faux la promesse de l'écran d'accueil est fausse pour
    --     tout le monde.
    update public.profiles p
       set is_owner = e.is_owner
      from public.decor_profiles e
     where e.id = p.id
       and p.is_owner is distinct from e.is_owner;
    get diagnostics roles_remis = row_count;

  exception when others then
    raise notice 'Personnes non remises cette fois (%) — la passe suivante réessaiera.', sqlerrm;
  end;

  -- ---------------------------------------------------------------------------
  -- 6. LES FAVORIS — la table que ce ménage ne connaissait pas
  --
  -- LE CRITÈRE EST LA PERSONNE, ET NON LA SALLE. Pour une date bloquée, le
  -- décor se reconnaît à la salle : `venue_id like '5a11e000-%'`. Un favori
  -- n'appartient pas à une salle, il appartient à quelqu'un — donc c'est
  -- `user_id like 'd0000000-%'` qui trace la frontière du décor. Un favori posé
  -- par une VRAIE personne sur une salle de démonstration porte un identifiant
  -- tiré au sort : il n'est pas touché, exactement comme les notifications.
  --
  -- L'ORDRE EST LIBRE ICI, ET IL FAUT LE DIRE PLUTÔT QUE DE LE LAISSER CROIRE.
  -- Les deux ensembles sont disjoints par construction : on retire ce qui n'est
  -- PAS dans l'empreinte, on repose ce qui Y EST et manque. Aucun des deux ne
  -- peut défaire le travail de l'autre, dans un sens comme dans l'autre. La
  -- seule séquence qui compte pour cette table est ailleurs — l'insertion des
  -- favoris du décor doit précéder capturer_le_decor(), et c'est écrit au bas de
  -- ce fichier.
  --
  -- AUCUN BLOC D'EXCEPTION, contrairement aux personnes. Il n'y a ici ni index
  -- unique sur une colonne libre, ni contrainte croisée : la clé primaire porte
  -- les deux colonnes qu'on insère, et le `not exists` les a déjà écartées.
  -- ---------------------------------------------------------------------------

  delete from public.favorites f
   where f.user_id::text like 'd0000000-%'
     and f.created_at < now() - p_delai
     and not exists (
       select 1 from public.decor_favorites e
        where e.user_id = f.user_id and e.venue_id = f.venue_id);
  get diagnostics favoris_de_visiteurs_retires = row_count;

  -- ON REPOSE SANS DÉLAI, comme les dates bloquées. Un favori du décor qu'un
  -- visiteur a retiré est une absence, pas une saisie en cours : il n'y a
  -- aucune frappe à protéger, et l'onglet d'Amina doit cesser d'être vide à la
  -- première heure ronde.
  --
  -- La jointure sur `venues` garde la fonction honnête sur une base où une
  -- salle du décor aurait disparu : la clé étrangère refuserait l'insertion, et
  -- tout le ménage tomberait avec elle.
  insert into public.favorites (user_id, venue_id, created_at)
  select e.user_id, e.venue_id, e.created_at
  from public.decor_favorites e
  join public.venues v on v.id = e.venue_id
  where not exists (
    select 1 from public.favorites f
     where f.user_id = e.user_id and f.venue_id = e.venue_id);
  get diagnostics favoris_du_decor_reposes = row_count;

end;
$$;

comment on function public.menage_du_decor(interval) is
  'Tâche pg_cron (J26, étendue au J28) : efface ce qu''un visiteur a créé sur les salles '
  'de démonstration, remet le décor, les personnes et les favoris tels que l''empreinte '
  'les décrit, resynchronise les dates bloquées et purge les notifications. Deux '
  'horloges : le rôle (is_owner) et les favoris du décor se remettent sans délai, tout '
  'le reste attend p_delai. Sans empreinte, ne fait rien. Rôle de service.';

revoke execute on function public.menage_du_decor(interval) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- etat_du_decor — deux colonnes, et elles prouvent la CONFORMITÉ
--
-- `empreinte_favoris` va avec les autres compteurs d'empreinte, en tête ;
-- `favoris_de_visiteurs_en_trop` va avec les autres écarts. Aucune des deux ne
-- dit que le ménage a tourné : elles disent ce que la base contient en ce
-- moment. Une tâche cron morte laisse `favoris_de_visiteurs_en_trop` monter, et
-- c'est précisément ce qu'on veut lire.
--
-- ON DÉPOSE LA VUE AVANT DE LA REFAIRE, comme en 036 : `create or replace view`
-- sait ajouter une colonne à la FIN, jamais en insérer une au milieu. Aucun
-- code ne lit cette vue, la déposer ne casse rien.
-- -----------------------------------------------------------------------------

drop view if exists public.etat_du_decor;

create view public.etat_du_decor as
select
  (select count(*) from public.decor_bookings)                              as empreinte_reservations,
  (select count(*) from public.decor_reviews)                               as empreinte_avis,
  (select count(*) from public.decor_blackouts)                             as empreinte_dates_bloquees,
  (select count(*) from public.decor_profiles)                              as empreinte_personnes,
  (select count(*) from public.decor_favorites)                             as empreinte_favoris,

  (select count(*) from public.bookings b
    where b.venue_id::text like '5a11e000-%'
      and b.id::text not like 'b0000000-%')                                 as reservations_de_visiteurs,

  case when exists (select 1 from public.decor_bookings) then
    (select count(*) from public.bookings b
      join public.decor_bookings e on e.id = b.id
     where (b.status, b.accepted_at, b.confirmed_at, b.completed_at,
            b.cancelled_at, b.status_reason)
           is distinct from
           (e.status, e.accepted_at, e.confirmed_at, e.completed_at,
            e.cancelled_at, e.status_reason))
  end                                                                       as decor_detourne,

  case when exists (select 1 from public.decor_bookings) then
    (select count(*) from public.decor_bookings e
      where not exists (select 1 from public.bookings b where b.id = e.id))
  end                                                                       as decor_disparu,

  (select count(*) from public.bookings b
    where b.id::text like 'b0000000-%'
      and b.status = 'pending')                                             as demandes_en_attente,

  case when exists (select 1 from public.decor_bookings) then
    (select count(*) from public.venue_blackouts vb
      where vb.venue_id::text like '5a11e000-%'
        and not exists (select 1 from public.decor_blackouts e
                         where e.venue_id = vb.venue_id and e.date = vb.date
                           and e.slot = vb.slot))
  end                                                                       as dates_bloquees_en_trop,

  case when exists (select 1 from public.decor_bookings) then
    (select count(*) from public.decor_blackouts e
      where not exists (select 1 from public.venue_blackouts vb
                         where vb.venue_id = e.venue_id and vb.date = e.date
                           and vb.slot = e.slot))
  end                                                                       as dates_bloquees_manquantes,

  -- LE RÔLE, SEUL, PARCE QU'IL CHANGE UNE PORTE.
  case when exists (select 1 from public.decor_profiles) then
    (select count(*) from public.profiles p
      join public.decor_profiles e on e.id = p.id
     where p.is_owner is distinct from e.is_owner)
  end                                                                       as roles_detournes,

  case when exists (select 1 from public.decor_profiles) then
    (select count(*) from public.profiles p
      join public.decor_profiles e on e.id = p.id
     where (p.full_name, p.email, p.phone, p.phone_verified, p.locale)
           is distinct from
           (e.full_name, e.email, e.phone, e.phone_verified, e.locale))
  end                                                                       as profils_detournes,

  -- LES FAVORIS QU'UN VISITEUR A POSÉS SUR UN COMPTE DE DÉMONSTRATION. Le
  -- compagnon de `dates_bloquees_en_trop`, et il se lit pareil : 0, ou le
  -- ménage ne tourne plus.
  case when exists (select 1 from public.decor_favorites) then
    (select count(*) from public.favorites f
      where f.user_id::text like 'd0000000-%'
        and not exists (select 1 from public.decor_favorites e
                         where e.user_id = f.user_id and e.venue_id = f.venue_id))
  end                                                                       as favoris_de_visiteurs_en_trop,

  case when exists (select 1 from public.decor_favorites) then
    (select count(*) from public.decor_favorites e
      where not exists (select 1 from public.favorites f
                         where f.user_id = e.user_id and f.venue_id = e.venue_id))
  end                                                                       as favoris_du_decor_manquants,

  (select count(*) from public.notifications
    where user_id::text like 'd0000000-%')                                  as notifications_de_demonstration,

  (select count(*) from public.venues
    where owner_id::text like 'd0000000-%'
      and id::text not like '5a11e000-%')                                   as salles_publiees_par_un_visiteur;

comment on view public.etat_du_decor is
  'L''état de la démonstration en une ligne (J26, étendu au J28). `demandes_en_attente` '
  'et `roles_detournes` sont les deux qui comptent le plus : la première dit que le '
  'tableau de bord n''a rien à montrer, la seconde qu''« Entrer comme Amina (cliente) » '
  'ment. `favoris_de_visiteurs_en_trop` et `favoris_du_decor_manquants` disent la même '
  'chose de l''onglet Favoris. Les compteurs relatifs à l''empreinte valent NULL tant '
  'qu''elle est vide.';

revoke all on public.etat_du_decor from anon, authenticated;

-- =============================================================================
-- LES TROIS FAVORIS D'AMINA
--
-- POURQUOI ILS SONT ICI ET AUSSI DANS seed/004. Le seed les pose sur une base
-- neuve ; ce bloc les pose sur CELLE QUI TOURNE DÉJÀ, qui a été semée le
-- 8 septembre 2026 et qu'on ne resème pas. C'est exactement la situation de
-- 037_les_dates_bloquees_manquantes.sql, et la même réponse : les deux fichiers
-- racontent la même histoire, si l'un change l'autre doit changer.
--
-- L'ORDRE EST UN GARDE-FOU, PAS UNE PRÉFÉRENCE — la leçon de 037, et elle
-- s'applique mot pour mot :
--
--     menage_du_decor() EFFACE les favoris de comptes de démonstration absents
--     de l'empreinte.
--
-- Insérer ces trois lignes sans reprendre l'empreinte derrière, c'est les voir
-- disparaître à la première heure ronde passé le délai de deux heures — sans
-- message, sans erreur, et l'onglet Favoris redeviendrait vide tout seul dans
-- la nuit. INSERTION D'ABORD, EMPREINTE ENSUITE.
--
-- LE CHOIX DES TROIS SALLES. Trois wilayas différentes — Oran, Alger,
-- Constantine —, trois propriétaires différents, et trois capacités éloignées.
-- C'est ce qu'une famille met de côté : pas trois variantes de la même salle,
-- mais les trois candidates entre lesquelles elle hésite encore. Salle El Bahia
-- est celle qui porte les trois avis du décor, donc la seule dont la carte
-- montre une note — un onglet où aucune carte n'aurait d'étoiles ne montrerait
-- pas ce que la carte sait faire.
--
-- Les trois sont `published` : `favorites_insert_self` exige `can_read_venue`,
-- et `mes_favoris()` ne rend que les salles publiées. Espace Nour El Houda et
-- Salle El Wiam, qui sont en `pending`, n'avaient donc rien à faire ici.
--
-- LES DATES SONT FIXES, ET C'EST VOULU. `created_at` porte l'ordre de l'onglet ;
-- trois `now()` donneraient trois valeurs à la milliseconde près, différentes à
-- chaque base, et l'ordre des cartes ne serait pas reproductible d'une capture
-- à l'autre.
--
-- CE BLOC EST ADDITIF ET REJOUABLE : `on conflict do nothing`, aucune ligne
-- existante réécrite, aucune ligne effacée. Le lancer deux fois n'insère rien
-- la seconde fois.
-- =============================================================================

create temp table if not exists _favoris_declares (
  user_id    uuid        not null,
  venue_id   uuid        not null,
  created_at timestamptz not null,
  primary key (user_id, venue_id)
);

delete from _favoris_declares;

insert into _favoris_declares (user_id, venue_id, created_at) values
  -- Amina Haddad, cliente.
  ('d0000000-0000-4000-a000-000000000010',
   '5a11e000-0000-4000-a000-000000000001',   -- Salle El Bahia, Oran, 450, notée
   '2026-09-02 19:20+01'),
  ('d0000000-0000-4000-a000-000000000010',
   '5a11e000-0000-4000-a000-000000000004',   -- Palais Dar El Feth, Zéralda, 700
   '2026-09-05 21:05+01'),
  ('d0000000-0000-4000-a000-000000000010',
   '5a11e000-0000-4000-a000-000000000013',   -- Salle Les Ponts, Constantine, 400
   '2026-09-09 13:40+01');

create temp table if not exists _preuve_039 (
  declares   integer,
  avant      integer,
  inseres    integer,
  apres      integer,
  manquants  integer
);

delete from _preuve_039;

do $$
declare
  v_declares  integer;
  v_avant     integer;
  v_inseres   integer;
  v_apres     integer;
  v_manquants integer;
begin
  select count(*) into v_declares from _favoris_declares;

  select count(*) into v_avant
  from _favoris_declares d
  join public.favorites f
    on f.user_id = d.user_id and f.venue_id = d.venue_id;

  -- L'INSERTION. La jointure sur `profiles` et `venues` garantit qu'on ne pose
  -- que des lignes dont les deux bouts existent : ce fichier ne casse donc pas
  -- sur une base où les seeds n'ont jamais tourné, il n'y insère simplement
  -- rien.
  insert into public.favorites (user_id, venue_id, created_at)
  select d.user_id, d.venue_id, d.created_at
  from _favoris_declares d
  join public.profiles p on p.id = d.user_id
  join public.venues   v on v.id = d.venue_id
  on conflict (user_id, venue_id) do nothing;

  get diagnostics v_inseres = row_count;

  -- L'EMPREINTE, APRÈS L'INSERTION ET JAMAIS AVANT. Voir l'en-tête de ce bloc.
  --
  -- On ne la reprend que si elle existe déjà. Une empreinte vide veut dire que
  -- personne n'a encore capturé le décor ; la remplir depuis une migration
  -- serait prendre une décision qui appartient à seed/004.
  if exists (select 1 from public.decor_bookings) then
    perform public.capturer_le_decor();
    raise notice 'Empreinte du décor reprise après l''insertion des favoris.';
  else
    raise notice 'Pas d''empreinte en place : rien à reprendre. Lancez seed/004 le moment venu.';
  end if;

  select count(*) into v_apres
  from _favoris_declares d
  join public.favorites f
    on f.user_id = d.user_id and f.venue_id = d.venue_id;

  select count(*) into v_manquants
  from _favoris_declares d
  where not exists (
    select 1 from public.favorites f
     where f.user_id = d.user_id and f.venue_id = d.venue_id);

  insert into _preuve_039 (declares, avant, inseres, apres, manquants)
  values (v_declares, v_avant, v_inseres, v_apres, v_manquants);

  raise notice 'Favoris déclarés : %. En base avant : %. Insérés : %. En base après : %. Encore manquants : %.',
    v_declares, v_avant, v_inseres, v_apres, v_manquants;
end $$;

-- -----------------------------------------------------------------------------
-- Le bloc de preuve. `manquants` doit valoir 0, `apres` doit valoir 3.
-- -----------------------------------------------------------------------------

select declares, avant, inseres, apres, manquants from _preuve_039;
