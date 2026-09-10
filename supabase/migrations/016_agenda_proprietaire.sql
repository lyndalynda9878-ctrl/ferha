-- =============================================================================
-- Ferha — 016_agenda_proprietaire.sql
-- L'agenda du propriétaire, et la fermeture de dates (§4.3, OWN-06 ; écran 9,
-- onglet « Agenda »).
--
-- CE QUE CE FICHIER APPORTE
--
--   owner_agenda()    un mois entier, jour par jour et créneau par créneau
--   bloquer_date()    le propriétaire ferme un créneau, avec son motif
--   debloquer_date()  il le rouvre
--
-- UN SEUL ALLER-RETOUR POUR UN MOIS, ET DEUX CRÉNEAUX DEDANS. C'est la
-- contrainte du §7.3 — la 4G algérienne — appliquée à un écran qu'on feuillette.
-- owner_agenda() rend la GRILLE COMPLÈTE : une ligne par jour et par créneau,
-- « libre » comprise. L'écran n'a donc aucun trou à combler et aucune règle à
-- réinventer pour les jours dont la base n'aurait rien dit ; et surtout, passer
-- de midi à soir ne redemande rien, les deux sont déjà là.
--
-- LES CINQ ÉTATS, DU PLUS ENGAGEANT AU MOINS ENGAGEANT
--
--   confirme  une réservation payée ou honorée — la date est vendue
--   option    une demande acceptée, option de 72 h en cours (§5.1)
--   ferme     le propriétaire a fermé le créneau (travaux, fête de famille)
--   demande   une demande en attente de réponse — elle n'enlève la date à
--             personne (§5.1), mais elle se voit
--   libre     à vendre
--
-- ET CET ORDRE EST UNE PRIORITÉ, PAS UNE LISTE. Un créneau peut porter
-- plusieurs de ces choses à la fois : trois familles peuvent avoir demandé le
-- même 14 août, et le propriétaire peut avoir fermé une date sur laquelle une
-- demande dormait. On affiche alors le plus contraignant, et « ferme » passe
-- devant « demande » parce que c'est une décision déjà prise, tandis qu'une
-- demande en attente n'engage rien. La demande, elle, reste dans la file du
-- tableau de bord, qui est l'endroit où l'on y répond.
--
-- LE MOTIF SORT ICI, ET C'EST NORMAL : owner_agenda() ne répond qu'au
-- propriétaire de la salle, et le motif est sa propre note. Ce qui ne doit
-- jamais sortir, c'est le motif vers le PUBLIC — et cela se joue dans la vue
-- venue_availability (002), qui n'expose que venue_id, date et slot. Ce fichier
-- n'y touche pas ; supabase/tests/004_agenda_proprietaire.sql le vérifie plutôt
-- que de le supposer.
--
-- CODES FERHA DE CE FICHIER — la série de l'agenda. Elle commence à 020 pour
-- laisser aux réponses du propriétaire (FE010–FE013, migration 015) la place de
-- s'étendre.
--
--   FE020  PT401  il faut être connecté
--   FE021  PT403  cette salle n'est pas la vôtre
--   FE022  PT409  le créneau porte une option ou une réservation confirmée
--
-- Rejouable : les trois fonctions sont remplacées.
-- Dépend de : 001 (venue_blackouts), 002 (owns_venue), 004 (bookings,
--             booking_groups), 014 (short_name).
-- =============================================================================

-- =============================================================================
-- owner_agenda — un mois, deux créneaux par jour, cinq états
--
-- SECURITY DEFINER, et pour la même raison qu'owner_pending_requests() (014) :
-- le prénom du client. profiles est fermée à son seul titulaire (002), et le
-- propriétaire n'a aucun moyen de la lire. La fonction porte donc elle-même la
-- condition que la politique porterait pour elle — « la salle est à moi » —, et
-- ne laisse passer du profil que ce que short_name() en garde.
--
-- LE MOIS SE DEMANDE, IL NE SE DÉDUIT PAS. p_month est n'importe quel jour du
-- mois voulu ; on le tronque ici. L'écran feuillette donc en envoyant une date,
-- sans avoir à savoir où commence et où finit un mois — surtout pas en février.
-- =============================================================================

create or replace function public.owner_agenda(
  p_venue_id uuid,
  p_month    date default null
)
returns table (
  day               date,
  slot              text,
  state             text,
  -- La ligne représentative du groupe, celle qu'attendent
  -- owner_request_detail(), accepter_demande() et refuser_demande(). NULL sur
  -- un créneau libre ou fermé : il n'y a rien à ouvrir.
  booking_id        uuid,
  group_id          uuid,
  client_name       text,
  guest_count       integer,
  quoted_amount     numeric,
  option_expires_at timestamptz,
  -- Le motif du blocage. NULL partout ailleurs.
  reason            text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_debut date;
  v_fin   date;
begin
  if auth.uid() is null then
    raise exception 'Il faut être connecté pour voir cet agenda.'
      using errcode = 'PT401', hint = 'FE020';
  end if;

  if not public.owns_venue(p_venue_id) then
    raise exception 'Cette salle n''est pas la vôtre.'
      using errcode = 'PT403', hint = 'FE021';
  end if;

  v_debut := date_trunc('month', coalesce(p_month, current_date))::date;
  v_fin   := (v_debut + interval '1 month')::date;

  return query
  with
  -- La grille : tous les jours du mois, deux créneaux chacun. C'est elle qui
  -- garantit qu'aucune case ne manque, y compris les libres.
  grille as (
    select j::date as jour, s.creneau
    from generate_series(v_debut, v_fin - 1, interval '1 day') j
    cross join (values ('midi'), ('soir')) as s(creneau)
  ),

  -- La réservation la plus engageante de chaque créneau.
  --
  -- `distinct on` avec un ORDER BY qui range d'abord par poids : plusieurs
  -- familles peuvent avoir demandé le même samedi, et c'est celle qui est allée
  -- le plus loin qui décide de la couleur. À poids égal, la plus ancienne — la
  -- première arrivée est celle dont on parle.
  reservations as (
    select distinct on (b.event_date, b.slot)
      b.event_date,
      b.slot,
      case
        when b.status in ('confirmed', 'completed') then 'confirme'
        when b.status = 'accepted'                  then 'option'
        else 'demande'
      end                     as etat,
      rep.id                  as booking_id,
      b.group_id,
      public.short_name(p.full_name) as client_name,
      bg.guest_count,
      bg.quoted_amount,
      bg.option_expires_at
    from public.bookings b
    join public.booking_groups bg on bg.group_id = b.group_id
    -- La ligne représentative du groupe : une journée entière s'ouvre par
    -- celle-là, et se répond d'un bloc. Même choix qu'en 014.
    join public.bookings rep
      on rep.group_id = b.group_id and rep.slot = bg.slots[1]
    join public.profiles p on p.id = b.client_id
    where b.venue_id   = p_venue_id
      and b.event_date >= v_debut
      and b.event_date <  v_fin
      -- refused, cancelled et expired ne prennent plus rien : le créneau est
      -- redevenu libre, et l'agenda doit le dire.
      and b.status in ('pending', 'accepted', 'confirmed', 'completed')
    order by
      b.event_date,
      b.slot,
      case b.status
        when 'confirmed' then 1
        when 'completed' then 1
        when 'accepted'  then 2
        else 3
      end,
      b.created_at
  ),

  fermetures as (
    select k.date, k.slot, k.reason
    from public.venue_blackouts k
    where k.venue_id = p_venue_id
      and k.date >= v_debut
      and k.date <  v_fin
  )

  select
    g.jour,
    g.creneau,
    case
      when r.etat in ('confirme', 'option') then r.etat
      when f.date is not null               then 'ferme'
      when r.etat = 'demande'               then 'demande'
      else 'libre'
    end,
    -- L'identifiant n'accompagne que l'état RÉELLEMENT affiché. Sur un créneau
    -- fermé qui portait aussi une demande en attente, la case dit « fermé » et
    -- n'ouvre donc rien : elle propose de rouvrir. La demande, elle, est dans la
    -- file du tableau de bord.
    case when r.etat in ('confirme', 'option')
           or (f.date is null and r.etat = 'demande')
         then r.booking_id end,
    case when r.etat in ('confirme', 'option')
           or (f.date is null and r.etat = 'demande')
         then r.group_id end,
    case when r.etat in ('confirme', 'option')
           or (f.date is null and r.etat = 'demande')
         then r.client_name end,
    case when r.etat in ('confirme', 'option')
           or (f.date is null and r.etat = 'demande')
         then r.guest_count end,
    case when r.etat in ('confirme', 'option')
           or (f.date is null and r.etat = 'demande')
         then r.quoted_amount end,
    case when r.etat = 'option' then r.option_expires_at end,
    case when r.etat in ('confirme', 'option') then null else f.reason end
  from grille g
  left join reservations r on r.event_date = g.jour and r.slot = g.creneau
  left join fermetures   f on f.date       = g.jour and f.slot = g.creneau
  order by g.jour, g.creneau;
end;
$$;

comment on function public.owner_agenda(uuid, date) is
  'L''agenda d''une salle sur un mois (§4.3, OWN-06) : une ligne par jour et par créneau, '
  'état compris — libre, demande, option, confirme, ferme. Un seul appel pour le mois entier.';

revoke execute on function public.owner_agenda(uuid, date) from public, anon;
grant  execute on function public.owner_agenda(uuid, date) to authenticated;

-- =============================================================================
-- bloquer_date — le propriétaire ferme un créneau
--
-- ON NE FERME PAS UNE DATE SUR LA TÊTE D'UN CLIENT. C'est la seule règle de
-- cette fonction, et elle vaut d'être écrite en toutes lettres : un créneau qui
-- porte une option de 72 h ou une réservation confirmée n'est plus au
-- propriétaire seul. Quelqu'un a réservé sa journée, prévenu sa famille,
-- peut-être versé son acompte. Fermer la date ne ferait d'ailleurs pas
-- disparaître la réservation — elle laisserait juste deux vérités
-- contradictoires dans la base, et un client qui se présente devant une salle
-- fermée.
--
-- Une demande EN ATTENTE, elle, n'empêche rien : elle n'a bloqué aucune date
-- (§5.1), et refuser une demande parce qu'on ferme la semaine est un usage
-- normal. Le propriétaire répondra depuis sa file.
--
-- LE MOTIF EST DEMANDÉ, PAS EXIGÉ, comme celui de refuser_demande() (015). Il
-- est ici une note pour soi — « travaux », « mariage de ma fille » — et non un
-- message à quelqu'un : personne d'autre ne le lira jamais.
--
-- ON RÉÉCRIT PLUTÔT QUE D'ÉCHOUER. Fermer un créneau déjà fermé n'est pas une
-- erreur, c'est une correction de motif : le `on conflict` met le nouveau à la
-- place de l'ancien. Un refus obligerait l'écran à savoir avant d'agir, et à
-- proposer deux boutons là où le propriétaire n'a qu'une intention.
--
-- « journee » ferme les deux créneaux, en deux lignes — c'est le découpage de
-- venue_blackouts depuis 001, le même que celui des réservations (§6.1). Si
-- l'un des deux est pris, RIEN n'est fermé : la fonction lève, et la
-- transaction remonte. Fermer la moitié d'une journée qu'on voulait fermer
-- entière serait le pire des deux résultats.
-- =============================================================================

create or replace function public.bloquer_date(
  p_venue_id uuid,
  p_date     date,
  p_creneau  text default 'soir',
  p_motif    text default null
)
returns setof public.venue_blackouts
language plpgsql
security definer
set search_path = public
as $$
declare
  v_creneaux text[];
  v_pris     text;
begin
  if auth.uid() is null then
    raise exception 'Il faut être connecté pour fermer une date.'
      using errcode = 'PT401', hint = 'FE020';
  end if;

  if not public.owns_venue(p_venue_id) then
    raise exception 'Cette salle n''est pas la vôtre.'
      using errcode = 'PT403', hint = 'FE021';
  end if;

  if coalesce(p_creneau, 'soir') not in ('midi', 'soir', 'journee') then
    raise exception 'Créneau inconnu : %. Attendu midi, soir ou journee.', p_creneau
      using errcode = 'invalid_parameter_value';
  end if;

  v_creneaux := case when coalesce(p_creneau, 'soir') = 'journee'
                     then array['midi', 'soir']
                     else array[coalesce(p_creneau, 'soir')] end;

  -- Le garde-fou. On regarde AVANT d'écrire, et sur tous les créneaux visés.
  select string_agg(distinct b.slot, ' et ' order by b.slot) into v_pris
  from public.bookings b
  where b.venue_id   = p_venue_id
    and b.event_date = p_date
    and b.slot       = any (v_creneaux)
    and b.status in ('accepted', 'confirmed', 'completed');

  if v_pris is not null then
    raise exception
      'Une réservation est en cours sur ce créneau (%). Fermer la date ne l''annulerait pas.',
      v_pris
      using errcode = 'PT409', hint = 'FE022';
  end if;

  return query
  insert into public.venue_blackouts (venue_id, date, slot, reason)
  select p_venue_id, p_date, c, nullif(btrim(p_motif), '')
  from unnest(v_creneaux) as c
  on conflict (venue_id, date, slot) do update
    set reason = excluded.reason
  returning *;
end;
$$;

comment on function public.bloquer_date(uuid, date, text, text) is
  'Le propriétaire ferme un créneau (§4.3, OWN-06). Refuse un créneau qui porte une option '
  'de 72 h ou une réservation confirmée (FE022) : on ne ferme pas une date sur la tête d''un client. '
  'Le motif est privé — il ne sort ni par venue_availability ni par venue_calendar.';

revoke execute on function public.bloquer_date(uuid, date, text, text) from public, anon;
grant  execute on function public.bloquer_date(uuid, date, text, text) to authenticated;

-- =============================================================================
-- debloquer_date — il rouvre
--
-- AUCUN GARDE-FOU ICI, ET CE N'EST PAS UN OUBLI. Rouvrir un créneau ne prend
-- rien à personne : la date redevient à vendre, ce qui est l'état par défaut de
-- toute date. Le seul cas voisin — un créneau à la fois fermé et confirmé, que
-- 001 autorise et que venue_calendar() résout en faveur du « réservé » — reste
-- réservé après le déblocage : c'est bookings qui le dit, pas venue_blackouts.
--
-- Rouvrir un créneau qui n'était pas fermé ne rend aucune ligne, et ne lève
-- pas : l'écran recharge l'agenda de toute façon, et faire une erreur d'un
-- geste sans effet ferait plus de bruit que de bien.
-- =============================================================================

create or replace function public.debloquer_date(
  p_venue_id uuid,
  p_date     date,
  p_creneau  text default 'soir'
)
returns setof public.venue_blackouts
language plpgsql
security definer
set search_path = public
as $$
declare
  v_creneaux text[];
begin
  if auth.uid() is null then
    raise exception 'Il faut être connecté pour rouvrir une date.'
      using errcode = 'PT401', hint = 'FE020';
  end if;

  if not public.owns_venue(p_venue_id) then
    raise exception 'Cette salle n''est pas la vôtre.'
      using errcode = 'PT403', hint = 'FE021';
  end if;

  if coalesce(p_creneau, 'soir') not in ('midi', 'soir', 'journee') then
    raise exception 'Créneau inconnu : %. Attendu midi, soir ou journee.', p_creneau
      using errcode = 'invalid_parameter_value';
  end if;

  v_creneaux := case when coalesce(p_creneau, 'soir') = 'journee'
                     then array['midi', 'soir']
                     else array[coalesce(p_creneau, 'soir')] end;

  return query
  delete from public.venue_blackouts k
  where k.venue_id = p_venue_id
    and k.date     = p_date
    and k.slot     = any (v_creneaux)
  returning *;
end;
$$;

comment on function public.debloquer_date(uuid, date, text) is
  'Le propriétaire rouvre un créneau qu''il avait fermé (§4.3, OWN-06). '
  'Sans garde-fou : rouvrir ne prend rien à personne.';

revoke execute on function public.debloquer_date(uuid, date, text) from public, anon;
grant  execute on function public.debloquer_date(uuid, date, text) to authenticated;
