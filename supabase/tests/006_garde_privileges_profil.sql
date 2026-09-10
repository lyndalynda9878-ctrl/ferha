-- =============================================================================
-- Ferha — tests/006_garde_privileges_profil.sql
--
-- CE QU'ON VÉRIFIE : qu'un compte connecté ordinaire ne peut plus se donner de
-- droits, et que les chemins légitimes n'ont rien perdu.
--
-- CE FICHIER REJOUE UNE ATTAQUE QUI MARCHAIT. Avant la migration 018, ces
-- quatre instructions suffisaient, avec la seule clé anon et un compte créé
-- normalement :
--
--   update public.profiles set is_admin = true where id = auth.uid();
--   select * from public.profiles;              -- tous, nom et téléphone
--   update public.venues set status = 'published' where ...;  -- n'importe laquelle
--
-- Le trou n'était pas dans une politique manquante : `profiles_update_self`
-- (002) existe et fait ce qu'elle dit — elle borne la LIGNE qu'on écrit, pas
-- les COLONNES. Or `is_admin` et `is_owner` ne sont pas des données, ce sont
-- des droits. Un `WITH CHECK` ne voit que la ligne d'arrivée et ne peut donc
-- pas distinguer « était déjà administrateur » de « vient de se déclarer
-- administrateur » : la règle vit dans un trigger, comme celle de
-- `venues_guard_status` en 001, et pour le même motif.
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
-- POURQUOI TOUT CE FICHIER TOURNE EN « set local role authenticated ». Ce qu'on
-- teste ici n'est pas une fonction dont le garde-fou lit `auth.uid()` : ce sont
-- des écritures DIRECTES dans une table, arrêtées par un trigger qui laisse
-- passer le rôle de service. Avec le rôle qui colle ce fichier, toutes les
-- attaques réussiraient et le test annoncerait un désastre qui n'existe pas —
-- ou, pire, le contraire.
--
-- CE QU'IL LAISSE : rien. Tout est fait dans une transaction annulée à la fin.
--
-- Prérequis : migrations 001 à 018 appliquées.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- Le décor, posé en rôle de service : deux comptes ordinaires, et une salle
-- qui appartient à l'un d'eux.
-- -----------------------------------------------------------------------------

do $$
declare
  c_pirate constant uuid := 'c0000006-0000-4000-a000-000000000001';
  c_karim  constant uuid := 'c0000006-0000-4000-a000-000000000002';
  c_salle  constant uuid := 'c0000006-0000-4000-a000-000000000003';
  v_wilaya text;
begin
  insert into auth.users (instance_id, id, aud, role, email,
                          encrypted_password, email_confirmed_at,
                          created_at, updated_at,
                          raw_app_meta_data, raw_user_meta_data)
  values
    ('00000000-0000-0000-0000-000000000000', c_pirate, 'authenticated', 'authenticated',
     'test.pirate.006@ferha.test', '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb),
    ('00000000-0000-0000-0000-000000000000', c_karim,  'authenticated', 'authenticated',
     'test.karim.006@ferha.test',  '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb);

  insert into public.profiles (id, full_name, email, is_owner, is_admin) values
    (c_pirate, 'Compte Ordinaire', 'test.pirate.006@ferha.test', false, false),
    (c_karim,  'Karim Belkacem',   'test.karim.006@ferha.test',  true,  false)
  on conflict (id) do update
    set full_name = excluded.full_name,
        is_owner  = excluded.is_owner,
        is_admin  = excluded.is_admin;

  select w.code into v_wilaya from public.wilayas w order by w.code limit 1;

  insert into public.venues (id, owner_id, name, wilaya_code, commune,
                             capacity_seated, status)
  values (c_salle, c_karim, 'Salle de test 006', v_wilaya, 'Oran', 400, 'published');
end $$;

-- =============================================================================
-- Les attaques, avec le rôle et le jeton d'un client de l'application.
-- =============================================================================

set local role authenticated;
set local request.jwt.claims = '{"sub":"c0000006-0000-4000-a000-000000000001","role":"authenticated"}';

do $$
declare
  c_pirate constant uuid := 'c0000006-0000-4000-a000-000000000001';
  c_karim  constant uuid := 'c0000006-0000-4000-a000-000000000002';
  c_salle  constant uuid := 'c0000006-0000-4000-a000-000000000003';
  v_bool   boolean;
  v_lignes integer;
begin
  -- ---------------------------------------------------------------------------
  -- Test 1 — LE COMPTE NE SE FAIT PLUS ADMINISTRATEUR
  --
  -- L'attaque exacte, en une ligne, telle qu'elle marchait.
  -- ---------------------------------------------------------------------------
  begin
    update public.profiles p set is_admin = true where p.id = c_pirate;
    raise exception
      'ÉCHEC 1 — UN COMPTE ORDINAIRE S''EST FAIT ADMINISTRATEUR. Il lit dès '
      'lors le nom, l''e-mail et le téléphone de tous les utilisateurs, et '
      'publie n''importe quelle salle.';
  exception when check_violation then
    null;   -- c'est le refus attendu
  end;

  select p.is_admin into v_bool from public.profiles p where p.id = c_pirate;
  if v_bool then
    raise exception 'ÉCHEC 1 — is_admin est vrai après le refus.';
  end if;

  -- Et la conséquence est bien fermée : il ne lit que son propre profil.
  select count(*) into v_lignes from public.profiles;
  if v_lignes <> 1 then
    raise exception
      'ÉCHEC 1 — le compte lit % profils au lieu du sien seul.', v_lignes;
  end if;

  raise notice 'OK 1 — is_admin ne se donne pas, et le compte ne lit que son profil.';

  -- ---------------------------------------------------------------------------
  -- Test 2 — IL NE SE DÉCLARE PAS PROPRIÉTAIRE NON PLUS
  --
  -- `is_owner` n'ouvrait aucun droit — tout l'espace propriétaire passe par
  -- `owns_venue()`. Ce qu'on ferme ici est plus modeste : la base ne doit pas
  -- porter une affirmation fausse.
  -- ---------------------------------------------------------------------------
  begin
    update public.profiles p set is_owner = true where p.id = c_pirate;
    raise exception
      'ÉCHEC 2 — un compte sans aucune salle s''est déclaré propriétaire.';
  exception when check_violation then
    null;
  end;

  select p.is_owner into v_bool from public.profiles p where p.id = c_pirate;
  if v_bool then
    raise exception 'ÉCHEC 2 — is_owner est vrai après le refus.';
  end if;

  raise notice 'OK 2 — is_owner ne se déclare pas sans salle.';

  -- ---------------------------------------------------------------------------
  -- Test 3 — CE QUI RESTE PERMIS L'EST RESTÉ
  --
  -- La garde ne doit pas fermer la modification du profil : changer son nom ou
  -- son téléphone est le geste normal de l'écran de profil (§4.1, CORE-02).
  -- Un correctif de sécurité qui casse l'usage courant se fait retirer.
  -- ---------------------------------------------------------------------------
  update public.profiles p
     set full_name = 'Nouveau Nom', phone = '0550123456'
   where p.id = c_pirate;

  if (select p.full_name from public.profiles p where p.id = c_pirate)
     is distinct from 'Nouveau Nom' then
    raise exception 'ÉCHEC 3 — le compte ne peut plus changer son propre nom.';
  end if;

  raise notice 'OK 3 — nom et téléphone se modifient toujours.';

  -- ---------------------------------------------------------------------------
  -- Test 4 — ET LE PROFIL DES AUTRES RESTE FERMÉ
  --
  -- Ce n'était pas cassé, mais c'est la porte que le test 1 protège : autant
  -- vérifier qu'elle est bien celle qu'on croit.
  -- ---------------------------------------------------------------------------
  update public.profiles p set is_admin = true where p.id = c_karim;
  select p.is_admin into v_bool from public.profiles p where p.id = c_karim;
  if coalesce(v_bool, false) then
    raise exception 'ÉCHEC 4 — le compte a promu QUELQU''UN D''AUTRE administrateur.';
  end if;

  -- Le profil de Karim n'est pas lisible : la valeur relue est NULL, pas false.
  if v_bool is not null then
    raise exception 'ÉCHEC 4 — le profil d''un autre compte est lisible.';
  end if;

  raise notice 'OK 4 — l''UPDATE sur le profil d''un autre ne touche aucune ligne.';

  -- ---------------------------------------------------------------------------
  -- Test 5 — LA SALLE D'UN AUTRE NE SE PUBLIE TOUJOURS PAS
  --
  -- La seconde conséquence de l'ancienne faille : administrateur, le compte
  -- passait `venues_guard_status` et publiait n'importe quoi. Il ne l'est plus,
  -- et la politique `venues_update_own` l'arrête de toute façon.
  -- ---------------------------------------------------------------------------
  update public.venues v set status = 'suspended' where v.id = c_salle;

  if (select v.status from public.venues v where v.id = c_salle)
     is distinct from 'published' then
    raise exception 'ÉCHEC 5 — la salle d''un autre a changé de statut.';
  end if;

  raise notice 'OK 5 — la salle d''un autre est intacte.';
end $$;

-- =============================================================================
-- Test 6 — LE CHEMIN LÉGITIME N'A RIEN PERDU
--
-- `creer_salle()` (017) lève `is_owner` sur un compte qui ne l'était pas. Elle
-- s'exécute avec `auth.uid()` renseigné — être SECURITY DEFINER n'y change
-- rien —, donc elle passe par le trigger comme tout le monde. Elle marche parce
-- qu'elle insère la salle AVANT de lever le drapeau : la condition « ce compte
-- possède une salle » est déjà vraie quand le trigger la vérifie.
--
-- C'est LE test qui empêche ce correctif de casser le J12, et il tourne avec le
-- même rôle et le même jeton qu'un vrai client.
-- =============================================================================

do $$
declare
  c_pirate constant uuid := 'c0000006-0000-4000-a000-000000000001';
  v_wilaya text;
  v_salle  uuid;
  v_bool   boolean;
begin
  select w.code into v_wilaya from public.wilayas w order by w.code limit 1;

  select v.id into v_salle
  from public.creer_salle('Ma première salle', v_wilaya, 'Oran',
                          'Cité 200 logements, route de l''aéroport', 250) v;

  if v_salle is null then
    raise exception 'ÉCHEC 6 — creer_salle() n''a rendu aucune salle.';
  end if;

  select p.is_owner into v_bool from public.profiles p where p.id = c_pirate;
  if not v_bool then
    raise exception
      'ÉCHEC 6 — LE CORRECTIF A CASSÉ LE J12 : creer_salle() n''arrive plus à '
      'lever is_owner, et une cliente qui inscrit une salle n''a plus aucun '
      'chemin pour la retrouver.';
  end if;

  raise notice 'OK 6 — creer_salle() lève toujours is_owner : le chemin légitime est intact.';
end $$;

reset role;

-- =============================================================================
-- Test 7 — LE RÔLE DE SERVICE PASSE ENCORE
--
-- C'est par lui, et par lui seul, que le premier administrateur existe : les
-- migrations, le déclencheur d'inscription de 007 et le futur back-office. Le
-- fermer aussi rendrait la plateforme ingouvernable.
-- =============================================================================

do $$
declare
  c_pirate constant uuid := 'c0000006-0000-4000-a000-000000000001';
  v_bool   boolean;
begin
  -- Le jeton est vide : `auth.uid()` est null, comme pour le rôle de service.
  perform set_config('request.jwt.claims', '', true);

  update public.profiles p set is_admin = true where p.id = c_pirate;

  select p.is_admin into v_bool from public.profiles p where p.id = c_pirate;
  if not v_bool then
    raise exception
      'ÉCHEC 7 — le rôle de service ne peut plus nommer un administrateur : '
      'plus personne ne pourrait en créer un.';
  end if;

  raise notice 'OK 7 — le rôle de service nomme toujours un administrateur.';
end $$;

rollback;
