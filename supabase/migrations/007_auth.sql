-- =============================================================================
-- Ferha — 007_auth.sql
-- Un compte créé, un profil créé. Automatiquement, et du côté de la base.
--
-- POURQUOI CE FICHIER EXISTE
--
-- auth.users appartient à Supabase ; profiles est à nous. Rien ne les relie
-- tant qu'on ne l'écrit pas. Sans ce déclencheur, l'inscription se ferait en
-- deux temps — GoTrue crée le compte, puis l'application insère le profil — et
-- ces deux temps peuvent se séparer : réseau coupé, application fermée, onglet
-- rechargé. Il reste alors un compte sans profil, c'est-à-dire un utilisateur
-- qui se connecte et à qui plus rien ne répond, parce que toutes les clés
-- étrangères du projet pointent vers profiles et non vers auth.users.
--
-- Une inscription doit être atomique. Elle l'est ici : le déclencheur s'exécute
-- dans la transaction de GoTrue. Si le profil échoue, le compte n'existe pas
-- non plus.
--
-- Ce qui rend la politique profiles_insert_self (002) inutile — elle n'est plus
-- le chemin normal. Elle reste en place : elle ne peut créer qu'un profil pour
-- soi-même, et la retirer n'apporterait rien.
--
-- Rejouable : la fonction est remplacée, le déclencheur supprimé puis recréé.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- handle_new_user — le profil qui accompagne le compte
--
-- La fonction ne doit JAMAIS lever d'exception sur une inscription légitime :
-- une erreur ici fait échouer la création du compte, avec un 500 côté client.
-- Chaque valeur est donc normalisée avant d'être écrite, plutôt que d'être
-- confiée aux contraintes CHECK de profiles :
--
--   full_name  jamais vide — repli sur la partie locale de l'e-mail
--   locale     'fr' ou 'ar', jamais autre chose
--   phone      NULL plutôt que chaîne vide
--
-- Ce qu'elle ne fait PAS : avaler ses erreurs. Un « exception when others then
-- return new » créerait exactement le compte sans profil que ce fichier existe
-- pour empêcher. Si une inscription échoue ici, c'est un vrai défaut, et il
-- doit se voir.
-- -----------------------------------------------------------------------------

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_meta   jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  v_email  text;
  v_name   text;
  v_phone  text;
  v_locale text;
begin
  -- L'inscription v2.0 se fait par e-mail (§4.1, CORE-01), donc new.email est
  -- toujours renseigné. Le repli n'est là que pour qu'une inscription par
  -- téléphone, si elle arrivait un jour, ne fasse pas échouer la création du
  -- compte — profiles.email est NOT NULL et porte un CHECK de forme.
  v_email := coalesce(new.email, new.id::text || '@sans-email.ferha');

  v_name := nullif(btrim(coalesce(v_meta ->> 'full_name', '')), '');
  v_name := coalesce(v_name, nullif(split_part(v_email, '@', 1), ''), 'Utilisateur');

  v_phone := nullif(btrim(coalesce(v_meta ->> 'phone', '')), '');

  -- Toute autre valeur que fr ou ar est ignorée : la contrainte de profiles ne
  -- doit pas pouvoir faire échouer une inscription.
  v_locale := lower(btrim(coalesce(v_meta ->> 'locale', '')));
  if v_locale not in ('fr', 'ar') then
    v_locale := 'fr';
  end if;

  insert into public.profiles (id, full_name, email, phone, locale)
  values (new.id, v_name, v_email, v_phone, v_locale)
  -- Le profil peut déjà exister : les données de démonstration écrivent
  -- auth.users et profiles côte à côte. On ne l'écrase pas.
  on conflict (id) do nothing;

  return new;
end;
$$;

comment on function public.handle_new_user() is
  'Crée la ligne profiles qui accompagne un compte auth.users. '
  'Sans elle, un compte existe sans profil et plus aucune clé étrangère du projet ne résout.';

-- Personne n'appelle cette fonction à la main : elle n'a de sens que dans son
-- déclencheur.
revoke execute on function public.handle_new_user() from public, anon, authenticated;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- -----------------------------------------------------------------------------
-- Rattrapage — les comptes déjà créés avant ce fichier
--
-- Un déclencheur ne regarde que l'avenir. S'il existe des comptes antérieurs
-- sans profil — c'est le cas si quelqu'un s'est inscrit avant cette migration —
-- ils resteraient cassés pour toujours. On les répare une fois, ici.
--
-- Sur une base neuve, cette instruction ne touche rien.
-- -----------------------------------------------------------------------------

insert into public.profiles (id, full_name, email, locale)
select
  u.id,
  coalesce(
    nullif(btrim(coalesce(u.raw_user_meta_data ->> 'full_name', '')), ''),
    nullif(split_part(coalesce(u.email, ''), '@', 1), ''),
    'Utilisateur'
  ),
  coalesce(u.email, u.id::text || '@sans-email.ferha'),
  'fr'
from auth.users u
where not exists (select 1 from public.profiles p where p.id = u.id)
on conflict (id) do nothing;
