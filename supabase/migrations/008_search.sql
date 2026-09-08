-- =============================================================================
-- Ferha — 008_search.sql
-- La recherche de salles (§4.2, CLI-01), appelée en RPC depuis Flutter.
--
-- TOUT LE FILTRAGE ET TOUT LE CALCUL DE PRIX SONT ICI. Le code Dart passe des
-- critères et affiche des lignes ; il ne trie pas, ne filtre pas, ne calcule
-- pas. C'est la seule façon de garantir que le prix affiché sur une carte de
-- résultat est le même que celui de la fiche salle et que celui du devis :
-- il vient d'estimate_price(), une seule fois, pour la date demandée.
--
-- « Le prix affiché est déjà calculé pour la date choisie, majorations
-- comprises — pas un "à partir de". » (maquettes, écran 2)
--
-- ⚠ LA VERSION COURANTE DE search_venues() EST DANS 010_event_types.sql.
--
-- Celle d'ici ne pouvait pas filtrer sur le type d'événement : la table qui
-- porte cette information n'existait pas encore. Le fichier reste tel qu'il a
-- été appliqué — on ne réécrit pas une migration passée — mais c'est 010 qui
-- fait foi, et c'est lui qu'il faut modifier.
--
-- Rejouable : la fonction est remplacée.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- search_venues — la recherche filtrée
--
-- POURQUOI SECURITY DEFINER
--
-- La fonction doit savoir si un créneau est déjà pris, et cela se lit dans
-- bookings — table fermée aux visiteurs par la politique du §9, et c'est très
-- bien ainsi : qui a réservé le 14 août ne regarde personne. En droits de
-- l'appelant, un visiteur non connecté ne verrait aucune réservation et la
-- fonction lui proposerait des salles déjà prises.
--
-- Elle s'exécute donc avec les droits de son propriétaire, exactement comme la
-- vue venue_availability (002), et pour la même raison : c'est son propre
-- WHERE qui borne ce qui sort.
--
-- CE QU'ELLE A LE DROIT DE RENVOYER — la règle à tenir si l'on y touche :
-- uniquement des colonnes publiques par nature d'une salle PUBLIÉE. Nom,
-- commune, wilaya, capacité, parking, photo de couverture, équipements, prix,
-- note. Rien d'autre.
--
-- N'Y AJOUTEZ AUCUNE COLONNE sans avoir vérifié qu'un inconnu, non connecté, a
-- le droit de la lire. En particulier : jamais le téléphone du propriétaire
-- (§9), jamais le motif d'un blocage (venue_blackouts.reason), jamais rien de
-- bookings. La réservation ne sert ici qu'à retirer une ligne du résultat —
-- son existence ne doit pas transparaître autrement.
-- -----------------------------------------------------------------------------

create or replace function public.search_venues(
  -- Où. p_query est le champ libre des maquettes : « Wilaya, commune ou nom de
  -- salle ».
  p_query        text    default null,
  p_wilaya_code  text    default null,
  p_commune      text    default null,

  -- Quand. NULL = peu importe : on n'écarte alors aucune salle pour cause de
  -- date prise, mais il faut quand même une date pour tarifer — c'est
  -- aujourd'hui qui sert de référence.
  p_event_date   date    default null,
  p_slot         text    default 'soir',

  -- Combien. p_guest_count sert DEUX fois : il écarte les salles trop petites,
  -- et il entre dans le calcul du prix comme nombre de couverts. C'est ce qui
  -- fait que « 300 invités » affiche le prix pour 300 couverts, supplément
  -- compris, et non le prix de base.
  p_guest_count  integer default null,
  p_max_budget   numeric default null,

  -- Type d'événement (§4.2, CLI-01). ACCEPTÉ MAIS NON FILTRANT — voir la note
  -- en bas de ce fichier.
  p_event_type   text    default null,

  p_amenities    text[]  default null,

  -- 'note', 'prix' ou 'capacite'.
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
  -- Le prix pour la date et le créneau demandés, majorations comprises.
  price           numeric,
  price_slot      text,
  -- NULL quand la salle n'a aucun avis. Pas 0.0 : une note de zéro et une
  -- absence de note ne se ressemblent pas, et l'écran ne doit jamais afficher
  -- « 0,0 (0) » (§5.4).
  rating          numeric,
  review_count    bigint,
  -- Nombre total de salles correspondant aux critères, avant p_limit. C'est le
  -- « 18 salles à Oran » du titre.
  total_count     bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
-- Les colonnes de RETURNS TABLE s'appellent name, commune, price, rating… soit
-- exactement les noms de colonnes qu'on interroge. Tout est qualifié par un
-- alias dans la requête, mais cette directive rend l'erreur impossible plutôt
-- qu'improbable : en cas de doute, plpgsql choisit la colonne, jamais la
-- variable. Les variables locales portent toutes un préfixe v_, et ne peuvent
-- donc pas être prises pour des colonnes.
#variable_conflict use_column
declare
  -- Date de tarification. Toujours une vraie date : estimate_price() en exige
  -- une, et un prix sans date n'est qu'un « à partir de ».
  v_date   date    := coalesce(p_event_date, current_date);
  -- Créneaux réellement occupés. Une journée entière prend midi ET soir (§6.1).
  v_slots  text[]  := case when p_slot = 'journee'
                           then array['midi', 'soir']
                           else array[coalesce(p_slot, 'soir')] end;
  v_slot   text    := coalesce(p_slot, 'soir');
  -- Couverts servant au calcul. 1 quand rien n'est demandé : le supplément par
  -- couvert est alors nul, et le prix affiché est celui de base.
  v_guests integer := greatest(coalesce(p_guest_count, 1), 1);
  v_texte  text    := nullif(btrim(coalesce(p_query, '')), '');
begin
  if v_slot not in ('midi', 'soir', 'journee') then
    raise exception 'Créneau inconnu : %. Attendu midi, soir ou journee.', v_slot
      using errcode = 'invalid_parameter_value';
  end if;

  return query
  select
    v.id,
    v.name,
    v.wilaya_code,
    v.commune,
    v.capacity_seated,
    v.parking_spaces,

    -- La couverture, ou à défaut la première photo de la galerie.
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

    -- LEFT JOIN : pas d'avis, pas de ligne, donc NULL. C'est exactement ce
    -- qu'il faut — l'écran n'affichera pas d'étoiles.
    vr.bayesian_rating,
    coalesce(vr.review_count, 0),

    count(*) over ()
  from public.venues v

  -- Le créneau doit être tarifé. Une salle qui ne vend pas le soir ne peut pas
  -- apparaître dans une recherche du soir, et cette jointure garantit aussi
  -- qu'estimate_price() trouvera sa ligne — elle lève une exception sinon, ce
  -- qui ferait tomber la recherche entière pour une seule salle mal remplie.
  join public.venue_pricing vp
    on vp.venue_id = v.id and vp.slot = v_slot

  -- LE PRIX. Une seule source, ici comme partout (§5.2).
  cross join lateral public.estimate_price(
    v.id, v_date, v_slot, v_guests, '{}'::uuid[]
  ) e

  left join public.venue_ratings vr on vr.venue_id = v.id

  where
    -- Seules les salles publiées se cherchent. Un brouillon n'est pas en vente,
    -- même pour son propriétaire : il le voit dans « Mes salles », pas ici.
    v.status = 'published'

    -- Où
    and (v_texte is null
         or v.name    ilike '%' || v_texte || '%'
         or v.commune ilike '%' || v_texte || '%'
         or v.wilaya_code = v_texte)
    and (p_wilaya_code is null or v.wilaya_code = p_wilaya_code)
    and (p_commune is null or v.commune ilike p_commune)

    -- Combien de couverts
    and (p_guest_count is null or v.capacity_seated >= p_guest_count)

    -- Budget : sur le prix réel de la date, pas sur le prix de base.
    and (p_max_budget is null or e.total <= p_max_budget)

    -- Tous les équipements demandés, pas seulement l'un d'eux : quelqu'un qui
    -- coche « climatisation » et « espace femmes » veut les deux.
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
    and (p_event_date is null or not exists (
          select 1 from public.bookings b
          where b.venue_id   = v.id
            and b.event_date = p_event_date
            and b.slot       = any (v_slots)
            -- Seules les réservations confirmées bloquent (§5.1) : une demande
            -- en attente n'enlève la salle à personne.
            and b.status in ('confirmed', 'completed')
        ))

  order by
    -- « Les mieux notées » : les salles sans avis passent après celles qui en
    -- ont, sans disparaître pour autant.
    case when p_order = 'note'     then vr.bayesian_rating end desc nulls last,
    case when p_order = 'note'     then vr.review_count    end desc nulls last,
    case when p_order = 'prix'     then e.total            end asc,
    case when p_order = 'capacite' then v.capacity_seated  end desc,
    -- Départage stable : sans lui, deux pages successives peuvent montrer deux
    -- fois la même salle et en oublier une autre.
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
  'd''estimate_price() pour la date demandée, majorations comprises. '
  'SECURITY DEFINER pour lire les disponibilités dans bookings — ne renvoyer que '
  'des colonnes publiques d''une salle publiée.';

-- Un visiteur non connecté doit pouvoir chercher : c'est le parcours du §3,
-- dont les deux premières étapes se font sans compte.
grant execute on function public.search_venues(
  text, text, text, date, text, integer, numeric, text, text[], text, integer, integer
) to anon, authenticated;

-- =============================================================================
-- p_event_type : IL FILTRE, DEPUIS 010_event_types.sql
--
-- À l'écriture de ce fichier, aucune table du §6 ne disait quels événements une
-- salle accueille. Le paramètre était donc accepté sans servir : inventer une
-- colonne et la laisser vide aurait fait un filtre qui ne renvoie jamais rien,
-- ce qui est pire que pas de filtre.
--
-- La signature avait été écrite pour ce jour-là : 010_event_types.sql apporte
-- venue_event_types, branche le filtre, et n'a eu à changer que le corps de la
-- fonction. Aucun appel côté Flutter n'a bougé.
-- =============================================================================
