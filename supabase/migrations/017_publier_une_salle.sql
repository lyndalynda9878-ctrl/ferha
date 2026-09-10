-- =============================================================================
-- Ferha — 017_publier_une_salle.sql
-- Le propriétaire inscrit sa salle (§4.3, OWN-01 ; écran 10 des maquettes).
--
-- CE QUE CE FICHIER APPORTE
--
--   creer_salle()                  la salle naît en « draft », avec ses
--                                  équipements et ses types d'événement
--   envoyer_salle_en_validation()  draft → pending, et le contrôle humain
--                                  d'ADM-01 prend la suite
--
-- DEUX TEMPS, ET PAS UN SEUL. On pourrait tout faire d'un coup — créer la salle
-- directement en « pending ». Ce serait juste aujourd'hui et faux demain : les
-- photos (OWN-02, étape suivante) ont besoin d'un `venue_id` pour leur chemin
-- de Storage `{venue_id}/{uuid}.webp`. Il faut donc que la salle EXISTE avant
-- qu'on puisse lui en attacher une. Le brouillon est cet entre-deux : il porte
-- un identifiant, il n'est visible de personne, et rien ne s'y engage. Les
-- photos viendront se glisser entre les deux fonctions de ce fichier sans en
-- déplacer une ligne.
--
-- UNE SEULE FONCTION POUR LA SALLE, SES ÉQUIPEMENTS ET SES TYPES, ET C'EST TOUT
-- OU RIEN. Trois appels séparés depuis Flutter laisseraient, sur une 4G qui
-- coupe (§7.3), une salle sans équipements dont personne ne saurait qu'elle est
-- incomplète — et le propriétaire recommencerait tout en créant un doublon. Une
-- fonction, une transaction : ou les trois écritures passent, ou aucune.
--
-- LE PROPRIÉTAIRE N'EST PAS UN PARAMÈTRE. `creer_salle()` ne demande pas à qui
-- appartient la salle : elle le lit dans `auth.uid()`. C'est ce qui rend
-- « créer une salle au nom d'un autre » non pas interdit mais INEXPRIMABLE —
-- il n'y a aucun argument par lequel le mentir. Le statut non plus n'est pas un
-- paramètre : il vaut « draft », en dur.
--
-- ET LE STATUT NE DÉPASSE JAMAIS « pending » PAR ICI.
-- `envoyer_salle_en_validation()` écrit « pending » en dur, et le trigger
-- `venues_guard_status` (001) reste posé sous elle : SECURITY DEFINER ne
-- l'endort pas — il lit `auth.uid()`, qui est toujours celui du propriétaire.
-- Publier reste une décision d'administration (ADM-01 : « aucune salle n'est
-- visible avant contrôle humain »).
--
-- CRÉER SA PREMIÈRE SALLE FAIT DE VOUS UN PROPRIÉTAIRE, dans la même
-- transaction. `profiles.is_owner` commande l'entrée de l'espace propriétaire
-- (profil_screen.dart) : sans cette ligne, une cliente qui inscrit une salle
-- n'aurait plus aucun chemin pour la retrouver. Le drapeau suit donc le fait,
-- au lieu de le précéder.
--
-- CODES FERHA DE CE FICHIER — la série de la publication. Elle commence à 030
-- pour laisser à l'agenda (FE020–FE022, migration 016) la place de s'étendre.
--
--   FE030  PT401  il faut être connecté
--   FE031  PT400  un champ obligatoire manque
--   FE032  PT400  wilaya inconnue
--   FE033  PT400  équipement ou type d'événement inconnu
--   FE034  PT403  cette salle n'est pas la vôtre
--   FE035  PT409  cette salle n'est plus un brouillon
--
-- CE QUI N'EST PAS ICI, ET QUI MANQUE VRAIMENT : la grille tarifaire (OWN-03).
-- Une salle sortie de ce fichier n'a aucune ligne dans `venue_pricing`, et
-- `search_venues()` fait une jointure INTERNE dessus : publiée, elle resterait
-- introuvable. Voir supabase/README.md, « Ce qui manque encore ».
--
-- Rejouable : les deux fonctions sont remplacées.
-- Dépend de : 001 (venues, venue_amenities, amenities, venues_guard_status),
--             002 (owns_venue), 009 (wilayas), 010 (event_types,
--             venue_event_types).
-- =============================================================================

-- =============================================================================
-- creer_salle — la salle naît en brouillon, complète
--
-- SECURITY DEFINER, et ce n'est PAS pour contourner RLS : les politiques de 002
-- laisseraient déjà le propriétaire écrire tout cela lui-même. C'est pour la
-- dernière ligne — `profiles.is_owner`. Une politique qui laisserait un compte
-- se déclarer propriétaire n'aurait aucun sens ; ici, le drapeau ne se lève que
-- pour qui vient VRAIMENT de créer une salle, et la fonction est le seul chemin.
--
-- LES VALIDATIONS D'ICI DOUBLENT LES CONTRAINTES DE LA TABLE, à dessein. Les
-- `CHECK` de `venues` (001) sont le dernier mot et le resteront ; mais un
-- `check_violation` brut arrive chez PostgREST en 400 sans rien de lisible, et
-- l'écran afficherait « new row violates check constraint venues_name_check ».
-- Les contrôles ci-dessous ne protègent donc rien de plus : ils donnent une
-- phrase à ce qui échoue.
-- =============================================================================

create or replace function public.creer_salle(
  p_name            text,
  p_wilaya_code     text,
  p_commune         text,
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
    owner_id, name, wilaya_code, commune, capacity_seated,
    area_sqm, parking_spaces, description, status
  )
  values (
    auth.uid(), v_nom, p_wilaya_code, v_commune, p_capacity_seated,
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

comment on function public.creer_salle(text, text, text, integer, integer, integer, text, text[], text[]) is
  'Inscrit une salle en brouillon avec ses équipements et ses types d''événement (§4.3, OWN-01), '
  'en une seule transaction. Le propriétaire vient d''auth.uid() et le statut est « draft » : '
  'ni l''un ni l''autre n''est un paramètre. Lève is_owner sur le profil.';

revoke execute on function public.creer_salle(text, text, text, integer, integer, integer, text, text[], text[])
  from public, anon;
grant  execute on function public.creer_salle(text, text, text, integer, integer, integer, text, text[], text[])
  to authenticated;

-- =============================================================================
-- envoyer_salle_en_validation — draft → pending
--
-- LE PROPRIÉTAIRE VA JUSQUE-LÀ ET PAS PLUS LOIN. ADM-01 : « aucune salle n'est
-- visible avant contrôle humain (photos réelles, adresse plausible,
-- propriétaire joignable) ». Cette fonction écrit « pending » en dur ; il n'y a
-- pas de paramètre de statut, donc pas de « published » à glisser. Et sous
-- elle, le trigger `venues_guard_status` (001) refuserait de toute façon — être
-- SECURITY DEFINER ne l'endort pas, puisqu'il lit `auth.uid()`, qui reste celui
-- du propriétaire.
--
-- ON N'ENVOIE QU'UN BROUILLON. Renvoyer une salle déjà en attente ne ferait
-- rien de mal, mais dirait au propriétaire qu'il vient d'agir alors que sa
-- demande dormait déjà dans la file de l'administration ; et renvoyer une salle
-- publiée la retirerait du catalogue, ce qui serait franchement mauvais. Le
-- refus est donc explicite (FE035), et sa phrase dit où en est la salle.
-- =============================================================================

create or replace function public.envoyer_salle_en_validation(p_venue_id uuid)
returns setof public.venues
language plpgsql
security definer
set search_path = public
as $$
declare
  v_statut text;
begin
  if auth.uid() is null then
    raise exception 'Il faut être connecté pour envoyer une salle en validation.'
      using errcode = 'PT401', hint = 'FE030';
  end if;

  if not public.owns_venue(p_venue_id) then
    -- Le même message qu'une salle inexistante, et c'est volontaire : répondre
    -- « elle n'est pas à vous » sur un identifiant tiré au hasard confirmerait
    -- qu'il existe.
    raise exception 'Cette salle n''est pas la vôtre.'
      using errcode = 'PT403', hint = 'FE034';
  end if;

  select v.status into v_statut
  from public.venues v where v.id = p_venue_id;

  if v_statut is distinct from 'draft' then
    raise exception 'Cette salle n''est plus un brouillon : elle est « % ».', v_statut
      using errcode = 'PT409', hint = 'FE035';
  end if;

  return query
  update public.venues v
     set status = 'pending'
   where v.id = p_venue_id
  returning v.*;
end;
$$;

comment on function public.envoyer_salle_en_validation(uuid) is
  'Le propriétaire envoie son brouillon à la validation humaine (§4.4, ADM-01) : draft → pending. '
  'Le statut est écrit en dur — publier reste une décision d''administration.';

revoke execute on function public.envoyer_salle_en_validation(uuid) from public, anon;
grant  execute on function public.envoyer_salle_en_validation(uuid) to authenticated;
