-- =============================================================================
-- Ferha — tests/022_connexion_figee_en_demonstration.sql
--
-- CE QU'ON VÉRIFIE : que la serrure des comptes de démonstration (041) est en
-- place sans enfermer ceux qui doivent pouvoir l'ouvrir, et que la ceinture
-- (042) remet demo1234 quand il a bougé.
--
-- LA MOITIÉ QUE CE FICHIER NE PEUT PAS PROUVER, ET OÙ ELLE L'EST. Le
-- déclencheur de 041 ne mord que sous le rôle `supabase_auth_admin`, celui de
-- GoTrue — et `postgres` n'a pas le droit de l'endosser (`set role` refusé).
-- Aucun test SQL ne peut donc jouer « un visiteur appelle auth.updateUser ».
-- Cette moitié-là se prouve par l'API, avec le script voisin :
--
--     .\supabase\tests\connexion_figee_demo.ps1
--
-- Ce fichier prouve l'autre moitié, celle qui casserait en silence :
--   * le test 0 : le déclencheur est actif, et SANS security definer — avec,
--     current_user vaudrait toujours `postgres` et la serrure ne fermerait
--     rien, sans la moindre erreur ;
--   * le test 1 : `postgres` (seed/003, le ménage) change encore le mot de
--     passe d'Amina. Sinon rejouer seed/003 ne ferait plus rien ;
--   * les tests 2 et 3 : la ceinture remet demo1234, n'écrit rien quand il n'y
--     a rien à remettre, et ne donne de mot de passe à personne d'autre ;
--   * le test 4 : un visiteur ne peut pas appeler la ceinture lui-même.
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
-- Prérequis : migrations 001 à 042, et le seed 003 (pour Amina et Karim).
-- =============================================================================

begin;

do $$
declare
  c_amina    constant uuid := 'd0000000-0000-4000-a000-000000000010';
  c_karim    constant uuid := 'd0000000-0000-4000-a000-000000000001';
  c_client   constant uuid := '7e000000-0000-4000-a000-000000000022';

  v_n        integer;
  v_definer  boolean;
  v_hash     text;
  v_remis    integer;
begin
  -- ---------------------------------------------------------------------------
  -- Test 0 — la serrure est posée, et posée du bon côté
  -- ---------------------------------------------------------------------------
  select count(*) into v_n
  from pg_trigger t
  join pg_class c     on c.oid = t.tgrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'auth' and c.relname = 'users'
    and t.tgname = 'auth_connexion_figee_en_demonstration'
    and t.tgenabled = 'O'
    and (t.tgtype & 2) = 2      -- BEFORE
    and (t.tgtype & 16) = 16;   -- UPDATE

  if v_n <> 1 then
    raise exception 'ÉCHEC 0 — le déclencheur de 041 n''est pas actif en BEFORE UPDATE sur auth.users.';
  end if;

  select p.prosecdef into v_definer
  from pg_proc p
  where p.oid = 'public.auth_connexion_figee_en_demonstration()'::regprocedure;

  if v_definer then
    raise exception 'ÉCHEC 0 — la fonction est SECURITY DEFINER : current_user y vaut son propriétaire, la serrure ne ferme rien.';
  end if;

  if not exists (select 1 from cron.job where jobname = 'ferha-connexion-du-decor') then
    raise exception 'ÉCHEC 0 — la tâche cron de 042 n''est pas planifiée.';
  end if;

  if not exists (
    select 1 from auth.users
     where id = c_amina
       and encrypted_password like '$2%'
       and encrypted_password = extensions.crypt('demo1234', encrypted_password)) then
    raise exception 'ÉCHEC 0 — Amina ne se connecte pas avec demo1234 au départ. Lancez seed/003.';
  end if;

  raise notice 'OK 0/4 — déclencheur actif, SECURITY INVOKER ; tâche cron planifiée ; Amina part de demo1234.';

  -- ---------------------------------------------------------------------------
  -- Test 1 — `postgres` garde la main sur le décor
  --
  -- C'est la situation de seed/003 et du ménage. Le déclencheur doit laisser
  -- passer, et le mot de passe doit réellement changer.
  -- ---------------------------------------------------------------------------
  update auth.users
     set encrypted_password = extensions.crypt('autre-mot-022', extensions.gen_salt('bf'))
   where id = c_amina;

  select encrypted_password into v_hash from auth.users where id = c_amina;

  if v_hash <> extensions.crypt('autre-mot-022', v_hash) then
    raise exception 'ÉCHEC 1 — postgres n''a pas pu changer le mot de passe d''Amina : rejouer seed/003 ne ferait plus rien.';
  end if;

  raise notice 'OK 1/4 — postgres change le mot de passe d''Amina : la serrure ne vise que GoTrue.';

  -- ---------------------------------------------------------------------------
  -- Test 2 — la ceinture remet demo1234, et seulement ce qui a bougé
  -- ---------------------------------------------------------------------------
  v_remis := public.remettre_la_connexion_du_decor();

  if v_remis <> 1 then
    raise exception 'ÉCHEC 2 — la ceinture a remis % compte(s) au lieu de 1 (Amina seule avait bougé).', v_remis;
  end if;

  select encrypted_password into v_hash from auth.users where id = c_amina;

  if v_hash <> extensions.crypt('demo1234', v_hash) then
    raise exception 'ÉCHEC 2 — après la ceinture, Amina n''a toujours pas demo1234.';
  end if;

  v_remis := public.remettre_la_connexion_du_decor();

  if v_remis <> 0 then
    raise exception 'ÉCHEC 2 — un second passage réécrit encore % compte(s) : la ceinture réécrit sans raison.', v_remis;
  end if;

  raise notice 'OK 2/4 — la ceinture remet demo1234, puis ne réécrit plus rien.';

  -- ---------------------------------------------------------------------------
  -- Test 3 — la ceinture ne donne de mot de passe à personne d'autre
  --
  -- Les six autres personnes du décor n'en ont pas, et ne doivent pas en
  -- recevoir. Un vrai compte n'est jamais touché.
  -- ---------------------------------------------------------------------------
  insert into auth.users (instance_id, id, aud, role, email,
                          encrypted_password, email_confirmed_at,
                          created_at, updated_at,
                          raw_app_meta_data, raw_user_meta_data)
  values
    ('00000000-0000-0000-0000-000000000000', c_client, 'authenticated', 'authenticated',
     'test.client.022@ferha.test', 'pas-un-hachage', now(), now(), now(), '{}'::jsonb, '{}'::jsonb);

  perform public.remettre_la_connexion_du_decor();

  select count(*) into v_n
  from auth.users
  where id::text like 'd0000000-%'
    and id not in (c_amina, c_karim)
    and coalesce(encrypted_password, '') <> '';

  if v_n <> 0 then
    raise exception 'ÉCHEC 3 — % autre(s) personne(s) du décor ont reçu un mot de passe.', v_n;
  end if;

  if (select encrypted_password from auth.users where id = c_client) <> 'pas-un-hachage' then
    raise exception 'ÉCHEC 3 — la ceinture a touché un vrai compte.';
  end if;

  raise notice 'OK 3/4 — personne d''autre qu''Amina et Karim n''est touché.';

  -- ---------------------------------------------------------------------------
  -- Test 4 — un visiteur ne peut pas appeler la ceinture
  -- ---------------------------------------------------------------------------
  if has_function_privilege('anon', 'public.remettre_la_connexion_du_decor()', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.remettre_la_connexion_du_decor()', 'EXECUTE') then
    raise exception 'ÉCHEC 4 — anon ou authenticated peut exécuter remettre_la_connexion_du_decor().';
  end if;

  raise notice 'OK 4/4 — la ceinture n''est pas exposée par l''API.';

  raise notice '--- Les 4 tests passent. La moitié GoTrue : connexion_figee_demo.ps1. ---';
end $$;

rollback;
