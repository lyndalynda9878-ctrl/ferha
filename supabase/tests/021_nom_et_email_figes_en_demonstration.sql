-- =============================================================================
-- Ferha — tests/021_nom_et_email_figes_en_demonstration.sql
--
-- CE QU'ON VÉRIFIE : que le déclencheur de la migration 040 empêche un compte
-- connecté de changer le nom ou l'adresse d'un compte de démonstration, sans
-- rien casser — ni la langue qu'on écrit dans la même requête, ni le produit
-- pour un vrai client, ni les seeds qui décident du décor.
--
-- POURQUOI DES ASSERTIONS NÉGATIVES. Chaque test ÉCRIT d'abord une valeur,
-- puis exige qu'elle ne soit pas restée. Un test qui n'écrirait rien
-- échouerait aux tests 3 et 4, qui attendent l'inverse.
--
-- LES TESTS 3 ET 4 SONT LES PLUS IMPORTANTS. Les deux premiers vérifient que
-- le nom ne bouge pas ; les deux suivants qu'il bouge encore là où il le doit.
--   * le test 3 : un VRAI client change son nom. Un correctif qui figerait
--     `full_name` pour tout le monde passerait les tests 1 et 2 et casserait
--     le produit en silence ;
--   * le test 4 : le rôle de service — seed/003, le ménage du décor — change
--     le nom d'Amina. Sans lui, rejouer le seed avec un nouveau nom ne ferait
--     rien, et personne ne s'en apercevrait.
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
-- Prérequis : migrations 001 à 040, et le seed 003 (pour Amina et Karim).
-- =============================================================================

begin;

do $$
declare
  -- Les deux comptes des boutons « Entrer comme… », tels que seed/003 les pose.
  c_amina    constant uuid := 'd0000000-0000-4000-a000-000000000010';
  c_karim    constant uuid := 'd0000000-0000-4000-a000-000000000001';

  -- Un vrai client, créé pour ce fichier. Son identifiant ne porte PAS le
  -- préfixe du décor : c'est tout le sujet.
  c_client   constant uuid := '7e000000-0000-4000-a000-000000000021';

  v_nom_amina    text;
  v_email_amina  text;
  v_nom_karim    text;
  v_email_karim  text;
  v_locale       text;
  v_autre_locale text;
  v_nom          text;
  v_email        text;
begin
  -- ---------------------------------------------------------------------------
  -- Test 0 — le décor attendu est là
  -- ---------------------------------------------------------------------------
  select full_name, email, locale into v_nom_amina, v_email_amina, v_locale
  from public.profiles where id = c_amina;

  if v_nom_amina is null then
    raise exception 'ÉCHEC 0 — Amina absente. Lancez seed/003_demo_accounts.sql.';
  end if;

  select full_name, email into v_nom_karim, v_email_karim
  from public.profiles where id = c_karim;

  if v_nom_karim is null then
    raise exception 'ÉCHEC 0 — Karim absent. Lancez seed/003_demo_accounts.sql.';
  end if;

  if not exists (
    select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid
     where c.relname = 'profiles'
       and t.tgname = 'profiles_nom_et_email_figes_en_demonstration') then
    raise exception 'ÉCHEC 0 — le déclencheur de 040 n''est pas en place.';
  end if;

  raise notice 'OK 0/4 — Amina, Karim et le déclencheur sont là.';

  -- ---------------------------------------------------------------------------
  -- Test 1 — un update direct, connecté comme le compte lui-même
  --
  -- C'est la porte de `profiles_update_self` : un visiteur entré comme Amina
  -- écrit sa propre ligne par PostgREST. Même chose pour Karim. L'écriture ne
  -- doit pas lever d'erreur — le déclencheur force, il ne refuse pas.
  -- ---------------------------------------------------------------------------
  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_amina, 'role', 'authenticated')::text,
                     true);
  begin
    update public.profiles
       set full_name = 'Nom barbouillé', email = 'barbouille@exemple.dz'
     where id = c_amina;
  exception when others then
    raise exception 'ÉCHEC 1 — l''écriture a été refusée (%), alors que le déclencheur doit forcer, pas refuser.',
      sqlerrm;
  end;

  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_karim, 'role', 'authenticated')::text,
                     true);
  update public.profiles
     set full_name = 'Nom barbouillé', email = 'barbouille2@exemple.dz'
   where id = c_karim;

  select full_name, email into v_nom, v_email from public.profiles where id = c_amina;
  if (v_nom, v_email) is distinct from (v_nom_amina, v_email_amina) then
    raise exception 'ÉCHEC 1 — Amina porte « % » / « % » au lieu de « % » / « % ».',
      v_nom, v_email, v_nom_amina, v_email_amina;
  end if;

  select full_name, email into v_nom, v_email from public.profiles where id = c_karim;
  if (v_nom, v_email) is distinct from (v_nom_karim, v_email_karim) then
    raise exception 'ÉCHEC 1 — Karim porte « % » / « % » au lieu de « % » / « % ».',
      v_nom, v_email, v_nom_karim, v_email_karim;
  end if;

  raise notice 'OK 1/4 — update direct : le nom et l''adresse d''Amina et de Karim n''ont pas bougé.';

  -- ---------------------------------------------------------------------------
  -- Test 2 — le nom ET la langue dans la même requête
  --
  -- La bascule fr / ar écrit `locale` pour de bon. Elle doit passer, même
  -- quand la requête porte aussi un nom : forcer, c'est remettre le nom et
  -- laisser le reste.
  -- ---------------------------------------------------------------------------
  v_autre_locale := case v_locale when 'fr' then 'ar' else 'fr' end;

  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_amina, 'role', 'authenticated')::text,
                     true);
  update public.profiles
     set full_name = 'Nom barbouillé', locale = v_autre_locale
   where id = c_amina;

  select full_name, locale into v_nom, v_locale from public.profiles where id = c_amina;

  if v_nom <> v_nom_amina then
    raise exception 'ÉCHEC 2 — le nom est devenu « % ».', v_nom;
  end if;

  if v_locale <> v_autre_locale then
    raise exception 'ÉCHEC 2 — la langue est restée « % » au lieu de « % » : le déclencheur en fait trop.',
      v_locale, v_autre_locale;
  end if;

  raise notice 'OK 2/4 — la langue passe à « % », le nom reste « % ».', v_locale, v_nom;

  -- ---------------------------------------------------------------------------
  -- Test 3 — un VRAI client change son nom : il change
  --
  -- LE TEST QUI PROTÈGE LE PRODUIT. Voir l'en-tête.
  -- ---------------------------------------------------------------------------
  perform set_config('request.jwt.claims', '', true);

  insert into auth.users (instance_id, id, aud, role, email,
                          encrypted_password, email_confirmed_at,
                          created_at, updated_at,
                          raw_app_meta_data, raw_user_meta_data)
  values
    ('00000000-0000-0000-0000-000000000000', c_client, 'authenticated', 'authenticated',
     'test.client.021@ferha.test', '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb);

  insert into public.profiles (id, full_name, email, is_owner) values
    (c_client, 'Client de test 021', 'test.client.021@ferha.test', false)
  on conflict (id) do nothing;

  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_client, 'role', 'authenticated')::text,
                     true);
  update public.profiles
     set full_name = 'Nouveau nom 021', email = 'nouveau.021@ferha.test'
   where id = c_client;

  select full_name, email into v_nom, v_email from public.profiles where id = c_client;

  if (v_nom, v_email) is distinct from ('Nouveau nom 021', 'nouveau.021@ferha.test') then
    raise exception 'ÉCHEC 3 — un VRAI client n''a pas pu changer son nom (« % » / « % »). Le correctif déborde.',
      v_nom, v_email;
  end if;

  raise notice 'OK 3/4 — compte normal : le nom et l''adresse changent.';

  -- ---------------------------------------------------------------------------
  -- Test 4 — le rôle de service change le nom d'Amina : il change
  --
  -- Sans jeton d'utilisateur, auth.uid() est null : c'est la situation de
  -- seed/003, du ménage sous pg_cron et des migrations. Ce sont eux qui
  -- décident du décor.
  -- ---------------------------------------------------------------------------
  perform set_config('request.jwt.claims', '', true);

  update public.profiles set full_name = 'Amina (décidé par le seed)' where id = c_amina;

  select full_name into v_nom from public.profiles where id = c_amina;

  if v_nom <> 'Amina (décidé par le seed)' then
    raise exception 'ÉCHEC 4 — le rôle de service n''a pas pu changer le nom (« % ») : rejouer seed/003 ne ferait plus rien.',
      v_nom;
  end if;

  raise notice 'OK 4/4 — rôle de service : le nom change, le seed garde la main sur le décor.';

  raise notice '--- Les 4 tests passent. ---';
end $$;

rollback;
