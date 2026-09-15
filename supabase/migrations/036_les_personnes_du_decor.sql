-- =============================================================================
-- Ferha — 036_les_personnes_du_decor.sql
-- L'empreinte tient aussi les personnes (J26).
--
-- CE QUE CE FICHIER APPORTE
--
--   decor_profiles          l'empreinte des comptes de démonstration
--   capturer_le_decor()     élargie — rend une quatrième colonne, `personnes`
--   vider_le_decor()        élargie
--   menage_du_decor()       deux gestes de plus, et DEUX HORLOGES
--   etat_du_decor           `roles_detournes` a sa propre ligne
--
-- POURQUOI. La migration 035 remet en place ce qu'un visiteur fait aux
-- réservations, aux avis et aux dates bloquées. Elle ne voit pas ce qu'il fait
-- AUX PERSONNES. Deux dérives mesurées sur la base le 16 septembre 2026, que le
-- ménage horaire aurait gardées pour toujours :
--
--   * Amina portait is_owner = true, alors que seed/003 la déclare « cliente,
--     aucune salle ». « Entrer comme Amina (cliente) » ouvrait l'espace
--     propriétaire, et c'est ce drapeau qui lui avait ouvert le parcours de
--     publication — d'où la salle « salle reve » ;
--   * Amina portait locale = 'ar' au lieu de 'fr'. L'application s'ouvrait donc
--     EN ARABE, de droite à gauche, pour tout visiteur entrant comme elle —
--     locale_controller.dart écrit profiles.locale à chaque bascule de langue,
--     et cette trace suit le COMPTE, pas l'appareil.
--
-- Les deux ont été remises à la main le jour même, avant la première empreinte.
--
-- -----------------------------------------------------------------------------
-- LA DÉCISION DE CE FICHIER : DEUX HORLOGES, ET POURQUOI
--
-- 035 attend deux heures avant de toucher à quoi que ce soit, pour ne pas
-- effacer sous les yeux d'un visiteur ce qu'il vient de faire. La question
-- posée ici est : ce délai a-t-il un sens pour `is_owner` ?
--
-- NON, ET LA RAISON N'EST PAS « PERSONNE NE TRAVAILLE SUR SON RÔLE ». Elle est
-- plus simple : L'APPLICATION N'ÉCRIT JAMAIS CE CHAMP. Aucun écran ne le
-- touche ; 018_garde_privileges_profil l'interdit même explicitement, dans les
-- deux sens. `is_owner` n'est pas une saisie, c'est une CONSÉQUENCE : seule
-- creer_salle() (017) le lève, en même temps qu'elle insère une salle. Il n'y a
-- donc aucune modification en cours à protéger — le délai ne protégerait rien,
-- et pendant ce temps la promesse de l'écran d'accueil est fausse pour tout le
-- monde.
--
-- L'OBJECTION ÉTAIT LA BONNE, MAIS SA PRÉMISSE EST FAUSSE. Elle disait : un
-- visiteur lève is_owner en publiant une salle, cette salle attend deux heures
-- avant d'être effacée, donc remettre le drapeau tout de suite laisserait une
-- salle dont le propriétaire n'est plus déclaré propriétaire.
--
-- Or LE MÉNAGE N'EFFACE JAMAIS LES SALLES PUBLIÉES PAR UN VISITEUR — ni au bout
-- de deux heures, ni jamais. C'est le trou n° 2 de 035, documenté et non
-- traité ; c'est même pour cela que etat_du_decor les COMPTE. Seul
-- seed/002_reset_demo.sql les efface, et c'est un geste manuel.
--
-- L'état « une salle dont le propriétaire n'est pas déclaré propriétaire »
-- n'est donc pas transitoire pendant deux heures : IL EST DÉFINITIF, quelle que
-- soit la durée choisie. Attendre ne le répare pas, attendre le retarde.
--
-- ET CE QU'IL CASSE, CONCRÈTEMENT, EST PETIT ET CONNU :
--   * côté base, RIEN. owns_venue() (002) lit owner_id, jamais is_owner. Les
--     politiques RLS des salles, des photos, des dates bloquées, les fonctions
--     de l'espace propriétaire (014, 015, 016) et la politique Storage de 021
--     reposent toutes sur owner_id. Le propriétaire garde la maîtrise entière
--     de sa salle ;
--   * côté application, le bouton « Mes salles » disparaît de l'écran profil.
--     C'est tout, et profil_screen.dart le dit lui-même : « ce n'est PAS ce qui
--     protège le tableau de bord ». La salle devient inatteignable à la souris,
--     pas inaccessible.
--
-- C'est exactement ce que 018 décrit quand il refuse de baisser le drapeau
-- depuis l'application : « la salle resterait, et son propriétaire n'aurait
-- plus de chemin vers elle ». Ce fichier ne contredit pas 018 — 018 protège un
-- VRAI propriétaire contre un geste qu'il regretterait. Ici il n'y a pas de
-- vrai propriétaire : il y a un décor, une salle en brouillon que personne ne
-- voit, et une promesse d'accueil qui doit être vraie à chaque visite.
--
-- Entre « une salle en brouillon, invisible du catalogue, sans chemin depuis le
-- profil » et « tout visiteur entrant comme Amina atterrit dans l'espace
-- propriétaire », le second coûte infiniment plus cher. Le rôle se remet donc
-- SANS DÉLAI.
--
-- LE RESTE GARDE LE DÉLAI, et `locale` est la preuve qu'il sert : un visiteur
-- qui bascule en arabe pour regarder la mise en page de droite à gauche doit la
-- garder le temps de sa visite. Le nom, l'e-mail, le téléphone et la langue
-- sont des SAISIES ; le rôle est une conséquence. La ligne de partage est là.
--
-- LA SUITE NATURELLE, NON FAITE ICI : effacer aussi les salles qu'un visiteur
-- publie, ce qui ferait tomber d'accord le drapeau et les salles à tout moment.
-- C'est une décision de produit, pas une correction, et elle n'a pas été prise.
-- -----------------------------------------------------------------------------
--
-- LA RESTAURATION SE FAIT PAR UPDATE, JAMAIS PAR DELETE-INSERT, et c'est
-- structurel. profiles.id est référencé par bookings.client_id en RESTRICT, par
-- venues.owner_id et notifications.user_id en CASCADE. Effacer un profil pour
-- le réécrire emporterait ses salles et ses notifications, et échouerait sur la
-- moindre réservation. C'est la différence majeure avec la restauration des
-- réservations de 035, qui, elle, passe par un delete-insert.
--
-- UN PROFIL ABSENT N'EST PAS RECRÉÉ. S'il manque, c'est que le compte lui-même
-- a disparu, et seul seed/003 sait le reposer — avec son identité GoTrue.
--
-- CE FICHIER N'APPROCHE PAS auth.users. Mots de passe, e-mails de connexion et
-- identités GoTrue relèvent de seed/003, pas d'un ménage horaire.
--
-- phone_verified EST CAPTURÉ, bien qu'il ne soit pas dans la liste des cinq
-- champs. Ce n'est pas un élargissement : la contrainte
-- profiles_phone_verified_requires_phone (001) interdit un téléphone vérifié
-- sans téléphone. Restaurer `phone` à NULL en laissant phone_verified à vrai
-- ferait échouer la ligne — donc, silencieusement, toute la restauration.
--
-- LE GARDE-FOU DE 018 LAISSE PASSER : profiles_guard_privileges() rend la main
-- dès que auth.uid() est null, ce qui est le cas sous pg_cron. Le ménage peut
-- donc baisser is_owner, là où l'application ne le peut pas. C'est voulu des
-- deux côtés.
--
-- Rejouable : table `if not exists`, fonctions remplacées.
-- Dépend de : 001 (profiles), 018 (le garde-fou), 035 (l'empreinte et le ménage).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- L'empreinte des personnes
--
-- Aucune clé étrangère vers profiles, pour la même raison qu'en 035 : une
-- empreinte doit survivre à ce qu'elle décrit.
-- -----------------------------------------------------------------------------

create table if not exists public.decor_profiles (
  id             uuid primary key,
  full_name      text        not null,
  email          text        not null,
  phone          text,
  phone_verified boolean     not null,
  is_owner       boolean     not null,
  locale         text        not null,
  capturee_a     timestamptz not null default now()
);

comment on table public.decor_profiles is
  'Empreinte des comptes de démonstration (J26). Cinq champs que l''application '
  'laisse modifier, plus phone_verified que la contrainte lie à phone. Ni mot de '
  'passe ni identité GoTrue : cela relève de seed/003.';

alter table public.decor_profiles enable row level security;
revoke all on public.decor_profiles from anon, authenticated;

-- -----------------------------------------------------------------------------
-- capturer_le_decor — une quatrième colonne
--
-- La signature change, donc on remplace la fonction au lieu de la modifier :
-- `create or replace` ne sait pas changer un type de retour.
-- -----------------------------------------------------------------------------

drop function if exists public.capturer_le_decor();

create function public.capturer_le_decor()
returns table (reservations integer, avis integer, dates_bloquees integer,
               personnes integer)
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.decor_reviews;
  delete from public.decor_bookings;
  delete from public.decor_blackouts;
  delete from public.decor_profiles;

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

  return query select
    (select count(*)::integer from public.decor_bookings),
    (select count(*)::integer from public.decor_reviews),
    (select count(*)::integer from public.decor_blackouts),
    (select count(*)::integer from public.decor_profiles);
end;
$$;

comment on function public.capturer_le_decor() is
  'Fige le décor — réservations b0000000-…, leurs avis, les dates bloquées des salles '
  '5a11e000-… et les comptes d0000000-… — dans les quatre tables d''empreinte. À appeler '
  'au sortir de seed/004, et à ce moment-là seulement. Rôle de service.';

revoke execute on function public.capturer_le_decor() from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- vider_le_decor — les personnes partent aussi
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
end;
$$;

comment on function public.vider_le_decor() is
  'Efface l''empreinte, les quatre tables. Appelée par seed/002_reset_demo.sql. '
  'Rôle de service.';

revoke execute on function public.vider_le_decor() from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- menage_du_decor — deux gestes de plus, et deux horloges
--
-- La signature gagne deux sorties, donc on remplace la fonction. La tâche
-- pg_cron n'a pas à être reposée : elle appelle `select public.menage_du_decor();`
-- et résout le nom à l'exécution.
-- -----------------------------------------------------------------------------

drop function if exists public.menage_du_decor(interval);

create function public.menage_du_decor(
  p_delai                        interval default interval '2 hours',
  out reservations_de_visiteurs  integer,
  out avis_de_visiteurs          integer,
  out paiements_de_visiteurs     integer,
  out decor_remis                boolean,
  out dates_bloquees_retirees    integer,
  out dates_bloquees_reposees    integer,
  out notifications_purgees      integer,
  out roles_remis                integer,
  out profils_remis              integer
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
  reservations_de_visiteurs := 0;
  avis_de_visiteurs         := 0;
  paiements_de_visiteurs    := 0;
  decor_remis               := false;
  dates_bloquees_retirees   := 0;
  dates_bloquees_reposees   := 0;
  notifications_purgees     := 0;
  roles_remis               := 0;
  profils_remis             := 0;

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

end;
$$;

comment on function public.menage_du_decor(interval) is
  'Tâche pg_cron (J26) : efface ce qu''un visiteur a créé sur les salles de démonstration, '
  'remet le décor et les personnes tels que l''empreinte les décrit, resynchronise les dates '
  'bloquées et purge les notifications. Deux horloges : le rôle (is_owner) se remet sans '
  'délai, tout le reste attend p_delai. Sans empreinte, ne fait rien. Rôle de service.';

revoke execute on function public.menage_du_decor(interval) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- etat_du_decor — `roles_detournes` a sa propre ligne
--
-- ELLE EST SÉPARÉE DE `profils_detournes` PARCE QU'ELLE NE DIT PAS LA MÊME
-- CHOSE. Un nom changé est une salissure ; un rôle changé modifie CE QU'UN
-- VISITEUR VOIT EN ENTRANT. C'est le seul champ de profiles dont la dérive
-- change une porte, et il mérite qu'on le lise sans le chercher.
--
-- ON DÉPOSE LA VUE AVANT DE LA REFAIRE. `create or replace view` sait ajouter
-- une colonne à la FIN, jamais en insérer une au milieu : il refuse en disant
-- « cannot change name of view column ». Or `empreinte_personnes` a sa place à
-- côté des trois autres compteurs d'empreinte, et `roles_detournes` à côté des
-- autres écarts — une vue qu'on lit d'un coup d'œil ne range pas ses colonnes
-- par ordre d'ancienneté. Aucun code ne lit cette vue : la déposer ne casse
-- rien.
-- -----------------------------------------------------------------------------

drop view if exists public.etat_du_decor;

create view public.etat_du_decor as
select
  (select count(*) from public.decor_bookings)                              as empreinte_reservations,
  (select count(*) from public.decor_reviews)                               as empreinte_avis,
  (select count(*) from public.decor_blackouts)                             as empreinte_dates_bloquees,
  (select count(*) from public.decor_profiles)                              as empreinte_personnes,

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

  (select count(*) from public.notifications
    where user_id::text like 'd0000000-%')                                  as notifications_de_demonstration,

  (select count(*) from public.venues
    where owner_id::text like 'd0000000-%'
      and id::text not like '5a11e000-%')                                   as salles_publiees_par_un_visiteur;

comment on view public.etat_du_decor is
  'L''état de la démonstration en une ligne (J26). `demandes_en_attente` et '
  '`roles_detournes` sont les deux qui comptent : la première dit que le tableau de bord '
  'n''a rien à montrer, la seconde qu''« Entrer comme Amina (cliente) » ment. Les '
  'compteurs relatifs à l''empreinte valent NULL tant qu''elle est vide.';

revoke all on public.etat_du_decor from anon, authenticated;
