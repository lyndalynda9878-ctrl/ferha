-- =============================================================================
-- Ferha — 040_nom_et_email_figes_en_demonstration.sql
-- Le nom et l'adresse d'un compte de démonstration ne se modifient plus depuis
-- l'application ni depuis l'API.
--
-- LA DÉCISION ÉTAIT ÉCRITE D'AVANCE. Le 17 septembre 2026, 038 a fermé `phone`
-- et laissé `full_name` et `email` ouverts : aucun écran ne les écrit, il faut
-- appeler l'API délibérément pour y toucher, et le ménage du décor les remet au
-- bout de deux heures. Le README nommait la condition qui retournerait ce
-- choix : « le jour où l'adresse du site est diffusée — un lien sur un CV ».
-- Ce jour est arrivé. Le calcul change avec le nombre de gens qui passent : un
-- nom grossier posé sur Amina resterait jusqu'à trois heures devant chaque
-- visiteur, et sur un lien de CV, ce visiteur est un recruteur.
--
-- -----------------------------------------------------------------------------
-- POURQUOI UN DÉCLENCHEUR — la même raison qu'en 038
--
-- La porte, c'est la politique `profiles_update_self` : tout compte connecté
-- peut écrire sa propre ligne par PostgREST. Aucune fonction n'est en travers.
-- Le déclencheur est en dessous de toutes les portes, présentes et à venir.
--
-- IL FORCE, IL NE REFUSE PAS. Une écriture qui touche le nom ET la langue doit
-- garder la langue : la bascule fr / ar écrit `profiles.locale` pour de bon.
-- Refuser la ligne entière casserait ce geste-là pour protéger l'autre. Le
-- déclencheur remet donc l'ancien nom et l'ancienne adresse, et laisse passer
-- le reste.
--
-- IL FIGE, IL NE RECOPIE PAS L'EMPREINTE. On remet `old.full_name` et
-- `old.email`, pas les valeurs de `decor_profiles` (036). La ligne en place est
-- déjà la bonne : le rattrapage ci-dessous l'y ramène une fois, et plus rien
-- côté application ne peut l'en écarter. Lire l'empreinte ajouterait une
-- dépendance, et une seconde vérité à tenir.
--
-- LE RÔLE DE SERVICE PASSE — `auth.uid()` est null. C'est la règle de 018,
-- recopiée : les migrations, `seed/003_demo_accounts.sql`, le ménage du décor
-- sous pg_cron et l'éditeur SQL écrivent sans jeton d'utilisateur. Ce sont eux
-- qui DÉCIDENT du nom d'Amina ; un visiteur connecté comme elle ne le décide
-- pas. Sans cette exception, rejouer seed/003 avec un nouveau nom échouerait
-- en silence — la ligne garderait l'ancien.
--
-- À la différence de 038, ce déclencheur ne regarde donc pas QUI est la ligne
-- seulement, mais aussi QUI écrit. 038 force `phone` même pour le rôle de
-- service, parce qu'aucun numéro n'a jamais lieu d'être sur ces comptes ; un
-- nom, lui, doit pouvoir être choisi.
--
-- SEULEMENT À LA MISE À JOUR. Un compte connecté ne peut pas insérer une
-- ligne `d0000000-…` : `profiles_insert_self` exige `id = auth.uid()`, et la
-- ligne de chaque compte de démonstration existe déjà. Un upsert passe par la
-- branche UPDATE, et donc par ici.
--
-- LE CRITÈRE N'EST PAS INVENTÉ ICI. `id::text like 'd0000000-%'`, mot pour mot
-- comme en 035, 036 et 038, et comme `prefixeCompteDemonstration` dans
-- lib/features/auth/demo_accounts.dart.
--
-- L'ORDRE DES DÉCLENCHEURS. Alphabétique à timing égal :
--
--     profiles_guard_privileges                    (018)
--     profiles_nom_et_email_figes_en_demonstration (celui-ci)
--     profiles_normalise_telephone                 (020)
--     profiles_pas_de_telephone_en_demonstration   (038)
--     profiles_set_updated_at                      (001)
--
-- Aucun autre ne touche `full_name` ni `email` : l'ordre est sans effet
-- aujourd'hui, et il le restera tant que ce sera vrai.
--
-- CE QU'IL NE FAIT PAS. Il ne touche pas `auth.users` : l'adresse de connexion
-- d'un compte de démonstration ne change que si l'on demande à GoTrue une
-- confirmation envoyée à `@demo.ferha.dz`, que personne ne reçoit. Il ne
-- touche à aucun compte réel.
--
-- Dépend de : 001 (profiles), 018 (la règle du rôle de service), 036
--             (decor_profiles, pour le rattrapage).
-- =============================================================================

create or replace function public.profiles_nom_et_email_figes_en_demonstration()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  -- Le rôle de service décide du décor : voir l'en-tête et 018.
  if auth.uid() is null then
    return new;
  end if;

  -- La convention du décor, mot pour mot comme en 035, 036 et 038.
  if new.id::text like 'd0000000-%' then
    new.full_name := old.full_name;
    new.email     := old.email;
  end if;

  return new;
end;
$$;

comment on function public.profiles_nom_et_email_figes_en_demonstration() is
  'Remet full_name et email à leur valeur précédente quand un compte connecté écrit '
  'une ligne de démonstration (d0000000-…). Force, ne refuse pas : la langue écrite dans '
  'la même requête passe. Le rôle de service (seeds, ménage, migrations) n''est pas concerné.';

drop trigger if exists profiles_nom_et_email_figes_en_demonstration on public.profiles;

create trigger profiles_nom_et_email_figes_en_demonstration
  before update on public.profiles
  for each row
  execute function public.profiles_nom_et_email_figes_en_demonstration();

-- -----------------------------------------------------------------------------
-- Le rattrapage — ce qui est déjà en base
--
-- Un barbouillage posé avant ce fichier, et pas encore remis par le ménage, se
-- figerait avec le reste. On ramène donc une fois les deux champs à
-- l'empreinte du décor, sans attendre le délai de deux heures. La migration
-- tourne sans jeton : le déclencheur la laisse passer.
-- -----------------------------------------------------------------------------

update public.profiles p
   set full_name = e.full_name,
       email     = e.email
  from public.decor_profiles e
 where e.id = p.id
   and p.id::text like 'd0000000-%'
   and (p.full_name, p.email) is distinct from (e.full_name, e.email);

-- -----------------------------------------------------------------------------
-- Le bloc de preuve
-- -----------------------------------------------------------------------------

do $$
declare
  v_comptes  integer;
  v_ecarts   integer;
  v_declench integer;
begin
  select count(*) into v_comptes
  from public.profiles where id::text like 'd0000000-%';

  select count(*) into v_ecarts
  from public.profiles p
  join public.decor_profiles e on e.id = p.id
  where (p.full_name, p.email) is distinct from (e.full_name, e.email);

  select count(*) into v_declench
  from pg_trigger t join pg_class c on c.oid = t.tgrelid
  where c.relname = 'profiles'
    and t.tgname = 'profiles_nom_et_email_figes_en_demonstration';

  raise notice 'Comptes de démonstration : %. Écarts à l''empreinte : %. Déclencheur en place : %.',
    v_comptes, v_ecarts, v_declench;

  if v_ecarts <> 0 then
    raise exception 'ÉCHEC — % compte(s) de démonstration s''écartent encore de l''empreinte.', v_ecarts;
  end if;

  if v_declench <> 1 then
    raise exception 'ÉCHEC — le déclencheur n''est pas en place.';
  end if;
end $$;

select
  (select count(*) from public.profiles where id::text like 'd0000000-%')   as comptes_de_demonstration,
  (select count(*) from public.profiles p
     join public.decor_profiles e on e.id = p.id
    where (p.full_name, p.email) is distinct from (e.full_name, e.email))   as ecarts_a_l_empreinte,
  (select count(*) from pg_trigger t join pg_class c on c.oid = t.tgrelid
    where c.relname = 'profiles'
      and t.tgname = 'profiles_nom_et_email_figes_en_demonstration')        as declencheur;
