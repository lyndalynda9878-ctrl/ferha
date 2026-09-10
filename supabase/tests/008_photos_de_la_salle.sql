-- =============================================================================
-- Ferha — tests/008_photos_de_la_salle.sql
--
-- CE QU'ON VÉRIFIE, SEPT CHOSES, ET AUCUNE N'EST DÉCORATIVE :
--
--   1. LA PREMIÈRE PHOTO EST LA COUVERTURE, sans que personne l'ait demandé.
--      C'est ce que dit la maquette de l'écran 10, et c'est ce que 021 rend
--      inexprimable autrement.
--
--   2. RÉORDONNER DÉPLACE LA COUVERTURE AVEC LE RANG. C'est le test le plus
--      technique du fichier : une permutation de rangs traverse des collisions
--      d'unicité qui n'existent plus à la fin de l'instruction, et sans la
--      contrainte DEFERRABLE de 021 elle serait refusée. Si ce test tombe, le
--      glisser-déposer de l'écran ne marche pas.
--
--   3. JAMAIS DEUX COUVERTURES, et pas seulement « pas par les fonctions ». On
--      pousse la porte de derrière : un UPDATE direct sur la table, comme un
--      client modifié pourrait en faire, doit échouer sur le CHECK.
--
--   4. SUPPRIMER LA COUVERTURE NE LAISSE PAS LA SALLE SANS COUVERTURE. Les
--      rangs se referment, et la deuxième devient première.
--
--   5. LA 21e PHOTO N'ENTRE PAS. Par la fonction ET par la table — c'est le
--      trigger qui refuse, donc les deux chemins.
--
--   6. UN AUTRE COMPTE N'ÉCRIT PAS DANS MON DOSSIER. Ni un fichier dans le
--      bucket (politiques de `storage.objects`), ni une ligne dans ma galerie.
--      C'est le test qui protège les photos de Karim d'Amina et réciproquement,
--      et il se joue en `set local role authenticated` : la vraie clé anon
--      n'est pas le rôle de service.
--
--   7. SOUS 5 PHOTOS, PAS D'ENVOI EN VALIDATION (FE041) — et le contrôle
--      POSITIF juste derrière, sans lequel le précédent ne prouverait rien.
--
-- COMMENT LE LANCER : coller le fichier entier dans l'éditeur SQL de Supabase
-- et exécuter. Une seule fois, d'un bloc.
--
-- COMMENT LE LIRE :
--   * des « NOTICE ... OK » et aucune erreur rouge   → tout va bien ;
--   * une erreur rouge commençant par « ÉCHEC »      → une règle ne tient pas,
--                                                      le message dit laquelle.
--   Certains clients SQL n'affichent que le résultat de la DERNIÈRE instruction,
--   et la dernière ici est ROLLBACK. Un « Success. No rows returned » sans
--   erreur rouge veut dire que tout est passé.
--
-- ON VÉRIFIE LE HINT, PAS LE MESSAGE. C'est le hint que lit l'application
-- (lib/features/owner/owner_messages.dart), et c'est lui le contrat ; le
-- message français, lui, peut être réécrit demain.
--
-- LES BORNES SONT LUES, PAS ÉCRITES. `photos_min()` et `photos_max()` disent 5
-- et 20 ; ce fichier les appelle plutôt que de recopier les nombres. Le jour où
-- la borne bouge, le test suit — c'est tout l'intérêt de les avoir mises dans
-- une fonction.
--
-- CE QU'IL LAISSE : rien. Tout est fait dans une transaction annulée à la fin,
-- y compris les lignes de `storage.objects` — aucun vrai fichier n'est
-- téléversé, on n'écrit que la table qui les indexe, et c'est elle que les
-- politiques gardent.
--
-- Prérequis : migrations 001 à 021 appliquées, et le référentiel des wilayas
--             rempli (009).
-- =============================================================================

begin;

do $$
declare
  c_amina  constant uuid := 'c0000008-0000-4000-a000-000000000001';
  c_karim  constant uuid := 'c0000008-0000-4000-a000-000000000002';
  c_salle  constant uuid := '5a110008-0000-4000-a000-000000000001';

  v_wilaya   text;
  v_sqlstate text;
  v_hint     text;

  v_photos   uuid[];
  v_photo    uuid;
  v_couv     uuid;
  v_rang     integer;
  v_bool     boolean;
  v_nombre   integer;
  v_chemin   text;
begin
  -- ---------------------------------------------------------------------------
  -- Le décor : deux propriétaires, et une salle qui appartient à Amina.
  --
  -- La salle est écrite DIRECTEMENT et non par `creer_salle()` : ce fichier
  -- teste les photos, et passer par le formulaire ferait dépendre ses sept
  -- tests des règles d'un autre (nom, adresse, capacité). C'est
  -- `tests/005_publier_une_salle.sql` qui garde celles-là.
  -- ---------------------------------------------------------------------------
  select w.code into v_wilaya from public.wilayas w order by w.code limit 1;
  if v_wilaya is null then
    raise exception 'ÉCHEC 0 — la table wilayas est vide. Appliquez 009 avant ce test.';
  end if;

  insert into auth.users (instance_id, id, aud, role, email,
                          encrypted_password, email_confirmed_at,
                          created_at, updated_at,
                          raw_app_meta_data, raw_user_meta_data)
  values
    ('00000000-0000-0000-0000-000000000000', c_amina, 'authenticated', 'authenticated',
     'test.amina.008@ferha.test', '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb),
    ('00000000-0000-0000-0000-000000000000', c_karim, 'authenticated', 'authenticated',
     'test.karim.008@ferha.test', '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb);

  insert into public.profiles (id, full_name, email, phone, is_owner) values
    (c_amina, 'Amina Haddad',  'test.amina.008@ferha.test', '0770112233', true),
    (c_karim, 'Karim Belkacem','test.karim.008@ferha.test', '0661998877', true)
  on conflict (id) do update
    set full_name = excluded.full_name,
        phone     = excluded.phone,
        is_owner  = excluded.is_owner;

  insert into public.venues (id, owner_id, name, wilaya_code, commune, address,
                             capacity_seated, status)
  values (c_salle, c_amina, 'Salle Les Palmiers', v_wilaya, 'Bir El Djir',
          'Cité 200 logements, route de l''aéroport', 300, 'draft');

  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_amina, 'role', 'authenticated')::text,
                     true);

  -- ---------------------------------------------------------------------------
  -- Test 1 — la première photo est la couverture, et les suivantes ne le sont
  --          pas
  -- ---------------------------------------------------------------------------
  for v_nombre in 1..4 loop
    select p.id into v_photo
    from public.ajouter_photo(c_salle, c_salle || '/' || gen_random_uuid() || '.webp') p;
    v_photos := coalesce(v_photos, '{}'::uuid[]) || v_photo;
  end loop;

  select p."position", p.is_cover into v_rang, v_bool
  from public.venue_photos p where p.id = v_photos[1];

  if v_rang <> 0 or not v_bool then
    raise exception
      'ÉCHEC 1 — la première photo est au rang %, is_cover=%. Attendu rang 0 et couverture.',
      v_rang, v_bool;
  end if;

  select count(*) into v_nombre
  from public.venue_photos p where p.venue_id = c_salle and p.is_cover;

  if v_nombre <> 1 then
    raise exception 'ÉCHEC 1 — % couverture(s) sur quatre photos, attendu exactement une.',
      v_nombre;
  end if;

  raise notice 'OK 1 — la première photo est la couverture, et elle est seule.';

  -- ---------------------------------------------------------------------------
  -- Test 2 — LA PHOTO DÉPLACÉE EN PREMIÈRE POSITION DEVIENT LA COUVERTURE
  --
  -- On met la quatrième en tête et on garde l'ordre des autres, exactement
  -- comme le fait un glisser-déposer sur l'écran. C'est la permutation qui
  -- ferait échouer une contrainte d'unicité non différée.
  -- ---------------------------------------------------------------------------
  perform * from public.reordonner_photos(
    c_salle,
    array[v_photos[4], v_photos[1], v_photos[2], v_photos[3]]
  );

  select p.id into v_couv
  from public.venue_photos p where p.venue_id = c_salle and p.is_cover;

  if v_couv is distinct from v_photos[4] then
    raise exception
      'ÉCHEC 2 — la couverture est % après réordonnancement, attendu la photo déplacée en tête (%).',
      coalesce(v_couv::text, '(aucune)'), v_photos[4];
  end if;

  select array_agg(p.id order by p."position") into v_photos
  from public.venue_photos p where p.venue_id = c_salle;

  if v_photos[1] is distinct from v_couv then
    raise exception 'ÉCHEC 2 — la couverture n''est pas la première par rang.';
  end if;

  select count(*) into v_nombre
  from public.venue_photos p where p.venue_id = c_salle and p.is_cover;

  if v_nombre <> 1 then
    raise exception 'ÉCHEC 2 — % couverture(s) après réordonnancement.', v_nombre;
  end if;

  raise notice 'OK 2 — la photo passée en tête devient la couverture, et l''ancienne la perd.';

  -- Et le refus d'un ordre incomplet (FE040), qui est ce qui protège une photo
  -- ajoutée depuis un second téléphone pendant qu'on réordonnait sur le premier.
  begin
    perform * from public.reordonner_photos(c_salle, array[v_photos[1], v_photos[2]]);
    raise exception 'ÉCHEC 2 — un ordre partiel a été accepté.';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE040' then
      raise exception 'ÉCHEC 2 — refus attendu FE040 sur un ordre partiel, reçu hint=%.',
        coalesce(v_hint, '(vide)');
    end if;
  end;

  raise notice 'OK 2 bis — un ordre qui n''est pas celui de la salle est refusé (FE040).';

  -- ---------------------------------------------------------------------------
  -- Test 3 — JAMAIS DEUX COUVERTURES, y compris par la porte de derrière
  --
  -- Les politiques RLS de 002 laissent le propriétaire écrire dans
  -- `venue_photos` sans passer par les fonctions. Ce qui l'arrête ici est le
  -- CHECK de 021, et il faut donc le pousser directement.
  -- ---------------------------------------------------------------------------
  begin
    update public.venue_photos p set is_cover = true where p.id = v_photos[2];
    raise exception 'ÉCHEC 3 — une seconde couverture a été posée par un UPDATE direct.';
  exception when check_violation then
    null;   -- c'est exactement ce qu'on attend
  end;

  -- Et l'inverse : une salle ne peut pas non plus perdre sa couverture en
  -- laissant une photo au rang 0.
  begin
    update public.venue_photos p set is_cover = false where p.id = v_photos[1];
    raise exception 'ÉCHEC 3 — la première photo a pu cesser d''être la couverture.';
  exception when check_violation then
    null;
  end;

  raise notice 'OK 3 — is_cover et position ne peuvent pas se contredire, même en écrivant la table.';

  -- ---------------------------------------------------------------------------
  -- Test 4 — supprimer la couverture ne laisse pas la salle sans couverture
  -- ---------------------------------------------------------------------------
  select public.supprimer_photo(v_photos[1]) into v_chemin;

  if v_chemin is null or v_chemin = '' then
    raise exception
      'ÉCHEC 4 — supprimer_photo() n''a pas rendu le chemin du fichier. Sans lui, '
      'l''application ne peut pas effacer le fichier du bucket.';
  end if;

  select p.id, p."position" into v_couv, v_rang
  from public.venue_photos p where p.venue_id = c_salle and p.is_cover;

  if v_couv is distinct from v_photos[2] or v_rang <> 0 then
    raise exception
      'ÉCHEC 4 — après suppression de la couverture, la nouvelle est % (rang %), attendu %.',
      coalesce(v_couv::text, '(aucune)'), v_rang, v_photos[2];
  end if;

  -- Les rangs se sont refermés : 0, 1, 2 et pas 1, 2, 3.
  select count(*) into v_nombre from public.venue_photos p where p.venue_id = c_salle;
  select max(p."position") into v_rang from public.venue_photos p where p.venue_id = c_salle;

  if v_rang <> v_nombre - 1 then
    raise exception
      'ÉCHEC 4 — % photos mais le dernier rang est % : les rangs ne se sont pas refermés.',
      v_nombre, v_rang;
  end if;

  raise notice 'OK 4 — la suppression rend le chemin, referme les rangs et redonne la couverture.';

  -- ---------------------------------------------------------------------------
  -- Test 5 — la 21e photo n'entre pas
  --
  -- On remplit jusqu'à photos_max(), puis on pousse une fois de trop. Deux
  -- fois : par la fonction, puis par un INSERT direct — c'est le même trigger
  -- qui doit refuser les deux.
  -- ---------------------------------------------------------------------------
  while (select count(*) from public.venue_photos p where p.venue_id = c_salle)
        < public.photos_max() loop
    perform * from public.ajouter_photo(
      c_salle, c_salle || '/' || gen_random_uuid() || '.webp');
  end loop;

  begin
    perform * from public.ajouter_photo(
      c_salle, c_salle || '/' || gen_random_uuid() || '.webp');
    raise exception 'ÉCHEC 5 — une % e photo est passée par ajouter_photo().',
      public.photos_max() + 1;
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE038' then
      raise exception 'ÉCHEC 5 — refus attendu FE038, reçu hint=% sqlstate=%.',
        coalesce(v_hint, '(vide)'), v_sqlstate;
    end if;
  end;

  begin
    insert into public.venue_photos (venue_id, storage_path, "position", is_cover)
    values (c_salle, c_salle || '/par-la-porte-de-derriere.webp',
            public.photos_max(), false);
    raise exception 'ÉCHEC 5 — une photo de trop est passée par un INSERT direct.';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE038' then
      raise exception
        'ÉCHEC 5 — l''INSERT direct devait être refusé en FE038, reçu hint=%.',
        coalesce(v_hint, '(vide)');
    end if;
  end;

  if (select count(*) from public.venue_photos p where p.venue_id = c_salle)
     <> public.photos_max() then
    raise exception 'ÉCHEC 5 — la salle a plus de % photos.', public.photos_max();
  end if;

  raise notice 'OK 5 — la % e photo est refusée (FE038), par la fonction comme par la table.',
    public.photos_max() + 1;

  -- ---------------------------------------------------------------------------
  -- Test 6a — Karim n'attache pas de ligne à la galerie d'Amina
  --
  -- La moitié « fichier » de ce test se joue plus bas, en `set local role
  -- authenticated` : les politiques de `storage.objects` ne s'appliquent pas au
  -- rôle qui exécute ce bloc.
  -- ---------------------------------------------------------------------------
  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_karim, 'role', 'authenticated')::text,
                     true);

  begin
    perform * from public.ajouter_photo(
      c_salle, c_salle || '/' || gen_random_uuid() || '.webp');
    raise exception 'ÉCHEC 6a — Karim a ajouté une photo à la salle d''Amina.';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE034' then
      raise exception 'ÉCHEC 6a — refus attendu FE034 sur ajouter_photo, reçu hint=%.',
        coalesce(v_hint, '(vide)');
    end if;
  end;

  select array_agg(p.id order by p."position") into v_photos
  from public.venue_photos p where p.venue_id = c_salle;

  begin
    perform public.supprimer_photo(v_photos[1]);
    raise exception 'ÉCHEC 6a — Karim a supprimé une photo de la salle d''Amina.';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE039' then
      raise exception 'ÉCHEC 6a — refus attendu FE039 sur supprimer_photo, reçu hint=%.',
        coalesce(v_hint, '(vide)');
    end if;
  end;

  begin
    perform * from public.reordonner_photos(c_salle, v_photos);
    raise exception 'ÉCHEC 6a — Karim a réordonné la galerie d''Amina.';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE034' then
      raise exception 'ÉCHEC 6a — refus attendu FE034 sur reordonner_photos, reçu hint=%.',
        coalesce(v_hint, '(vide)');
    end if;
  end;

  raise notice 'OK 6a — la galerie d''Amina est fermée à Karim : FE034 et FE039.';

  -- ---------------------------------------------------------------------------
  -- Test 6b — un chemin hors du dossier de la salle est refusé (FE042)
  --
  -- Les politiques de `storage.objects` empêchent d'écrire un FICHIER ailleurs
  -- que chez soi ; rien n'empêcherait d'écrire une LIGNE qui pointe ailleurs.
  -- Sans ce refus, la salle d'Amina pourrait afficher la photo d'une autre.
  -- ---------------------------------------------------------------------------
  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_amina, 'role', 'authenticated')::text,
                     true);

  begin
    perform * from public.ajouter_photo(
      c_salle, gen_random_uuid() || '/' || gen_random_uuid() || '.webp');
    raise exception 'ÉCHEC 6b — un chemin d''un autre dossier a été accepté.';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE042' then
      raise exception 'ÉCHEC 6b — refus attendu FE042, reçu hint=%.',
        coalesce(v_hint, '(vide)');
    end if;
  end;

  raise notice 'OK 6b — une ligne ne peut pas pointer hors du dossier de sa salle (FE042).';
end $$;

-- =============================================================================
-- Test 6c — Karim ne dépose ni n'efface un FICHIER dans le dossier d'Amina
--
-- POURQUOI UN « set local role authenticated » ICI, comme au test 3b de 005.
-- Les blocs ci-dessus s'exécutent avec le rôle de la session — celui des
-- migrations —, pour qui les politiques RLS ne s'appliquent pas. Ce qui garde
-- `storage.objects` EST une politique : sans changer de rôle, l'insertion
-- passerait et le test signalerait un trou qui n'en est pas un.
--
-- ON N'ENVOIE AUCUN VRAI FICHIER. `storage.objects` est la table qui indexe le
-- bucket, et c'est elle que les deux politiques de 021 gardent : y écrire une
-- ligne est exactement le geste que fait un téléversement, du point de vue des
-- droits.
--
-- AMINA D'ABORD, KARIM ENSUITE, ET C'EST L'ORDRE QUI FAIT LE TEST. Un refus
-- opposé à Karim ne prouve rien tout seul : « permission refusée » sort aussi
-- bien d'une politique qui fait son travail que d'un GRANT manquant sur
-- `storage.objects`, qui refuserait tout le monde — Amina comprise — et
-- laisserait ce fichier vert sur une fonctionnalité entièrement cassée. On
-- montre donc d'abord qu'Amina PEUT écrire chez elle.
-- =============================================================================

set local role authenticated;

do $$
declare
  c_amina  constant uuid := 'c0000008-0000-4000-a000-000000000001';
  c_karim  constant uuid := 'c0000008-0000-4000-a000-000000000002';
  c_salle  constant uuid := '5a110008-0000-4000-a000-000000000001';
  v_lignes integer;
begin
  -- Amina, chez elle : ça doit passer.
  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_amina, 'role', 'authenticated')::text,
                     true);

  begin
    insert into storage.objects (bucket_id, name, owner)
    values ('venue-photos', c_salle || '/la-sienne.webp', auth.uid());
  exception when others then
    raise exception
      'ÉCHEC 6c — Amina ne peut pas déposer un fichier dans le dossier de SA salle (%). '
      'Les tests de refus qui suivent ne prouveraient rien.', sqlerrm;
  end;

  -- Karim, chez elle : ça ne doit pas passer.
  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_karim, 'role', 'authenticated')::text,
                     true);

  begin
    insert into storage.objects (bucket_id, name, owner)
    values ('venue-photos', c_salle || '/intrus.webp', auth.uid());
    raise exception
      'ÉCHEC 6c — Karim a déposé un fichier dans le dossier de la salle d''Amina.';
  exception when insufficient_privilege then
    null;   -- « new row violates row-level security policy » : c'est le but
  end;

  -- Karim ne VOIT pas non plus le dossier d'Amina. C'est la politique de
  -- lecture de 021, et elle n'a rien de décoratif : c'est elle qui décide de
  -- ce qu'un DELETE trouve.
  select count(*) into v_lignes
  from storage.objects o
  where o.bucket_id = 'venue-photos' and o.name like c_salle || '/%';

  if v_lignes <> 0 then
    raise exception
      'ÉCHEC 6c — Karim voit % fichier(s) du dossier d''Amina.', v_lignes;
  end if;

  -- LA CLÉ QUI OUVRE LE VERROU DE SUPABASE, ET CE QU'ELLE N'OUVRE PAS.
  -- `storage.protect_delete()` — un trigger posé par Supabase — refuse TOUT
  -- DELETE direct sur `storage.objects`, quel que soit le rôle, sauf si
  -- `storage.allow_delete_query` vaut « true ». Ce garde-fou-là protège des
  -- fichiers orphelins, pas des intrus : il refuserait Amina comme Karim, et
  -- laisserait ce test vert sans avoir rien prouvé. On le lève donc, et ce qui
  -- reste en face de Karim est exactement ce qu'on veut mesurer — la politique
  -- de 021. En production, personne ne pose ce paramètre : PostgREST ne le
  -- permet pas, et l'application passe par l'API Storage.
  perform set_config('storage.allow_delete_query', 'true', true);

  -- La suppression, qui est l'autre moitié de la porte. Un DELETE que la
  -- politique écarte ne LÈVE pas : il ne trouve simplement aucune ligne. C'est
  -- donc le compte de lignes qu'on regarde, pas une exception.
  delete from storage.objects o
  where o.bucket_id = 'venue-photos'
    and o.name like c_salle || '/%';

  get diagnostics v_lignes = row_count;

  if v_lignes <> 0 then
    raise exception
      'ÉCHEC 6c — Karim a effacé % fichier(s) du dossier d''Amina.', v_lignes;
  end if;

  -- Le contrôle positif de la suppression, pour la même raison qu'au-dessus :
  -- zéro ligne effacée dirait aussi bien « la politique tient » que « le
  -- fichier n'était pas là ».
  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_amina, 'role', 'authenticated')::text,
                     true);

  delete from storage.objects o
  where o.bucket_id = 'venue-photos'
    and o.name = c_salle || '/la-sienne.webp';

  get diagnostics v_lignes = row_count;

  if v_lignes <> 1 then
    raise exception
      'ÉCHEC 6c — Amina n''a pas pu effacer son propre fichier (% ligne(s)) : le refus '
      'opposé à Karim ne prouvait donc rien.', v_lignes;
  end if;

  raise notice 'OK 6c — le dossier d''une salle est ouvert à son propriétaire, et fermé à tout autre.';
end $$;

reset role;

-- =============================================================================
-- Test 7 — sous photos_min() photos, pas d'envoi en validation (FE041)
-- =============================================================================

do $$
declare
  c_amina constant uuid := 'c0000008-0000-4000-a000-000000000001';
  c_salle constant uuid := '5a110008-0000-4000-a000-000000000001';

  v_hint     text;
  v_sqlstate text;
  v_photos   uuid[];
  v_statut   text;
  v_nombre   integer;
begin
  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_amina, 'role', 'authenticated')::text,
                     true);

  -- On redescend juste SOUS la borne : photos_min() - 1. C'est le cas limite,
  -- et c'est le seul qui distingue un « < » d'un « <= » mal écrit.
  select array_agg(p.id order by p."position" desc) into v_photos
  from public.venue_photos p where p.venue_id = c_salle;

  for v_nombre in 1..(array_length(v_photos, 1) - (public.photos_min() - 1)) loop
    perform public.supprimer_photo(v_photos[v_nombre]);
  end loop;

  select count(*) into v_nombre
  from public.venue_photos p where p.venue_id = c_salle;

  if v_nombre <> public.photos_min() - 1 then
    raise exception 'ÉCHEC 7 — le décor est faux : % photos au lieu de %.',
      v_nombre, public.photos_min() - 1;
  end if;

  begin
    perform * from public.envoyer_salle_en_validation(c_salle, '0770112233');
    raise exception 'ÉCHEC 7 — une salle de % photos est partie en validation.', v_nombre;
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE041' then
      raise exception 'ÉCHEC 7 — refus attendu FE041, reçu hint=% sqlstate=%.',
        coalesce(v_hint, '(vide)'), v_sqlstate;
    end if;
  end;

  select v.status into v_statut from public.venues v where v.id = c_salle;
  if v_statut is distinct from 'draft' then
    raise exception 'ÉCHEC 7 — la salle est passée à « % » malgré le refus.', v_statut;
  end if;

  -- LE CONTRÔLE POSITIF, sans lequel le précédent ne prouve rien : une
  -- cinquième photo, et la même salle part.
  perform * from public.ajouter_photo(
    c_salle, c_salle || '/' || gen_random_uuid() || '.webp');

  perform * from public.envoyer_salle_en_validation(c_salle, '0770112233');

  select v.status into v_statut from public.venues v where v.id = c_salle;
  if v_statut is distinct from 'pending' then
    raise exception
      'ÉCHEC 7 — avec % photos la salle est restée « % » : le refus du dessus ne prouvait donc rien.',
      public.photos_min(), v_statut;
  end if;

  raise notice
    'OK 7 — sous % photos c''est FE041 (sqlstate %, donc HTTP 400) ; avec %, la salle part.',
    public.photos_min(), v_sqlstate, public.photos_min();
end $$;

rollback;
