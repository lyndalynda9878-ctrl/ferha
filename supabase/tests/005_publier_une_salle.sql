-- =============================================================================
-- Ferha — tests/005_publier_une_salle.sql
--
-- CE QU'ON VÉRIFIE, QUATRE CHOSES, ET AUCUNE N'EST DÉCORATIVE :
--
--   1. SANS SESSION, RIEN. La clé anon suffit à appeler une fonction PostgREST,
--      et c'est le SQL qui doit dire non.
--
--   2. ON NE CRÉE PAS UNE SALLE AU NOM D'UN AUTRE. C'est le test le plus
--      important du fichier, et il se lit à l'envers des autres : il ne vérifie
--      pas qu'un refus tombe, il vérifie qu'il n'y a RIEN À REFUSER.
--      `creer_salle()` ne prend pas de propriétaire en paramètre — elle le lit
--      dans `auth.uid()`. Le test appelle donc la fonction en étant Amina et
--      constate que la salle est à Amina, quoi qu'on ait pu vouloir.
--
--   3. LE PROPRIÉTAIRE NE SE PUBLIE PAS LUI-MÊME (ADM-01). Ni par la fonction,
--      ni par un UPDATE direct sur la table — c'est le trigger
--      `venues_guard_status` (001) qui tient la seconde porte, et il faut donc
--      la pousser aussi.
--
--   4. UNE SALLE « pending » N'EST PAS AU CATALOGUE. `search_venues()` filtre
--      sur `status = 'published'` : une salle envoyée en validation ne doit
--      apparaître dans aucune recherche.
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
-- POURQUOI UN « set local role authenticated » AU TEST 3b. Les autres tests
-- appellent des fonctions dont le garde-fou lit `auth.uid()` : poser le JWT
-- suffit. Celui-là écrit DIRECTEMENT dans `venues`, et ce qui l'arrête est un
-- trigger qui laisse passer le rôle de service (`auth.uid() is null`). Sans
-- changer de rôle, l'UPDATE passerait et le test signalerait un trou qui n'en
-- est pas un.
--
-- CE QU'IL LAISSE : rien. Tout est fait dans une transaction annulée à la fin.
--
-- Prérequis : migrations 001 à 017 appliquées, et les référentiels remplis
--             (003 équipements, 009 wilayas, 010 types d'événement).
-- =============================================================================

begin;

do $$
declare
  c_amina  constant uuid := 'c0000005-0000-4000-a000-000000000001';
  c_karim  constant uuid := 'c0000005-0000-4000-a000-000000000002';

  v_salle    uuid;
  v_sqlstate text;
  v_hint     text;
  v_statut   text;
  v_owner    uuid;
  v_bool     boolean;
  v_lignes   integer;

  -- Les codes lus dans les référentiels.
  v_wilaya   text;
  v_equip    text;
  v_type     text;

  -- Ce qu'on relit de la salle créée. UNE VARIABLE PAR CHOSE, et non des
  -- tampons réemployés : la première version de ce fichier relisait area_sqm
  -- dans une variable `uuid`, et Postgres l'a refusé — à juste titre.
  v_nom      text;
  v_commune  text;
  v_desc     text;
  v_parking  integer;
  v_area     integer;
begin
  -- ---------------------------------------------------------------------------
  -- Le décor : deux comptes, dont AUCUN n'est propriétaire au départ.
  --
  -- C'est le point de départ d'OWN-01 : Amina est une cliente, et publier une
  -- salle est ce qui doit la faire devenir propriétaire.
  -- ---------------------------------------------------------------------------
  insert into auth.users (instance_id, id, aud, role, email,
                          encrypted_password, email_confirmed_at,
                          created_at, updated_at,
                          raw_app_meta_data, raw_user_meta_data)
  values
    ('00000000-0000-0000-0000-000000000000', c_amina, 'authenticated', 'authenticated',
     'test.amina.005@ferha.test', '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb),
    ('00000000-0000-0000-0000-000000000000', c_karim, 'authenticated', 'authenticated',
     'test.karim.005@ferha.test', '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb);

  -- DO UPDATE et non DO NOTHING : le déclencheur de 007 a déjà créé les profils
  -- à l'insertion dans auth.users, avec is_owner à faux. On réaffirme l'état de
  -- départ plutôt que de le supposer.
  insert into public.profiles (id, full_name, email, is_owner) values
    (c_amina, 'Amina Haddad', 'test.amina.005@ferha.test', false),
    (c_karim, 'Karim Belkacem', 'test.karim.005@ferha.test', false)
  on conflict (id) do update
    set full_name = excluded.full_name,
        is_owner  = excluded.is_owner;

  -- Les référentiels ne sont pas inventés ici : on lit ce qui existe. Un test
  -- qui écrirait « 31 » et « climatisation » en dur mentirait le jour où les
  -- référentiels changent.
  select w.code into v_wilaya from public.wilayas w order by w.code limit 1;
  select a.code into v_equip  from public.amenities a order by a.code limit 1;
  select t.code into v_type   from public.event_types t order by t.code limit 1;

  if v_wilaya is null or v_equip is null or v_type is null then
    raise exception
      'ÉCHEC 0 — un référentiel est vide (wilaya %, équipement %, type %). '
      'Appliquez 003, 009 et 010 avant ce test.',
      coalesce(v_wilaya, '(vide)'), coalesce(v_equip, '(vide)'),
      coalesce(v_type, '(vide)');
  end if;

  -- ---------------------------------------------------------------------------
  -- Test 1 — sans session, rien
  -- ---------------------------------------------------------------------------
  perform set_config('request.jwt.claims', '', true);

  begin
    perform * from public.creer_salle('Salle fantôme', v_wilaya, 'Oran', 300);
    raise exception 'ÉCHEC 1 — une salle a été créée sans session.';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE030' then
      raise exception 'ÉCHEC 1 — refus attendu FE030 sur creer_salle, reçu hint=% sqlstate=%.',
        coalesce(v_hint, '(vide)'), v_sqlstate;
    end if;
  end;

  begin
    perform * from public.envoyer_salle_en_validation(gen_random_uuid());
    raise exception 'ÉCHEC 1 — une validation a été demandée sans session.';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE030' then
      raise exception 'ÉCHEC 1 — refus attendu FE030 sur envoyer_salle_en_validation, reçu hint=%.',
        coalesce(v_hint, '(vide)');
    end if;
  end;

  if (select count(*) from public.venues v where v.name = 'Salle fantôme') <> 0 then
    raise exception 'ÉCHEC 1 — une salle a été écrite malgré le refus.';
  end if;

  raise notice 'OK 1 — sans session : FE030, sqlstate % (donc HTTP 401), et rien n''est écrit.',
    v_sqlstate;

  -- ---------------------------------------------------------------------------
  -- Test 2 — LA SALLE EST À CELUI QUI L'INSCRIT, ET IL N'Y A PAS D'AUTRE CHOIX
  --
  -- Amina, cliente, inscrit sa salle. On vérifie trois choses d'un coup :
  -- le propriétaire, le statut, et le drapeau is_owner qui vient de se lever.
  -- ---------------------------------------------------------------------------
  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_amina, 'role', 'authenticated')::text,
                     true);

  select v.id, v.owner_id, v.status
    into v_salle, v_owner, v_statut
  from public.creer_salle(
    '  Salle Les Palmiers  ',       -- les blancs autour du nom ne sont pas le nom
    v_wilaya,
    '  Bir El Djir  ',
    380,
    p_area_sqm       => 620,
    p_parking_spaces => 0,          -- ZÉRO, et non « non renseigné » : les deux se disent
    p_description    => '   ',      -- des blancs ne sont pas une description
    p_amenities      => array[v_equip, v_equip],  -- deux fois le même : ne doit pas casser
    p_event_types    => array[v_type]
  ) v;

  if v_owner is distinct from c_amina then
    raise exception
      'ÉCHEC 2 — la salle appartient à % au lieu d''Amina. Le propriétaire ne '
      'vient plus d''auth.uid().', coalesce(v_owner::text, 'personne');
  end if;

  if v_statut is distinct from 'draft' then
    raise exception 'ÉCHEC 2 — la salle naît en « % » au lieu de « draft ».', v_statut;
  end if;

  select v.name, v.commune, v.description, v.parking_spaces, v.area_sqm
    into v_nom, v_commune, v_desc, v_parking, v_area
  from public.venues v where v.id = v_salle;

  if v_nom is distinct from 'Salle Les Palmiers' then
    raise exception 'ÉCHEC 2 — le nom est « % » : les blancs n''ont pas été retirés.', v_nom;
  end if;
  if v_commune is distinct from 'Bir El Djir' then
    raise exception 'ÉCHEC 2 — la commune est « % ».', v_commune;
  end if;
  if v_desc is not null then
    raise exception 'ÉCHEC 2 — une description de blancs a été enregistrée : « % ».', v_desc;
  end if;
  if v_parking is distinct from 0 then
    raise exception
      'ÉCHEC 2 — parking_spaces vaut % au lieu de 0. « Pas de parking » et '
      '« non renseigné » ne se disent pas pareil (§6).', coalesce(v_parking::text, 'NULL');
  end if;
  if v_area is distinct from 620 then
    raise exception 'ÉCHEC 2 — la superficie vaut % au lieu de 620.',
      coalesce(v_area::text, 'NULL');
  end if;

  -- Les équipements et les types ont suivi, dans la même transaction.
  select count(*) into v_lignes
  from public.venue_amenities va where va.venue_id = v_salle;
  if v_lignes <> 1 then
    raise exception
      'ÉCHEC 2 — % ligne(s) d''équipement au lieu d''une : un code répété a '
      'cassé la clé primaire.', v_lignes;
  end if;

  select count(*) into v_lignes
  from public.venue_event_types vet where vet.venue_id = v_salle;
  if v_lignes <> 1 then
    raise exception 'ÉCHEC 2 — % ligne(s) de type d''événement au lieu d''une.', v_lignes;
  end if;

  -- LE DRAPEAU. Sans lui, Amina n'aurait plus aucun chemin vers sa salle.
  select p.is_owner into v_bool from public.profiles p where p.id = c_amina;
  if not v_bool then
    raise exception
      'ÉCHEC 2 — is_owner est resté faux : la cliente qui vient d''inscrire une '
      'salle ne verra pas l''entrée de son espace propriétaire.';
  end if;

  -- Et celui de Karim n'a pas bougé : on ne promeut que qui a agi.
  select p.is_owner into v_bool from public.profiles p where p.id = c_karim;
  if v_bool then
    raise exception 'ÉCHEC 2 — is_owner s''est levé sur un compte qui n''a rien fait.';
  end if;

  raise notice 'OK 2 — la salle est à celle qui l''a inscrite, en « draft », et is_owner s''est levé.';

  -- ---------------------------------------------------------------------------
  -- Test 3 — la salle d'un autre ne s'envoie pas en validation
  -- ---------------------------------------------------------------------------
  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_karim, 'role', 'authenticated')::text,
                     true);

  begin
    perform * from public.envoyer_salle_en_validation(v_salle);
    raise exception 'ÉCHEC 3 — UN INCONNU A ENVOYÉ EN VALIDATION LA SALLE D''UN AUTRE.';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE034' then
      raise exception 'ÉCHEC 3 — refus attendu FE034, reçu hint=% sqlstate=%.',
        coalesce(v_hint, '(vide)'), v_sqlstate;
    end if;
  end;

  select v.status into v_statut from public.venues v where v.id = v_salle;
  if v_statut is distinct from 'draft' then
    raise exception 'ÉCHEC 3 — la salle est passée en « % » malgré le refus.', v_statut;
  end if;

  raise notice 'OK 3 — la salle d''un autre est protégée (FE034, sqlstate %).', v_sqlstate;

  -- ---------------------------------------------------------------------------
  -- Test 4 — draft → pending, et pas plus loin
  -- ---------------------------------------------------------------------------
  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_amina, 'role', 'authenticated')::text,
                     true);

  select v.status into v_statut
  from public.envoyer_salle_en_validation(v_salle) v;

  if v_statut is distinct from 'pending' then
    raise exception 'ÉCHEC 4 — la salle est en « % » au lieu de « pending ».', v_statut;
  end if;

  -- On n'envoie pas deux fois. Le cas courant n'est pas une attaque : un double
  -- appui, ou un retour en arrière suivi d'un second envoi.
  begin
    perform * from public.envoyer_salle_en_validation(v_salle);
    raise exception 'ÉCHEC 4 — une salle déjà en attente a été renvoyée en validation.';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE035' then
      raise exception 'ÉCHEC 4 — refus attendu FE035, reçu hint=% sqlstate=%.',
        coalesce(v_hint, '(vide)'), v_sqlstate;
    end if;
  end;

  raise notice 'OK 4 — draft → pending, et un second envoi est refusé (FE035, sqlstate %).',
    v_sqlstate;
end $$;

-- =============================================================================
-- Test 5 — LE PROPRIÉTAIRE NE SE PUBLIE PAS LUI-MÊME (ADM-01)
--
-- Deux portes, et il faut pousser les deux. La première est qu'aucune fonction
-- de 017 n'accepte de statut en paramètre — c'est vérifié par le test 4, qui
-- constate « pending » et rien d'autre. La seconde est le trigger
-- `venues_guard_status`, pour le jour où quelqu'un écrirait dans la table
-- directement depuis l'application.
--
-- D'où le changement de rôle : le trigger laisse passer le rôle de service
-- (`auth.uid() is null`), et c'est normal — les migrations et les webhooks en
-- ont besoin. Sans `set local role`, ce test s'exécuterait avec ce rôle-là,
-- l'UPDATE passerait, et il annoncerait un trou qui n'existe pas.
-- =============================================================================

set local role authenticated;
set local request.jwt.claims = '{"sub":"c0000005-0000-4000-a000-000000000001","role":"authenticated"}';

do $$
declare
  c_amina constant uuid := 'c0000005-0000-4000-a000-000000000001';
  v_salle uuid;
  v_statut text;
begin
  select v.id into v_salle
  from public.venues v where v.owner_id = c_amina and v.name = 'Salle Les Palmiers';

  if v_salle is null then
    raise exception 'ÉCHEC 5 — la salle du test 2 est introuvable.';
  end if;

  begin
    update public.venues v set status = 'published' where v.id = v_salle;
    raise exception
      'ÉCHEC 5 — UNE PROPRIÉTAIRE A PUBLIÉ SA PROPRE SALLE. ADM-01 dit qu''aucune '
      'salle n''est visible avant contrôle humain ; le trigger venues_guard_status '
      'est tombé.';
  exception when check_violation then
    null;   -- c'est le refus attendu
  end;

  -- Céder sa salle en douce est refusé par le même trigger.
  begin
    update public.venues v
       set owner_id = 'c0000005-0000-4000-a000-000000000002'
     where v.id = v_salle;
    raise exception 'ÉCHEC 5 — une salle a changé de propriétaire par un simple UPDATE.';
  exception when check_violation then
    null;
  end;

  select v.status into v_statut from public.venues v where v.id = v_salle;
  if v_statut is distinct from 'pending' then
    raise exception 'ÉCHEC 5 — la salle est en « % » après les tentatives.', v_statut;
  end if;

  raise notice 'OK 5 — ni publication ni cession par le propriétaire : le trigger tient.';
end $$;

reset role;

-- =============================================================================
-- Test 6 — UNE SALLE « pending » N'EST PAS AU CATALOGUE
--
-- `search_venues()` filtre sur `status = 'published'` (010). Une salle envoyée
-- en validation attend un humain, et le catalogue ne doit pas la montrer entre
-- les deux.
--
-- On lui donne d'abord une grille tarifaire — sans quoi le test ne prouverait
-- rien : `search_venues()` fait une jointure INTERNE sur `venue_pricing`, et la
-- salle serait absente pour la mauvaise raison.
-- =============================================================================

do $$
declare
  c_amina constant uuid := 'c0000005-0000-4000-a000-000000000001';
  v_salle  uuid;
  v_wilaya text;
  v_vues   integer;
begin
  select v.id, v.wilaya_code into v_salle, v_wilaya
  from public.venues v where v.owner_id = c_amina and v.name = 'Salle Les Palmiers';

  insert into public.venue_pricing (venue_id, slot, base_price, weekend_coef,
                                    high_season_coef, included_seats, extra_seat_price)
  values
    (v_salle, 'midi',    100000, 1.30, 1.20, 200, 800),
    (v_salle, 'soir',    200000, 1.30, 1.20, 200, 800),
    (v_salle, 'journee', 280000, 1.30, 1.20, 200, 800);

  perform set_config('request.jwt.claims', '', true);

  select count(*) into v_vues
  from public.search_venues(p_wilaya_code => v_wilaya) s
  where s.venue_id = v_salle;

  if v_vues <> 0 then
    raise exception
      'ÉCHEC 6 — UNE SALLE « pending » APPARAÎT DANS LA RECHERCHE. ADM-01 : aucune '
      'salle n''est visible avant contrôle humain.';
  end if;

  -- Et le contrôle POSITIF, sans lequel le précédent ne vaut rien : la même
  -- salle publiée par l'administration ressort bien. Un test qui ne montre que
  -- des zéros passerait aussi sur une fonction cassée.
  perform set_config('request.jwt.claims', '', true);
  update public.venues v set status = 'published' where v.id = v_salle;

  select count(*) into v_vues
  from public.search_venues(p_wilaya_code => v_wilaya) s
  where s.venue_id = v_salle;

  if v_vues <> 1 then
    raise exception
      'ÉCHEC 6 — la salle publiée ne ressort pas non plus (% ligne(s)) : le test '
      'du dessus ne prouvait donc rien.', v_vues;
  end if;

  raise notice 'OK 6 — « pending » reste hors du catalogue, « published » y entre.';
end $$;

rollback;
