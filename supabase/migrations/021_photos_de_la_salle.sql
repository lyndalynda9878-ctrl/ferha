-- =============================================================================
-- Ferha — 021_photos_de_la_salle.sql
-- Le propriétaire ajoute ses photos (§7.3, OWN-02 ; écran 10 des maquettes).
--
-- CE QUE CE FICHIER APPORTE
--
--   le bucket « venue-photos »     public, borné en taille et en type
--   les politiques de storage      seul le propriétaire écrit dans son dossier
--   photos_min() / photos_max()    5 et 20, écrits UNE fois
--   deux garde-fous de table       la couverture EST la première photo,
--                                  et la 21e n'entre pas
--   ajouter_photo()                une ligne de plus, à la fin de la galerie
--   supprimer_photo()              la ligne s'en va, et les rangs se resserrent
--   reordonner_photos()            l'ordre complet, en une écriture
--   envoyer_salle_en_validation()  refuse désormais sous 5 photos
--
-- OÙ CETTE ÉTAPE SE GLISSE. 017 avait laissé la place en toutes lettres : la
-- salle naît en brouillon par `creer_salle()`, et le brouillon existe justement
-- pour que les photos aient un `venue_id` avant d'exister — leur chemin est
-- `{venue_id}/{uuid}.webp`. Ce fichier remplit ce creux, et ne déplace rien :
-- `creer_salle()` n'est pas touchée, et `envoyer_salle_en_validation()` gagne
-- une condition sans changer de forme.
--
-- LE BUCKET EST PUBLIC, ET CE N'EST PAS UN RELÂCHEMENT (§7.3). Une photo de
-- salle est faite pour être vue par des inconnus non connectés : c'est la
-- première chose qu'une famille regarde dans les résultats de recherche. Signer
-- chaque URL coûterait un aller-retour par vignette sur une liste de vingt
-- salles, et pour cacher... des photos que leur propriétaire publie exprès.
-- Ce qui est protégé ici est l'ÉCRITURE : les politiques ci-dessous n'ouvrent
-- le dossier `{venue_id}/` qu'au propriétaire de cette salle-là.
--
-- PAS DE TRANSFORMATIONS D'IMAGE, ET DONC UNE SEULE TAILLE ENVOYÉE. Le §7.3
-- annonce « miniatures générées à la volée par les transformations d'image du
-- Storage » ; elles sont réservées aux offres payantes, et le projet coûte
-- 0 DA. On envoie donc UN fichier par photo, déjà réduit à 1600 px de large
-- côté appareil, et les vignettes des cartes affichent ce même fichier. Voir
-- supabase/README.md, « Les photos ».
--
-- LA COUVERTURE N'EST PAS UN CHOIX SÉPARÉ, C'EST UN RANG. `is_cover` et
-- `position` ne peuvent plus se contredire parce que l'un est une FONCTION de
-- l'autre : `check (is_cover = (position = 0))`. Il n'y a donc pas deux gestes
-- — réordonner, puis désigner la couverture — mais un seul, et aucune fenêtre
-- pendant laquelle la salle aurait deux couvertures ou aucune. C'est aussi ce
-- que dit la maquette : « la première devient la couverture ».
--
-- CODES FERHA DE CE FICHIER — la suite de la série de la publication (017), qui
-- s'arrêtait à FE037 :
--
--   FE038  PT400  cette salle a déjà 20 photos
--   FE039  PT404  cette photo n'existe pas, ou n'est pas la vôtre
--   FE040  PT400  l'ordre envoyé ne correspond pas aux photos de la salle
--   FE041  PT400  moins de 5 photos : pas d'envoi en validation
--   FE042  PT400  ce chemin n'est pas dans le dossier de cette salle
--
-- Rejouable : le bucket est mis à jour s'il existe, les politiques et les
--             contraintes sont déposées avant d'être reposées, les fonctions
--             sont remplacées.
-- Dépend de : 001 (venues, venue_photos), 002 (owns_venue), 017 et 020
--             (envoyer_salle_en_validation, dont ce fichier porte la version
--             courante).
-- =============================================================================

-- =============================================================================
-- Les deux nombres, écrits une fois
--
-- 5 ET 20 VIVENT ICI, ET NULLE PART AILLEURS EN SQL. Le trigger, les fonctions
-- et les messages les lisent ; changer la borne un jour est une ligne à
-- reprendre, pas une chasse. C'est la règle qu'on applique au prix
-- (`estimate_price()`) et au téléphone (`telephone_valide()`).
--
-- Il en existe UN second exemplaire, côté Flutter, pour éteindre « Continuer »
-- sous cinq photos sans demander la permission à la base à chaque vignette
-- ajoutée. Deux exemplaires, pas trois — et `tests/008_photos_de_la_salle.sql`
-- avec `test/photos_salle_ecran_test.dart` les épinglent chacun de leur côté.
-- =============================================================================

create or replace function public.photos_min()
returns integer
language sql
immutable
set search_path = public
as $$ select 5 $$;

comment on function public.photos_min() is
  'Le nombre de photos sans lequel une salle ne part pas en validation (§4.3, OWN-02).';

create or replace function public.photos_max()
returns integer
language sql
immutable
set search_path = public
as $$ select 20 $$;

comment on function public.photos_max() is
  'Le nombre de photos au-delà duquel la base refuse (§4.3, OWN-02).';

grant execute on function public.photos_min() to anon, authenticated;
grant execute on function public.photos_max() to anon, authenticated;

-- =============================================================================
-- venue_du_chemin — de « {venue_id}/{uuid}.webp » à la salle
--
-- LE SEUL ENDROIT OÙ LE CHEMIN DE STORAGE EST DÉCOUPÉ. Les politiques de
-- `storage.objects` et `ajouter_photo()` posent la même question — « à quelle
-- salle appartient ce fichier ? » — et une seconde façon de la découper finirait
-- par répondre autre chose que la première.
--
-- ELLE REND NULL PLUTÔT QUE DE LEVER, et c'est ce qui compte. Un client qui
-- téléverse dans « bidule/x.webp » doit se voir REFUSER, pas provoquer une
-- erreur 500 : `split_part(...)::uuid` sur du non-uuid lèverait
-- `invalid_text_representation` au milieu de l'évaluation d'une politique. Le
-- filtre par expression régulière écarte cela avant la conversion, et
-- `owns_venue(null)` répond « non » — ce qui est la bonne réponse.
-- =============================================================================

create or replace function public.venue_du_chemin(p_name text)
returns uuid
language sql
immutable
set search_path = public
as $$
  select case
           when split_part(coalesce(p_name, ''), '/', 1)
                ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
           then split_part(p_name, '/', 1)::uuid
         end;
$$;

comment on function public.venue_du_chemin(text) is
  'La salle à qui appartient un chemin « {venue_id}/{uuid}.webp » (§7.3). '
  'NULL si le premier segment n''est pas un uuid — un chemin inventé se refuse, il ne lève pas.';

grant execute on function public.venue_du_chemin(text) to anon, authenticated;

-- =============================================================================
-- Le bucket
--
-- LES DEUX BORNES SONT SUR LE BUCKET, ET NON DANS L'APPLICATION. Une limite de
-- taille et une liste de types vérifiées côté Flutter ne protègent que ceux qui
-- passent par Flutter ; posées ici, elles valent pour n'importe quel appel avec
-- la clé anon.
--
--   2 Mo — une photo de 1600 px de large en WebP à 80 % pèse 150 à 400 Ko. Deux
--   mégaoctets laissent de l'air à une photo très détaillée tout en refusant
--   nettement un original de 4 Mo qui aurait échappé à la compression : c'est
--   exactement ce qu'on veut attraper, parce que c'est cela qui fait abandonner
--   le propriétaire au milieu du formulaire (§7.3).
--
--   image/webp et image/jpeg, et RIEN D'AUTRE. Le JPEG est le repli assumé des
--   navigateurs qui ne savent pas encoder du WebP. Le PNG est absent exprès :
--   `canvas.toDataURL('image/webp')` retombe SILENCIEUSEMENT sur du PNG quand
--   le navigateur ne connaît pas le WebP, et un PNG de photo pèse cinq fois le
--   JPEG équivalent. L'application renifle déjà les octets produits pour ne
--   jamais nommer « .webp » un fichier qui n'en est pas un ; cette liste est le
--   filet sous ce reniflement.
-- =============================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'venue-photos',
  'venue-photos',
  true,
  2 * 1024 * 1024,
  array['image/webp', 'image/jpeg']
)
on conflict (id) do update
  set public            = excluded.public,
      file_size_limit   = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- -----------------------------------------------------------------------------
-- Les politiques d'écriture sur storage.objects
--
-- TROIS PORTES, ET PAS QUATRE. Ajouter, lire, supprimer ; pas de mise à jour.
-- Un envoi qui a échoué se refait sous un NOUVEL uuid — le nom d'un fichier de
-- photo n'a aucune raison d'être réutilisé, et une porte qu'on n'ouvre pas est
-- une porte qu'on n'a pas à surveiller.
--
-- POURQUOI UNE POLITIQUE DE LECTURE SUR UN BUCKET PUBLIC — ce n'est pas une
-- contradiction, et l'oublier casse la suppression. Deux chemins mènent à un
-- fichier, et un seul passe par RLS :
--
--   * `/object/public/venue-photos/...` — ce que met `getPublicUrl()` dans un
--     `Image.network`. Il ne consulte AUCUNE politique : c'est le drapeau
--     `public` du bucket qui décide, et c'est pour cela que les photos
--     s'affichent chez un visiteur non connecté ;
--
--   * `storage.objects`, la table qui indexe le bucket. Elle, est sous RLS.
--
-- Or supprimer un fichier commence par le RETROUVER : PostgreSQL applique les
-- politiques `select` à un `DELETE ... WHERE`, et l'API Storage cherche l'objet
-- avant de l'effacer. Sans politique de lecture, la suppression ne trouve rien,
-- n'efface rien et ne se plaint de rien — le fichier resterait dans le bucket
-- après que sa ligne a disparu de la galerie. C'est exactement l'orphelin que
-- `supprimer_photo()` cherche à éviter.
--
-- Elle porte donc le MÊME prédicat que les deux autres : le propriétaire de la
-- salle, et lui seul. Personne ne gagne le droit de lire une photo — elles sont
-- déjà publiques par l'autre chemin ; ce qui s'ouvre ici est le droit
-- d'ÉNUMÉRER le dossier de sa propre salle, ce qu'il faut pour y faire le
-- ménage.
-- -----------------------------------------------------------------------------

drop policy if exists venue_photos_storage_insert on storage.objects;
create policy venue_photos_storage_insert
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'venue-photos'
    and public.owns_venue(public.venue_du_chemin(name))
  );

drop policy if exists venue_photos_storage_select on storage.objects;
create policy venue_photos_storage_select
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'venue-photos'
    and public.owns_venue(public.venue_du_chemin(name))
  );

drop policy if exists venue_photos_storage_delete on storage.objects;
create policy venue_photos_storage_delete
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'venue-photos'
    and public.owns_venue(public.venue_du_chemin(name))
  );

-- =============================================================================
-- Les garde-fous de la table
-- =============================================================================

-- -----------------------------------------------------------------------------
-- La couverture EST la première photo
--
-- Un `CHECK` plutôt qu'un trigger, parce qu'il ne s'agit pas d'une règle mais
-- d'une DÉFINITION : `is_cover` n'a plus de valeur propre, il redit `position`.
-- Deux couvertures deviennent inexprimables, une salle qui en perdrait sa
-- couverture aussi — il n'y a plus rien à synchroniser.
-- -----------------------------------------------------------------------------

alter table public.venue_photos
  drop constraint if exists venue_photos_cover_is_first;
alter table public.venue_photos
  add  constraint venue_photos_cover_is_first
  check (is_cover = ("position" = 0));

-- -----------------------------------------------------------------------------
-- Un rang par photo, et DEFERRABLE
--
-- POURQUOI DEFERRABLE, ALORS QUE LA CONTRAINTE EST IMMÉDIATE PARTOUT AILLEURS.
-- Réordonner une galerie est une PERMUTATION : la photo qui était troisième
-- devient première pendant que la première devient deuxième. Dans un `UPDATE`
-- unique, PostgreSQL vérifie l'unicité au fur et à mesure des lignes ; la
-- deuxième ligne réécrite tombe alors sur un rang que la troisième n'a pas
-- encore libéré, et l'ordre entier est refusé pour une collision qui n'existe
-- plus à la fin de l'instruction. `set constraints ... deferred` repousse la
-- vérification à la fin de la transaction, où l'ordre est de nouveau cohérent.
-- Elle reste `initially immediate` : seules les deux fonctions qui permutent la
-- diffèrent, tout le reste est vérifié sur-le-champ.
-- -----------------------------------------------------------------------------

alter table public.venue_photos
  drop constraint if exists venue_photos_position_unique;
alter table public.venue_photos
  add  constraint venue_photos_position_unique
  unique (venue_id, "position")
  deferrable initially immediate;

-- -----------------------------------------------------------------------------
-- L'index de 001 s'en va, remplacé par plus fort que lui
--
-- `venue_photos_one_cover_per_venue` disait « au plus une couverture par
-- salle ». Le `CHECK` du dessus et l'unicité du rang le disent DÉJÀ, et disent
-- plus : au plus une photo au rang 0, donc au plus une couverture, ET pas deux
-- photos au même rang, ET la couverture forcément première.
--
-- Il ne suffit pas qu'il soit redondant, il FAUT qu'il parte : un index unique
-- créé par `create unique index` ne peut pas être différé, et il referait
-- échouer la permutation que la contrainte du dessus vient d'autoriser.
--
-- Une base neuve applique 001 puis 021 dans l'ordre et finit ici. C'est le
-- fichier le plus récent qui dit l'état courant — 001 n'est pas réécrit, on ne
-- réécrit pas une migration déjà appliquée.
-- -----------------------------------------------------------------------------

drop index if exists public.venue_photos_one_cover_per_venue;

-- -----------------------------------------------------------------------------
-- La 21e photo n'entre pas
--
-- UN TRIGGER, PARCE QU'UN `CHECK` NE SAIT PAS COMPTER SES VOISINS. Il porte le
-- code FE038 lui-même : `ajouter_photo()` ne recompte donc pas derrière lui —
-- ce serait une seconde règle à tenir à jour pour une phrase déjà juste.
--
-- LE VERROU SUR LA SALLE N'EST PAS DU ZÈLE. L'écran des photos envoie les
-- fichiers EN PARALLÈLE — c'est ce qui fait tenir six photos lourdes en moins
-- de vingt secondes. Deux insertions simultanées qui compteraient chacune
-- vingt en laisseraient passer vingt-deux. Le `for update` sur la ligne de
-- `venues` sérialise les ajouts d'une même salle, et d'elle seule.
-- -----------------------------------------------------------------------------

create or replace function public.venue_photos_guard_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nombre integer;
begin
  perform 1 from public.venues v where v.id = new.venue_id for update;

  select count(*) into v_nombre
  from public.venue_photos p where p.venue_id = new.venue_id;

  if v_nombre >= public.photos_max() then
    raise exception 'Une salle ne peut pas avoir plus de % photos.', public.photos_max()
      using errcode = 'PT400', hint = 'FE038',
            detail  = 'OWN-02 : de 5 à 20 photos par salle.';
  end if;

  return new;
end;
$$;

comment on function public.venue_photos_guard_count() is
  'Trigger BEFORE INSERT : refuse la 21e photo d''une salle (§4.3, OWN-02), FE038.';

drop trigger if exists venue_photos_guard_count on public.venue_photos;
create trigger venue_photos_guard_count
  before insert on public.venue_photos
  for each row execute function public.venue_photos_guard_count();

-- =============================================================================
-- ajouter_photo — une ligne de plus, à la fin de la galerie
--
-- LE FICHIER EST DÉJÀ DANS LE BUCKET QUAND ON ARRIVE ICI. L'application
-- téléverse d'abord, écrit la ligne ensuite, et cet ordre est le bon : un
-- fichier sans ligne est invisible et ne coûte que de la place ; une ligne sans
-- fichier est un trou dans la galerie d'une salle publiée. On préfère la panne
-- qu'on ne voit pas.
--
-- LE RANG N'EST PAS UN PARAMÈTRE. Une photo qui arrive va à la fin, point — et
-- `is_cover` se déduit du rang, comme partout dans ce fichier. La première
-- photo d'une salle vide devient donc sa couverture sans que personne ne l'ait
-- demandé, ce qui est exactement ce que dit la maquette.
--
-- LE CHEMIN EST VÉRIFIÉ CONTRE LA SALLE (FE042). Les politiques de
-- `storage.objects` empêchent déjà d'écrire un FICHIER hors de son dossier ;
-- rien n'empêcherait d'écrire une LIGNE qui pointe ailleurs. Sans ce contrôle,
-- une salle pourrait afficher la photo d'une autre.
-- =============================================================================

create or replace function public.ajouter_photo(
  p_venue_id     uuid,
  p_storage_path text
)
returns setof public.venue_photos
language plpgsql
security definer
set search_path = public
as $$
declare
  v_chemin text := btrim(coalesce(p_storage_path, ''));
  v_rang   integer;
  v_photo  uuid;
begin
  if auth.uid() is null then
    raise exception 'Il faut être connecté pour ajouter une photo.'
      using errcode = 'PT401', hint = 'FE030';
  end if;

  if not public.owns_venue(p_venue_id) then
    raise exception 'Cette salle n''est pas la vôtre.'
      using errcode = 'PT403', hint = 'FE034';
  end if;

  if public.venue_du_chemin(v_chemin) is distinct from p_venue_id then
    raise exception 'Ce chemin n''est pas dans le dossier de cette salle : %.', v_chemin
      using errcode = 'PT400', hint = 'FE042',
            detail  = 'Le chemin attendu est « {venue_id}/{uuid}.webp » (§7.3).';
  end if;

  -- Le même verrou que le trigger, pris AVANT de calculer le rang : deux envois
  -- simultanés qui liraient tous deux « le dernier rang est 3 » viseraient tous
  -- deux le rang 4, et l'unicité en refuserait un — un envoi perdu pour rien.
  perform 1 from public.venues v where v.id = p_venue_id for update;

  select coalesce(max(p."position") + 1, 0) into v_rang
  from public.venue_photos p where p.venue_id = p_venue_id;

  insert into public.venue_photos (venue_id, storage_path, "position", is_cover)
  values (p_venue_id, v_chemin, v_rang, v_rang = 0)
  returning id into v_photo;

  return query select * from public.venue_photos p where p.id = v_photo;
end;
$$;

comment on function public.ajouter_photo(uuid, text) is
  'Attache une photo déjà téléversée à la fin de la galerie d''une salle (§4.3, OWN-02). '
  'Le rang et la couverture ne sont pas des paramètres : la photo va à la fin, et la '
  'couverture est toujours la première.';

revoke execute on function public.ajouter_photo(uuid, text) from public, anon;
grant  execute on function public.ajouter_photo(uuid, text) to authenticated;

-- =============================================================================
-- supprimer_photo — la ligne s'en va, et les rangs se resserrent
--
-- ELLE REND LE CHEMIN, ET C'EST LE POINT. « Supprimer une photo supprime la
-- ligne ET le fichier » : le fichier vit dans le Storage, que le SQL ne touche
-- pas. La fonction rend donc à l'appelant ce qu'il lui faut pour finir le
-- travail.
--
-- LA LIGNE D'ABORD, LE FICHIER ENSUITE, et l'ordre inverse serait un vrai bug.
-- Si le fichier partait le premier et que la ligne restait — réseau coupé entre
-- les deux —, la galerie d'une salle publiée montrerait un trou à tout le
-- monde. Dans cet ordre-ci, l'accident laisse un fichier orphelin que personne
-- ne voit et qui coûte deux cents kilo-octets. On choisit la panne invisible.
--
-- LES RANGS SE REFERMENT DERRIÈRE. Sans cela, supprimer la première photo
-- laisserait la salle SANS couverture — plus aucune ligne au rang 0 —, et
-- `search_venues()` retomberait sur « la première par position », ce qui marche
-- par chance et non par construction. La renumérotation rétablit 0..n-1 et
-- redonne la couverture à celle qui est devenue première.
-- =============================================================================

create or replace function public.supprimer_photo(p_photo_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_venue  uuid;
  v_chemin text;
begin
  if auth.uid() is null then
    raise exception 'Il faut être connecté pour supprimer une photo.'
      using errcode = 'PT401', hint = 'FE030';
  end if;

  select p.venue_id, p.storage_path into v_venue, v_chemin
  from public.venue_photos p where p.id = p_photo_id;

  -- Une photo inconnue et la photo d'un autre donnent la même phrase : répondre
  -- « elle n'est pas à vous » sur un identifiant tiré au hasard confirmerait
  -- qu'il existe. C'est la règle de FE034, appliquée aux photos.
  if v_venue is null or not public.owns_venue(v_venue) then
    raise exception 'Cette photo est introuvable.'
      using errcode = 'PT404', hint = 'FE039';
  end if;

  perform 1 from public.venues v where v.id = v_venue for update;

  delete from public.venue_photos p where p.id = p_photo_id;

  -- Voir la contrainte `venue_photos_position_unique` : la renumérotation fait
  -- glisser tous les rangs d'un cran, et chaque ligne vise donc le rang que sa
  -- voisine n'a pas encore libéré.
  set constraints public.venue_photos_position_unique deferred;

  update public.venue_photos p
     set "position" = r.rang,
         is_cover   = (r.rang = 0)
    from (
      select p2.id,
             (row_number() over (order by p2."position") - 1)::integer as rang
      from public.venue_photos p2
      where p2.venue_id = v_venue
    ) r
   where p.id = r.id
     and (p."position" is distinct from r.rang
          or p.is_cover is distinct from (r.rang = 0));

  return v_chemin;
end;
$$;

comment on function public.supprimer_photo(uuid) is
  'Retire une photo de la galerie et rend son storage_path, que l''appelant efface du bucket '
  '(§4.3, OWN-02). Les rangs se referment derrière, et la nouvelle première devient la couverture.';

revoke execute on function public.supprimer_photo(uuid) from public, anon;
grant  execute on function public.supprimer_photo(uuid) to authenticated;

-- =============================================================================
-- reordonner_photos — l'ordre complet, en une écriture
--
-- LA LISTE DOIT ÊTRE EXACTEMENT CELLE DE LA SALLE (FE040), ni partielle ni
-- rallongée. Deux raisons, et la seconde est la vraie.
--
-- La première : un ordre partiel laisserait les photos absentes de la liste à
-- des rangs quelconques, et il n'existe aucune réponse évidente à « où les
-- mettre ». Refuser vaut mieux que deviner.
--
-- La seconde : c'est un contrôle de concurrence gratuit. Si le propriétaire a
-- ajouté une photo depuis un second téléphone pendant qu'il réordonnait sur le
-- premier, la liste envoyée ne correspond plus — et au lieu de faire disparaître
-- silencieusement la nouvelle venue, la base refuse et l'écran relit.
--
-- UNE SEULE INSTRUCTION POUR TOUTE LA GALERIE. Vingt `UPDATE` successifs
-- passeraient par vingt états intermédiaires dont aucun n'est cohérent ; ici,
-- chaque ligne reçoit son rang ET sa couverture en même temps, si bien que le
-- `CHECK` de la couverture tient pour chacune, à chaque instant.
-- =============================================================================

create or replace function public.reordonner_photos(
  p_venue_id  uuid,
  p_photo_ids uuid[]
)
returns setof public.venue_photos
language plpgsql
security definer
set search_path = public
as $$
declare
  v_recues integer := coalesce(array_length(p_photo_ids, 1), 0);
  v_connues integer;
begin
  if auth.uid() is null then
    raise exception 'Il faut être connecté pour réordonner vos photos.'
      using errcode = 'PT401', hint = 'FE030';
  end if;

  if not public.owns_venue(p_venue_id) then
    raise exception 'Cette salle n''est pas la vôtre.'
      using errcode = 'PT403', hint = 'FE034';
  end if;

  perform 1 from public.venues v where v.id = p_venue_id for update;

  -- Trois vérifications en deux comptes : autant d'identifiants DISTINCTS que
  -- de photos reçues (donc pas de doublon), et autant de photos de CETTE salle
  -- parmi eux que la salle en a (donc ni oubli, ni intrus).
  select count(*) into v_connues
  from public.venue_photos p
  where p.venue_id = p_venue_id;

  if v_recues <> v_connues
     or v_recues <> (select count(distinct id) from unnest(p_photo_ids) as id)
     or v_recues <> (
          select count(*) from public.venue_photos p
          where p.venue_id = p_venue_id and p.id = any(p_photo_ids)
        )
  then
    raise exception
      'L''ordre envoyé ne correspond pas aux photos de cette salle (% reçues, % en base).',
      v_recues, v_connues
      using errcode = 'PT400', hint = 'FE040',
            detail  = 'Envoyez la liste complète des photos de la salle, sans doublon.';
  end if;

  -- Voir `supprimer_photo()` : une permutation traverse des collisions de rang
  -- qui n'existent plus à la fin de l'instruction.
  set constraints public.venue_photos_position_unique deferred;

  update public.venue_photos p
     set "position" = r.rang,
         is_cover   = (r.rang = 0)
    from (
      select t.id, (t.ord - 1)::integer as rang
      from unnest(p_photo_ids) with ordinality as t(id, ord)
    ) r
   where p.id = r.id
     and p.venue_id = p_venue_id
     and (p."position" is distinct from r.rang
          or p.is_cover is distinct from (r.rang = 0));

  return query
  select * from public.venue_photos p
  where p.venue_id = p_venue_id
  order by p."position";
end;
$$;

comment on function public.reordonner_photos(uuid, uuid[]) is
  'Réécrit l''ordre complet de la galerie d''une salle (§4.3, OWN-02). La première de la liste '
  'devient la couverture. Refuse une liste qui n''est pas exactement celle de la salle (FE040).';

revoke execute on function public.reordonner_photos(uuid, uuid[]) from public, anon;
grant  execute on function public.reordonner_photos(uuid, uuid[]) to authenticated;

-- =============================================================================
-- envoyer_salle_en_validation — la version de 020, plus le compte des photos
--
-- CE QUI CHANGE : un refus de plus, FE041, sous cinq photos. Rien d'autre —
-- le numéro, la propriété et le statut sont mot pour mot ceux de 020.
--
-- POURQUOI EN BASE, ALORS QUE L'ÉCRAN ÉTEINT DÉJÀ SON BOUTON. ADM-01 demande
-- « des photos réelles » avant toute publication : c'est une condition
-- d'existence de la salle au catalogue, pas une politesse d'interface. Un écran
-- qui compte est un écran ; un client modifié, un vieil APK ou un appel direct
-- avec la clé anon n'ont pas cet écran. La règle qui compte est celle qui reste
-- quand on retire Flutter.
--
-- LE COMPTE VIENT APRÈS LE STATUT, ET C'EST L'ORDRE DE LECTURE DU PROPRIÉTAIRE.
-- Une salle déjà envoyée doit s'entendre dire qu'elle est déjà partie (FE035),
-- pas qu'il lui manque des photos qu'elle a peut-être.
-- =============================================================================

create or replace function public.envoyer_salle_en_validation(
  p_venue_id uuid,
  p_phone    text
)
returns setof public.venues
language plpgsql
security definer
set search_path = public
as $$
declare
  v_statut text;
  v_phone  text := public.telephone_normalise(p_phone);
  v_photos integer;
begin
  if auth.uid() is null then
    raise exception 'Il faut être connecté pour envoyer une salle en validation.'
      using errcode = 'PT401', hint = 'FE030';
  end if;

  -- LE NUMÉRO D'ABORD, avant même de regarder la salle. Un refus qui parle du
  -- numéro pendant que le vrai problème est ailleurs perdrait le propriétaire ;
  -- l'ordre inverse, lui, ne coûte rien.
  if not public.telephone_valide(v_phone) then
    raise exception
      'Un numéro de téléphone valide est nécessaire : mobile 05, 06 ou 07 suivi de '
      '8 chiffres, ou fixe 02, 03 ou 04 suivi de 7 chiffres.'
      using errcode = 'PT400', hint = 'FE037',
            detail  = 'ADM-01 demande un propriétaire joignable avant toute publication.';
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

  select count(*) into v_photos
  from public.venue_photos p where p.venue_id = p_venue_id;

  if v_photos < public.photos_min() then
    raise exception
      'Il faut au moins % photos pour envoyer votre salle : il y en a %.',
      public.photos_min(), v_photos
      using errcode = 'PT400', hint = 'FE041',
            detail  = 'ADM-01 : aucune salle n''est visible avant contrôle humain (photos réelles).';
  end if;

  -- On n'écrit que si le numéro change : reposer la même valeur ferait bouger
  -- `updated_at` sans raison, et le trigger de normalisation ferait retomber
  -- `phone_verified` sur un numéro qui n'a pas bougé.
  update public.profiles p
     set phone = v_phone
   where p.id = auth.uid() and p.phone is distinct from v_phone;

  return query
  update public.venues v
     set status = 'pending'
   where v.id = p_venue_id
  returning v.*;
end;
$$;

comment on function public.envoyer_salle_en_validation(uuid, text) is
  'Le propriétaire envoie son brouillon à la validation humaine (§4.4, ADM-01) : draft → pending. '
  'Reçoit le numéro auquel le joindre et l''écrit dans profiles.phone ; refuse sans lui (FE037), '
  'et refuse sous photos_min() photos (FE041). '
  'Le statut est écrit en dur — publier reste une décision d''administration.';

revoke execute on function public.envoyer_salle_en_validation(uuid, text) from public, anon;
grant  execute on function public.envoyer_salle_en_validation(uuid, text) to authenticated;
