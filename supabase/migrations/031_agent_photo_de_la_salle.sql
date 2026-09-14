-- =============================================================================
-- Ferha — 031_agent_photo_de_la_salle.sql
-- salles_pour_agent rend aussi la photo de couverture (maquettes, écran 8).
--
-- POURQUOI UNE COLONNE DE PLUS. L'écran 8 ne montre pas une liste de noms : il
-- montre des CARTES — photo, nom, commune, prix —, et chacune ouvre la vraie
-- fiche. C'est ce qui fait la différence entre un agent qui cite et un agent qui
-- mène quelque part. La photo manquait, et une carte sans photo est un trou dans
-- la rangée.
--
-- `search_venues()` LA RENDAIT DÉJÀ. Elle sort de la même requête que le reste,
-- sous le nom `cover_photo` : il n'y a ni jointure ni sous-select à ajouter,
-- seulement une colonne à laisser passer. C'est pour cela que ce fichier est
-- court.
--
-- =============================================================================
-- ELLE NE VA PAS DANS LE CONTEXTE DU MODÈLE, ET C'EST DÉLIBÉRÉ
--
-- L'Edge Function sépare désormais deux choses qui étaient une seule :
--
--   * ce que le MODÈLE voit           — nom, commune, capacité, équipements,
--                                       prix, note. Pas la photo.
--   * ce que l'APPLICATION reçoit     — la même chose, plus la photo.
--
-- Un chemin de Storage n'aide pas à rédiger trois phrases ; il occupe du
-- contexte, et le §8.5 tient parce que ce contexte est PAUVRE. Chaque champ
-- ajouté est de la matière à reformuler — et à déborder. La photo s'affiche,
-- elle ne se raconte pas.
--
-- =============================================================================
-- ENCORE UN DROP, POUR LA TROISIÈME FOIS
--
-- Ajouter une colonne au RETURNS TABLE change la signature de sortie, et
-- `create or replace` refuse. Le DROP porte la signature d'ENTRÉE de la 030 —
-- inchangée ici : on ne touche à aucun paramètre.
--
-- Dépend de : 023 (search_venues et son cover_photo), 027 (venue_embeddings),
--             029, 030 (la fonction qu'on remplace).
--
-- Rejouable : drop conditionnel, fonction remplacée.
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
  wilaya_name_ar  text,
  -- La photo de couverture, chemin de Storage ou URL — c'est `urlPhoto()` qui
  -- tranche côté Flutter, comme pour toutes les autres listes de salles.
  -- Elle part vers l'APPLICATION et non vers le modèle : voir l'en-tête.
  cover_photo     text,
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
         s.cover_photo,
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
  'qu''une réponse en arabe ne coupe pas un nom propre entre deux écritures. '
  'cover_photo sert la CARTE de l''écran 8 et ne va pas dans le contexte du '
  'modèle : une photo s''affiche, elle ne se raconte pas.';

revoke execute on function public.salles_pour_agent from public, anon, authenticated;
