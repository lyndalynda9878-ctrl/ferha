-- =============================================================================
-- 029 — salles_pour_agent : le parking et le prix deviennent des critères
--
-- DEUX DÉFAUTS DU BANC DU J20, ET LE MÊME EN DESSOUS.
--
-- Q14, « نحتاج قاعة فيها بلاصة للطوموبيلات بزاف » — beaucoup de places de
-- parking. L'agent proposait les parkings de 75 et 55 places quand la base en
-- a un de 150 et un de 110. Ce n'était pas une erreur du modèle : le nombre de
-- places n'entrait NULLE PART dans la requête. Il partait dans `soft_query`, au
-- vecteur, et le §8.1 dit pourquoi c'était perdu d'avance — « la similarité ne
-- sait pas compter ». Elle rapproche « beaucoup de parking » d'une description
-- qui parle de voitures, pas du plus grand nombre.
--
-- Q13 et Q23, « une salle pas chère » — l'agent citait la salle chère à côté de
-- la bon marché. Même cause : « pas cher » est un ORDRE, et l'ordre était celui
-- du vecteur.
--
-- parking_spaces EST UNE COLONNE, PAS UN ÉQUIPEMENT. On lui donne donc ce que
-- toute colonne chiffrée mérite : un filtre (`p_parking_min`) et un tri
-- (`p_ordre`). Le prix, déjà calculé par estimate_price() en amont, obtient le
-- même tri — et pas une seconde formule, il n'y en aura jamais qu'une.
--
-- LE VECTEUR RESTE LE CLASSEMENT PAR DÉFAUT. `p_ordre` null, et rien ne change :
-- c'est toujours la distance cosinus qui ordonne, puis la note, puis le nom.
-- Quand `p_ordre` est donné, le vecteur ne disparaît pas — il passe en second et
-- départage les ex æquo. Une demande chiffrée se tranche par le chiffre ; ce que
-- le chiffre ne sépare pas, le sens le sépare encore.
--
-- ON REMPLACE PAR UN DROP, ET NON PAR UN CREATE OR REPLACE. Ajouter des
-- paramètres change la signature : `create or replace` ne remplacerait rien, il
-- créerait une SECONDE fonction du même nom, et PostgREST aurait deux candidates
-- pour un même appel. Une ambiguïté à l'exécution, découverte en production.
-- =============================================================================

drop function if exists public.salles_pour_agent(
  extensions.vector, text, text, text, date, text, integer, numeric, text,
  text[], integer
);

create or replace function public.salles_pour_agent(
  p_embedding    extensions.vector(384) default null,
  p_model        text default null,
  p_wilaya_code  text default null,
  p_commune      text default null,
  p_event_date   date default null,
  p_slot         text default null,
  p_guest_count  integer default null,
  p_max_budget   numeric default null,
  p_event_type   text default null,
  p_amenities    text[] default null,
  -- Le nombre de places exigé, quand la question en donne un chiffre.
  p_parking_min  integer default null,
  -- 'parking', 'prix', ou null pour le classement par le vecteur.
  p_ordre        text default null,
  p_limit        integer default 8
)
returns table (
  venue_id        uuid,
  name            text,
  commune         text,
  wilaya_name     text,
  capacity_seated integer,
  parking_spaces  integer,
  amenity_codes   text[],
  price           numeric,
  price_slot      text,
  rating          numeric,
  review_count    bigint,
  proximite       double precision
)
language sql
stable
security definer
set search_path = public, extensions
as $$
  select s.venue_id,
         s.name,
         s.commune,
         w.name_fr,
         s.capacity_seated,
         s.parking_spaces,
         s.amenity_codes,
         s.price,
         s.price_slot,
         s.rating,
         s.review_count,
         case when p_embedding is null or e.embedding is null then null
              else 1 - (e.embedding <=> p_embedding) end
    from public.search_venues(
           p_query       => null,
           p_wilaya_code => p_wilaya_code,
           p_commune     => p_commune,
           p_event_date  => p_event_date,
           p_slot        => p_slot,
           p_guest_count => p_guest_count,
           p_max_budget  => p_max_budget,
           p_event_type  => p_event_type,
           p_amenities   => p_amenities,
           p_limit       => 60,
           p_offset      => 0) s
    left join public.venue_embeddings e
      on e.venue_id = s.venue_id
     and (p_model is null or e.model = p_model)
    left join public.wilayas w on w.code = s.wilaya_code
   -- UNE EXIGENCE CHIFFRÉE SE FILTRE, elle ne se classe pas. « un parking d'au
   -- moins 100 places » n'est pas une préférence : une salle de 40 places ne
   -- convient pas, et la mettre en fin de liste serait la proposer quand même.
   -- Un parking non renseigné est écarté : on ne sait pas, donc on n'affirme pas.
   where p_parking_min is null
      or (s.parking_spaces is not null and s.parking_spaces >= p_parking_min)
   order by
     -- Le tri demandé d'abord, quand il y en a un.
     case when p_ordre = 'parking' then s.parking_spaces end desc nulls last,
     case when p_ordre = 'prix'    then s.price          end asc  nulls last,
     -- Puis le vecteur : classement principal par défaut, départage ensuite.
     case when p_embedding is null then null
          else e.embedding <=> p_embedding end asc nulls last,
     s.rating desc nulls last,
     s.name asc
   limit greatest(1, least(coalesce(p_limit, 8), 20));
$$;

comment on function public.salles_pour_agent is
  'La requête unique du §8.1 : search_venues() fait le tri EXACT — wilaya, '
  'capacité, budget, disponibilité —, puis le classement ordonne ce qui a '
  'survécu. Aucun seuil. Le prix vient de search_venues() et arrive déjà '
  'calculé. p_query reste null à dessein : le plein texte est strict et '
  'viderait le résultat, le flou est le travail du vecteur. p_parking_min '
  'filtre sur une exigence chiffrée de parking ; p_ordre vaut parking ou prix '
  'quand la demande porte sur l''un des deux, et le vecteur passe alors en '
  'départage.';

revoke execute on function public.salles_pour_agent from public, anon, authenticated;
