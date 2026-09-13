-- =============================================================================
-- Ferha — 028_agent.sql
-- Ce dont l'agent a besoin côté base (§8.1, §8.5 ; §4.2 CLI-02).
--
-- CE FICHIER NE CONTIENT AUCUNE INTELLIGENCE. Il pose deux choses : la requête
-- unique du §8.1 — tri exact puis classement vectoriel — et le journal des
-- conversations. Le modèle de langage vit dans l'Edge Function « ai-chat » ;
-- ici, on ne fait que filtrer, classer et noter.
--
-- =============================================================================
-- POURQUOI UNE SEULE FONCTION POUR LE TRI ET LE CLASSEMENT
--
-- Le §8.1 le dit en une phrase : « la similarité ne sait pas compter ». Elle
-- rapprochera « 300 personnes » de « 250 personnes » et proposera une salle
-- déjà réservée. Le tri exact — wilaya, capacité, budget, disponibilité — doit
-- donc se faire AVANT, et il se fait dans `search_venues()`, écrite au J8 et
-- qui n'a pas bougé depuis.
--
-- On aurait pu appeler les deux fonctions l'une après l'autre depuis l'Edge
-- Function et croiser les résultats en TypeScript. C'est ce qu'il ne faut pas
-- faire : `recherche_semantique()` classe TOUTES les salles publiées, et il
-- faudrait lui demander les cinquante premières pour espérer y retrouver les
-- deux qui survivent au filtre. Ici, le filtre décide de l'ensemble et le
-- vecteur ne décide que de l'ordre — ce qui est exactement l'inverse, et ce que
-- le §8.1 demande.
--
-- =============================================================================
-- LE PRIX SORT D'ICI, ET DE NULLE PART AILLEURS (§8.5)
--
-- `search_venues()` rend un prix calculé pour chaque salle : celui de la date
-- et du créneau demandés quand ils sont connus, le tarif du soir sinon. Ce
-- nombre traverse l'Edge Function sans être touché et arrive au modèle déjà
-- calculé. Le modèle n'a donc jamais à faire une multiplication — et c'est
-- précisément ce qu'un modèle de langage fait mal et avec aplomb.
--
-- =============================================================================
-- LE JOURNAL NE PORTE AUCUNE DONNÉE PERSONNELLE
--
-- Pas d'identifiant d'utilisateur, pas d'adresse IP, pas de session. Une ligne
-- d'`ai_conversations` dit ce qui a été demandé et ce que l'agent a répondu,
-- sans dire par qui. C'est assez pour améliorer l'agent — relire les questions
-- auxquelles il a mal répondu est le seul moyen de le corriger — et trop peu
-- pour reconstituer le parcours de quelqu'un.
--
-- LA QUESTION EST GARDÉE TELLE QUELLE, et c'est le seul champ qui pourrait
-- contenir un nom si l'utilisateur en écrit un. Sans identifiant à côté, il
-- n'est rattachable à personne.
--
-- Dépend de : 008 (search_venues), 027 (venue_embeddings, recherche_semantique).
-- Rejouable : table conditionnelle, fonctions remplacées.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- ai_conversations — ce que l'agent a fait, et en combien de temps
-- -----------------------------------------------------------------------------

create table if not exists public.ai_conversations (
  id           uuid primary key default gen_random_uuid(),
  created_at   timestamptz not null default now(),

  -- La question posée, mot pour mot. Aucun identifiant à côté.
  question     text not null,

  -- « fr », « ar », « mixte » — ce que le modèle a cru reconnaître. Sert à
  -- savoir si le darja est aussi bien servi que le français (§8.4).
  langue       text,

  -- Les critères extraits, tels que le modèle les a rendus. En jsonb parce
  -- qu'ils bougeront : le jour où l'on extraira « proche de la mer », la
  -- colonne n'a pas à changer.
  criteres     jsonb,

  -- Les salles réellement proposées, dans l'ordre. C'est ce qui permet de
  -- relire une réponse douteuse six mois plus tard.
  venue_ids    uuid[],

  -- Combien de salles le tri exact a laissé passer. `0` avec une question
  -- sensée est le signal qu'un filtre est trop serré.
  nb_candidats integer,

  -- Combien de fois la génération a dû être rejouée parce que le modèle citait
  -- une salle absente du contexte (§8.5). Au-dessus de zéro en moyenne, c'est
  -- le prompt système qu'il faut reprendre.
  rejeux       integer not null default 0,

  duree_ms     integer,
  modele       text,

  -- « ok », « aucune_salle », « hors_sujet », « liste_brute », « quota »,
  -- « erreur ». C'est la colonne qu'on compte pour savoir si l'agent tient.
  statut       text not null
);

comment on table public.ai_conversations is
  'Journal de l''agent (§8.5) : la question, les critères extraits, les salles '
  'proposées, la durée. AUCUNE donnée personnelle — ni utilisateur, ni IP, ni '
  'session : une ligne dit ce qui a été demandé, jamais par qui.';

create index if not exists ai_conversations_created_at_idx
  on public.ai_conversations (created_at desc);

alter table public.ai_conversations enable row level security;

-- Aucune politique : comme venue_embeddings, la table ne sort pas côté client.
revoke all on public.ai_conversations from anon, authenticated;

-- =============================================================================
-- salles_pour_agent — LA REQUÊTE UNIQUE DU §8.1
--
-- LE FILTRE DÉCIDE DE L'ENSEMBLE, LE VECTEUR DÉCIDE DE L'ORDRE.
--
-- `p_query` de `search_venues()` RESTE NULL, volontairement. C'est une
-- recherche plein texte stricte : « jardin » n'y rend aucune salle, alors que
-- trois en ont un dans leur description. Lui passer la partie floue de la
-- question viderait le résultat au lieu de l'enrichir. Le flou est le travail
-- du vecteur, et de lui seul.
--
-- LA LIMITE INTÉRIEURE EST LARGE (60). Le tri exact doit rendre TOUT ce qui
-- convient ; c'est le classement qui coupe ensuite. L'inverse — couper à huit
-- avant de classer — laisserait le hasard de l'ordre SQL décider quelles salles
-- le vecteur a le droit de voir.
--
-- UN VECTEUR ABSENT NE FAIT PAS DISPARAÎTRE UNE SALLE. Une salle publiée mais
-- pas encore indexée — créée entre deux passages d'`embed-venue` — sort quand
-- même, en fin de liste (`nulls last`). Elle est moins bien placée, elle n'est
-- pas cachée : le tri exact a dit qu'elle convenait, et c'est lui qui fait foi.
--
-- `p_embedding` PEUT ÊTRE NULL, et alors on classe par note. C'est le cas où le
-- service d'empreintes n'a pas répondu : l'agent répond quand même, un peu
-- moins finement, plutôt que de ne pas répondre.
-- =============================================================================

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
   order by
     case when p_embedding is null then null
          else e.embedding <=> p_embedding end asc nulls last,
     s.rating desc nulls last,
     s.name asc
   limit greatest(1, least(coalesce(p_limit, 8), 20));
$$;

comment on function public.salles_pour_agent is
  'La requête unique du §8.1 : search_venues() fait le tri EXACT — wilaya, '
  'capacité, budget, disponibilité —, puis la distance cosinus ne fait que '
  'CLASSER ce qui a survécu. Aucun seuil. Le prix vient de search_venues() et '
  'arrive déjà calculé. p_query reste null à dessein : le plein texte est '
  'strict et viderait le résultat, le flou est le travail du vecteur.';

revoke execute on function public.salles_pour_agent from public, anon, authenticated;

-- =============================================================================
-- journaliser_conversation — une ligne par question, écrite par l'Edge Function
--
-- ELLE NE LÈVE JAMAIS. Un journal qui fait échouer la requête qu'il journalise
-- transforme un incident de traçabilité en panne visible par l'utilisateur. En
-- cas de problème, elle rend NULL et se tait ; l'agent a déjà répondu.
-- =============================================================================

create or replace function public.journaliser_conversation(
  p_question     text,
  p_langue       text default null,
  p_criteres     jsonb default null,
  p_venue_ids    uuid[] default null,
  p_nb_candidats integer default null,
  p_rejeux       integer default 0,
  p_duree_ms     integer default null,
  p_modele       text default null,
  p_statut       text default 'ok'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  insert into public.ai_conversations
    (question, langue, criteres, venue_ids, nb_candidats, rejeux,
     duree_ms, modele, statut)
  values
    (p_question, p_langue, p_criteres, p_venue_ids, p_nb_candidats,
     coalesce(p_rejeux, 0), p_duree_ms, p_modele, p_statut)
  returning id into v_id;

  return v_id;
exception when others then
  -- Voir l'en-tête : on ne fait pas tomber une réponse déjà rendue.
  return null;
end;
$$;

comment on function public.journaliser_conversation is
  'Écrit une ligne d''ai_conversations (§8.5). Ne lève jamais : un journal qui '
  'fait échouer la requête qu''il journalise transforme un incident de '
  'traçabilité en panne visible.';

revoke execute on function public.journaliser_conversation from public, anon, authenticated;
