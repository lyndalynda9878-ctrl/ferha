-- =============================================================================
-- 030 — salles_pour_agent rend aussi le nom ARABE de la wilaya
--
-- « البلida ». Le modèle a écrit Blida à cheval sur deux écritures — trois
-- lettres arabes, puis quatre latines, dans un seul mot. Illisible dans l'une
-- comme dans l'autre, et introuvable dans une recherche.
--
-- La règle 9 du prompt interdisait déjà de couper le nom d'une SALLE. Elle
-- s'étend maintenant à tout nom propre, et un nom propre a besoin d'une source :
-- interdire la coupure sans fournir la forme arabe, c'est demander au modèle de
-- la retrouver de mémoire. C'est précisément ce qu'il a raté.
--
-- LA COLONNE EXISTE DÉJÀ : `wilayas.name_ar`, renseignée pour les 58 wilayas.
-- Elle ne sortait simplement pas jusqu'ici. On la fait remonter dans le contexte
-- pour que le nom arabe soit une DONNÉE, et non un souvenir — c'est la même
-- règle que pour le prix, la capacité et les équipements (règle 10 : le modèle
-- ne dit d'une salle que ce que le contexte contient).
--
-- LES COMMUNES N'ONT PAS D'ÉQUIVALENT. `venues.commune` est un texte libre en
-- écriture latine, et il n'existe pas de table des communes. Une commune s'écrit
-- donc en latin, même au milieu d'une phrase en arabe — ce que le prompt dit
-- explicitement plutôt que de laisser le modèle inventer « أولاد يعيش » et le
-- couper en chemin. Le jour où une table des communes existera, avec un nom
-- arabe, cette exception tombera.
--
-- ENCORE UN DROP : changer le RETURNS TABLE change la signature de sortie, et
-- `create or replace` refuse. Voir la migration 029, même raison.
-- =============================================================================

drop function if exists public.salles_pour_agent(
  extensions.vector, text, text, text, date, text, integer, numeric, text,
  text[], integer, text, integer
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
  p_parking_min  integer default null,
  p_ordre        text default null,
  p_limit        integer default 8
)
returns table (
  venue_id        uuid,
  name            text,
  commune         text,
  wilaya_name     text,
  -- Le nom arabe de la wilaya, pour qu'une réponse en arabe l'écrive
  -- entièrement en arabe au lieu de le couper en deux écritures.
  wilaya_name_ar  text,
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
         w.name_ar,
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
   where p_parking_min is null
      or (s.parking_spaces is not null and s.parking_spaces >= p_parking_min)
   order by
     case when p_ordre = 'parking' then s.parking_spaces end desc nulls last,
     case when p_ordre = 'prix'    then s.price          end asc  nulls last,
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
  'départage. wilaya_name_ar donne la forme arabe du nom de wilaya, pour '
  'qu''une réponse en arabe ne coupe pas un nom propre entre deux écritures.';

revoke execute on function public.salles_pour_agent from public, anon, authenticated;
