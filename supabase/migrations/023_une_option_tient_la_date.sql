-- =============================================================================
-- Ferha — 023_une_option_tient_la_date.sql
-- Une option de 72 h TIENT la date (§5.1).
--
-- CE QUI ÉTAIT FAUX, ET QUE L'ÉCRAN 6 PROMETTAIT QUAND MÊME
--
-- « La date vous est réservée pendant 71 h. » L'écran de suivi l'écrit au
-- client dès que le propriétaire accepte. La base, elle, n'en tenait aucun
-- compte : venue_calendar() montrait la date libre, search_venues() proposait
-- la salle, request_booking() acceptait une demande de plus, et
-- accepter_demande() laissait Karim poser une SECONDE option sur le même
-- créneau — son garde-fou ne regardait que « confirmed » et « completed ».
-- Deux familles avaient alors chacune leur option de 72 h sur le 14 août, et
-- la première qui payait gagnait. L'autre l'apprenait en appelant la salle.
--
-- LA RÈGLE, ET ELLE EST ÉCRITE UNE FOIS
--
--   Un créneau est PRIS s'il porte une réservation « confirmed » ou
--   « completed », OU une option « accepted » dont l'échéance n'est pas passée.
--
-- Elle vit dans tient_la_date(), trois lignes, et TOUT ce qui décide ou montre
-- la disponibilité passe par elle. C'est la seule façon d'éviter qu'un septième
-- endroit se mette un jour à répondre autre chose que les six autres — ce qui
-- est exactement ce qui vient d'arriver.
--
-- L'ÉCHÉANCE SE COMPARE À now(), ET NON AU DERNIER PASSAGE DU CRON. Le cron
-- expire-options (022) tourne tous les quarts d'heure ; entre deux passages,
-- une option échue laisserait une date « prise » alors qu'elle est à vendre —
-- et c'est précisément le moment où une autre famille regarde. La condition
-- `option_expires_at > now()` rend la règle exacte à la minute. Le cron ne
-- devient plus qu'un rangement : il écrit « expired » dans la colonne, prévient
-- les deux parties, et libère l'index — il ne décide plus de rien.
--
-- L'INDEX uniq_booking_slot NE BOUGE PAS. Il reste partiel, sur « confirmed »
-- et « completed », et c'est voulu : le §5.1 dit qu'une option pose une option,
-- pas qu'elle prend la date pour de bon. Une option échue doit pouvoir laisser
-- passer la confirmation d'une autre réservation sans qu'un index s'y oppose.
-- La règle ci-dessous est un garde-fou métier, exact à la minute ; l'index est
-- la garantie physique du §6.1, au moment du paiement. Les deux, pas l'un.
--
-- LES DEMANDES « pending » NE BLOQUENT TOUJOURS RIEN (§5.1). Plusieurs familles
-- peuvent demander le même 14 août ; le propriétaire arbitre. Rien ici ne
-- change cela, et tient_la_date() rend NULL sur « pending » pour le dire.
--
-- LE CALENDRIER PUBLIC NE DIT PAS QUE C'EST UNE OPTION. venue_calendar() écrit
-- « reserve », le même mot que pour une réservation payée. Qu'une date soit
-- sous option de 72 h plutôt que vendue est une information commerciale sur la
-- salle et sur quelqu'un d'autre — un concurrent y lirait le rythme des
-- affaires, un client y lirait qu'il peut attendre l'échéance pour se
-- glisser dedans. Le calendrier dit qu'un créneau est pris. Pas pourquoi, et
-- surtout pas pour qui.
--
-- CE QUI CHANGE DE FONCTION, ET C'EST LA LISTE COMPLÈTE
--
--   venue_calendar()     (011) une date sous option s'affiche « reserve »
--   search_venues()      (010) la salle sort des résultats pour cette date
--   request_booking()    (022) une nouvelle demande est refusée — FE001
--   accepter_demande()   (015) une deuxième acceptation est refusée — FE014
--   bloquer_date()       (016) inchangée dans l'esprit : elle refusait déjà
--                              « accepted », mais sans regarder l'échéance —
--                              elle refusait donc une option MORTE
--   owner_agenda()       (016) une option échue n'est plus peinte « option »
--
-- CE QUI NE CHANGE PAS, ET POURQUOI. owner_dashboard() (014) compte un taux
-- d'occupation et un revenu : ce sont des statistiques de ce qui a été VENDU,
-- pas de ce qui est tenu. Y compter les options gonflerait le taux d'une
-- recette pas encore acquise, et le mettrait en désaccord avec la ligne de
-- revenu juste à côté, qui ne compte que « confirmed » et « completed ».
--
-- NOUVEAU CODE FERHA
--
--   FE014  PT409  une autre demande est déjà acceptée sur ce créneau, et son
--                 option de 72 h court encore
--
-- Rejouable : trois fonctions créées, six remplacées.
-- Dépend de : 004 (bookings, option_expires_at), 010 (search_venues),
--             011 (venue_calendar), 015 (accepter_demande),
--             016 (owner_agenda, bloquer_date), 022 (request_booking).
-- =============================================================================

-- =============================================================================
-- 1. LA RÈGLE, ET SES DEUX FAÇONS DE SE POSER
-- =============================================================================

-- -----------------------------------------------------------------------------
-- tient_la_date — LA RÈGLE. Tout le reste de ce fichier la cite.
--
-- Elle répond à une question sur UNE réservation : « celle-ci tient-elle son
-- créneau, en ce moment ? ». Trois réponses :
--
--   'confirme'  une réservation payée ou honorée — la date est vendue
--   'option'    une demande acceptée, option de 72 h en cours (§5.1)
--   NULL        elle ne tient rien : en attente, refusée, annulée, expirée,
--               ou acceptée mais dont l'option est échue
--
-- DEUX MOTS PLUTÔT QU'UN BOOLÉEN, parce que deux appelants ont besoin de savoir
-- lequel des deux : accepter_demande() n'a pas la même phrase à dire à Karim
-- selon que la date a été vendue ou qu'il a lui-même déjà dit oui à quelqu'un.
-- Ceux que la distinction ne regarde pas — le calendrier public — la jettent.
--
-- UNE OPTION SANS ÉCHÉANCE TIENT LA DATE. accept_booking() (004) en pose
-- toujours une, et le cas ne devrait pas exister ; mais si une ligne
-- « accepted » se retrouvait un jour sans `option_expires_at`, la lire comme
-- « libre » perdrait silencieusement une réservation. On la lit comme
-- éternelle : le propriétaire verra une date tenue qu'il ne comprend pas et
-- appellera, ce qui vaut mieux que deux familles au même mariage.
--
-- STABLE et non IMMUTABLE : elle lit now().
-- -----------------------------------------------------------------------------

create or replace function public.tient_la_date(
  p_status            text,
  p_option_expires_at timestamptz
)
returns text
language sql
stable
-- Elle ne lit aucune table, et `now()` vient de pg_catalog quoi qu'il arrive.
-- Le search_path est quand même figé : c'est la règle que suit chaque fonction
-- de ce projet, et le linter Supabase compte celles qui s'en dispensent.
set search_path = public
as $$
  select case
           when p_status in ('confirmed', 'completed') then 'confirme'
           when p_status = 'accepted'
            and coalesce(p_option_expires_at, 'infinity'::timestamptz) > now()
                then 'option'
         end;
$$;

comment on function public.tient_la_date(text, timestamptz) is
  'LA RÈGLE de disponibilité (§5.1), écrite une seule fois : « confirme » pour une '
  'réservation confirmée ou honorée, « option » pour une demande acceptée dont l''option '
  'de 72 h court encore, NULL sinon. Exacte à la minute — elle compare à now(), sans '
  'attendre le cron expire-options. Toute fonction qui décide ou montre une disponibilité '
  'passe par elle ; n''en écrivez pas une seconde.';

-- Plomberie interne. Aucun rôle PostgREST n'a besoin de l'appeler : ce sont les
-- fonctions publiques qui la citent, et elles s'exécutent en droits de leur
-- propriétaire.
revoke execute on function public.tient_la_date(text, timestamptz)
  from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- creneaux_pris — la règle appliquée à une salle et à une période
--
-- Elle ne porte AUCUNE règle : elle lit bookings et demande à tient_la_date()
-- ce qu'il faut en penser. Elle rend une ligne par créneau réellement tenu —
-- rien pour les créneaux libres, comme venue_calendar() rend l'occupé et se tait
-- sur le reste.
--
-- SECURITY DEFINER pour la même raison que search_venues() et venue_calendar() :
-- bookings est fermée aux visiteurs (§9), et un calendrier lu en droits de
-- l'appelant montrerait toutes les dates libres à un inconnu. Elle ne sort que
-- ce que le calendrier a déjà le droit de montrer — une date, un créneau — plus
-- deux colonnes réservées à ses appelants du côté propriétaire.
--
-- ELLE NE VÉRIFIE PAS QUI APPELLE, et c'est pour cela qu'elle n'est donnée à
-- personne. Le droit de regarder est celui de voir la salle : c'est
-- can_read_venue() dans venue_calendar(), owns_venue() dans bloquer_date(),
-- `status = 'published'` dans search_venues(). Chacun garde sa porte ; celle-ci
-- n'en est pas une, elle est derrière.
-- -----------------------------------------------------------------------------

create or replace function public.creneaux_pris(
  p_venue_id uuid,
  p_from     date default null,
  p_to       date default null
)
returns table (
  jour     date,
  creneau  text,
  -- 'confirme' ou 'option'. NE SORT JAMAIS TEL QUEL VERS LE PUBLIC : le
  -- calendrier client écrase les deux en « reserve ».
  etat     text,
  -- L'échéance de l'option, pour qui a le droit de la connaître — le
  -- propriétaire. NULL sur une réservation confirmée.
  echeance timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    b.event_date,
    b.slot,
    public.tient_la_date(b.status, b.option_expires_at),
    case when b.status = 'accepted' then b.option_expires_at end
  from public.bookings b
  where b.venue_id = p_venue_id
    and (p_from is null or b.event_date >= p_from)
    and (p_to   is null or b.event_date <= p_to)
    and public.tient_la_date(b.status, b.option_expires_at) is not null;
$$;

comment on function public.creneaux_pris(uuid, date, date) is
  'Les créneaux qu''une salle ne peut plus vendre sur une période (§5.1). Ne porte aucune '
  'règle : elle interroge tient_la_date(). Ne rend que l''occupé — l''absence vaut « libre ». '
  'SECURITY DEFINER pour lire bookings (§9) ; sans contrôle d''accès, donc donnée à personne : '
  'ses appelants gardent chacun leur porte.';

revoke execute on function public.creneaux_pris(uuid, date, date)
  from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- creneau_est_pris — la même question, en oui ou non
--
-- Deux appelants n'ont besoin de rien d'autre : request_booking() refuse ou
-- laisse passer, search_venues() garde la salle ou l'écarte. Un `exists` sur
-- creneaux_pris(), et pas une ligne de règle — le jour où la règle change,
-- c'est tient_la_date() qu'on ouvre, et elle seule.
--
-- p_creneaux est un TABLEAU parce qu'une journée entière occupe midi ET soir
-- (§6.1) : la demande porte sur les deux, et l'un des deux suffit à la refuser.
-- -----------------------------------------------------------------------------

create or replace function public.creneau_est_pris(
  p_venue_id uuid,
  p_date     date,
  p_creneaux text[]
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.creneaux_pris(p_venue_id, p_date, p_date) c
    where c.creneau = any (p_creneaux)
  );
$$;

comment on function public.creneau_est_pris(uuid, date, text[]) is
  'Ce créneau est-il pris (§5.1) ? Un exists sur creneaux_pris(), donc sur tient_la_date(). '
  'Le tableau de créneaux prend en charge la journée entière : l''un des deux suffit (§6.1). '
  'Plomberie interne, donnée à personne.';

revoke execute on function public.creneau_est_pris(uuid, date, text[])
  from public, anon, authenticated;

-- =============================================================================
-- 2. LE CALENDRIER CLIENT — venue_calendar(), VERSION COURANTE
--
-- Identique à celle de 011, à une chose près : la branche « réservations » de
-- son UNION vient maintenant de creneaux_pris(). Une date sous option de 72 h
-- ressort donc « reserve », au même titre qu'une date payée.
--
-- ET ELLE NE DIT PAS LAQUELLE DES DEUX. creneaux_pris() rend pourtant un `etat`
-- et une `echeance` : on les jette ici, exprès. Deux mots différents dans le
-- calendrier public apprendraient à un inconnu qu'une option court sur le
-- 14 août — donc qu'une famille hésite, donc qu'il y a peut-être une place à
-- prendre dans trois jours. Ce n'est ni son affaire ni celle d'un concurrent.
-- Le reste du commentaire de 011 vaut mot pour mot : deux colonnes, une date et
-- un état, et jamais le motif d'un blocage.
-- =============================================================================

create or replace function public.venue_calendar(
  p_venue_id uuid,
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
  v_to    date   := least(
                      coalesce(p_to, (current_date + interval '18 months')::date),
                      (v_from + interval '18 months')::date
                    );
begin
  if coalesce(p_slot, 'soir') not in ('midi', 'soir', 'journee') then
    raise exception 'Créneau inconnu : %. Attendu midi, soir ou journee.', p_slot
      using errcode = 'invalid_parameter_value';
  end if;

  if not public.can_read_venue(p_venue_id) then
    raise exception 'Salle introuvable.' using errcode = 'no_data_found';
  end if;

  return query
  with occupe as (
    -- Ce qui est pris, au sens du §5.1 : confirmé, honoré, ou sous option en
    -- cours. Un seul mot en sortie — « reserve » — pour les trois.
    select c.jour, 'reserve'::text as etat
    from public.creneaux_pris(p_venue_id, v_from, v_to) c
    where c.creneau = any (v_slots)

    union all

    -- Blocages du propriétaire. Le motif reste où il est.
    select vb.date, 'indisponible'::text
    from public.venue_blackouts vb
    where vb.venue_id = p_venue_id
      and vb.slot     = any (v_slots)
      and vb.date between v_from and v_to
  )
  select
    o.jour,
    case when bool_or(o.etat = 'reserve') then 'reserve' else 'indisponible' end
  from occupe o
  group by o.jour
  order by o.jour;
end;
$$;

comment on function public.venue_calendar(uuid, text, date, date) is
  'Créneaux occupés d''une salle sur dix-huit mois (§4.2, CLI-04). Ne renvoie que ce qui est '
  'pris : l''absence vaut « libre ». Une option de 72 h en cours s''affiche « reserve », comme '
  'une réservation payée — le calendrier public ne dit jamais que c''est une option, ni pour qui. '
  'Jamais le motif d''un blocage.';

grant execute on function public.venue_calendar(uuid, text, date, date)
  to anon, authenticated;

-- =============================================================================
-- 3. LA RECHERCHE — search_venues(), VERSION COURANTE
--
-- Identique à celle de 010, à une ligne près : le filtre de disponibilité est
-- maintenant un appel à creneau_est_pris(). Une salle dont le créneau est sous
-- option sort des résultats pour cette date-là — elle n'est pas à vendre ce
-- jour-là, et la proposer enverrait le client faire une demande que
-- request_booking() refuserait trois écrans plus loin.
--
-- Le reste du commentaire de 008 et de 010 vaut mot pour mot, et notamment ce
-- qu'elle a le droit de renvoyer : des colonnes publiques par nature d'une
-- salle PUBLIÉE, et rien de bookings. La réservation ne sert ici qu'à retirer
-- une ligne du résultat — son existence ne doit pas transparaître autrement.
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

    -- Le type d'événement : une salle passe si elle n'a rien déclaré — le
    -- silence ne vaut pas refus — ou si elle a déclaré accepter ce type-là.
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

    -- Disponibilité — seulement si une date est demandée. Sans date, on ne
    -- retire rien : le client regarde le catalogue, pas un calendrier.
    and (p_event_date is null or not exists (
          select 1 from public.venue_blackouts vb
          where vb.venue_id = v.id
            and vb.date     = p_event_date
            and vb.slot     = any (v_slots)
        ))
    -- LA RÈGLE DU §5.1, et elle n'est pas écrite ici : une réservation
    -- confirmée ou honorée, ou une option de 72 h en cours, retire la salle des
    -- résultats pour cette date. Une demande en attente, non.
    and (p_event_date is null
         or not public.creneau_est_pris(v.id, p_event_date, v_slots))

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
  'd''estimate_price() pour la date demandée, majorations comprises. La disponibilité vient '
  'de creneau_est_pris(), donc de tient_la_date() — une option de 72 h en cours retire la '
  'salle des résultats pour cette date (§5.1). '
  'SECURITY DEFINER pour lire les disponibilités dans bookings — ne renvoyer que '
  'des colonnes publiques d''une salle publiée.';

grant execute on function public.search_venues(
  text, text, text, date, text, integer, numeric, text, text[], text, integer, integer
) to anon, authenticated;

-- =============================================================================
-- 4. LA DEMANDE — request_booking(), VERSION COURANTE
--
-- Identique à celle de 022, à son garde-fou de créneau près : il passe par
-- creneau_est_pris(). Une option de 72 h en cours refuse donc une nouvelle
-- demande, avec le code FE001 — le même qu'une date vendue.
--
-- LE MÊME CODE, PARCE QUE C'EST LA MÊME CHOSE VUE DU CLIENT. Il ne peut pas
-- réserver ce jour-là, et lui dire « une option court jusqu'à jeudi 14 h »
-- reviendrait à lui apprendre qu'une autre famille hésite — et à l'inviter à
-- attendre son échec. FE001 dit ce qu'il a besoin de savoir : cette date n'est
-- plus à lui, qu'il en choisisse une autre.
--
-- CE CONTRÔLE RESTE UN CONFORT, PAS LA GARANTIE. C'est l'index
-- uniq_booking_slot (§6.1) qui arbitre pour de bon, au moment de la
-- confirmation, et lui seul tient face à deux paiements à la même seconde.
-- =============================================================================

create or replace function public.request_booking(
  p_venue_id     uuid,
  p_event_date   date,
  p_slot         text,
  p_guest_count  integer,
  p_phone        text,
  p_event_type   text    default null,
  p_message      text    default null,
  p_option_ids   uuid[]  default '{}'::uuid[]
)
returns setof public.bookings
language plpgsql
security definer
set search_path = public
as $$
declare
  v_client  uuid := auth.uid();
  v_owner   uuid;
  v_group   uuid := gen_random_uuid();
  v_slots   text[];
  v_phone   text := public.telephone_normalise(p_phone);
  v_demande uuid;
begin
  if v_client is null then
    raise exception 'Il faut être connecté pour demander une réservation.'
      using errcode = 'PT401', hint = 'FE006';
  end if;

  -- LE NUMÉRO AVANT LA DATE ET LE CRÉNEAU, parce que c'est le seul de ces
  -- refus que le client répare sans quitter l'écran.
  if not public.telephone_valide(v_phone) then
    raise exception
      'Un numéro de téléphone valide est nécessaire : mobile 05, 06 ou 07 suivi de '
      '8 chiffres, ou fixe 02, 03 ou 04 suivi de 7 chiffres.'
      using errcode = 'PT400', hint = 'FE007',
            detail  = 'C''est par ce numéro que la salle rappelle après acceptation (§9).';
  end if;

  if p_slot not in ('midi', 'soir', 'journee') then
    raise exception 'Créneau inconnu : %. Attendu midi, soir ou journee.', p_slot
      using errcode = 'invalid_parameter_value';
  end if;

  if p_event_date < current_date then
    raise exception 'On ne réserve pas une date passée.'
      using errcode = 'PT400', hint = 'FE003';
  end if;

  select v.owner_id into v_owner
  from public.venues v
  where v.id = p_venue_id and v.status = 'published';

  if v_owner is null then
    raise exception 'Cette salle n''est pas ouverte à la réservation.'
      using errcode = 'PT409', hint = 'FE004';
  end if;

  if v_owner = v_client then
    raise exception 'On ne réserve pas sa propre salle.'
      using errcode = 'PT403', hint = 'FE005';
  end if;

  -- Une journée entière occupe midi ET soir (§6.1).
  v_slots := case when p_slot = 'journee' then array['midi', 'soir'] else array[p_slot] end;

  -- Le propriétaire a bloqué le créneau (travaux, fête de famille) : inutile de
  -- lui envoyer une demande qu'il refusera.
  if exists (
    select 1 from public.venue_blackouts vb
    where vb.venue_id = p_venue_id
      and vb.date     = p_event_date
      and vb.slot     = any (v_slots)
  ) then
    raise exception 'Ce créneau est bloqué par le propriétaire.'
      using errcode = 'PT409', hint = 'FE002';
  end if;

  -- Le créneau est pris, au sens du §5.1 : vendu, ou tenu par une option de
  -- 72 h en cours. La règle n'est pas écrite ici — voir tient_la_date().
  if public.creneau_est_pris(p_venue_id, p_event_date, v_slots) then
    raise exception 'Ce créneau est déjà réservé.'
      using errcode = 'PT409', hint = 'FE001';
  end if;

  -- Le numéro par lequel la salle rappellera. On n'écrit que s'il change.
  update public.profiles p
     set phone = v_phone
   where p.id = v_client and p.phone is distinct from v_phone;

  -- UNE SEULE INSTRUCTION pour les deux lignes d'une journée entière — c'est ce
  -- que vérifie le trigger bookings_check_journee (§6.1).
  insert into public.bookings (
    group_id, venue_id, client_id, event_date, slot, requested_slot,
    guest_count, event_type, client_message, option_ids,
    -- Valeur de façade : le trigger bookings_set_price l'écrase par
    -- estimate_price(). Elle n'est là que parce que la colonne est NOT NULL.
    quoted_amount, status
  )
  select
    v_group, p_venue_id, v_client, p_event_date, s, p_slot,
    p_guest_count, p_event_type, p_message, coalesce(p_option_ids, '{}'::uuid[]),
    0, 'pending'
  from unnest(v_slots) as s;

  -- La ligne représentative du groupe : le premier créneau. C'est elle que la
  -- notification désigne, et c'est elle qu'attendent les trois fonctions de
  -- l'espace propriétaire.
  select b.id into v_demande
  from public.bookings b
  where b.group_id = v_group
  order by b.slot
  limit 1;

  perform public.notify_user(
    v_owner, 'booking_requested',
    jsonb_build_object('booking_id', v_demande)
  );

  return query
  select b.* from public.bookings b where b.group_id = v_group order by b.slot;
end;
$$;

comment on function public.request_booking(uuid, date, text, integer, text, text, text, uuid[]) is
  'Pose une demande (§3, étape 3). Insère les deux lignes d''une journée entière en une instruction (§6.1). '
  'Reçoit le numéro auquel la salle rappellera et l''écrit dans profiles.phone ; refuse sans lui (FE007). '
  'Le montant vient du trigger bookings_set_price, donc d''estimate_price() — aucune règle de prix ici. '
  'La disponibilité vient de creneau_est_pris(), donc de tient_la_date() : une option de 72 h en cours '
  'refuse la demande, au même titre qu''une date vendue (§5.1). '
  'Notifie le propriétaire APRÈS l''insertion, avec l''identifiant de la ligne représentative. '
  'Chaque refus porte son code Ferha dans son hint : FE001 créneau pris, FE002 bloqué, '
  'FE003 date passée, FE004 salle fermée, FE005 sa propre salle, FE006 non connecté, '
  'FE007 numéro manquant ou mal formé.';

revoke execute on function public.request_booking(uuid, date, text, integer, text, text, text, uuid[])
  from public, anon;
grant execute on function public.request_booking(uuid, date, text, integer, text, text, text, uuid[])
  to authenticated;

-- =============================================================================
-- 5. LA RÉPONSE DU PROPRIÉTAIRE — accepter_demande(), VERSION COURANTE
--
-- LE TROU QUE CE FICHIER REFERME EST ICI. Le garde-fou de 015 ne regardait que
-- « confirmed » et « completed » : Karim pouvait accepter deux familles sur le
-- même 14 août, chacune repartait avec son option de 72 h et sa phrase « la
-- date vous est réservée », et la première qui payait gagnait. L'autre
-- l'apprenait en appelant la salle — après avoir prévenu la sienne.
--
-- DEUX REFUS PLUTÔT QU'UN, PARCE QUE CE NE SONT PAS LES MÊMES FAITS.
--
--   FE013  la date a été VENDUE entre-temps. Karim n'y est pour rien, il ne
--          peut plus rien pour cette cliente, il ne lui reste qu'à refuser en
--          expliquant pourquoi.
--   FE014  Karim A DÉJÀ DIT OUI à quelqu'un d'autre sur ce créneau, et l'option
--          court encore. Ce n'est pas une course perdue, c'est son propre
--          engagement : il a le choix d'attendre l'échéance — la demande reste
--          en attente, et redeviendra acceptable toute seule si l'option
--          expire — ou de refuser tout de suite pour libérer la famille.
--
-- Les confondre sous FE013 lui dirait « quelqu'un d'autre a confirmé » alors
-- que personne n'a rien confirmé, et lui cacherait la seule information qui
-- change ce qu'il peut faire : cette option-là est la sienne, et elle a une
-- échéance.
--
-- LE FILET `unique_violation` RESTE POSÉ. Aujourd'hui l'index du §6.1 ne peut
-- pas se déclencher sur une acceptation ; si sa clause partielle changeait un
-- jour, le propriétaire lirait quand même une phrase et non une erreur Postgres.
-- =============================================================================

create or replace function public.accepter_demande(p_booking_id uuid)
returns setof public.bookings
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group    uuid;
  v_quoted   numeric;
  v_acompte  numeric;
  v_conflit  text;
  v_echeance timestamptz;
begin
  if auth.uid() is null then
    raise exception 'Il faut être connecté pour répondre à une demande.'
      using errcode = 'PT401', hint = 'FE010';
  end if;

  -- LA MÊME QUESTION QUE accept_booking(), POSÉE POUR UNE AUTRE RAISON : celle
  -- de 004 protège la table, celle-ci existe pour que le refus porte un code.
  if not public.owns_booking(p_booking_id) then
    raise exception 'Cette demande ne concerne pas une de vos salles.'
      using errcode = 'PT403', hint = 'FE011';
  end if;

  select b.group_id, b.quoted_amount into v_group, v_quoted
  from public.bookings b
  where b.id = p_booking_id and b.status = 'pending';

  if v_group is null then
    -- Le cas courant n'est pas une attaque : deux téléphones ouverts sur la
    -- même demande, ou le client qui vient d'annuler.
    raise exception 'Cette demande n''est plus en attente de réponse.'
      using errcode = 'PT409', hint = 'FE012';
  end if;

  -- LE CRÉNEAU EST-IL ENCORE À VENDRE ? Une journée entière occupe deux
  -- lignes : on les regarde toutes les deux, et l'une des deux suffit. La règle
  -- vient de creneaux_pris(), donc de tient_la_date() — elle n'est pas réécrite
  -- ici. On garde l'état le plus contraignant : une date vendue se dit vendue,
  -- même si une option traîne à côté sur l'autre créneau de la journée.
  --
  -- Les lignes de la demande en cours ne peuvent pas se répondre à
  -- elles-mêmes : elles sont « pending », et tient_la_date() rend NULL dessus.
  select c.etat, c.echeance
    into v_conflit, v_echeance
  from public.bookings mienne
  cross join lateral public.creneaux_pris(mienne.venue_id, mienne.event_date,
                                          mienne.event_date) c
  where mienne.group_id = v_group
    and c.creneau = mienne.slot
  order by case c.etat when 'confirme' then 1 else 2 end
  limit 1;

  if v_conflit = 'confirme' then
    raise exception 'Ce créneau a été confirmé entre-temps par une autre réservation.'
      using errcode = 'PT409', hint = 'FE013';

  elsif v_conflit = 'option' then
    -- L'échéance part dans le `detail` plutôt que d'être recollée dans la
    -- phrase : l'application traduit le hint, pas le message (012), et une date
    -- lisible par un humain n'a pas la même forme en français et en arabe.
    raise exception
      'Vous avez déjà accepté une autre demande sur ce créneau, et son option de 72 h '
      'court encore.'
      using errcode = 'PT409', hint = 'FE014',
            detail  = 'Option en cours jusqu''au ' || v_echeance::text || '.';
  end if;

  -- L'acompte que la plateforme propose (§5.3), appliqué au devis déjà en base.
  -- Le taux ne s'écrit pas ici : il vit dans deposit_rate(), et nulle part
  -- ailleurs.
  v_acompte := round(v_quoted * public.deposit_rate(), 2);

  begin
    return query
    select * from public.accept_booking(p_booking_id, v_acompte);
  exception when unique_violation then
    raise exception 'Ce créneau a été confirmé entre-temps par une autre réservation.'
      using errcode = 'PT409', hint = 'FE013';
  end;
end;
$$;

comment on function public.accepter_demande(uuid) is
  'Le propriétaire accepte une demande (§4.3, OWN-05) : pending → accepted, option de 72 h (§5.1). '
  'Délègue la transition à accept_booking() (004) ; ajoute les codes Ferha et l''acompte de '
  'deposit_rate() (§5.3). Refuse un créneau déjà vendu (FE013) ET un créneau qu''une autre '
  'demande acceptée tient encore (FE014) : la règle vient de tient_la_date(), pas d''ici.';

revoke execute on function public.accepter_demande(uuid) from public, anon;
grant  execute on function public.accepter_demande(uuid) to authenticated;

-- =============================================================================
-- 6. L'AGENDA DU PROPRIÉTAIRE — bloquer_date() ET owner_agenda()
-- =============================================================================

-- -----------------------------------------------------------------------------
-- bloquer_date — VERSION COURANTE
--
-- Identique à celle de 016, à son garde-fou près. Elle refusait déjà
-- « accepted », mais SANS REGARDER L'ÉCHÉANCE : une option morte depuis dix
-- jours, que le cron n'aurait pas encore rangée, empêchait le propriétaire de
-- fermer sa propre date. Le garde-fou vient maintenant de creneaux_pris(), et
-- il tombe à la minute où l'option tombe.
--
-- La règle qu'il porte ne change pas d'un mot : ON NE FERME PAS UNE DATE SUR LA
-- TÊTE D'UN CLIENT. Une option EN COURS reste un engagement — quelqu'un a
-- réservé sa journée et prévenu sa famille — et une demande EN ATTENTE
-- n'empêche toujours rien (§5.1).
-- -----------------------------------------------------------------------------

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

  -- Le garde-fou. On regarde AVANT d'écrire, et sur tous les créneaux visés :
  -- fermer la moitié d'une journée qu'on voulait fermer entière serait le pire
  -- des deux résultats.
  select string_agg(distinct c.creneau, ' et ' order by c.creneau) into v_pris
  from public.creneaux_pris(p_venue_id, p_date, p_date) c
  where c.creneau = any (v_creneaux);

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
  'Le propriétaire ferme un créneau (§4.3, OWN-06). Refuse un créneau pris au sens de '
  'tient_la_date() — réservation confirmée, ou option de 72 h EN COURS (FE022) : on ne ferme '
  'pas une date sur la tête d''un client. Une option échue, elle, n''empêche plus rien. '
  'Le motif est privé — il ne sort ni par venue_availability ni par venue_calendar.';

revoke execute on function public.bloquer_date(uuid, date, text, text) from public, anon;
grant  execute on function public.bloquer_date(uuid, date, text, text) to authenticated;

-- -----------------------------------------------------------------------------
-- owner_agenda — VERSION COURANTE
--
-- Identique à celle de 016, à l'endroit où elle nommait l'état d'une
-- réservation. Elle le lisait dans un `case b.status` à elle ; elle le demande
-- maintenant à tient_la_date(), qui rend justement les deux mots qu'elle
-- employait déjà — « confirme » et « option ».
--
-- CE QUI CHANGE POUR KARIM : une option échue que le cron n'a pas encore rangée
-- ne se peint plus « option ». Elle disparaît de l'agenda, et le créneau
-- redevient « libre » — ce qu'il est vraiment, et ce que dit déjà le calendrier
-- de sa cliente. Il pourra donc fermer cette date, ou accepter la demande
-- suivante, sans attendre le quart d'heure du cron. L'ancienne version lui
-- montrait une option morte et lui refusait les deux gestes.
--
-- LA PRIORITÉ NE CHANGE PAS : confirme, option, ferme, demande, libre. Un
-- créneau peut porter plusieurs de ces choses à la fois ; on affiche le plus
-- contraignant, et « ferme » passe devant « demande » parce que c'est une
-- décision déjà prise.
-- -----------------------------------------------------------------------------

create or replace function public.owner_agenda(
  p_venue_id uuid,
  p_month    date default null
)
returns table (
  day               date,
  slot              text,
  state             text,
  booking_id        uuid,
  group_id          uuid,
  client_name       text,
  guest_count       integer,
  quoted_amount     numeric,
  option_expires_at timestamptz,
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

  -- La réservation la plus engageante de chaque créneau. L'état vient de
  -- tient_la_date() : 'confirme', 'option', ou — pour les lignes qui ne tiennent
  -- rien et qu'on garde quand même — 'demande'.
  reservations as (
    select distinct on (b.event_date, b.slot)
      b.event_date,
      b.slot,
      coalesce(public.tient_la_date(b.status, b.option_expires_at), 'demande') as etat,
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
      -- CE QUI RESTE À L'AGENDA : les demandes en attente, qui se voient sans
      -- rien bloquer (§5.1), et tout ce qui tient la date. refused, cancelled,
      -- expired — ET une option échue que le cron n'a pas encore rangée — ne
      -- prennent plus rien : le créneau est redevenu libre, et l'agenda doit le
      -- dire tout de suite plutôt qu'au prochain quart d'heure.
      and (b.status = 'pending'
           or public.tient_la_date(b.status, b.option_expires_at) is not null)
    order by
      b.event_date,
      b.slot,
      case public.tient_la_date(b.status, b.option_expires_at)
        when 'confirme' then 1
        when 'option'   then 2
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
    -- n'ouvre donc rien : elle propose de rouvrir.
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
  'état compris — libre, demande, option, confirme, ferme. L''état vient de tient_la_date() : '
  'une option échue redevient « libre » à la minute, sans attendre le cron. '
  'Un seul appel pour le mois entier.';

revoke execute on function public.owner_agenda(uuid, date) from public, anon;
grant  execute on function public.owner_agenda(uuid, date) to authenticated;
