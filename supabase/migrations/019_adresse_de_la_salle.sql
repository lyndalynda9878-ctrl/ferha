-- =============================================================================
-- Ferha — 019_adresse_de_la_salle.sql
-- L'adresse d'une salle : exigée pour l'inscrire, invisible au public.
--
-- CE QUE CE FICHIER APPORTE
--
--   venues.address                 la rue, telle qu'on la dit en Algérie
--   SELECT colonne par colonne     `address` ne sort plus de la table
--   creer_salle()  REDÉFINIE       elle exige désormais l'adresse
--
-- POURQUOI CETTE COLONNE MANQUAIT VRAIMENT. ADM-01 : « aucune salle n'est
-- visible avant contrôle humain (photos réelles, ADRESSE PLAUSIBLE,
-- propriétaire joignable) ». Le J12 a écrit le chemin qui mène une salle
-- jusqu'à ce contrôle sans jamais lui demander d'adresse : la personne qui
-- valide devait juger « plausible » quelque chose qu'elle n'avait pas. La
-- commune et la wilaya ne suffisent pas — elles disent la ville, pas le lieu.
--
-- NULLABLE EN TABLE, OBLIGATOIRE À LA CRÉATION, et les deux à la fois n'est pas
-- une contradiction. Les quinze salles de démonstration existent depuis 001 et
-- n'ont pas d'adresse ; un `not null` les rendrait inécrivables, et inventer
-- quinze adresses fausses pour satisfaire une contrainte serait la pire des
-- réponses — le back-office validerait alors des rues qui n'existent pas. La
-- contrainte vit donc là où arrivent les salles NEUVES : dans `creer_salle()`.
-- Le jour où les salles de démonstration porteront une vraie adresse, le
-- `not null` pourra descendre dans la table.
--
-- ⚠ L'ADRESSE NE SORT PAS. Ni `venue_detail()`, ni `search_venues()`, ni
-- `owner_venues()`, ni aucune vue ne la nomment — mais cela n'aurait pas suffi,
-- et c'est le point le moins évident de ce fichier. La politique
-- `venues_select_published_or_own` (002) laisse un inconnu lire la LIGNE d'une
-- salle publiée ; RLS borne les lignes, jamais les colonnes. Un simple
--
--   GET /rest/v1/venues?select=address
--
-- avec la clé anon aurait donc rendu l'adresse des treize salles publiées, sans
-- qu'aucune fonction ne soit en cause. D'où la seconde moitié de ce fichier :
-- le droit de SELECT est repris sur la table et redonné colonne par colonne.
--
-- POURQUOI L'ADRESSE EST PRIVÉE ALORS QU'ON VIENT S'Y MARIER. Parce que la
-- plateforme se ferait contourner dès la première recherche — c'est le même
-- raisonnement que le §9 sur les téléphones. Une adresse et un nom suffisent à
-- appeler la salle directement. Le client obtient l'adresse quand il a de quoi
-- s'en servir : à partir de « accepted », comme le numéro (§9). Le chemin
-- viendra avec la carte (CLI-02) ; voir supabase/README.md, « Ce qui manque
-- encore ».
--
-- CODES FERHA DE CE FICHIER — la suite de la série de la publication (017) :
--
--   FE036  PT400  l'adresse manque
--
-- Rejouable : la colonne, la contrainte, les droits et la fonction se reposent
--             sans erreur ni doublon.
-- Dépend de : 001 (venues), 002 (venues_select_published_or_own), 017
--             (creer_salle, dont ce fichier porte désormais la version
--             courante).
-- =============================================================================

-- =============================================================================
-- La colonne
-- =============================================================================

alter table public.venues
  add column if not exists address text;

-- Une adresse faite de blancs n'est pas une adresse. Même raison qu'ailleurs :
-- la contrainte est le dernier mot, la fonction donne la phrase.
alter table public.venues
  drop constraint if exists venues_address_not_blank;
alter table public.venues
  add  constraint venues_address_not_blank
  check (address is null or length(btrim(address)) > 0);

comment on column public.venues.address is
  'Rue et repères — « Cité 200 logements, route de l''aéroport ». Sert au contrôle humain '
  'd''ADM-01 (« adresse plausible »). NE SORT PAR AUCUNE FONCTION NI VUE PUBLIQUE : le droit '
  'de SELECT est donné colonne par colonne (019), address exclue.';

-- =============================================================================
-- Le droit de lire, colonne par colonne
--
-- RLS BORNE LES LIGNES ; LES DROITS DE COLONNE BORNENT LES COLONNES. Les deux
-- sont nécessaires, et c'est le second qui manquait. On reprend donc le SELECT
-- de la table — hérité des droits par défaut de Supabase — et on le rend sur
-- les quatorze colonnes qui étaient déjà publiques hier. Aucune lecture
-- existante ne change : `venue_detail()` (012), la seule fonction qui lise
-- `venues` avec les droits de l'appelant, ne nomme que des colonnes de cette
-- liste.
--
-- CE QUE CELA COÛTE, ET POURQUOI ON LE PAIE. Une colonne ajoutée demain à
-- `venues` sera invisible tant qu'on ne l'aura pas ajoutée ici. C'est un oubli
-- qui se voit tout de suite — la donnée ne sort pas — plutôt qu'un oubli qui ne
-- se voit jamais : une colonne privée lisible de tous. « En cas de doute, la
-- réponse est non », comme pour venue_availability (002).
--
-- LE PROPRIÉTAIRE RELIT SON ADRESSE PAR UNE FONCTION, PAS PAR LA TABLE.
-- `creer_salle()` et `envoyer_salle_en_validation()` rendent `setof venues` en
-- SECURITY DEFINER : les droits de colonne ne s'appliquent pas au résultat
-- d'une fonction, et le propriétaire y retrouve son adresse — la sienne, et
-- seulement la sienne.
-- =============================================================================

revoke select on public.venues from anon, authenticated;

grant select (
  id, owner_id, name, wilaya_code, commune, lat, lng,
  capacity_seated, area_sqm, parking_spaces, description, status,
  created_at, updated_at
) on public.venues to anon, authenticated;

-- =============================================================================
-- creer_salle — VERSION COURANTE
--
-- Identique à celle de 017, à l'adresse près. Tout ce que 017 explique reste
-- vrai mot pour mot : le propriétaire vient d'`auth.uid()` et n'est pas un
-- paramètre, le statut vaut « draft » en dur, les trois écritures tiennent dans
-- une seule transaction, et les validations d'ici ne font que donner une phrase
-- à ce que les CHECK de la table refuseraient de toute façon.
--
-- ⚠ LA VERSION DE 017 EST SUPPRIMÉE, pas seulement remplacée : la signature
-- change, et deux versions d'une même fonction cohabiteraient sous deux jeux
-- d'arguments. PostgREST choisirait alors celle qui correspond au corps JSON
-- reçu — c'est-à-dire l'ancienne, sans adresse, dès qu'un client oublierait le
-- champ. Une salle sans adresse redeviendrait possible par la petite porte.
--
-- L'ADRESSE EST LE QUATRIÈME PARAMÈTRE, à côté de la commune, parce que c'est
-- là qu'elle se lit. Elle est SANS défaut : un appel qui l'oublie ne compile
-- pas côté PostgREST au lieu d'écrire une salle muette.
-- =============================================================================

drop function if exists public.creer_salle(
  text, text, text, integer, integer, integer, text, text[], text[]
);

create or replace function public.creer_salle(
  p_name            text,
  p_wilaya_code     text,
  p_commune         text,
  p_address         text,
  p_capacity_seated integer,
  p_area_sqm        integer default null,
  p_parking_spaces  integer default null,
  p_description     text    default null,
  p_amenities       text[]  default '{}',
  p_event_types     text[]  default '{}'
)
returns setof public.venues
language plpgsql
security definer
set search_path = public
as $$
declare
  v_venue    uuid;
  v_nom      text := btrim(coalesce(p_name, ''));
  v_commune  text := btrim(coalesce(p_commune, ''));
  v_adresse  text := btrim(coalesce(p_address, ''));
  v_inconnus text;
begin
  if auth.uid() is null then
    raise exception 'Il faut être connecté pour inscrire une salle.'
      using errcode = 'PT401', hint = 'FE030';
  end if;

  -- Les quatre colonnes que la table impose. Tout le reste est facultatif, et
  -- le rester est une décision produit : Karim ne connaît pas toujours sa
  -- superficie, et une salle reste publiable sans elle.
  if v_nom = '' or v_commune = ''
     or p_wilaya_code is null
     or p_capacity_seated is null or p_capacity_seated <= 0 then
    raise exception
      'Le nom, la wilaya, la commune et la capacité sont obligatoires.'
      using errcode = 'PT400', hint = 'FE031';
  end if;

  -- L'ADRESSE, ET SON REFUS À ELLE. Un code distinct de FE031 parce que la
  -- phrase à dire est distincte : « il manque le nom, la wilaya, la commune ou
  -- la capacité » enverrait chercher aux étapes 1 et 3 un champ qui est à
  -- l'étape 2.
  if v_adresse = '' then
    raise exception
      'L''adresse de la salle est obligatoire : elle est vérifiée avant publication.'
      using errcode = 'PT400', hint = 'FE036',
            detail  = 'ADM-01 : aucune salle n''est visible avant contrôle humain, '
                      'et ce contrôle porte notamment sur l''adresse.';
  end if;

  if not exists (select 1 from public.wilayas w where w.code = p_wilaya_code) then
    raise exception 'Wilaya inconnue : %.', p_wilaya_code
      using errcode = 'PT400', hint = 'FE032',
            detail  = 'Les codes valides sont dans la table wilayas.';
  end if;

  -- Les codes sont vérifiés AVANT l'insertion, et tous ensemble. Les clés
  -- étrangères de venue_amenities et venue_event_types les refuseraient de
  -- toute façon — mais une par une, et en `foreign_key_violation` : le
  -- propriétaire apprendrait qu'un code est faux sans savoir lequel, puis
  -- recommencerait pour découvrir le suivant.
  select string_agg(c, ', ' order by c) into v_inconnus
  from unnest(coalesce(p_amenities, '{}')) as c
  where not exists (select 1 from public.amenities a where a.code = c);

  if v_inconnus is not null then
    raise exception 'Équipement inconnu : %.', v_inconnus
      using errcode = 'PT400', hint = 'FE033';
  end if;

  select string_agg(c, ', ' order by c) into v_inconnus
  from unnest(coalesce(p_event_types, '{}')) as c
  where not exists (select 1 from public.event_types t where t.code = c);

  if v_inconnus is not null then
    raise exception 'Type d''événement inconnu : %.', v_inconnus
      using errcode = 'PT400', hint = 'FE033';
  end if;

  -- LA SALLE. `owner_id` vient d'`auth.uid()` et le statut est écrit en dur :
  -- ni l'un ni l'autre n'est un paramètre, il n'y a donc rien à mentir.
  insert into public.venues (
    owner_id, name, wilaya_code, commune, address, capacity_seated,
    area_sqm, parking_spaces, description, status
  )
  values (
    auth.uid(), v_nom, p_wilaya_code, v_commune, v_adresse, p_capacity_seated,
    -- Le zéro se distingue de l'absence sur le parking : NULL veut dire « non
    -- renseigné », 0 veut dire « pas de parking » (001). On ne transforme donc
    -- pas l'un en l'autre en passant.
    p_area_sqm, p_parking_spaces,
    nullif(btrim(coalesce(p_description, '')), ''), 'draft'
  )
  returning id into v_venue;

  -- `distinct` : deux fois le même code dans le tableau reçu ne doit pas faire
  -- échouer la clé primaire (venue_id, amenity_code) et perdre toute la salle.
  insert into public.venue_amenities (venue_id, amenity_code)
  select distinct v_venue, c from unnest(coalesce(p_amenities, '{}')) as c;

  insert into public.venue_event_types (venue_id, event_type)
  select distinct v_venue, c from unnest(coalesce(p_event_types, '{}')) as c;

  -- Le drapeau qui ouvre l'espace propriétaire. On n'écrit que s'il change :
  -- une écriture par salle créée pour reposer la même valeur ne sert personne,
  -- et fait bouger `updated_at` sans raison.
  update public.profiles p
     set is_owner = true
   where p.id = auth.uid() and not p.is_owner;

  return query select * from public.venues v where v.id = v_venue;
end;
$$;

comment on function public.creer_salle(text, text, text, text, integer, integer, integer, text, text[], text[]) is
  'Inscrit une salle en brouillon avec son adresse, ses équipements et ses types d''événement '
  '(§4.3, OWN-01), en une seule transaction. L''adresse est obligatoire — elle est ce que le '
  'contrôle humain d''ADM-01 vérifie — et ne ressort d''aucune lecture publique. Le propriétaire '
  'vient d''auth.uid() et le statut est « draft » : ni l''un ni l''autre n''est un paramètre.';

revoke execute on function public.creer_salle(text, text, text, text, integer, integer, integer, text, text[], text[])
  from public, anon;
grant  execute on function public.creer_salle(text, text, text, text, integer, integer, integer, text, text[], text[])
  to authenticated;
