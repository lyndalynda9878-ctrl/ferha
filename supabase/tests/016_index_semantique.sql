-- =============================================================================
-- Ferha — tests/016_index_semantique.sql
--
-- CE QU'ON VÉRIFIE : que l'index sémantique ne puisse ni mentir, ni fuir.
--
-- POURQUOI CE FICHIER EXISTE. Un index sémantique se trompe SANS RIEN CASSER.
-- Un document incomplet, une salle en brouillon indexée, un vecteur d'un autre
-- modèle : dans les trois cas, la requête tourne, rend des lignes, et personne
-- ne voit rien. Ce ne sont pas des pannes, ce sont des réponses fausses — et
-- c'est exactement ce qu'un test doit attraper, parce que rien d'autre ne le
-- fera.
--
-- LE TEST 3 EST LE PLUS IMPORTANT POUR LE J20. « Une salle non publiée n'est
-- jamais indexée » ferme la question 29 du document de référence : « 3andkom
-- salle f Birtouta ? » doit rester sans réponse, parce qu'Espace Nour El Houda
-- n'est pas publiée. Si l'indexeur la prenait, l'agent la citerait — et il
-- citerait une salle que son propriétaire n'a pas mise en vente.
--
-- LE TEST 5 EST LE PLUS IMPORTANT POUR LA VIE PRIVÉE. venue_embeddings ne
-- contient rien de secret aujourd'hui, mais c'est une table technique : elle se
-- ferme par défaut, et l'on n'ouvre que si un besoin apparaît.
--
-- COMMENT LE LANCER : coller le fichier entier dans l'éditeur SQL de Supabase
-- et exécuter. Une seule fois, d'un bloc.
--
-- COMMENT LE LIRE :
--   * des « NOTICE ... OK » et aucune erreur rouge   → tout va bien ;
--   * une erreur rouge commençant par « ÉCHEC »      → une règle ne tient pas.
--   La dernière instruction est ROLLBACK.
--
-- CE QU'IL LAISSE : rien.
--
-- Prérequis : migrations 001 à 027 appliquées.
-- =============================================================================

begin;

do $$
declare
  c_owner   constant uuid := 'c0000016-0000-4000-a000-000000000001';
  c_publiee constant uuid := 'c0000016-0000-4000-a000-000000000002';
  c_draft   constant uuid := 'c0000016-0000-4000-a000-000000000003';

  v_doc       text;
  v_hash1     text;
  v_hash2     text;
  v_hash3     text;
  v_lignes    integer;
  v_ecrites   integer;
  v_vecteur   extensions.vector(384);
  v_autre     extensions.vector(384);
  v_a_refaire boolean;
  v_nom       text;
begin
  -- ---------------------------------------------------------------------------
  -- Le décor : un propriétaire, une salle publiée bien garnie, une en brouillon.
  -- ---------------------------------------------------------------------------
  insert into auth.users (instance_id, id, aud, role, email,
                          encrypted_password, email_confirmed_at,
                          created_at, updated_at,
                          raw_app_meta_data, raw_user_meta_data)
  values ('00000000-0000-0000-0000-000000000000', c_owner, 'authenticated',
          'authenticated', 'test.owner.016@ferha.test', '', now(), now(), now(),
          '{}'::jsonb, '{}'::jsonb);

  insert into public.profiles (id, full_name, email, phone, is_owner)
  values (c_owner, 'Propriétaire 016', 'test.owner.016@ferha.test',
          '0770000016', true)
  on conflict (id) do update set is_owner = true;

  insert into public.venues (id, owner_id, name, wilaya_code, commune,
                             capacity_seated, area_sqm, parking_spaces,
                             description, status)
  values
    (c_publiee, c_owner, 'Salle de test 016', '19', 'Testville016',
     333, 444, 55, 'Une description de test.', 'published'),
    (c_draft,   c_owner, 'Brouillon de test 016', '19', 'Testville016',
     222, 300, 10, 'Pas encore publiée.', 'draft');

  insert into public.venue_pricing (venue_id, slot, base_price, weekend_coef,
                                    high_season_coef, included_seats,
                                    extra_seat_price)
  select v.id, s.slot, 100000, 1.30, 1.20, 200, 800
  from (values (c_publiee), (c_draft)) as v(id),
       (values ('midi'), ('soir'), ('journee')) as s(slot);

  insert into public.venue_event_types (venue_id, event_type)
  values (c_publiee, 'mariage'), (c_publiee, 'fiancailles');

  insert into public.venue_amenities (venue_id, amenity_code)
  values (c_publiee, 'climatisation'), (c_publiee, 'espace_femmes');

  -- ===========================================================================
  -- Test 1 — LE DOCUMENT DIT CE QU'IL DOIT DIRE (§8.3)
  --
  -- On cherche chaque information par son CONTENU, et non par son étiquette :
  -- un document qui écrirait « Wilaya : » suivi de rien passerait un test sur
  -- l'étiquette, et ne dirait pourtant pas dans quelle wilaya est la salle.
  -- ===========================================================================
  select d.content, d.content_hash into v_doc, v_hash1
    from public.document_salle(c_publiee) d;

  if v_doc is null then
    raise exception 'ÉCHEC 1 — document_salle() ne rend rien pour une salle '
      'publiée.';
  end if;

  if v_doc not like '%Sétif%' then
    raise exception 'ÉCHEC 1a — LA WILAYA N''EST PAS DANS LE DOCUMENT. La '
      'moitié des questions du J20 nomment une wilaya : sans elle, la '
      'recherche par le sens ne peut pas les distinguer.';
  end if;

  -- Et en arabe : les questions 11 à 20 arrivent dans cette graphie-là.
  if v_doc not like '%سطيف%' then
    raise exception 'ÉCHEC 1b — la wilaya n''est pas écrite en arabe. Les '
      'questions en darja nomment « سطيف », pas « Sétif ».';
  end if;

  if v_doc not like '%333%' then
    raise exception 'ÉCHEC 1c — LA CAPACITÉ N''EST PAS DANS LE DOCUMENT. '
      '« une salle pour 300 invités » ne trouverait plus rien.';
  end if;

  if v_doc not like '%Climatisation%' then
    raise exception 'ÉCHEC 1d — LES ÉQUIPEMENTS NE SONT PAS DANS LE DOCUMENT. '
      'Les questions 4, 6, 17, 24, 25 et 28 portent toutes sur un équipement.';
  end if;

  if v_doc not like '%55 places%' then
    raise exception 'ÉCHEC 1e — le parking n''est pas dans le document.';
  end if;

  if v_doc not like '%Note%' then
    raise exception 'ÉCHEC 1f — LA NOTE N''EST PAS DANS LE DOCUMENT (§8.3).';
  end if;

  if v_doc not like '%Une description de test.%' then
    raise exception 'ÉCHEC 1g — la description libre n''est pas dans le '
      'document. C''est elle qui porte tout ce que les colonnes ne disent pas.';
  end if;

  -- CE QUI NE DOIT PAS Y ÊTRE : le prix. Il se calcule (§5), et un prix figé
  -- dans un document vieillirait en silence.
  if v_doc like '%100000%' or v_doc ilike '%prix de base%' then
    raise exception 'ÉCHEC 1h — UN PRIX EST ENTRÉ DANS LE DOCUMENT. Le prix '
      'vient d''estimate_price() et de nulle part ailleurs.';
  end if;

  raise notice 'OK 1 — le document porte wilaya (deux graphies), capacité, '
    'équipements, parking, note et description — et aucun prix.';

  -- ===========================================================================
  -- Test 2 — LE HACHAGE NE BOUGE PAS SI RIEN NE BOUGE
  --
  -- C'est lui qui évite de rappeler le service d'empreintes pour rien. S'il
  -- changeait à chaque appel, chaque passage de l'indexeur revectoriserait tout
  -- le catalogue sur un dixième de vCPU.
  -- ===========================================================================
  select d.content_hash into v_hash2 from public.document_salle(c_publiee) d;

  if v_hash1 is distinct from v_hash2 then
    raise exception 'ÉCHEC 2 — DEUX APPELS DONNENT DEUX HACHAGES : % puis %. '
      'Tout se réindexerait à chaque passage.', v_hash1, v_hash2;
  end if;

  -- ET IL BOUGE QUAND LE CONTENU BOUGE. Un hachage stable qui ne réagit à rien
  -- serait pire que pas de hachage : la salle garderait une empreinte fausse
  -- pour toujours.
  update public.venues set capacity_seated = 334 where id = c_publiee;
  select d.content_hash into v_hash3 from public.document_salle(c_publiee) d;

  if v_hash3 = v_hash1 then
    raise exception 'ÉCHEC 2b — LA CAPACITÉ A CHANGÉ ET LE HACHAGE N''A PAS '
      'BOUGÉ. La salle garderait son ancienne empreinte indéfiniment.';
  end if;

  update public.venues set capacity_seated = 333 where id = c_publiee;

  -- Un équipement ajouté doit compter autant qu'une colonne.
  insert into public.venue_amenities (venue_id, amenity_code)
  values (c_publiee, 'sono');
  select d.content_hash into v_hash3 from public.document_salle(c_publiee) d;

  if v_hash3 = v_hash1 then
    raise exception 'ÉCHEC 2c — un équipement ajouté n''a pas changé le '
      'hachage.';
  end if;

  delete from public.venue_amenities
   where venue_id = c_publiee and amenity_code = 'sono';

  select d.content_hash into v_hash3 from public.document_salle(c_publiee) d;
  if v_hash3 is distinct from v_hash1 then
    raise exception 'ÉCHEC 2d — après retour en arrière, le hachage ne '
      'retombe pas sur sa valeur d''origine. Il dépend donc d''autre chose que '
      'du contenu — de l''ordre des lignes, sans doute.';
  end if;

  raise notice 'OK 2 — le hachage est stable à contenu égal, change dès que le '
    'contenu change, et revient quand on revient en arrière.';

  -- ===========================================================================
  -- Test 3 — UNE SALLE NON PUBLIÉE N'EST JAMAIS INDEXÉE (§4.4)
  --
  -- Deux gardiens, et on les vérifie tous les deux : la liste ne la propose
  -- pas, et la porte d'écriture la refuse même si on insiste.
  -- ===========================================================================
  select count(*) into v_lignes
  from public.salles_a_indexer('modele-de-test') s
  where s.venue_id = c_draft;

  if v_lignes <> 0 then
    raise exception 'ÉCHEC 3 — UNE SALLE EN BROUILLON EST PROPOSÉE À '
      'L''INDEXATION. L''agent du J20 citerait une salle que son propriétaire '
      'n''a pas mise en vente.';
  end if;

  select count(*) into v_lignes
  from public.salles_a_indexer('modele-de-test') s
  where s.venue_id = c_publiee;

  if v_lignes <> 1 then
    raise exception 'ÉCHEC 3b — la salle publiée n''est pas proposée à '
      'l''indexation.';
  end if;

  -- ON INSISTE : la porte d'écriture doit refuser d'elle-même.
  select ('[' || string_agg('0.05', ',') || ']')::extensions.vector
    into v_vecteur
  from generate_series(1, 384);

  v_ecrites := public.enregistrer_empreinte(
                 c_draft, 'document du brouillon', 'un-hachage',
                 v_vecteur, 'modele-de-test');

  if v_ecrites <> 0 then
    raise exception 'ÉCHEC 3c — ON A PU ÉCRIRE L''EMPREINTE D''UN BROUILLON. '
      'C''est le filet sous l''Edge Function : entre la liste et l''écriture, '
      'une salle peut être dépubliée.';
  end if;

  if exists (select 1 from public.venue_embeddings e where e.venue_id = c_draft) then
    raise exception 'ÉCHEC 3d — une ligne d''empreinte existe pour le '
      'brouillon.';
  end if;

  raise notice 'OK 3 — un brouillon n''est ni proposé à l''indexation, ni '
    'écrit quand on insiste.';

  -- ===========================================================================
  -- Test 4 — LA RECHERCHE CLASSE, NE SEUILLE PAS, ET OUBLIE LES DÉPUBLIÉES
  -- ===========================================================================
  v_ecrites := public.enregistrer_empreinte(
                 c_publiee, v_doc, v_hash1, v_vecteur, 'modele-de-test');

  if v_ecrites <> 1 then
    raise exception 'ÉCHEC 4 — l''empreinte d''une salle publiée n''a pas été '
      'écrite.';
  end if;

  select count(*) into v_lignes
  from public.recherche_semantique(v_vecteur, 'modele-de-test', 5) r
  where r.venue_id = c_publiee;

  if v_lignes <> 1 then
    raise exception 'ÉCHEC 4a — la salle indexée ne ressort pas de la '
      'recherche.';
  end if;

  -- UN AUTRE MODÈLE NE SE MÉLANGE PAS. Deux systèmes de coordonnées comparés
  -- donneraient des lignes plausibles et fausses.
  select count(*) into v_lignes
  from public.recherche_semantique(v_vecteur, 'un-autre-modele', 5) r
  where r.venue_id = c_publiee;

  if v_lignes <> 0 then
    raise exception 'ÉCHEC 4b — UNE EMPREINTE D''UN MODÈLE RESSORT POUR UN '
      'AUTRE MODÈLE. Rien ne le signalerait à l''écran : juste des salles mal '
      'classées.';
  end if;

  -- AUCUN SEUIL : même un vecteur qui n'a rien à voir rend des lignes. C'est
  -- voulu (§8.4) — c'est l'agent qui dit « rien ne convient », sur des critères
  -- vérifiables, et non un cosinus réglé sur trois exemples.
  select ('[' || string_agg(case when g = 1 then '1' else '0' end, ',') || ']')::extensions.vector
    into v_autre
  from generate_series(1, 384) g;

  select count(*) into v_lignes
  from public.recherche_semantique(v_autre, 'modele-de-test', 5);

  if v_lignes = 0 then
    raise exception 'ÉCHEC 4c — la recherche a filtré sur un seuil. Elle doit '
      'CLASSER et couper au nombre : la marge mesurée au J18 est de trois '
      'centièmes, un seuil se tromperait.';
  end if;

  -- LA LIMITE EST RESPECTÉE, et bornée.
  if (select count(*) from public.recherche_semantique(v_vecteur, 'modele-de-test', 1)) <> 1 then
    raise exception 'ÉCHEC 4d — la limite n''est pas respectée.';
  end if;

  -- DÉPUBLIER RETIRE DE LA RECHERCHE TOUT DE SUITE, sans toucher à l'index.
  update public.venues set status = 'suspended' where id = c_publiee;

  select count(*) into v_lignes
  from public.recherche_semantique(v_vecteur, 'modele-de-test', 5) r
  where r.venue_id = c_publiee;

  if v_lignes <> 0 then
    raise exception 'ÉCHEC 4e — UNE SALLE DÉPUBLIÉE SORT ENCORE DE LA '
      'RECHERCHE. Son empreinte est toujours dans l''index — c''est le join '
      'sur le statut qui doit la retenir, et il ne le fait pas.';
  end if;

  update public.venues set status = 'published' where id = c_publiee;

  raise notice 'OK 4 — la recherche classe sans seuil, ne mélange pas les '
    'modèles, respecte sa limite, et oublie une salle dépubliée sur-le-champ.';

  -- ===========================================================================
  -- Test 5 — AUCUN COMPTE CLIENT NE LIT venue_embeddings
  -- ===========================================================================
  if has_table_privilege('anon', 'public.venue_embeddings', 'select')
     or has_table_privilege('authenticated', 'public.venue_embeddings', 'select') then
    raise exception 'ÉCHEC 5 — UN COMPTE CLIENT PEUT LIRE venue_embeddings. '
      'C''est une table technique : elle se ferme par défaut.';
  end if;

  if has_table_privilege('anon', 'public.venue_embeddings', 'insert')
     or has_table_privilege('authenticated', 'public.venue_embeddings', 'insert')
     or has_table_privilege('authenticated', 'public.venue_embeddings', 'update')
     or has_table_privilege('authenticated', 'public.venue_embeddings', 'delete') then
    raise exception 'ÉCHEC 5b — un compte client peut écrire dans '
      'venue_embeddings.';
  end if;

  if not (select c.relrowsecurity from pg_class c
           where c.oid = 'public.venue_embeddings'::regclass) then
    raise exception 'ÉCHEC 5c — la RLS n''est pas active sur venue_embeddings.';
  end if;

  select count(*) into v_lignes from pg_policies
   where schemaname = 'public' and tablename = 'venue_embeddings';

  if v_lignes <> 0 then
    raise exception 'ÉCHEC 5d — % politique(s) sur venue_embeddings. La table '
      'ne doit sortir que par recherche_semantique().', v_lignes;
  end if;

  -- LES FONCTIONS D'INDEXATION NE SONT PAS OUVERTES AUX CLIENTS non plus :
  -- `document_salle()` lit une salle en brouillon, `enregistrer_empreinte()`
  -- écrit. Seul `service_role` les appelle, depuis l'Edge Function.
  if has_function_privilege('anon', 'public.salles_a_indexer(text)', 'execute')
     or has_function_privilege('authenticated', 'public.salles_a_indexer(text)', 'execute') then
    raise exception 'ÉCHEC 5e — salles_a_indexer() est ouverte à un client : '
      'elle rend le document de CHAQUE salle publiée en un appel.';
  end if;

  if has_function_privilege('anon', 'public.document_salle(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.document_salle(uuid)', 'execute') then
    raise exception 'ÉCHEC 5f — document_salle() est ouverte à un client. Elle '
      'est SECURITY DEFINER et ne regarde pas le statut : elle décrirait un '
      'brouillon à qui le demande.';
  end if;

  -- Et la recherche, elle, EST ouverte : chercher une salle se fait sans compte.
  if not has_function_privilege('anon',
       'public.recherche_semantique(extensions.vector, text, integer)', 'execute') then
    raise exception 'ÉCHEC 5g — un visiteur ne peut pas chercher une salle. '
      'C''est l''étape 2 du parcours du §3, et elle se fait sans compte.';
  end if;

  raise notice 'OK 5 — venue_embeddings est fermée, les fonctions '
    'd''indexation aussi, et seule la recherche est ouverte aux visiteurs.';

  -- ===========================================================================
  -- Test 6 — L'INDEX EST BIEN UN HNSW EN COSINUS (§8.4)
  --
  -- Un IVFFlat posé par mégarde tournerait, rendrait des résultats, et se
  -- dégraderait à mesure que le catalogue grandit — sans que rien ne le dise.
  -- ===========================================================================
  select count(*) into v_lignes
  from pg_class i
  join pg_index x on x.indexrelid = i.oid
  join pg_am am on am.oid = i.relam
  where x.indrelid = 'public.venue_embeddings'::regclass
    and am.amname = 'hnsw';

  if v_lignes <> 1 then
    raise exception 'ÉCHEC 6 — % index HNSW sur venue_embeddings, attendu 1.',
      v_lignes;
  end if;

  select count(*) into v_lignes
  from pg_index x
  join pg_opclass o on o.oid = x.indclass[0]
  where x.indrelid = 'public.venue_embeddings'::regclass
    and o.opcname = 'vector_cosine_ops';

  if v_lignes <> 1 then
    raise exception 'ÉCHEC 6b — l''index n''est pas en distance cosinus. La '
      'requête utilise « <=> » : avec un autre opérateur, l''index n''est tout '
      'simplement pas utilisé, silencieusement.';
  end if;

  raise notice 'OK 6 — un index HNSW, en distance cosinus, et pas d''IVFFlat.';

  -- ===========================================================================
  -- Test 7 — RÉINDEXER NE REFAIT QUE CE QUI A CHANGÉ
  -- ===========================================================================
  select s.a_refaire, s.name into v_a_refaire, v_nom
  from public.salles_a_indexer('modele-de-test') s
  where s.venue_id = c_publiee;

  if v_a_refaire then
    raise exception 'ÉCHEC 7 — une salle fraîchement indexée est déjà « à '
      'refaire ». Chaque passage revectoriserait tout.';
  end if;

  -- Un changement de modèle, lui, refait tout.
  select s.a_refaire into v_a_refaire
  from public.salles_a_indexer('un-autre-modele') s
  where s.venue_id = c_publiee;

  if not v_a_refaire then
    raise exception 'ÉCHEC 7b — UN CHANGEMENT DE MODÈLE NE DÉCLENCHE PAS LE '
      'RÉINDEXAGE. Les anciennes empreintes resteraient, comparées à des '
      'vecteurs d''un autre modèle.';
  end if;

  -- Et un changement de contenu aussi.
  update public.venues set description = 'Description modifiée.'
   where id = c_publiee;

  select s.a_refaire into v_a_refaire
  from public.salles_a_indexer('modele-de-test') s
  where s.venue_id = c_publiee;

  if not v_a_refaire then
    raise exception 'ÉCHEC 7c — la description a changé et la salle n''est pas '
      'à refaire.';
  end if;

  raise notice 'OK 7 — on ne refait que ce qui a changé : ni plus, ni moins.';
end $$;

rollback;
