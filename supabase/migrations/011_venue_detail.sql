-- =============================================================================
-- Ferha — 011_venue_detail.sql
-- La fiche salle (§4.2, CLI-03) et le calendrier de disponibilité (CLI-04).
--
-- Deux fonctions, et deux régimes de sécurité différents — la distinction est
-- le cœur de ce fichier :
--
--   venue_detail()   droits de l'appelant. Elle ne lit que des tables déjà
--                    ouvertes par leurs politiques : venues publiées,
--                    venue_photos, venue_amenities, venue_pricing, reviews.
--                    Rien à contourner, donc rien à contourner.
--
--   venue_calendar() droits du propriétaire. Elle doit lire bookings pour
--                    savoir qu'un créneau est pris, et cette table est fermée
--                    aux visiteurs (§9). Elle vérifie donc elle-même qui a le
--                    droit de regarder, et ne renvoie que deux colonnes.
--
-- CE QUI NE SORT JAMAIS DE CES DEUX FONCTIONS :
--   * le téléphone du propriétaire, ni son nom, ni son adresse (§9) — il n'est
--     révélé qu'après passage à « accepted », par booking_contact() ;
--   * le motif d'un blocage (venue_blackouts.reason), qui est une note interne ;
--   * quoi que ce soit d'une réservation : ni qui, ni combien, ni pour quoi.
--     Le calendrier dit qu'un créneau est pris. Pas par qui.
--
-- ⚠ LA VERSION COURANTE DE venue_detail() EST DANS 012_booking_request.sql.
-- ⚠ LA VERSION COURANTE DE venue_calendar() EST DANS
--   023_une_option_tient_la_date.sql : une date sous option de 72 h s'y affiche
--   « reserve » (§5.1), et la règle vient de tient_la_date().
--
-- Celle d'ici ne renvoyait ni les options de la salle — l'écran 5 n'existait
-- pas encore — ni le référentiel des types d'événement quand le propriétaire
-- n'en a déclaré aucun. Le fichier reste tel qu'il a été appliqué — on ne
-- réécrit pas une migration passée — mais c'est 012 qui fait foi pour
-- venue_detail(), et 023 pour venue_calendar() : ce sont ceux-là qu'il faut
-- modifier.
--
-- Rejouable : les fonctions sont remplacées.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- venue_detail — tout ce qu'il faut pour la fiche, en un seul appel
--
-- Un objet JSON plutôt que cinq requêtes. Le §7.3 rappelle ce qu'est le réseau
-- algérien : « sur une 4G algérienne, envoyer 12 photos brutes de 4 Mo fait
-- abandonner le propriétaire au milieu du formulaire ». Cinq allers-retours
-- pour ouvrir une fiche, c'est le même problème vu de l'autre côté.
--
-- LE PRIX VIENT D'estimate_price(), COMME PARTOUT. Chaque ligne de la grille
-- tarifaire porte son montant calculé pour la date demandée, majorations
-- comprises — la fiche affiche donc exactement ce qu'affichait la carte de
-- résultat, et ce que dira le devis.
-- -----------------------------------------------------------------------------

create or replace function public.venue_detail(
  p_venue_id    uuid,
  -- La date et le créneau que le client cherchait. NULL = aujourd'hui : il faut
  -- une vraie date pour tarifer, un prix sans date n'est qu'un « à partir de ».
  p_event_date  date    default null,
  p_guest_count integer default null
)
returns jsonb
language plpgsql
stable
set search_path = public
as $$
declare
  v_date   date    := coalesce(p_event_date, current_date);
  v_guests integer := greatest(coalesce(p_guest_count, 1), 1);
  v_salle  jsonb;
begin
  select jsonb_build_object(
    'id',              v.id,
    'name',            v.name,
    'commune',         v.commune,
    'wilaya_code',     v.wilaya_code,
    'wilaya_name',     w.name_fr,
    'capacity_seated', v.capacity_seated,
    'area_sqm',        v.area_sqm,
    'parking_spaces',  v.parking_spaces,
    'description',     v.description,
    'status',          v.status,
    'event_date',      v_date,
    'guest_count',     p_guest_count,

    -- Note bayésienne (§5.4), ou null si la salle n'a aucun avis. Jamais 0.0 :
    -- une salle neuve n'est pas une salle mal notée.
    'rating',          vr.bayesian_rating,
    'review_count',    coalesce(vr.review_count, 0),

    'photos', coalesce((
      select jsonb_agg(jsonb_build_object('path', p.storage_path, 'is_cover', p.is_cover)
                       order by p.is_cover desc, p.position asc)
      from public.venue_photos p where p.venue_id = v.id
    ), '[]'::jsonb),

    'amenities', coalesce((
      select jsonb_agg(jsonb_build_object(
               'code', a.code, 'label', a.label_fr,
               'icon', a.icon, 'category', a.category)
             order by a.category, a.position)
      from public.venue_amenities va
      join public.amenities a on a.code = va.amenity_code
      where va.venue_id = v.id
    ), '[]'::jsonb),

    'event_types', coalesce((
      select jsonb_agg(jsonb_build_object('code', t.code, 'label', t.label_fr)
                       order by t.position)
      from public.venue_event_types vet
      join public.event_types t on t.code = vet.event_type
      where vet.venue_id = v.id
    ), '[]'::jsonb),

    -- La grille tarifaire, chaque créneau avec SON prix pour la date demandée.
    -- day_coef et season_coef sortent aussi : c'est ce qui permet à la fiche
    -- d'écrire « samedi, haute saison » au lieu d'un montant sans explication.
    'pricing', coalesce((
      select jsonb_agg(jsonb_build_object(
               'slot',               vp.slot,
               'base_price',         vp.base_price,
               'included_seats',     vp.included_seats,
               'extra_seat_price',   vp.extra_seat_price,
               'day_coef',           e.day_coef,
               'season_coef',        e.season_coef,
               'extra_seats',        e.extra_seats,
               'extra_seats_amount', e.extra_seats_amount,
               'total',              e.total)
             order by case vp.slot when 'midi' then 1 when 'soir' then 2 else 3 end)
      from public.venue_pricing vp
      cross join lateral public.estimate_price(
        v.id, v_date, vp.slot, v_guests, '{}'::uuid[]
      ) e
      where vp.venue_id = v.id
    ), '[]'::jsonb)
  )
  into v_salle
  from public.venues v
  left join public.wilayas w       on w.code = v.wilaya_code
  left join public.venue_ratings vr on vr.venue_id = v.id
  where v.id = p_venue_id;

  -- Salle inconnue, ou salle que l'appelant n'a pas le droit de voir : la
  -- politique de venues a filtré la ligne et le SELECT n'a rien ramené. On ne
  -- distingue pas les deux cas — dire « cette salle existe mais elle n'est pas
  -- publiée » en apprendrait déjà trop.
  if v_salle is null then
    raise exception 'Salle introuvable.' using errcode = 'no_data_found';
  end if;

  return v_salle;
end;
$$;

comment on function public.venue_detail(uuid, date, integer) is
  'Fiche salle en un seul appel (§4.2, CLI-03). Droits de l''appelant : ne lit que '
  'des tables déjà ouvertes. Le prix de chaque créneau vient d''estimate_price() '
  'pour la date demandée. Ne renvoie rien du propriétaire — jamais son téléphone (§9).';

grant execute on function public.venue_detail(uuid, date, integer)
  to anon, authenticated;

-- -----------------------------------------------------------------------------
-- venue_calendar — les créneaux occupés, et rien d'autre
--
-- ELLE NE RENVOIE QUE CE QUI EST PRIS. Tout ce qui n'est pas dans le résultat
-- est libre : sur dix-huit mois, cela fait quelques dizaines de lignes au lieu
-- de mille cent. Le calendrier n'a pas besoin qu'on lui dise qu'un jour est
-- libre, il a besoin qu'on lui dise qu'il ne l'est pas.
--
-- DEUX ÉTATS SEULEMENT EN SORTIE, et le troisième est l'absence :
--   'reserve'       une réservation confirmée occupe le créneau (§6.1)
--   'indisponible'  le propriétaire a bloqué la date
--   (absent)        libre
--
-- Une réservation l'emporte sur un blocage quand les deux existent : c'est la
-- plus contraignante des deux, et la seule qui engage quelqu'un d'autre.
--
-- LE MOTIF NE SORT JAMAIS. venue_blackouts.reason est une note interne du
-- propriétaire — « fête de famille », « travaux » — et la vue
-- venue_availability existe précisément pour ne pas l'exposer (002). Cette
-- fonction suit la même règle : deux colonnes, une date et un état.
--
-- SECURITY DEFINER parce qu'il faut lire bookings, fermée aux visiteurs (§9).
-- Elle vérifie donc elle-même que l'appelant a le droit de voir cette salle.
-- -----------------------------------------------------------------------------

create or replace function public.venue_calendar(
  p_venue_id uuid,
  -- 'midi', 'soir' ou 'journee'. Le créneau se choisit AVANT le jour : un
  -- 14 août libre le midi et pris le soir doit se lire d'un coup d'œil, ce qui
  -- suppose de savoir de quel créneau on parle.
  p_slot     text default 'soir',
  p_from     date default null,
  p_to       date default null
)
returns table (
  day   date,
  state text
)
language plpgsql
stable
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  v_slots text[] := case when p_slot = 'journee'
                         then array['midi', 'soir']
                         else array[coalesce(p_slot, 'soir')] end;
  v_from  date   := coalesce(p_from, current_date);
  -- Dix-huit mois (§4.2, CLI-04). On ne montre pas au-delà de ce qu'on sait
  -- dire, et on ne laisse pas non plus demander cinq ans de calendrier.
  v_to    date   := least(
                      coalesce(p_to, (current_date + interval '18 months')::date),
                      (v_from + interval '18 months')::date
                    );
begin
  if coalesce(p_slot, 'soir') not in ('midi', 'soir', 'journee') then
    raise exception 'Créneau inconnu : %. Attendu midi, soir ou journee.', p_slot
      using errcode = 'invalid_parameter_value';
  end if;

  -- Le droit de regarder ce calendrier est celui de voir la salle : publiée
  -- pour tout le monde, brouillon pour son seul propriétaire.
  if not public.can_read_venue(p_venue_id) then
    raise exception 'Salle introuvable.' using errcode = 'no_data_found';
  end if;

  return query
  with occupe as (
    -- Réservations confirmées. Seules celles-là bloquent (§5.1) : une demande
    -- en attente n'enlève la date à personne, et le calendrier ne doit pas
    -- laisser croire le contraire.
    select b.event_date as jour, 'reserve'::text as etat
    from public.bookings b
    where b.venue_id   = p_venue_id
      and b.slot       = any (v_slots)
      and b.event_date between v_from and v_to
      and b.status in ('confirmed', 'completed')

    union all

    -- Blocages du propriétaire. On lit la table et non la vue
    -- venue_availability : la fonction est déjà en droits du propriétaire, et
    -- on ne prend ici que la date et le créneau. Le motif reste où il est.
    select vb.date, 'indisponible'::text
    from public.venue_blackouts vb
    where vb.venue_id = p_venue_id
      and vb.slot     = any (v_slots)
      and vb.date between v_from and v_to
  )
  -- Quand les deux se superposent — le propriétaire a bloqué une date déjà
  -- réservée — c'est « réservé » qui l'emporte : c'est le plus contraignant des
  -- deux, et le seul qui engage quelqu'un d'autre. Écrit explicitement plutôt
  -- que confié à min() ou max(), dont le résultat dépendrait de l'ordre
  -- alphabétique de deux mots français.
  select
    o.jour,
    case when bool_or(o.etat = 'reserve') then 'reserve' else 'indisponible' end
  from occupe o
  group by o.jour
  order by o.jour;
end;
$$;

comment on function public.venue_calendar(uuid, text, date, date) is
  'Créneaux occupés d''une salle sur dix-huit mois (§4.2, CLI-04). '
  'Ne renvoie que ce qui est pris : l''absence vaut « libre ». '
  'Jamais le motif d''un blocage, jamais rien d''une réservation.';

-- Un visiteur non connecté doit pouvoir consulter le calendrier : c'est
-- l'étape 2 du parcours du §3, et elle se fait sans compte.
grant execute on function public.venue_calendar(uuid, text, date, date)
  to anon, authenticated;
