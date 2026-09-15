-- =============================================================================
-- Ferha — 035_le_decor_se_remet_en_place.sql
-- La démonstration se répare toute seule entre deux visiteurs (J26).
--
-- CE QUE CE FICHIER APPORTE
--
--   decor_bookings, decor_reviews, decor_blackouts   l'empreinte du décor
--   capturer_le_decor()     fige le décor tel que les seeds viennent de le poser
--   menage_du_decor()       efface ce qu'un visiteur a fait, remet le décor
--   etat_du_decor           une ligne qui dit ce qui est sale en ce moment
--   ferha-menage-du-decor   la tâche pg_cron, toutes les heures
--
-- POURQUOI. Le chemin d'entrée de la démonstration est « Entrer comme Amina »
-- ou « Entrer comme Karim », en un tap, sans créer de compte : c'est le seul
-- praticable pour quelqu'un qui teste dix minutes. Tout ce qu'un visiteur fait
-- est donc fait AU NOM DES COMPTES DE DÉMONSTRATION, et reste après lui.
--
-- Mesuré sur la base le 16 septembre 2026, avant ce fichier : 19 réservations
-- de visiteurs sur les salles du décor, 3 paiements, 4 dates bloquées de plus,
-- 45 notifications — et surtout, LES CINQ DEMANDES EN ATTENTE DU DÉCOR AVAIENT
-- DISPARU : deux refusées, deux annulées, une expirée. Le tableau de bord de
-- l'écran 9 n'avait plus rien à montrer. C'est le vrai dégât, et il est muet :
-- rien n'a cassé, il n'y a simplement plus rien à voir.
--
-- LE CRITÈRE N'EST PAS « QUI », C'EST « QUOI ». Distinguer les réservations par
-- leur compte ne marche pas : un visiteur EST Amina. Ce qui se distingue, c'est
-- le décor de ce qui est arrivé après, et le décor se reconnaît à ses
-- identifiants — `b0000000-…` pour une réservation, `5a11e000-…` pour une
-- salle, `d0000000-…` pour une personne. On n'invente rien : c'est déjà la
-- convention de seed/002_reset_demo.sql et seed/004_demo_bookings.sql, posée
-- exprès. Une réservation créée depuis l'application passe par
-- request_booking(), donc par le `default gen_random_uuid()` de bookings.id :
-- elle ne peut pas porter ce préfixe.
--
-- SUPPRIMER NE SUFFIT PAS, IL FAUT REMETTRE. Un visiteur entré comme Karim qui
-- refuse une demande du décor ne crée rien : il vide. Au bout de cinq visiteurs
-- la file est vide et aucun ménage par suppression ne la rendra. Ce fichier
-- remet donc le décor en place autant qu'il efface.
--
-- POURQUOI UNE EMPREINTE, ET NON « REJOUER 004 ». seed/004_demo_bookings.sql
-- est rejouable — il le dit, et c'est vrai — mais c'est un FICHIER, et pg_cron
-- ne lit pas le dépôt. Recopier ses 24 lignes ici en ferait une seconde source
-- de vérité, qui divergerait au premier changement. On capture donc le RÉSULTAT
-- des seeds une fois, dans trois tables, et le ménage restaure depuis elles.
-- 004 reste le seul endroit où le décor est décrit.
--
-- LE PRIX NE FAIT PAS PARTIE DE L'EMPREINTE, et c'est la règle du projet : la
-- restauration réinsère les lignes, le trigger bookings_set_price (005) écrit
-- quoted_amount depuis estimate_price(), et l'acompte s'en déduit par
-- deposit_rate() (012) — exactement comme fait 004. Aucun montant n'est recopié
-- d'une table à l'autre, et un décor restauré après un changement de tarif
-- porte le tarif du jour.
--
-- LA BORNE DES 2 HEURES. Rien n'est touché avant deux heures : ni une
-- réservation de visiteur, ni une retouche du décor. Un visiteur qui teste dix
-- minutes garde ce qu'il vient de faire sous les yeux ; deux heures plus tard,
-- il est parti.
--
-- LE PARAMÈTRE p_delai EXISTE POUR LE BANC D'ESSAI, ET CELUI-CI LUI PASSE UNE
-- VALEUR NÉGATIVE, pas zéro. La raison mérite d'être écrite : dans une
-- transaction unique, now() ne bouge pas. Les lignes que le test vient d'écrire
-- portent donc updated_at = now() exactement, et `updated_at < now() -
-- interval '0'` est faux — rien ne serait jamais éligible. `interval '-1 hour'`
-- décale la borne dans l'autre sens et rend éligible ce qui vient d'être fait.
-- En production la question ne se pose pas : ce qu'un visiteur a touché
-- appartient à une transaction antérieure.
--
-- SANS EMPREINTE, LE MÉNAGE NE FAIT RIEN. C'est le garde-fou principal : cette
-- migration s'installe inerte. Tant que personne n'a appelé capturer_le_decor()
-- en connaissance de cause, la tâche tourne à vide et ne supprime rien.
--
-- -----------------------------------------------------------------------------
-- DEUX TROUS CONNUS, DOCUMENTÉS ET NON TRAITÉS
--
-- 1. UNE VRAIE PERSONNE QUI RÉSERVERAIT UNE SALLE DE DÉMONSTRATION verrait sa
--    réservation effacée. Son identifiant est aléatoire, comme celui d'un
--    visiteur : rien ne les distingue. Toutes les salles du catalogue sont
--    aujourd'hui de démonstration, donc le risque est maximal — mais ce dépôt
--    est une pièce de portfolio et il n'y a pas de vraies réservations. À
--    revoir le jour où il y en aurait. C'est aussi pourquoi le ménage se borne
--    à `venue_id like '5a11e000-%'` : une salle sans ce préfixe n'est pas du
--    décor, et ce qui s'y passe ne nous regarde pas.
--
-- 2. UNE SALLE PUBLIÉE PAR UN VISITEUR ENTRÉ COMME KARIM porte un identifiant
--    aléatoire : seed/002_reset_demo.sql ne la voit pas et échouera à supprimer
--    le profil de Karim. C'est le même trou, un cran plus loin. Il y en a trois
--    sur la base au 16 septembre 2026. Ce fichier n'y touche pas.
--
-- Et un chantier à part, noté ici pour ne pas l'oublier : EMPÊCHER LES COMPTES
-- DE DÉMONSTRATION DE RÉSERVER HORS DU DÉCOR. Ce serait l'autre moitié du
-- problème — une demande d'Amina sur la salle d'un vrai propriétaire resterait
-- à vie, et le ménage ne doit pas y toucher. Ce n'est pas ce fichier.
-- -----------------------------------------------------------------------------
--
-- CE QUE LE MÉNAGE TOUCHE, DANS L'ORDRE, ET POURQUOI CET ORDRE :
--   1. les réservations de visiteurs, avec leurs paiements et leurs avis —
--      D'ABORD, parce qu'une réservation de visiteur confirmée sur un créneau
--      du décor ferait échouer la réinsertion sur uniq_booking_slot ;
--   2. le décor, remis depuis l'empreinte s'il a bougé ;
--   3. les dates bloquées des salles du décor, resynchronisées ;
--   4. les notifications des comptes de démonstration.
--
-- LE POINT 4 N'ÉTAIT PAS DEMANDÉ. Il est là parce que le décor n'en pose
-- aucune — 004 écrit les états directement, sans passer par notify_user() —
-- donc TOUTE notification d'un compte de démonstration vient d'un visiteur, et
-- sans elle la cloche de la démonstration accumule indéfiniment. Une ligne à
-- retirer si tu préfères la laisser dehors.
--
-- Rejouable : tables `if not exists`, fonctions remplacées, tâche décrochée
-- avant d'être reposée.
-- Dépend de : migrations 001 à 034, et de seed/001 + 003 + 004 pour avoir
-- quelque chose à capturer.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- L'empreinte du décor
--
-- TROIS TABLES SANS AUCUNE CLÉ ÉTRANGÈRE. C'est délibéré : l'empreinte doit
-- survivre à la disparition de ce qu'elle décrit — c'est même sa seule raison
-- d'être. Une clé vers bookings la ferait tomber avec lui.
--
-- LES COLONNES SONT NOMMÉES UNE PAR UNE, et non copiées par `create table as`.
-- Le jour où bookings gagne une colonne, l'empreinte ne la connaîtra pas et la
-- restauration la laissera à sa valeur par défaut : dégradé, mais lisible. Un
-- `select *` figé, lui, aurait cassé la comparaison de lignes sans prévenir.
--
-- quoted_amount ET deposit_amount N'Y SONT PAS : ils se recalculent (voir
-- l'en-tête). Les y mettre serait recopier un prix, ce que le projet interdit.
-- updated_at non plus : c'est une conséquence, pas une description.
-- -----------------------------------------------------------------------------

create table if not exists public.decor_bookings (
  id                uuid primary key,
  group_id          uuid           not null,
  venue_id          uuid           not null,
  client_id         uuid           not null,
  event_date        date           not null,
  slot              text           not null,
  requested_slot    text           not null,
  guest_count       integer        not null,
  event_type        text,
  client_message    text,
  option_ids        uuid[]         not null default '{}',
  status            text           not null,
  option_expires_at timestamptz,
  accepted_at       timestamptz,
  confirmed_at      timestamptz,
  completed_at      timestamptz,
  cancelled_at      timestamptz,
  cancelled_by      uuid,
  status_reason     text,
  created_at        timestamptz    not null,
  capturee_a        timestamptz    not null default now()
);

comment on table public.decor_bookings is
  'Empreinte des réservations du décor (J26), figée par capturer_le_decor() au sortir '
  'de seed/004. Aucune clé étrangère : elle doit survivre à ce qu''elle décrit. Ni prix '
  'ni acompte — ils se recalculent à la restauration.';

create table if not exists public.decor_reviews (
  booking_id         uuid primary key,
  venue_id           uuid     not null,
  rating             smallint not null,
  rating_cleanliness smallint,
  rating_service     smallint,
  rating_value       smallint,
  rating_accuracy    smallint,
  body               text,
  owner_reply        text,
  owner_replied_at   timestamptz,
  created_at         timestamptz not null,
  capturee_a         timestamptz not null default now()
);

comment on table public.decor_reviews is
  'Empreinte des avis du décor (J26). booking_group_id n''y est pas : reviews_guard (004) '
  'le renseigne lui-même à la réinsertion, et c''est lui qui garantit un avis par événement.';

-- La clé naturelle est (venue_id, date, slot) — celle de l'unique de 001 — et
-- non l'identifiant : les dates bloquées du décor sont posées par seed/001 avec
-- des identifiants tirés au sort, qui ne se reproduisent pas d'un seed à
-- l'autre. C'est la raison pour laquelle le préfixe ne suffisait pas ici.
create table if not exists public.decor_blackouts (
  venue_id   uuid not null,
  date       date not null,
  slot       text not null,
  reason     text,
  capturee_a timestamptz not null default now(),
  primary key (venue_id, date, slot)
);

comment on table public.decor_blackouts is
  'Empreinte des dates bloquées des salles du décor (J26). Clé naturelle (venue_id, date, '
  'slot) : les identifiants de venue_blackouts sont tirés au sort par seed/001 et ne '
  'servent à rien ici.';

-- CES TABLES NE REGARDENT QUE L'EXPLOITATION. RLS active, aucune politique :
-- personne ne lit, pas même un compte connecté. Le rôle de service passe outre,
-- et il est le seul à en avoir besoin. Même choix qu'en 034.
alter table public.decor_bookings  enable row level security;
alter table public.decor_reviews   enable row level security;
alter table public.decor_blackouts enable row level security;

revoke all on public.decor_bookings  from anon, authenticated;
revoke all on public.decor_reviews   from anon, authenticated;
revoke all on public.decor_blackouts from anon, authenticated;

-- -----------------------------------------------------------------------------
-- capturer_le_decor — figer ce que les seeds viennent de poser
--
-- À APPELER JUSTE APRÈS seed/004_demo_bookings.sql, et à ce moment-là
-- seulement. Capturer un décor déjà abîmé fige le dégât : le ménage remettrait
-- alors fidèlement en place une file d'attente vide.
--
-- seed/004 l'appelle en dernière instruction, pour qu'on n'ait pas à y penser.
-- Les dates bloquées viennent de seed/001, qui tourne avant : à la fin de 004,
-- tout est là.
-- -----------------------------------------------------------------------------

create or replace function public.capturer_le_decor()
returns table (reservations integer, avis integer, dates_bloquees integer)
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.decor_reviews;
  delete from public.decor_bookings;
  delete from public.decor_blackouts;

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

  return query select
    (select count(*)::integer from public.decor_bookings),
    (select count(*)::integer from public.decor_reviews),
    (select count(*)::integer from public.decor_blackouts);
end;
$$;

comment on function public.capturer_le_decor() is
  'Fige le décor (réservations b0000000-…, leurs avis, les dates bloquées des salles '
  '5a11e000-…) dans les trois tables d''empreinte. À appeler au sortir de seed/004, et '
  'à ce moment-là seulement : capturer un décor abîmé fige le dégât. Rôle de service.';

revoke execute on function public.capturer_le_decor() from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- vider_le_decor — l'empreinte n'a plus d'objet
--
-- seed/002_reset_demo.sql l'appelle : après lui, les salles du décor n'existent
-- plus, et une empreinte qui leur survit ferait tenter au ménage d'insérer des
-- réservations vers des salles supprimées — une violation de clé étrangère
-- toutes les heures, dans les journaux, pour rien.
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
end;
$$;

comment on function public.vider_le_decor() is
  'Efface l''empreinte. Appelée par seed/002_reset_demo.sql : sans elle, le ménage '
  'tenterait de restaurer un décor sur des salles supprimées. Rôle de service.';

revoke execute on function public.vider_le_decor() from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- menage_du_decor — effacer ce qui est arrivé après, remettre ce qui manque
-- -----------------------------------------------------------------------------

create or replace function public.menage_du_decor(
  p_delai                        interval default interval '2 hours',
  out reservations_de_visiteurs  integer,
  out avis_de_visiteurs          integer,
  out paiements_de_visiteurs     integer,
  out decor_remis                boolean,
  out dates_bloquees_retirees    integer,
  out dates_bloquees_reposees    integer,
  out notifications_purgees      integer
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

  -- 0. SANS EMPREINTE, ON NE FAIT RIEN — ni ménage, ni restauration. Une
  --    empreinte vide ne veut pas dire « le décor est vide », elle veut dire
  --    « personne ne m'a dit à quoi il ressemble ». Supprimer sur cette base-là
  --    serait exactement l'erreur que ce fichier cherche à éviter.
  if not exists (select 1 from public.decor_bookings) then
    raise notice 'Aucune empreinte du décor : rien n''est touché. Lancez seed/004, '
                 'qui appelle capturer_le_decor(), ou appelez-la à la main.';
    return;
  end if;

  -- Et si les salles du décor ont disparu, l'empreinte est périmée : même
  -- prudence. seed/002 appelle vider_le_decor(), mais on ne parie pas dessus.
  if not exists (select 1 from public.venues where id::text like '5a11e000-%') then
    raise notice 'Plus aucune salle de démonstration : empreinte périmée, rien n''est touché.';
    return;
  end if;

  -- ---------------------------------------------------------------------------
  -- 1. CE QU'UN VISITEUR A CRÉÉ
  --
  -- Sur les salles du décor, une réservation dont l'identifiant ne porte pas le
  -- préfixe vient de request_booking(), donc d'un visiteur — quel que soit le
  -- compte, Amina comprise.
  --
  -- ON SUPPRIME PAR GROUPE, jamais par ligne : une journée entière, ce sont
  -- deux lignes (§6.1), et n'en effacer qu'une laisserait une demi-journée
  -- vendue. Les deux lignes d'un groupe naissent dans la même instruction et
  -- portent donc le même created_at ; le `max` ci-dessous ne fait que rendre la
  -- règle explicite.
  --
  -- C'EST LA PREMIÈRE ÉTAPE ET CE N'EST PAS UN HASARD : une réservation de
  -- visiteur confirmée sur un créneau que le décor occupe ferait échouer la
  -- réinsertion de l'étape 2 sur uniq_booking_slot.
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
    -- Les filles d'abord : payments.booking_id et reviews.booking_id sont en
    -- RESTRICT (004), et c'est voulu — une trace comptable ne s'efface pas dans
    -- le dos de son client. Ici on l'efface en connaissance de cause, en la
    -- nommant.
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
  -- 2. CE QU'UN VISITEUR A DÉFAIT
  --
  -- Le décor a-t-il bougé ? On compare ligne à ligne avec l'empreinte, sur les
  -- colonnes qui le DÉCRIVENT. Pas quoted_amount ni deposit_amount : ils se
  -- recalculent à la restauration, et les comparer ferait boucler le ménage au
  -- premier changement de tarif — il restaurerait sans fin un écart qu'il vient
  -- lui-même de créer. Pas updated_at non plus, qui bouge à chaque
  -- restauration.
  --
  -- ET QUAND A-T-IL BOUGÉ ? updated_at de la ligne fautive. Attention au piège :
  -- toutes les lignes du décor ont un updated_at postérieur à leur created_at,
  -- parce que 004 les insère puis les met à jour pour poser leur état. Comparer
  -- ces deux colonnes ne dit donc RIEN ; seule la comparaison à l'empreinte dit
  -- quelque chose.
  -- ---------------------------------------------------------------------------

  select count(*), max(d.quand)
    into v_ecarts, v_derniere_retouche
  from (
    -- une ligne du décor qui ne correspond plus
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

    -- une ligne en trop sous le préfixe du décor
    select b.updated_at
    from public.bookings b
    where b.id::text like 'b0000000-%'
      and not exists (select 1 from public.decor_bookings e where e.id = b.id)

    union all

    -- un avis du décor qui ne correspond plus, ou en trop
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

    -- une ligne disparue : on ne sait pas quand, et c'est le cas le plus grave
    -- — une demande en attente supprimée ne laisse aucune trace de sa date. On
    -- la traite comme infiniment ancienne, donc toujours éligible.
    select '-infinity'::timestamptz
    from public.decor_bookings e
    where not exists (select 1 from public.bookings b where b.id = e.id)

    union all

    select '-infinity'::timestamptz
    from public.decor_reviews e
    where not exists (select 1 from public.reviews r where r.booking_id = e.booking_id)
  ) d;

  if v_ecarts > 0 and v_derniere_retouche < now() - p_delai then
    -- LE BLOC D'EXCEPTION EST UNE SOUS-TRANSACTION, et c'est pour cela qu'il est
    -- là : si la réinsertion butait sur un créneau qu'une réservation de
    -- visiteur trop récente occupe encore, tout ce bloc est annulé — le décor
    -- reste tel qu'il était, abîmé mais entier — et la passe suivante
    -- réessaiera, la réservation gênante ayant alors dépassé le délai. Sans
    -- cela, une tâche cron en erreur toutes les heures, et un décor à moitié
    -- effacé.
    begin
      delete from public.reviews  where booking_id::text like 'b0000000-%';

      delete from public.payments p
       using public.bookings b
       where p.booking_id = b.id
         and b.id::text like 'b0000000-%';

      delete from public.bookings where id::text like 'b0000000-%';

      -- TOUT NAÎT EN ATTENTE, comme dans 004 et pour la même raison : la
      -- contrainte bookings_confirmed_requires_deposit interdit d'insérer une
      -- réservation confirmée sans acompte, et l'acompte se déduit du devis, que
      -- le trigger ne pose qu'une fois la ligne écrite.
      --
      -- EN UNE SEULE INSTRUCTION : bookings_check_journee (005) est un trigger
      -- d'instruction et exige les deux lignes d'une journée ensemble.
      --
      -- quoted_amount vaut 0 et sera écrasé par bookings_set_price, donc par
      -- estimate_price(). C'est le seul chemin d'un prix dans ce projet.
      insert into public.bookings (
        id, group_id, venue_id, client_id, event_date, slot, requested_slot,
        guest_count, event_type, client_message, option_ids,
        quoted_amount, created_at)
      select
        e.id, e.group_id, e.venue_id, e.client_id, e.event_date, e.slot, e.requested_slot,
        e.guest_count, e.event_type, e.client_message, e.option_ids,
        0, e.created_at
      from public.decor_bookings e;

      -- L'état d'arrivée et son acompte, en une instruction — comme 004, et
      -- pour l'acompte avec UNE CONDITION DE PLUS QUE LUI. 004 écrit un acompte
      -- « quand accepted_at est renseigné », ce qui suffit à ses 24 lignes,
      -- qu'il pose lui-même. Le décor réel, lui, en contient une qui n'est pas
      -- de 004 : b…0099, honorée sans jamais avoir été acceptée, posée à la main
      -- le 13 septembre 2026 pour éprouver les avis. Sur elle, la règle de 004
      -- rendait un acompte nul, et bookings_confirmed_requires_deposit refusait
      -- la ligne — donc la restauration entière, silencieusement, par le bloc
      -- d'exception ci-dessus. Le banc d'essai l'a attrapée ; sans lui, le décor
      -- ne se serait jamais remis et rien n'aurait crié.
      --
      -- La condition est donc celle de 004 OU celle de la contrainte : un état
      -- confirmé ou honoré exige un acompte, quelle que soit la façon dont la
      -- ligne y est arrivée. deposit_rate() reste le seul endroit où le taux est
      -- écrit, et quoted_amount est relu tel que le trigger vient de le poser.
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

      -- booking_group_id n'est pas écrit : reviews_guard (004) le renseigne, et
      -- c'est lui qui garantit un seul avis par événement.
      insert into public.reviews (
        booking_id, venue_id, rating, rating_cleanliness, rating_service,
        rating_value, rating_accuracy, body, owner_reply, created_at)
      select
        e.booking_id, e.venue_id, e.rating, e.rating_cleanliness, e.rating_service,
        e.rating_value, e.rating_accuracy, e.body, e.owner_reply, e.created_at
      from public.decor_reviews e;

      -- reviews_guard horodate la réponse du propriétaire à l'insertion : on
      -- lui rend sa date d'origine. Le même trigger, en UPDATE, ne la réécrit
      -- pas — la réponse n'a pas changé. Aucun avis du décor n'en porte
      -- aujourd'hui ; cette ligne existe pour le jour où l'un en portera.
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
  -- 3. LES DATES BLOQUÉES
  --
  -- Même geste, même risque : un visiteur entré comme Karim ferme des dates
  -- dans son agenda, et elles resteraient à vie. Le préfixe ne sert à rien ici —
  -- venue_blackouts.id est tiré au sort, y compris pour le décor — d'où la clé
  -- naturelle (venue_id, date, slot).
  --
  -- ASYMÉTRIE ASSUMÉE : ce qu'un visiteur AJOUTE attend le délai avant d'être
  -- retiré, ce qu'il SUPPRIME est reposé tout de suite. Une ligne effacée ne
  -- laisse pas la date de son effacement ; attendre voudrait dire ne jamais
  -- remettre. Un visiteur qui débloque une date la voit donc rebloquée dans
  -- l'heure.
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

  -- Le motif est interne au propriétaire (002) mais il s'affiche dans son
  -- agenda : « Travaux de peinture » réécrit en autre chose se voit.
  update public.venue_blackouts vb
     set reason = e.reason
    from public.decor_blackouts e
   where vb.venue_id = e.venue_id and vb.date = e.date and vb.slot = e.slot
     and vb.reason is distinct from e.reason
     and vb.updated_at < now() - p_delai;

  -- ---------------------------------------------------------------------------
  -- 4. LES NOTIFICATIONS DES COMPTES DE DÉMONSTRATION
  --
  -- Le décor n'en pose aucune : 004 écrit les états directement, sans passer par
  -- notify_user(). Toute notification d'un compte en d0000000-… vient donc d'un
  -- visiteur. Voir l'en-tête : ce geste n'était pas demandé.
  -- ---------------------------------------------------------------------------

  delete from public.notifications
   where user_id::text like 'd0000000-%'
     and created_at < now() - p_delai;
  get diagnostics notifications_purgees = row_count;

end;
$$;

comment on function public.menage_du_decor(interval) is
  'Tâche pg_cron (J26) : efface ce qu''un visiteur a créé sur les salles de démonstration, '
  'remet le décor tel que l''empreinte le décrit, resynchronise les dates bloquées et purge '
  'les notifications des comptes de démonstration. Ne touche à rien avant p_delai (2 h par '
  'défaut, zéro pour le banc d''essai). Sans empreinte, ne fait rien. Rôle de service.';

revoke execute on function public.menage_du_decor(interval) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- etat_du_decor — ce qui est sale en ce moment
--
-- UNE VUE, ET NON UNE REQUÊTE À RETENIR : le jour où la démonstration paraît
-- vide, on ne se souviendra pas de la comparaison de lignes, on se souviendra
-- d'un nom. Même raison qu'en 034 pour etat_du_gardien.
--
-- Elle ne dit PAS quand le dernier ménage a tourné : cron.job_run_details le
-- dit déjà, et cette fois-ci fidèlement — contrairement au gardien des
-- empreintes, ce ménage fait tout son travail dans sa propre transaction, donc
-- une tâche « succeeded » est une tâche qui a réellement nettoyé.
--
--   select * from cron.job_run_details
--    where jobid = (select jobid from cron.job where jobname = 'ferha-menage-du-decor')
--    order by start_time desc limit 10;
-- -----------------------------------------------------------------------------

create or replace view public.etat_du_decor as
select
  (select count(*) from public.decor_bookings)                              as empreinte_reservations,
  (select count(*) from public.decor_reviews)                               as empreinte_avis,
  (select count(*) from public.decor_blackouts)                             as empreinte_dates_bloquees,

  (select count(*) from public.bookings b
    where b.venue_id::text like '5a11e000-%'
      and b.id::text not like 'b0000000-%')                                 as reservations_de_visiteurs,

  -- LES QUATRE COMPTEURS SUIVANTS SE LISENT PAR RAPPORT À L'EMPREINTE, et sans
  -- elle ils ne veulent rien dire : « 35 dates bloquées en trop » quand on n'a
  -- rien à quoi les comparer est un mensonge, pas un avertissement. NULL dit
  -- « la question ne se pose pas encore ».
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

  (select count(*) from public.notifications
    where user_id::text like 'd0000000-%')                                  as notifications_de_demonstration,

  -- Le trou n° 2 de l'en-tête, compté sans être traité : une salle publiée par
  -- un visiteur entré comme Karim. Elle est ici pour qu'on la voie grandir.
  (select count(*) from public.venues
    where owner_id::text like 'd0000000-%'
      and id::text not like '5a11e000-%')                                   as salles_publiees_par_un_visiteur;

comment on view public.etat_du_decor is
  'L''état de la démonstration en une ligne (J26). `demandes_en_attente` est celle qui '
  'compte : le tableau de bord de l''écran 9 n''a rien à montrer quand elle tombe à zéro. '
  '`salles_publiees_par_un_visiteur` compte un trou connu que le ménage ne bouche pas.';

revoke all on public.etat_du_decor from anon, authenticated;

-- -----------------------------------------------------------------------------
-- La tâche
--
-- TOUTES LES HEURES. Le délai de grâce est de deux heures : une passe horaire
-- rend donc le décor entre deux et trois heures après la visite qui l'a abîmé,
-- ce qui suffit largement — deux recruteurs ne se suivent pas à la minute. Plus
-- souvent ne raccourcirait rien, puisque c'est le délai qui commande.
--
-- À LA MINUTE 10, entre ferha-expire-options (aux quarts d'heure) et
-- ferha-reveil-empreintes (toutes les 5 minutes) : rien ne les fait se marcher
-- dessus, mais les journaux se lisent mieux quand les tâches ne partent pas
-- ensemble.
--
-- REJOUABLE : on décroche explicitement avant de reposer, comme 032 et 034.
-- -----------------------------------------------------------------------------

grant usage on schema cron to postgres;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'ferha-menage-du-decor') then
    perform cron.unschedule('ferha-menage-du-decor');
  end if;
end $$;

select cron.schedule(
  'ferha-menage-du-decor',
  '10 * * * *',
  $cron$select public.menage_du_decor();$cron$
);
