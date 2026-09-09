-- =============================================================================
-- Ferha — 014_espace_proprietaire.sql
-- Le tableau de bord du propriétaire, première partie (§4.3 OWN-07, OWN-08 ;
-- écran 9 des maquettes).
--
-- CE QUE CE FICHIER APPORTE
--
--   short_name()             « Amina Haddad » → « Amina H. »
--   owner_venues()           le sélecteur de salle — Karim en a quatre
--   owner_dashboard()        les quatre indicateurs, calculés ICI
--   owner_pending_requests() les demandes en attente, une ligne par demande
--   owner_request_detail()   le détail d'une demande, en lecture seule
--
-- LES CHIFFRES SE CALCULENT EN BASE, ET C'EST LE POINT DU FICHIER. Un taux
-- d'occupation recalculé en Dart, c'est une seconde définition du mot
-- « occupé » — et deux définitions finissent toujours par diverger. Les quatre
-- indicateurs sortent d'ici avec leur variation déjà faite : l'écran met un
-- signe et une couleur, il ne fait pas une soustraction.
--
-- CE FICHIER NE CHANGE AUCUN ÉTAT. Accepter, refuser, contre-proposer viendront
-- à l'étape suivante, par des fonctions SECURITY DEFINER qui vérifieront qui
-- appelle. Ici, on lit. `owner_request_detail()` renvoie donc une demande sans
-- offrir le moindre moyen d'y répondre.
--
-- LE TÉLÉPHONE DU CLIENT N'EST PAS RECOPIÉ ICI, pas plus qu'il ne l'était en
-- 013 du côté client. La règle du §9 — « les numéros ne sont révélés qu'après
-- passage à accepted » — vit dans booking_contact() (006).
-- owner_request_detail() l'APPELLE et recopie sa réponse sans la relire : une
-- demande en attente ressort donc sans numéro, et l'écran n'a rien à filtrer.
--
-- Rejouable : les cinq fonctions sont remplacées.
-- Dépend de : 002 (owns_venue), 004 (bookings, booking_groups, venue_ratings),
--             006 (RLS, booking_contact), 005 (venue_options), 009, 010.
-- =============================================================================

-- =============================================================================
-- short_name — « Amina Haddad » → « Amina H. »
--
-- Le nom de famille entier ne quitte pas la base tant que la demande est en
-- attente. Ce n'est pas la règle du §9 — elle ne parle que des téléphones —
-- c'est la même idée appliquée à ce qui n'est pas nécessaire : pour décider
-- d'accepter un mariage, le propriétaire n'a pas besoin du patronyme, et la
-- maquette de l'écran 9 écrit d'ailleurs « Amina K. ».
--
-- Le détail d'une demande, lui, affiche le nom entier — il vient de
-- booking_contact(), comme le téléphone, et par le même chemin.
-- =============================================================================

create or replace function public.short_name(p_full_name text)
returns text
language sql
immutable
set search_path = public
as $$
  select case
    when p_full_name is null or btrim(p_full_name) = '' then null
    -- Un seul mot : il n'y a rien à abréger.
    when array_length(regexp_split_to_array(btrim(p_full_name), '\s+'), 1) = 1
      then btrim(p_full_name)
    else
      (regexp_split_to_array(btrim(p_full_name), '\s+'))[1]
      || ' '
      || upper(left(
           (regexp_split_to_array(btrim(p_full_name), '\s+'))
             [array_length(regexp_split_to_array(btrim(p_full_name), '\s+'), 1)],
           1))
      || '.'
  end;
$$;

comment on function public.short_name(text) is
  'Prénom et initiale du nom — « Amina Haddad » → « Amina H. ». '
  'Ce que voit le propriétaire d''une demande qu''il n''a pas encore acceptée.';

-- =============================================================================
-- owner_venues — le sélecteur de salle
--
-- SECURITY INVOKER, et c'est délibéré : tout ce que cette fonction lit, le
-- propriétaire a déjà le droit de le lire. venues (002) lui ouvre ses propres
-- salles, brouillons compris ; bookings (006) lui ouvre celles de ses salles.
-- La rendre DEFINER lui donnerait des droits qu'elle n'a pas besoin d'emprunter
-- — et il faudrait alors réécrire ici la condition « owner_id = auth.uid() »
-- que la politique porte déjà.
--
-- pending_count accompagne chaque salle : c'est ce qui permet au sélecteur de
-- dire « Salle des Roses · 2 demandes » sans un second appel par salle.
-- =============================================================================

create or replace function public.owner_venues()
returns table (
  venue_id      uuid,
  name          text,
  commune       text,
  wilaya_name   text,
  status        text,
  cover_photo   text,
  pending_count integer
)
language sql
stable
set search_path = public
as $$
  select
    v.id,
    v.name,
    v.commune,
    w.name_fr,
    v.status,
    (select p.storage_path
       from public.venue_photos p
      where p.venue_id = v.id
      order by p.is_cover desc, p.position asc
      limit 1),
    -- Les demandes, pas les créneaux : une journée entière occupe deux lignes
    -- de bookings et reste UNE demande (§6.1).
    (select count(distinct b.group_id)
       from public.bookings b
      where b.venue_id = v.id
        and b.status = 'pending')::integer
  from public.venues v
  left join public.wilayas w on w.code = v.wilaya_code
  where v.owner_id = auth.uid()
  -- Un ordre stable : le sélecteur ne doit pas changer de premier élément d'une
  -- ouverture à l'autre, puisque c'est lui qu'on retient faute de mémoire.
  order by v.name;
$$;

comment on function public.owner_venues() is
  'Les salles du propriétaire connecté, avec le nombre de demandes en attente. '
  'Alimente le sélecteur de l''écran 9 (§4.3, OWN-08).';

revoke execute on function public.owner_venues() from public, anon;
grant execute on function public.owner_venues() to authenticated;

-- =============================================================================
-- owner_dashboard — les quatre indicateurs, et rien qui se recalcule ailleurs
--
-- Chaque indicateur porte sa définition en clair, parce qu'un pourcentage sans
-- définition ne veut rien dire :
--
--   TAUX D'OCCUPATION du mois. Numérateur : les créneaux réellement pris —
--   confirmed et completed, jamais accepted, qui n'est qu'une option de 72 h.
--   Dénominateur : les créneaux VENDABLES, soit deux par jour, moins ceux que
--   le propriétaire a lui-même bloqués (travaux, fête de famille). Bloquer une
--   semaine ne doit pas faire chuter le taux : ces jours-là n'étaient pas à
--   vendre.
--
--   REVENU PRÉVISIONNEL du mois. La somme des devis des réservations tenues —
--   confirmed et completed —, lue sur booking_groups, jamais sur bookings :
--   une journée entière y répète son montant sur deux lignes (§6.1), et une
--   somme faite sur la table compterait double.
--
--   NOTE MOYENNE. Celle de venue_ratings (004), c'est-à-dire exactement celle
--   que voient les clients : moyenne bayésienne du §5.4. Aucun avis, aucune
--   note — null, et surtout pas « 0,0 », qui se lirait comme la pire note
--   possible.
--
--   PART DES DEMANDES ACCEPTÉES du mois, par date de demande. Acceptée se lit
--   sur accepted_at : une option expirée ou annulée ensuite avait bien été
--   acceptée. Le dénominateur ne compte que les demandes TRANCHÉES — une
--   demande encore en attente n'est ni un oui ni un non, et la compter
--   ferait baisser le taux du seul fait qu'on n'a pas encore répondu.
--
-- LES VARIATIONS. Chacune est calculée ici, contre le mois précédent, et vaut
-- null quand la comparaison n'a pas de sens — un mois précédent sans aucune
-- réservation, sans aucun revenu, sans aucune demande tranchée. « quand elle a
-- un sens » est une règle de l'étape J10, et c'est la base qui la tient : un
-- écran ne peut pas deviner qu'un +100 % vient d'un mois vide.
--
-- La note n'a pas de variation, et ce n'est pas un oubli. Une moyenne
-- bayésienne cumulée depuis toujours ne se compare pas d'un mois à l'autre :
-- elle bougerait de trois centièmes, ce qui n'apprendrait rien. Sa deuxième
-- ligne est le nombre d'avis, comme sur la maquette.
--
-- SECURITY INVOKER là encore : bookings, venue_blackouts et venue_ratings sont
-- ouvertes au propriétaire par leurs politiques. Le garde-fou ci-dessous n'est
-- donc pas ce qui protège les chiffres — il évite seulement de renvoyer une
-- ligne de zéros à qui demande la salle d'un autre, ce qui se lirait comme
-- « cette salle ne marche pas ».
-- =============================================================================

create or replace function public.owner_dashboard(
  p_venue_id uuid,
  p_month    date default null
)
returns table (
  month            date,
  occupancy_rate   numeric,
  occupancy_delta  numeric,
  revenue          numeric,
  revenue_dates    integer,
  revenue_delta    numeric,
  rating           numeric,
  review_count     integer,
  acceptance_rate  numeric,
  acceptance_delta numeric,
  decided_count    integer,
  pending_count    integer
)
language plpgsql
stable
set search_path = public
as $$
declare
  v_mois      date;
  v_precedent date;
begin
  if auth.uid() is null then
    raise exception 'Il faut être connecté pour voir ce tableau de bord.'
      using errcode = 'PT401';
  end if;

  if not public.owns_venue(p_venue_id) then
    raise exception 'Cette salle n''est pas la vôtre.'
      using errcode = 'PT403';
  end if;

  v_mois      := date_trunc('month', coalesce(p_month, current_date))::date;
  v_precedent := (v_mois - interval '1 month')::date;

  return query
  with
  -- Les deux mois, côte à côte, pour n'écrire chaque définition qu'une fois.
  bornes as (
    select v_mois as debut, (v_mois + interval '1 month')::date as fin, true  as courant
    union all
    select v_precedent,     v_mois,                                   false
  ),

  -- Créneaux pris : les lignes de bookings, qui sont atomiques par nature.
  occupation as (
    select
      b2.courant,
      count(*) filter (
        where bk.status in ('confirmed', 'completed')
      )::numeric as pris
    from bornes b2
    left join public.bookings bk
      on bk.venue_id = p_venue_id
     and bk.event_date >= b2.debut
     and bk.event_date <  b2.fin
    group by b2.courant
  ),

  -- Créneaux vendables : deux par jour, moins les blocages du propriétaire.
  capacite as (
    select
      b2.courant,
      ((b2.fin - b2.debut) * 2)::numeric
        - (select count(*)
             from public.venue_blackouts k
            where k.venue_id = p_venue_id
              and k.date >= b2.debut
              and k.date <  b2.fin) as vendables
    from bornes b2
  ),

  -- Revenu : sur booking_groups, une ligne par réservation.
  recettes as (
    select
      b2.courant,
      coalesce(sum(bg.quoted_amount), 0)   as total,
      count(distinct bg.event_date)::integer as dates
    from bornes b2
    left join public.booking_groups bg
      on bg.venue_id = p_venue_id
     and bg.event_date >= b2.debut
     and bg.event_date <  b2.fin
     and bg.status in ('confirmed', 'completed')
    group by b2.courant
  ),

  -- Demandes tranchées, par date de demande. On repasse par bookings et non par
  -- booking_groups : accepted_at n'est pas dans la vue, et c'est lui qui dit
  -- « le propriétaire a dit oui », même si l'option a expiré depuis.
  reponses as (
    select
      b2.courant,
      count(distinct bk.group_id) filter (
        where bk.accepted_at is not null
      )::numeric as acceptees,
      count(distinct bk.group_id) filter (
        where bk.accepted_at is not null or bk.status = 'refused'
      )::numeric as tranchees
    from bornes b2
    left join public.bookings bk
      on bk.venue_id = p_venue_id
     and bk.created_at >= b2.debut
     and bk.created_at <  b2.fin
    group by b2.courant
  ),

  notes as (
    select vr.bayesian_rating, vr.review_count
    from public.venue_ratings vr
    where vr.venue_id = p_venue_id
  )

  select
    v_mois,

    -- Occupation, en part de 1. Une salle entièrement bloquée n'a pas de taux :
    -- diviser par zéro créneau vendable ne veut rien dire.
    case when cap_c.vendables > 0
         then round(occ_c.pris / cap_c.vendables, 4) end,
    case when cap_c.vendables > 0 and cap_p.vendables > 0 and occ_p.pris > 0
         then round(
           (occ_c.pris / cap_c.vendables - occ_p.pris / cap_p.vendables) * 100,
           1) end,

    rec_c.total,
    rec_c.dates,
    case when rec_p.total > 0
         then round((rec_c.total - rec_p.total) / rec_p.total, 4) end,

    (select n.bayesian_rating from notes n),
    coalesce((select n.review_count from notes n), 0)::integer,

    case when rep_c.tranchees > 0
         then round(rep_c.acceptees / rep_c.tranchees, 4) end,
    case when rep_c.tranchees > 0 and rep_p.tranchees > 0
         then round(
           (rep_c.acceptees / rep_c.tranchees
            - rep_p.acceptees / rep_p.tranchees) * 100,
           1) end,
    rep_c.tranchees::integer,

    -- En attente : toutes dates confondues, pas seulement ce mois-ci. C'est une
    -- file de travail, pas une statistique — une demande d'août reçue en juin
    -- attend une réponse en juin.
    (select count(distinct b.group_id)
       from public.bookings b
      where b.venue_id = p_venue_id
        and b.status = 'pending')::integer

  from      occupation occ_c
  join      occupation occ_p on not occ_p.courant
  join      capacite   cap_c on     cap_c.courant
  join      capacite   cap_p on not cap_p.courant
  join      recettes   rec_c on     rec_c.courant
  join      recettes   rec_p on not rec_p.courant
  join      reponses   rep_c on     rep_c.courant
  join      reponses   rep_p on not rep_p.courant
  where occ_c.courant;
end;
$$;

comment on function public.owner_dashboard(uuid, date) is
  'Les quatre indicateurs de l''écran 9 (§4.3, OWN-07), variations comprises. '
  'Seul endroit où « taux d''occupation », « prévisionnel » et « part acceptée » sont définis.';

revoke execute on function public.owner_dashboard(uuid, date) from public, anon;
grant execute on function public.owner_dashboard(uuid, date) to authenticated;

-- =============================================================================
-- owner_pending_requests — la file de travail du jour
--
-- SECURITY DEFINER, pour une seule raison : le prénom du client. profiles est
-- fermée à son titulaire (002), et le propriétaire n'a aucun moyen de la lire.
-- La fonction porte donc elle-même la condition que la politique porterait pour
-- elle — « la salle est à moi » —, écrite en toutes lettres ci-dessous, et ne
-- renvoie du profil que ce que short_name() en laisse passer.
--
-- Une ligne par DEMANDE, pas par créneau : booking_groups (004) compte chaque
-- réservation une fois, et le devis y est celui du groupe entier.
-- =============================================================================

create or replace function public.owner_pending_requests(p_venue_id uuid)
returns table (
  group_id       uuid,
  booking_id     uuid,
  client_name    text,
  event_date     date,
  requested_slot text,
  slots          text[],
  guest_count    integer,
  event_type     text,
  event_label    text,
  quoted_amount  numeric,
  created_at     timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Il faut être connecté pour voir ces demandes.'
      using errcode = 'PT401';
  end if;

  if not public.owns_venue(p_venue_id) then
    raise exception 'Cette salle n''est pas la vôtre.'
      using errcode = 'PT403';
  end if;

  return query
  select
    bg.group_id,
    b.id,
    public.short_name(p.full_name),
    bg.event_date,
    bg.requested_slot,
    bg.slots,
    bg.guest_count,
    bg.event_type,
    t.label_fr,
    bg.quoted_amount,
    bg.created_at
  from public.booking_groups bg
  -- La ligne représentative du groupe, celle qu'attendront accept_booking() et
  -- refuse_booking() à l'étape suivante.
  join public.bookings b
    on b.group_id = bg.group_id and b.slot = bg.slots[1]
  join public.profiles p on p.id = bg.client_id
  left join public.event_types t on t.code = bg.event_type
  where bg.venue_id = p_venue_id
    and bg.status = 'pending'
  -- La plus récente en haut, comme sur la maquette : c'est celle qui vient
  -- d'arriver qu'on n'a pas encore vue. L'écran dit à côté depuis combien de
  -- temps chacune attend.
  order by bg.created_at desc;
end;
$$;

comment on function public.owner_pending_requests(uuid) is
  'Les demandes en attente d''une salle (§4.3, OWN-05), une ligne par demande. '
  'Le client n''y apparaît que par son prénom et l''initiale de son nom.';

revoke execute on function public.owner_pending_requests(uuid) from public, anon;
grant execute on function public.owner_pending_requests(uuid) to authenticated;

-- =============================================================================
-- owner_request_detail — tout ce que le client a demandé, et rien de plus
--
-- EN LECTURE SEULE, à dessein. Accepter, refuser, contre-proposer sont des
-- transitions d'état : elles passeront par accept_booking() et
-- refuse_booking() (004), qui vérifient d'où l'on part et qui appelle. Cette
-- fonction ne sait rien faire d'autre que lire.
--
-- LE TÉLÉPHONE VIENT DE booking_contact(), APPELÉ ET NON RECOPIÉ. C'est le même
-- chemin qu'en 013 côté client, et la même raison : la règle du §9 n'a pas de
-- second exemplaire. Une demande « pending » ressort donc avec phone à null et
-- phone_available à false — l'écran n'a aucune condition à écrire, il n'y a
-- rien à cacher dans ce qu'il reçoit.
--
-- Les options sont rendues en JSON, libellé et prix compris, parce que
-- bookings.option_ids ne porte que des identifiants et qu'une liste de uuid
-- n'apprend rien à personne.
-- =============================================================================

create or replace function public.owner_request_detail(p_booking_id uuid)
returns table (
  group_id        uuid,
  booking_id      uuid,
  venue_id        uuid,
  venue_name      text,
  client_name     text,
  client_phone    text,
  phone_available boolean,
  event_date      date,
  requested_slot  text,
  slots           text[],
  guest_count     integer,
  event_type      text,
  event_label     text,
  client_message  text,
  options         jsonb,
  quoted_amount   numeric,
  deposit_amount  numeric,
  status          text,
  status_reason   text,
  created_at      timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_venue_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Il faut être connecté pour voir cette demande.'
      using errcode = 'PT401';
  end if;

  select b.venue_id into v_venue_id
  from public.bookings b where b.id = p_booking_id;

  if v_venue_id is null then
    raise exception 'Demande inconnue.' using errcode = 'no_data_found';
  end if;

  -- Le propriétaire de la salle, et lui seul. Un client qui appellerait cette
  -- fonction sur sa propre réservation se verrait refusé ici : il a
  -- client_bookings() (013), qui lui montre son point de vue à lui.
  if not public.owns_venue(v_venue_id) then
    raise exception 'Cette demande ne concerne pas vos salles.'
      using errcode = 'PT403';
  end if;

  return query
  select
    bg.group_id,
    b.id,
    bg.venue_id,
    v.name,
    -- Le nom entier ici, et abrégé dans la liste : on décide d'une demande en
    -- sachant à qui l'on répond. Il vient de booking_contact(), comme le
    -- téléphone, et par le même chemin.
    c.full_name,
    c.phone,
    c.phone_available,
    bg.event_date,
    bg.requested_slot,
    bg.slots,
    bg.guest_count,
    bg.event_type,
    t.label_fr,
    b.client_message,
    coalesce(
      (select jsonb_agg(
                jsonb_build_object(
                  'code',  o.code,
                  'label', o.label_fr,
                  'price', o.price)
                order by o.position, o.code)
         from public.venue_options o
        where o.id = any (b.option_ids)),
      '[]'::jsonb),
    bg.quoted_amount,
    bg.deposit_amount,
    bg.status,
    b.status_reason,
    bg.created_at
  from public.booking_groups bg
  join public.bookings b
    on b.group_id = bg.group_id and b.slot = bg.slots[1]
  join public.venues v on v.id = bg.venue_id
  left join public.event_types t on t.code = bg.event_type
  -- LA règle du §9, appelée et non recopiée.
  cross join lateral public.booking_contact(b.id) c
  where bg.group_id = (select g.group_id from public.bookings g
                        where g.id = p_booking_id);
end;
$$;

comment on function public.owner_request_detail(uuid) is
  'Le détail d''une demande, du point de vue du propriétaire (§4.3, OWN-05), en lecture seule. '
  'Le téléphone du client vient de booking_contact() : rien avant « accepted » (§9).';

revoke execute on function public.owner_request_detail(uuid) from public, anon;
grant execute on function public.owner_request_detail(uuid) to authenticated;
