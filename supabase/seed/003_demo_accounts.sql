-- =============================================================================
-- Ferha — seed/003_demo_accounts.sql
-- Les deux comptes de démonstration du §4.1 (CORE-01) : « Deux comptes de
-- démonstration sont proposés en un tap sur l'écran de connexion. »
--
--   Amina Haddad   amina@demo.ferha.dz    cliente, aucune salle
--   Karim Belhadj  karim.belhadj@demo.ferha.dz   propriétaire, QUATRE salles
--
--   Mot de passe des deux comptes : demo1234
--
-- LE MOT DE PASSE EST EN CLAIR, ET C'EST VOULU. Ce sont des comptes publics de
-- démonstration, proposés en un tap sur l'écran de connexion : le cacher ne
-- protégerait rien et compliquerait la reprise du projet. Ils n'existent que
-- sur une base de démonstration, ne portent aucune donnée réelle, et
-- disparaissent avec 002_reset_demo.sql.
--
-- KARIM EST LE MÊME COMPTE QUE LE PROPRIÉTAIRE DE 001_demo_venues.sql. Même
-- UUID, d0000000-0000-4000-a000-000000000001. En se connectant, il voit ses
-- quatre salles — Salle El Bahia, Résidence Les Andalouses, Salle Ennour et
-- Salle Ibn Khaldoun — et non un espace vide. C'est tout l'intérêt du compte :
-- montrer l'espace propriétaire rempli.
--
-- ORDRE : ce fichier vient APRÈS 001_demo_venues.sql, qui crée le compte de
-- Karim, et après la migration 007. Il s'arrête avec un message clair si l'un
-- des deux manque.
--
-- REJOUABLE : les deux comptes sont posés en ON CONFLICT, et le mot de passe
-- est réécrit à chaque passage. Relancer ce fichier remet les deux comptes en
-- état connu — c'est le moyen prévu pour réparer un mot de passe perdu.
--
-- CE FICHIER ÉCRIT DANS auth.users, un schéma qui appartient à Supabase et
-- dont les colonnes changent d'une version de GoTrue à l'autre. C'est la
-- partie du dépôt la plus susceptible de casser lors d'une mise à jour. Si la
-- connexion échoue après l'avoir lancé, la solution de repli est en bas de ce
-- fichier.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- Ce qui doit être en place avant
-- -----------------------------------------------------------------------------

do $$
begin
  -- pgcrypto fournit crypt() et gen_salt(), qui produisent le bcrypt attendu
  -- par GoTrue. Sur Supabase l'extension est installée dans le schéma
  -- « extensions », lui-même dans le search_path par défaut.
  begin
    perform crypt('verification', gen_salt('bf'));
  exception when undefined_function then
    raise exception
      'pgcrypto est introuvable : impossible de chiffrer un mot de passe.'
      using hint = 'create extension if not exists pgcrypto with schema extensions;';
  end;

  if not exists (
    select 1 from auth.users u
    where u.id = 'd0000000-0000-4000-a000-000000000001'
  ) then
    raise exception
      'Le compte de Karim n''existe pas : lancez d''abord seed/001_demo_venues.sql.'
      using hint = 'Sans lui, Karim se connecterait sur un espace propriétaire vide.';
  end if;

  if not exists (
    select 1 from pg_trigger t where t.tgname = 'on_auth_user_created'
  ) then
    raise warning
      'La migration 007_auth.sql ne semble pas appliquée. Les profils sont '
      'écrits explicitement ici, mais une inscription normale créerait un '
      'compte sans profil.';
  end if;
end;
$$;

-- -----------------------------------------------------------------------------
-- Amina — la cliente
--
-- Compte neuf, aucune salle, aucune réservation. C'est le point de vue par
-- défaut de l'application : quelqu'un qui cherche une salle.
--
-- Le préfixe d0000000- la range avec les autres données de démonstration, donc
-- 002_reset_demo.sql l'efface sans qu'il faille l'y ajouter.
-- -----------------------------------------------------------------------------

insert into auth.users (
  instance_id, id, aud, role, email,
  encrypted_password,
  -- email_confirmed_at EST OBLIGATOIRE ICI. Si « Confirm email » est actif sur
  -- le projet Supabase, GoTrue refuse la connexion de tout compte dont cette
  -- colonne est nulle — avec un « Email not confirmed » qui n'a aucun sens
  -- pour un compte de démonstration : personne ne recevra jamais le message,
  -- l'adresse @demo.ferha.dz n'existe pas.
  --
  -- La remplir revient à confirmer l'adresse à la main, ce qui est exactement
  -- ce qu'on veut : ces deux comptes doivent fonctionner en un tap, quel que
  -- soit le réglage du projet. NE PAS LA RETIRER.
  email_confirmed_at,
  created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data,
  -- GoTrue lit ces colonnes comme des chaînes, pas comme des valeurs
  -- optionnelles : les laisser à NULL fait échouer la connexion sur certaines
  -- versions, avec une erreur qui ne dit pas pourquoi.
  confirmation_token, recovery_token,
  email_change, email_change_token_new, email_change_token_current
)
values (
  '00000000-0000-0000-0000-000000000000',
  'd0000000-0000-4000-a000-000000000010',
  'authenticated', 'authenticated',
  'amina@demo.ferha.dz',
  crypt('demo1234', gen_salt('bf')),
  now(), now(), now(),
  '{"provider": "email", "providers": ["email"]}'::jsonb,
  '{"full_name": "Amina Haddad", "locale": "fr"}'::jsonb,
  '', '', '', '', ''
)
on conflict (id) do update set
  email              = excluded.email,
  encrypted_password = excluded.encrypted_password,
  email_confirmed_at = excluded.email_confirmed_at,
  raw_app_meta_data  = excluded.raw_app_meta_data,
  raw_user_meta_data = excluded.raw_user_meta_data,
  updated_at         = now();

-- -----------------------------------------------------------------------------
-- Karim — le propriétaire, celui des maquettes et celui des salles
--
-- Le compte existe déjà : 001_demo_venues.sql l'a créé pour porter les salles,
-- avec un mot de passe vide. On ne le recrée pas — on lui en donne un.
-- Recréer la ligne changerait son UUID, et ses quatre salles se
-- retrouveraient orphelines.
-- -----------------------------------------------------------------------------

update auth.users set
  encrypted_password = crypt('demo1234', gen_salt('bf')),
  email_confirmed_at = coalesce(email_confirmed_at, now()),
  aud                = 'authenticated',
  role               = 'authenticated',
  raw_app_meta_data  = '{"provider": "email", "providers": ["email"]}'::jsonb,
  raw_user_meta_data = '{"full_name": "Karim Belhadj", "locale": "fr"}'::jsonb,
  updated_at         = now()
where id = 'd0000000-0000-4000-a000-000000000001';

-- Les autres propriétaires de démonstration ne servent pas à se connecter,
-- mais leurs colonnes de jetons sont à NULL depuis 001 : GoTrue les lit dès
-- qu'il liste les comptes, y compris dans le tableau de bord. On les normalise
-- toutes d'un coup — et on confirme leur adresse au passage, pour qu'aucun
-- compte de démonstration ne dépende du réglage « Confirm email » du projet.
update auth.users set
  email_confirmed_at        = coalesce(email_confirmed_at, now()),
  confirmation_token        = coalesce(confirmation_token, ''),
  recovery_token            = coalesce(recovery_token, ''),
  email_change              = coalesce(email_change, ''),
  email_change_token_new    = coalesce(email_change_token_new, ''),
  email_change_token_current = coalesce(email_change_token_current, '')
where id::text like 'd0000000-%';

-- Vérification, pas décoration : si une version de GoTrue rend
-- email_confirmed_at non écrivable, ou si quelqu'un retire une des lignes
-- ci-dessus, la connexion échouerait plus tard avec « Email not confirmed » et
-- il faudrait remonter jusqu'ici pour comprendre. On le dit maintenant.
do $$
declare
  v_non_confirmes integer;
begin
  select count(*) into v_non_confirmes
  from auth.users u
  where u.id::text like 'd0000000-%'
    and u.email_confirmed_at is null;

  if v_non_confirmes > 0 then
    raise exception
      '% compte(s) de démonstration ont email_confirmed_at à NULL. Ils '
      'seront refusés si « Confirm email » est actif sur ce projet.',
      v_non_confirmes
      using hint = 'Authentication › Providers › Email, ou confirmez-les à la main.';
  end if;
end;
$$;

-- -----------------------------------------------------------------------------
-- auth.identities — le fournisseur « email » de chaque compte
--
-- GoTrue rattache chaque compte à au moins une identité. La connexion par mot
-- de passe fonctionne sans, mais le tableau de bord affiche alors un compte
-- sans fournisseur, et certaines opérations (changement d'e-mail, liaison de
-- compte) la réclament.
--
-- WHERE NOT EXISTS plutôt qu'ON CONFLICT : le nom et les colonnes de la
-- contrainte d'unicité ont changé selon les versions de GoTrue, celles-ci non.
-- -----------------------------------------------------------------------------

insert into auth.identities (
  id, provider_id, user_id, identity_data, provider,
  last_sign_in_at, created_at, updated_at
)
select
  gen_random_uuid(),
  u.id::text,
  u.id,
  jsonb_build_object(
    'sub', u.id::text,
    'email', u.email,
    'email_verified', true,
    'phone_verified', false
  ),
  'email',
  now(), now(), now()
from auth.users u
where u.id in (
        'd0000000-0000-4000-a000-000000000001',   -- Karim
        'd0000000-0000-4000-a000-000000000010'    -- Amina
      )
  and not exists (
    select 1 from auth.identities i
    where i.user_id = u.id and i.provider = 'email'
  );

-- -----------------------------------------------------------------------------
-- Les profils
--
-- Le déclencheur de 007 s'en charge à l'insertion d'Amina. On les écrit quand
-- même, explicitement : ce fichier doit produire le même résultat qu'on l'ait
-- lancé avant ou après 007, et Karim, lui, n'est pas inséré mais mis à jour —
-- aucun déclencheur ne se déclenche pour lui.
-- -----------------------------------------------------------------------------

insert into public.profiles (id, full_name, email, phone, is_owner, locale) values
  ('d0000000-0000-4000-a000-000000000010', 'Amina Haddad',
   'amina@demo.ferha.dz', '0770 00 11 22', false, 'fr'),
  ('d0000000-0000-4000-a000-000000000001', 'Karim Belhadj',
   'karim.belhadj@demo.ferha.dz', '0770 11 22 33', true, 'fr')
on conflict (id) do update set
  full_name = excluded.full_name,
  email     = excluded.email,
  phone     = excluded.phone,
  is_owner  = excluded.is_owner,
  locale    = excluded.locale;

commit;

-- -----------------------------------------------------------------------------
-- Ce qui doit sortir
--
-- Karim doit avoir 4 salles. Amina, 0 — et c'est normal : elle est cliente.
-- -----------------------------------------------------------------------------

select
  p.full_name,
  p.email,
  case when p.is_owner then 'propriétaire' else 'cliente' end as role,
  (select count(*) from public.venues v where v.owner_id = p.id) as salles,
  (u.encrypted_password is not null and u.encrypted_password <> '')  as mot_de_passe_pose,
  (u.email_confirmed_at is not null)                                as email_confirme,
  exists (select 1 from auth.identities i
           where i.user_id = p.id and i.provider = 'email')          as identite_email
from public.profiles p
join auth.users u on u.id = p.id
where p.id in (
  'd0000000-0000-4000-a000-000000000010',
  'd0000000-0000-4000-a000-000000000001'
)
order by p.is_owner;

-- Attendu :
--   Amina Haddad   cliente        0 salle    t  t  t
--   Karim Belhadj  propriétaire   4 salles   t  t  t

-- =============================================================================
-- SI LA CONNEXION ÉCHOUE MALGRÉ TOUT
--
-- auth.users est un schéma interne à Supabase. Si une version de GoTrue change
-- ses colonnes, ce fichier peut poser des comptes que le serveur refuse, avec
-- un « Invalid login credentials » qui ne dit pas pourquoi.
--
-- La solution de repli ne demande pas de déboguer GoTrue :
--
--   1. Créez les deux comptes par le chemin normal — l'écran d'inscription de
--      l'application, ou Authentication › Users dans le tableau de bord.
--      Le déclencheur de 007 leur crée un profil.
--
--   2. Rattachez les quatre salles de Karim à son nouveau compte :
--
--        update public.venues
--           set owner_id = '<UUID du nouveau compte de Karim>'
--         where owner_id = 'd0000000-0000-4000-a000-000000000001';
--
--        update public.profiles
--           set is_owner = true
--         where id = '<UUID du nouveau compte de Karim>';
--
--   3. Mettez les deux adresses et le mot de passe choisis dans
--      lib/features/auth/demo_accounts.dart — c'est le seul endroit du code
--      Flutter qui les connaît.
-- =============================================================================
