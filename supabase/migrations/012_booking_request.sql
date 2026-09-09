-- =============================================================================
-- Ferha — 012_booking_request.sql
-- La demande de réservation (§3 étape 3, §4.2 CLI-05) — écran 5 des maquettes.
--
-- CE QUE CE FICHIER APPORTE
--
--   deposit_rate()   le taux d'acompte, à UN SEUL endroit
--   booking_quote()  le devis de l'écran de demande, recalculé à chaque geste
--   venue_detail()   REDÉFINIE : elle renvoie désormais les options de la salle
--   request_booking() REDÉFINIE : mêmes règles, mais chaque refus porte un code
--                     Ferha, pour que l'application puisse en faire une phrase
--                     française sans lire un message.
--
-- LE PRIX NE SE CALCULE TOUJOURS QU'À UN SEUL ENDROIT. booking_quote() ne
-- porte AUCUNE formule de prix : elle appelle estimate_price() et se contente
-- d'en rhabiller le résultat. La seule chose qu'elle ajoute est l'acompte, qui
-- n'est pas un prix mais une fraction de celui-ci — et cette fraction vit dans
-- deposit_rate(), une fonction d'une ligne, pour ne pas être écrite deux fois.
--
-- ⚠ LA VERSION COURANTE DE venue_detail() ET DE request_booking() EST ICI.
-- Celles de 011 et de 005 restent telles qu'elles ont été appliquées — on ne
-- réécrit pas une migration passée — mais c'est ce fichier qui fait foi, et
-- c'est lui qu'il faut modifier.
--
-- Rejouable : les fonctions sont remplacées.
-- Dépend de : 005 (estimate_price, venue_options), 010 (event_types), 011.
-- =============================================================================

-- =============================================================================
-- deposit_rate — le taux d'acompte, et le seul
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 25 %, et d'où vient ce chiffre
--
-- Le cahier des charges ne le fixe pas : son §5.3 donne le barème de
-- REMBOURSEMENT (100 / 50 / 0 % selon la date), pas la part à verser. Ce sont
-- les maquettes qui le donnent, et deux fois plutôt qu'une — l'écran 5 écrit
-- « Acompte à verser (25 %) · 51 250 DA » sous une estimation de 205 000 DA,
-- et l'écran 6 reprend « Acompte (25 %) · 51 250 DA ». 51 250 = 205 000 × 0,25 :
-- les deux écrans sont d'accord entre eux, et avec ce taux.
--
-- C'EST DONC UNE VALEUR À CONFIRMER, comme l'était venue_options en 005 : les
-- maquettes donnent la structure, et le cahier des charges les valeurs. Ici le
-- cahier se tait, on prend donc les maquettes — mais on l'écrit.
--
-- CE MONTANT N'EST QU'UNE INDICATION À CE STADE. L'acompte réellement dû est
-- fixé par le propriétaire quand il accepte la demande (accept_booking, 004,
-- paramètre p_deposit_amount), et le §5.2 lui laisse expressément le droit de
-- s'écarter de l'estimation. Ce que l'écran 5 affiche est ce que le client
-- versera si le propriétaire suit le taux de la plateforme.
--
-- Une fonction plutôt qu'une constante en dur répétée : le jour où le taux
-- change, ou devient propre à chaque salle, il y a UN endroit à ouvrir.
-- -----------------------------------------------------------------------------

create or replace function public.deposit_rate()
returns numeric
language sql
immutable
as $$
  select 0.25::numeric;
$$;

comment on function public.deposit_rate() is
  'Part du devis demandée en acompte (maquettes, écrans 5 et 6). '
  'Valeur à confirmer : le cahier des charges ne la fixe pas. '
  'Indicative seulement — accept_booking() laisse le propriétaire fixer le montant réel (§5.2).';

grant execute on function public.deposit_rate() to anon, authenticated;

-- =============================================================================
-- venue_detail — VERSION COURANTE
--
-- Identique à celle de 011_venue_detail.sql, à deux choses près :
--
--   1. Elle renvoie « options » : les options payantes de la salle, celles que
--      l'écran 5 propose à cocher. Elles arrivent avec la fiche plutôt que par
--      un appel de plus — c'est le même argument qu'en 011 : « sur une 4G
--      algérienne », cinq allers-retours pour ouvrir un écran se sentent (§7.3).
--      L'écran de demande s'ouvre depuis le calendrier, qui a déjà la fiche en
--      main : les cases à cocher s'affichent donc sans un octet de réseau.
--
--   2. « event_types » applique enfin la règle posée en 010 : AUCUNE LIGNE
--      DÉCLARÉE = LA SALLE ACCEPTE TOUT. La version de 011 renvoyait un tableau
--      vide, ce qui laissait l'écran de demande sans aucune puce d'événement à
--      proposer — c'est-à-dire l'inverse exact de ce que le vide veut dire.
--      search_venues() suit cette règle depuis 010 ; la fiche la suit à son tour.
--
-- Le reste du commentaire de 011 reste valable mot pour mot, et notamment ce
-- qui ne sort JAMAIS d'ici : rien du propriétaire, rien d'une réservation,
-- jamais le motif d'un blocage.
-- =============================================================================

create or replace function public.venue_detail(
  p_venue_id    uuid,
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

    -- Ce que la salle accueille. Si le propriétaire n'a rien déclaré, elle
    -- accueille tout (010) : on renvoie alors le référentiel entier, plutôt
    -- qu'un tableau vide qui se lirait « elle n'accueille rien ».
    'event_types', coalesce((
      select jsonb_agg(jsonb_build_object('code', t.code, 'label', t.label_fr)
                       order by t.position)
      from public.venue_event_types vet
      join public.event_types t on t.code = vet.event_type
      where vet.venue_id = v.id
    ), (
      select jsonb_agg(jsonb_build_object('code', t.code, 'label', t.label_fr)
                       order by t.position)
      from public.event_types t
    ), '[]'::jsonb),

    -- Les options payantes proposées à l'écran 5 (§5.2, « Σ options_choisies »).
    --
    -- Seules les actives : une option retirée du catalogue reste en base parce
    -- que les réservations passées la citent (005), mais on ne la propose plus.
    --
    -- PRIX À ZÉRO = OPTION INCLUSE. C'est le « ☑ Chambre de la mariée · Incluse »
    -- de la maquette : la salle la mentionne pour qu'on sache qu'elle existe, et
    -- la cocher n'ajoute rien au devis. Ce n'est pas un cas particulier à écrire
    -- ici — c'est simplement price = 0, et l'application l'écrit en toutes lettres.
    'options', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id',    vo.id,
               'code',  vo.code,
               'label', vo.label_fr,
               'price', vo.price)
             order by vo.position, vo.label_fr)
      from public.venue_options vo
      where vo.venue_id = v.id and vo.is_active
    ), '[]'::jsonb),

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
  left join public.wilayas w        on w.code = v.wilaya_code
  left join public.venue_ratings vr on vr.venue_id = v.id
  where v.id = p_venue_id;

  if v_salle is null then
    raise exception 'Salle introuvable.' using errcode = 'no_data_found';
  end if;

  return v_salle;
end;
$$;

comment on function public.venue_detail(uuid, date, integer) is
  'Fiche salle en un seul appel (§4.2, CLI-03), options de l''écran 5 comprises. '
  'Droits de l''appelant : ne lit que des tables déjà ouvertes. Le prix de chaque '
  'créneau vient d''estimate_price(). Aucune ligne dans venue_event_types = la salle '
  'accueille tout, et le référentiel entier ressort (010). '
  'Ne renvoie rien du propriétaire — jamais son téléphone (§9).';

grant execute on function public.venue_detail(uuid, date, integer)
  to anon, authenticated;

-- =============================================================================
-- booking_quote — le devis de l'écran 5, recalculé à chaque geste
--
-- « Le devis se recalcule à chaque option cochée » (maquettes, écran 5). Chaque
-- case cochée, chaque invité ajouté, chaque type d'événement changé rappelle
-- cette fonction : c'est elle qui donne les montants, et l'application n'en
-- fabrique aucun — pas même une addition.
--
-- ELLE NE PORTE AUCUNE FORMULE DE PRIX. Tout vient d'estimate_price() (005), en
-- un seul appel, et ressort tel quel. Ce que cette fonction ajoute :
--
--   * l'acompte, qui n'est pas un prix mais une part du devis — deposit_rate() ;
--   * les options réellement retenues, avec leur libellé et leur prix, pour que
--     le récapitulatif nomme ce qu'il facture.
--
-- Les options retenues sont cherchées avec EXACTEMENT le même filtre que celui
-- d'estimate_price — même salle, identifiant dans la liste, sans regarder
-- is_active. Ainsi le récapitulatif ne peut pas montrer autre chose que ce qui
-- a été compté : un identifiant qui n'appartient pas à cette salle ne rapporte
-- rien à estimate_price(), et n'apparaît pas non plus ici.
--
-- DROITS DE L'APPELANT, et grant à anon : le devis se consulte AVANT de se
-- connecter. C'est la règle du parcours (§3) — on ne demande son identité à
-- personne pour lui montrer un prix. La connexion n'est réclamée qu'à
-- l'instant d'envoyer, par request_booking(), qui elle est fermée à anon.
-- =============================================================================

create or replace function public.booking_quote(
  p_venue_id    uuid,
  p_event_date  date,
  p_slot        text,
  p_guest_count integer,
  p_option_ids  uuid[] default '{}'::uuid[]
)
returns jsonb
language plpgsql
stable
set search_path = public
as $$
declare
  v_options uuid[] := coalesce(p_option_ids, '{}'::uuid[]);
  v_prix    record;
begin
  -- La salle doit être lisible. Sans ce contrôle, estimate_price() renverrait
  -- « aucune grille tarifaire » sur une salle qui existe mais qu'on n'a pas le
  -- droit de voir — ce qui en apprendrait déjà trop.
  if not public.can_read_venue(p_venue_id) then
    raise exception 'Salle introuvable.' using errcode = 'no_data_found';
  end if;

  -- LE prix, en un appel. Les contrôles de créneau et de nombre d'invités sont
  -- les siens : on ne les recopie pas ici, ils diraient un jour autre chose.
  select * into v_prix
  from public.estimate_price(p_venue_id, p_event_date, p_slot,
                             p_guest_count, v_options);

  return jsonb_build_object(
    -- Ce sur quoi porte le devis, renvoyé pour que l'écran vérifie qu'il
    -- affiche bien la réponse à sa dernière question.
    'venue_id',           p_venue_id,
    'event_date',         p_event_date,
    'slot',               p_slot,
    'guest_count',        p_guest_count,

    -- La décomposition d'estimate_price(), telle quelle.
    'base_price',         v_prix.base_price,
    'day_coef',           v_prix.day_coef,
    'season_coef',        v_prix.season_coef,
    'slot_price',         v_prix.slot_price,
    'included_seats',     v_prix.included_seats,
    'extra_seats',        v_prix.extra_seats,
    'extra_seats_amount', v_prix.extra_seats_amount,
    'options_amount',     v_prix.options_amount,
    'total',              v_prix.total,

    -- L'acompte. Le taux ressort avec le montant : la maquette écrit
    -- « Acompte à verser (25 %) », et un pourcentage affiché doit venir de la
    -- même source que la somme qu'il explique.
    'deposit_rate',       public.deposit_rate(),
    'deposit_amount',     round(v_prix.total * public.deposit_rate(), 2),

    -- Ce qui a réellement été facturé en options, nommé.
    'options', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id',    vo.id,
               'code',  vo.code,
               'label', vo.label_fr,
               'price', vo.price)
             order by vo.position, vo.label_fr)
      from public.venue_options vo
      where vo.venue_id = p_venue_id
        and vo.id = any (v_options)
    ), '[]'::jsonb)
  );
end;
$$;

comment on function public.booking_quote(uuid, date, text, integer, uuid[]) is
  'Devis de l''écran de demande (§4.2, CLI-05). Aucune formule de prix ici : tout vient '
  'd''estimate_price() (§5.2). Ajoute l''acompte — deposit_rate() — et nomme les options '
  'facturées. Se consulte sans compte : la connexion n''est exigée qu''à l''envoi.';

grant execute on function public.booking_quote(uuid, date, text, integer, uuid[])
  to anon, authenticated;

-- =============================================================================
-- request_booking — VERSION COURANTE
--
-- Mêmes règles, mêmes refus, même corps que la version de 005_pricing.sql. Une
-- seule chose change, et elle est entièrement au service de l'écran :
--
--   CHAQUE REFUS PORTE DÉSORMAIS UN CODE FERHA, DANS SON « hint ».
--
-- La version de 005 rendait quatre refus différents sous le même code 23514
-- (check_violation) : « date passée », « salle fermée », « votre propre
-- salle », « créneau bloqué », « créneau déjà réservé ». L'application ne
-- pouvait les distinguer qu'en lisant le texte français du message — c'est-à-
-- dire en faisant dépendre son affichage d'une chaîne qui peut être reformulée
-- à tout moment, et qui ne serait de toute façon jamais traduite en arabe.
--
-- DEUX CHAMPS, PARCE QU'ILS RÉPONDENT À DEUX QUESTIONS. Le SQLSTATE, chez
-- PostgREST, ne sert pas à identifier l'erreur : il choisit le CODE HTTP. Un
-- code inventé — « FE001 » — ne tombe dans aucune classe connue, et PostgREST
-- répond alors 500. Or « ce créneau vient d'être pris » n'est pas une panne de
-- serveur : c'est un conflit, et un journal qui compte les 500 doit pouvoir
-- continuer à les compter.
--
--   errcode  PTxxx — PostgREST en fait le code HTTP (409, 403, 401, 400).
--   hint     le code Ferha, stable, que l'application traduit en français.
--
--   FE001  le créneau est déjà pris par une réservation confirmée   409
--   FE002  le propriétaire a bloqué ce créneau                      409
--   FE003  la date est passée                                       400
--   FE004  la salle n'est pas ouverte à la réservation              409
--   FE005  on ne réserve pas sa propre salle                        403
--   FE006  il faut être connecté                                    401
--
-- Le « hint » de PostgreSQL est fait pour cela : une indication destinée à
-- l'appelant, à côté du message destiné à l'humain. PostgREST le recopie tel
-- quel dans sa réponse JSON, et supabase_flutter l'expose sur
-- PostgrestException.hint. Six codes, six phrases côté Flutter
-- (lib/features/booking/booking_messages.dart), et la maquette obtient ce
-- qu'elle demande : « Ce créneau vient d'être réservé », jamais un code.
--
-- LE PRIX N'EST TOUJOURS PAS ÉCRIT ICI. quoted_amount part à 0 et le trigger
-- bookings_set_price (005) l'écrase par estimate_price() — le même montant,
-- exactement, que celui que booking_quote() vient de montrer au client.
-- =============================================================================

create or replace function public.request_booking(
  p_venue_id     uuid,
  p_event_date   date,
  p_slot         text,
  p_guest_count  integer,
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
  v_client uuid := auth.uid();
  v_owner  uuid;
  v_group  uuid := gen_random_uuid();
  v_slots  text[];
begin
  if v_client is null then
    raise exception 'Il faut être connecté pour demander une réservation.'
      using errcode = 'PT401', hint = 'FE006';
  end if;

  if p_slot not in ('midi', 'soir', 'journee') then
    raise exception 'Créneau inconnu : %. Attendu midi, soir ou journee.', p_slot
      using errcode = 'invalid_parameter_value';
  end if;

  if p_event_date < current_date then
    raise exception 'On ne réserve pas une date passée.'
      using errcode = 'PT400', hint = 'FE003';
  end if;

  -- Une demande ne se pose que sur une salle publiée : un brouillon n'est pas
  -- en vente, même si son propriétaire en connaît l'identifiant.
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

  -- Le créneau est déjà pris. Ce contrôle est un CONFORT, pas la garantie : une
  -- demande pending ne bloque rien (§5.1), et c'est l'index uniq_booking_slot
  -- (§6.1) qui arbitre pour de bon, au moment de la confirmation.
  --
  -- C'est lui, en pratique, qui attrape le cas de la maquette : le client a
  -- ouvert le calendrier quand la date était libre, quelqu'un d'autre a confirmé
  -- entre-temps, et il appuie sur « Envoyer ». D'où un code à lui, FE001 : ce
  -- refus-là n'est pas une erreur du client, c'est une course qu'il a perdue, et
  -- l'écran doit le lui dire en français.
  if exists (
    select 1 from public.bookings b
    where b.venue_id   = p_venue_id
      and b.event_date = p_event_date
      and b.slot       = any (v_slots)
      and b.status in ('confirmed', 'completed')
  ) then
    raise exception 'Ce créneau est déjà réservé.'
      using errcode = 'PT409', hint = 'FE001';
  end if;

  perform public.notify_user(
    v_owner, 'booking_requested',
    jsonb_build_object('venue_id', p_venue_id, 'group_id', v_group,
                       'event_date', p_event_date, 'slot', p_slot)
  );

  -- CTE : plpgsql ne sait pas renvoyer directement un INSERT ... RETURNING.
  -- Les deux lignes d'une journée entière partent dans UNE seule instruction —
  -- c'est ce que vérifie le trigger bookings_check_journee (§6.1).
  return query
  with created as (
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
    from unnest(v_slots) as s
    returning public.bookings.*
  )
  select c.* from created c;
end;
$$;

comment on function public.request_booking(uuid, date, text, integer, text, text, uuid[]) is
  'Pose une demande (§3, étape 3). Insère les deux lignes d''une journée entière en une instruction (§6.1). '
  'Le montant vient du trigger bookings_set_price, donc d''estimate_price() — aucune règle de prix ici. '
  'Chaque refus porte son code Ferha dans son hint : FE001 créneau pris, FE002 bloqué, '
  'FE003 date passée, FE004 salle fermée, FE005 sa propre salle, FE006 non connecté. '
  'Le SQLSTATE PTxxx, lui, ne sert qu''à donner son code HTTP à PostgREST.';

revoke execute on function public.request_booking(uuid, date, text, integer, text, text, uuid[])
  from public, anon;
grant execute on function public.request_booking(uuid, date, text, integer, text, text, uuid[])
  to authenticated;
