-- =============================================================================
-- Ferha — 041_connexion_figee_en_demonstration.sql
-- Le mot de passe, l'adresse, le téléphone et les métadonnées d'un compte de
-- démonstration ne se modifient plus par l'API d'authentification.
--
-- LA FAILLE, CONSTATÉE LE 3 OCTOBRE 2026, PAS SUPPOSÉE. Connecté comme Amina
-- avec la clé publique, un seul appel suffisait :
--
--     PUT /auth/v1/user  {"password": "…"}          → 200
--     connexion avec demo1234                       → 400 invalid_credentials
--
-- Même chose pour Karim. Les deux boutons « Entrer comme… » cessaient de
-- marcher pour tout le monde, et aucun ménage ne réparait : 035 à 039 ne
-- touchent pas auth.users. Le mot de passe a été remis par l'API le jour même.
--
-- L'adresse, elle, était refusée — mais par chance : GoTrue doit écrire à
-- l'adresse ACTUELLE pour confirmer le changement, et `demo.ferha.dz` n'a pas de
-- serveur de courrier (« email_address_invalid »). Une protection qui tient au
-- DNS tombe le jour où `ferha.dz` reçoit des enregistrements MX. On la fige ici
-- pour de bon.
--
-- 040 protège `profiles`, la fiche. Ce fichier protège `auth.users`, la
-- serrure. La porte n'est pas PostgREST mais GoTrue : `auth.updateUser` écrit
-- dans auth.users sous le rôle `supabase_auth_admin`.
--
-- -----------------------------------------------------------------------------
-- QUI ÉCRIT — LE CRITÈRE N'EST PAS CELUI DE 040, ET C'EST VOULU
--
-- 040 regarde `auth.uid()`. Ici il vaut toujours NULL : GoTrue ne pose pas de
-- jeton sur sa propre connexion. On regarde donc `current_user`. GoTrue est le
-- SEUL à écrire sous `supabase_auth_admin` ; seed/003, le ménage sous pg_cron,
-- les migrations et l'éditeur SQL écrivent en `postgres`. Ce sont eux qui
-- décident du mot de passe de démonstration : ils passent.
--
-- PAS DE SECURITY DEFINER, ET C'EST LA LIGNE LA PLUS IMPORTANTE DU FICHIER.
-- Une fonction SECURITY DEFINER s'exécute sous son propriétaire : `current_user`
-- y vaudrait `postgres` pour tout le monde, la condition ne serait jamais vraie,
-- et le déclencheur ne protégerait rien — sans la moindre erreur. Le corps ne
-- lit aucune table, il n'a besoin d'aucun droit : SECURITY INVOKER suffit.
--
-- -----------------------------------------------------------------------------
-- IL FORCE, IL NE REFUSE PAS — et ici c'est une question de sûreté
--
-- GoTrue écrit dans auth.users à CHAQUE connexion (last_sign_in_at). Un
-- déclencheur qui lèverait une erreur, ou qui planterait, empêcherait toute
-- connexion, démonstration ou non. Celui-ci ne fait que recopier OLD dans NEW
-- pour quelques colonnes, sans requête ni conversion : il n'a aucun moyen
-- d'échouer. Le visiteur reçoit 200, et rien n'a changé.
--
-- CE QUI EST FIGÉ, ET POURQUOI CHACUN :
--   encrypted_password        la faille constatée ;
--   email, email_change*      la confirmation d'adresse, quel que soit le DNS ;
--   phone, phone_change*      `auth.updateUser({phone})`, même raisonnement ;
--   raw_user_meta_data        `auth.updateUser({data})` y écrit du texte libre,
--                             et handle_new_user (007) y lit le nom.
-- last_sign_in_at, updated_at et les jetons de session ne sont PAS figés : la
-- connexion doit continuer d'écrire ce qu'elle écrit.
--
-- LE PRIX. `auth.admin.updateUserById`, l'API d'administration, passe elle
-- aussi par GoTrue : elle ne changera plus ces colonnes sur un compte de
-- démonstration. On les change en SQL, comme seed/003 l'a toujours fait.
--
-- LE CRITÈRE DU DÉCOR, mot pour mot comme en 035, 036, 038 et 040 :
-- `id::text like 'd0000000-%'`. Aucun compte réel n'est concerné.
--
-- ANNULER EN UNE SECONDE, si une connexion échoue après ce fichier :
--
--     drop trigger if exists auth_connexion_figee_en_demonstration on auth.users;
--
-- Dépend de : seed/003 (les comptes), 040 (la même décision côté profiles).
-- =============================================================================

create or replace function public.auth_connexion_figee_en_demonstration()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  -- GoTrue, et lui seul, écrit sous ce rôle. Voir l'en-tête.
  if current_user <> 'supabase_auth_admin' then
    return new;
  end if;

  -- La convention du décor, mot pour mot comme en 035, 036, 038 et 040.
  if new.id::text like 'd0000000-%' then
    new.encrypted_password         := old.encrypted_password;
    new.email                      := old.email;
    new.email_change               := old.email_change;
    new.email_change_token_new     := old.email_change_token_new;
    new.email_change_token_current := old.email_change_token_current;
    new.email_change_confirm_status := old.email_change_confirm_status;
    new.email_change_sent_at       := old.email_change_sent_at;
    new.phone                      := old.phone;
    new.phone_change               := old.phone_change;
    new.phone_change_token         := old.phone_change_token;
    new.phone_change_sent_at       := old.phone_change_sent_at;
    new.raw_user_meta_data         := old.raw_user_meta_data;
  end if;

  return new;
end;
$$;

comment on function public.auth_connexion_figee_en_demonstration() is
  'Remet mot de passe, adresse, téléphone et métadonnées à leur valeur précédente quand '
  'GoTrue (supabase_auth_admin) écrit un compte de démonstration (d0000000-…). Force, ne '
  'refuse pas : la connexion continue d''écrire last_sign_in_at. SECURITY INVOKER exprès.';

drop trigger if exists auth_connexion_figee_en_demonstration on auth.users;

create trigger auth_connexion_figee_en_demonstration
  before update on auth.users
  for each row
  execute function public.auth_connexion_figee_en_demonstration();

-- -----------------------------------------------------------------------------
-- Le bloc de preuve
-- -----------------------------------------------------------------------------

do $$
declare
  v_declench integer;
  v_definer  boolean;
begin
  select count(*) into v_declench
  from pg_trigger t
  join pg_class c     on c.oid = t.tgrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'auth' and c.relname = 'users'
    and t.tgname = 'auth_connexion_figee_en_demonstration'
    and t.tgenabled = 'O';

  select p.prosecdef into v_definer
  from pg_proc p
  where p.oid = 'public.auth_connexion_figee_en_demonstration()'::regprocedure;

  raise notice 'Déclencheur actif : %. SECURITY DEFINER : %.', v_declench, v_definer;

  if v_declench <> 1 then
    raise exception 'ÉCHEC — le déclencheur n''est pas actif sur auth.users.';
  end if;

  if v_definer then
    raise exception 'ÉCHEC — la fonction est SECURITY DEFINER : current_user y vaudrait son propriétaire.';
  end if;
end $$;
