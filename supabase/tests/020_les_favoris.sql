-- =============================================================================
-- Ferha — tests/020_les_favoris.sql
--
-- CE QU'ON VÉRIFIE : les deux règles de la migration 039 qui ne peuvent pas
-- vivre ailleurs que dans la base.
--
--   1. LA CLÉ PRIMAIRE COMPOSITE rend le doublon IMPOSSIBLE. Aimer deux fois
--      la même salle ne crée pas deux lignes — et ce n'est pas un `if` en Dart
--      qui l'empêche, c'est `primary key (user_id, venue_id)`.
--
--   2. LA RLS ISOLE. La personne B ne voit AUCUN favori de la personne A, ne
--      peut pas en retirer un, et ne peut pas en poser un au nom de A.
--
-- POURQUOI DES ASSERTIONS NÉGATIVES, ET NON DES « ÇA RENVOIE VIDE ». « La
-- requête ne renvoie rien » est le genre de test qui passe aussi quand rien n'a
-- été écrit — donc quand la table est vide, quand le décor n'est pas là, quand
-- la migration n'a pas tourné. Chaque test ci-dessous ÉCRIT d'abord, PROUVE que
-- l'écriture a pris, puis exige que l'autre ne la voie pas. Un fichier qui ne
-- poserait rien échouerait au test 2, qui attend l'inverse.
--
-- POURQUOI DES « set local role authenticated » DANS LA SECONDE MOITIÉ. Les
-- tests 1 à 3 portent sur des CONTRAINTES — clé primaire, clés étrangères — et
-- une contrainte s'applique à tout le monde, rôle de service compris. Les tests
-- 4 à 8 portent sur la RLS, qui NE S'APPLIQUE PAS au rôle avec lequel on colle
-- ce fichier dans l'éditeur SQL. Sans changer de rôle, ils liraient tout et
-- passeraient toujours : ils ne prouveraient rien. C'est la même raison qu'au
-- test 6 de tests/004_agenda_proprietaire.sql.
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
-- Prérequis : migrations 001 à 039. Aucun seed : ce fichier crée ses propres
--             personnes et ses propres salles, hors de tout préfixe de
--             démonstration — le ménage du décor ne doit jamais les voir.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- Le décor de CE fichier — deux personnes, deux salles
--
-- Les identifiants en 7e000020- ne portent aucun préfixe de démonstration :
-- ni d0000000-, ni 5a11e000-. C'est délibéré, et le test 9 s'en sert.
-- -----------------------------------------------------------------------------

do $$
declare
  c_a        constant uuid := '7e000020-0000-4000-a000-00000000000a';
  c_b        constant uuid := '7e000020-0000-4000-a000-00000000000b';
  c_prop     constant uuid := '7e000020-0000-4000-a000-00000000000c';
  c_salle    constant uuid := '7e000020-0000-4000-a000-000000000001';
  c_brouillon constant uuid := '7e000020-0000-4000-a000-000000000002';

  v_lignes   integer;
  v_refus    text;
begin
  -- ---------------------------------------------------------------------------
  -- Test 0 — la table existe, et elle est bien fermée en UPDATE
  -- ---------------------------------------------------------------------------
  if to_regclass('public.favorites') is null then
    raise exception 'ÉCHEC 0 — la table favorites n''existe pas. Appliquez la migration 039.';
  end if;

  if not (select relrowsecurity from pg_class where oid = 'public.favorites'::regclass) then
    raise exception 'ÉCHEC 0 — RLS n''est pas activé sur favorites.';
  end if;

  -- AUCUNE POLITIQUE D'UPDATE : un favori existe ou n'existe pas. Si quelqu'un
  -- en ajoute une un jour, ce test le lui dira.
  if exists (select 1 from pg_policies
              where schemaname = 'public' and tablename = 'favorites' and cmd = 'UPDATE') then
    raise exception 'ÉCHEC 0 — une politique d''UPDATE est apparue sur favorites. '
                    'Un favori n''a rien à modifier : il existe, ou il n''existe pas.';
  end if;

  if (select count(*) from pg_policies
       where schemaname = 'public' and tablename = 'favorites') <> 3 then
    raise exception 'ÉCHEC 0 — favorites porte % politiques au lieu des 3 attendues '
                    '(select, insert, delete).',
      (select count(*) from pg_policies where schemaname = 'public' and tablename = 'favorites');
  end if;

  raise notice 'OK 0/9 — favorites est là, RLS activé, trois politiques, aucune en UPDATE.';

  -- ---------------------------------------------------------------------------
  -- Les personnes et les salles du fichier
  -- ---------------------------------------------------------------------------
  insert into auth.users (instance_id, id, aud, role, email,
                          encrypted_password, email_confirmed_at,
                          created_at, updated_at,
                          raw_app_meta_data, raw_user_meta_data)
  values
    ('00000000-0000-0000-0000-000000000000', c_a, 'authenticated', 'authenticated',
     'test.a.020@ferha.test', '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb),
    ('00000000-0000-0000-0000-000000000000', c_b, 'authenticated', 'authenticated',
     'test.b.020@ferha.test', '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb),
    ('00000000-0000-0000-0000-000000000000', c_prop, 'authenticated', 'authenticated',
     'test.prop.020@ferha.test', '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb);

  insert into public.profiles (id, full_name, email, is_owner) values
    (c_a,    'Personne A du test 020',   'test.a.020@ferha.test',    false),
    (c_b,    'Personne B du test 020',   'test.b.020@ferha.test',    false),
    (c_prop, 'Propriétaire du test 020', 'test.prop.020@ferha.test', true)
  on conflict (id) do nothing;

  insert into public.venues (id, owner_id, name, wilaya_code, commune,
                             capacity_seated, status)
  values
    (c_salle,     c_prop, 'Salle du test 020',     '31', 'Oran', 300, 'published'),
    (c_brouillon, c_prop, 'Brouillon du test 020', '31', 'Oran', 120, 'draft');

  insert into public.venue_pricing (venue_id, slot, base_price, weekend_coef,
                                    high_season_coef, included_seats, extra_seat_price)
  values
    (c_salle, 'midi',    100000, 1.30, 1.20, 200, 800),
    (c_salle, 'soir',    200000, 1.30, 1.20, 200, 800),
    (c_salle, 'journee', 280000, 1.30, 1.20, 200, 800);

  -- ===========================================================================
  -- TEST 1 — LA CLÉ PRIMAIRE COMPOSITE : UNE SECONDE INSERTION NE CRÉE PAS
  --          UNE SECONDE LIGNE
  --
  -- C'est la même doctrine que l'index partiel qui rend la double réservation
  -- impossible (004) : la base dit non, et le Dart n'a rien à vérifier.
  -- ===========================================================================
  insert into public.favorites (user_id, venue_id) values (c_a, c_salle);

  -- L'ÉCRITURE A PRIS. Sans cette assertion, le test 1 passerait sur une table
  -- où l'insertion échoue silencieusement.
  select count(*) into v_lignes
  from public.favorites where user_id = c_a and venue_id = c_salle;
  if v_lignes <> 1 then
    raise exception 'ÉCHEC 1 — la première insertion n''a pas pris (% ligne(s)).', v_lignes;
  end if;

  -- LA SECONDE EST REFUSÉE, ET ON EXIGE LE CODE. `unique_violation` (23505) est
  -- ce que la clé primaire lève ; exiger le code plutôt qu'« une erreur
  -- quelconque » évite qu'un test passe sur un refus qui n'aurait rien à voir —
  -- une clé étrangère absente, par exemple.
  begin
    insert into public.favorites (user_id, venue_id) values (c_a, c_salle);
    raise exception 'ÉCHEC 1 — une seconde insertion du même favori a été ACCEPTÉE. '
                    'La clé primaire ne porte pas les deux colonnes.';
  exception
    when unique_violation then
      null;  -- c'est exactement ce qu'on attend
    when others then
      raise exception 'ÉCHEC 1 — refus inattendu (%) : %', sqlstate, sqlerrm;
  end;

  -- ET IL N'Y A TOUJOURS QU'UNE LIGNE. Le vrai sujet : le refus ne sert à rien
  -- s'il laisse une ligne derrière lui.
  select count(*) into v_lignes
  from public.favorites where user_id = c_a and venue_id = c_salle;
  if v_lignes <> 1 then
    raise exception 'ÉCHEC 1 — % lignes pour le même favori après le refus.', v_lignes;
  end if;

  raise notice 'OK 1/9 — aimer deux fois la même salle ne crée pas deux lignes.';

  -- ===========================================================================
  -- TEST 2 — LES DEUX PERSONNES PEUVENT AIMER LA MÊME SALLE
  --
  -- LE TEST QUI EMPÊCHE DE « CORRIGER » LE TEST 1 EN CASSANT TOUT. Une clé
  -- primaire posée sur venue_id seul passerait le test 1 et rendrait une salle
  -- aimable par une seule personne au monde. Sans ce test-ci, on ne le saurait
  -- qu'en production.
  -- ===========================================================================
  insert into public.favorites (user_id, venue_id) values (c_b, c_salle);

  select count(*) into v_lignes from public.favorites where venue_id = c_salle;
  if v_lignes <> 2 then
    raise exception 'ÉCHEC 2 — % ligne(s) pour deux personnes sur la même salle, au lieu de 2.',
      v_lignes;
  end if;

  raise notice 'OK 2/9 — deux personnes aiment la même salle, chacune sa ligne.';

  -- ===========================================================================
  -- TEST 3 — LA SALLE QUI DISPARAÎT EMPORTE SES FAVORIS (cascade venue_id)
  --
  -- On le prouve sur une salle À PART, créée et détruite ici : le contenu d'un
  -- favori EST la salle, et l'onglet n'a pas à afficher une carte vide.
  -- ===========================================================================
  insert into public.favorites (user_id, venue_id) values (c_a, c_brouillon);

  select count(*) into v_lignes from public.favorites where venue_id = c_brouillon;
  if v_lignes <> 1 then
    raise exception 'ÉCHEC 3 — le favori sur le brouillon n''a pas été posé.';
  end if;

  delete from public.venues where id = c_brouillon;

  select count(*) into v_lignes from public.favorites where venue_id = c_brouillon;
  if v_lignes <> 0 then
    raise exception 'ÉCHEC 3 — la salle est supprimée et % favori(s) la désigne(nt) encore.',
      v_lignes;
  end if;

  raise notice 'OK 3/9 — une salle supprimée emporte les favoris qui la désignaient.';
end $$;

-- =============================================================================
-- LA RLS — à partir d'ici, on cesse d'être le rôle de service
--
-- Voir l'en-tête : sans « set local role », ces tests liraient tout.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- TEST 4 — A VOIT SES DEUX FAVORIS, ET RIEN QUE LES SIENS
-- -----------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims = '{"sub":"7e000020-0000-4000-a000-00000000000a","role":"authenticated"}';

do $$
declare
  c_a     constant uuid := '7e000020-0000-4000-a000-00000000000a';
  c_salle constant uuid := '7e000020-0000-4000-a000-000000000001';
  v_lignes integer;
begin
  select count(*) into v_lignes from public.favorites;

  -- A EN A UN : celui du test 1. (Celui du test 3 est parti avec sa salle.)
  if v_lignes <> 1 then
    raise exception 'ÉCHEC 4 — A voit % ligne(s) au lieu de 1. Soit il ne voit pas la '
                    'sienne, soit il voit celle de B.', v_lignes;
  end if;

  if not exists (select 1 from public.favorites
                  where user_id = c_a and venue_id = c_salle) then
    raise exception 'ÉCHEC 4 — A ne voit pas son propre favori.';
  end if;

  raise notice 'OK 4/9 — A voit son favori.';
end $$;

reset role;

-- -----------------------------------------------------------------------------
-- TEST 5 — B NE VOIT AUCUN FAVORI DE A
--
-- LE TEST QUI COMPTE LE PLUS DE CE FICHIER, avec le test 1. B a un favori à
-- lui — posé au test 2 — donc « B voit 1 ligne » est une assertion qui a du
-- contenu : elle dit à la fois qu'il voit la sienne et qu'il ne voit pas celle
-- de A. Une table vide échouerait ici.
-- -----------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims = '{"sub":"7e000020-0000-4000-a000-00000000000b","role":"authenticated"}';

do $$
declare
  c_a      constant uuid := '7e000020-0000-4000-a000-00000000000a';
  c_b      constant uuid := '7e000020-0000-4000-a000-00000000000b';
  v_lignes integer;
  v_de_a   integer;
begin
  select count(*) into v_lignes from public.favorites;
  select count(*) into v_de_a   from public.favorites where user_id = c_a;

  if v_de_a <> 0 then
    raise exception 'ÉCHEC 5 — B LIT % FAVORI(S) DE A. La politique de lecture fuit.', v_de_a;
  end if;

  if v_lignes <> 1 then
    raise exception 'ÉCHEC 5 — B voit % ligne(s) au lieu de la sienne seule.', v_lignes;
  end if;

  if not exists (select 1 from public.favorites where user_id = c_b) then
    raise exception 'ÉCHEC 5 — B ne voit même pas son propre favori : la politique est trop fermée.';
  end if;

  raise notice 'OK 5/9 — B voit le sien, et AUCUN de ceux de A.';
end $$;

-- -----------------------------------------------------------------------------
-- TEST 6 — B NE PEUT PAS RETIRER LE FAVORI DE A
--
-- La politique de DELETE ne lève pas d'erreur : elle ne voit simplement pas la
-- ligne, et le DELETE touche zéro ligne. On vérifie donc ce qui RESTE, et on le
-- vérifie depuis le rôle de service — car depuis B, la ligne est invisible de
-- toute façon, et « elle a disparu » serait indiscernable de « je ne la vois
-- pas ». C'est tout le piège de ce test.
-- -----------------------------------------------------------------------------

do $$
declare
  c_a constant uuid := '7e000020-0000-4000-a000-00000000000a';
begin
  delete from public.favorites where user_id = c_a;
  raise notice '    (B a tenté de retirer le favori de A ; on va compter ce qui reste.)';
end $$;

reset role;

do $$
declare
  c_a      constant uuid := '7e000020-0000-4000-a000-00000000000a';
  v_lignes integer;
begin
  select count(*) into v_lignes from public.favorites where user_id = c_a;
  if v_lignes <> 1 then
    raise exception 'ÉCHEC 6 — B A SUPPRIMÉ LE FAVORI DE A (il en reste %).', v_lignes;
  end if;
  raise notice 'OK 6/9 — le favori de A a survécu au DELETE de B.';
end $$;

-- -----------------------------------------------------------------------------
-- TEST 7 — B NE PEUT PAS POSER UN FAVORI AU NOM DE A
--
-- `with check (user_id = auth.uid())`. Sans lui, n'importe qui remplirait
-- l'onglet Favoris de n'importe qui.
-- -----------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims = '{"sub":"7e000020-0000-4000-a000-00000000000b","role":"authenticated"}';

do $$
declare
  c_a         constant uuid := '7e000020-0000-4000-a000-00000000000a';
  c_autre     constant uuid := '7e000020-0000-4000-a000-000000000001';
begin
  begin
    insert into public.favorites (user_id, venue_id) values (c_a, c_autre);
    raise exception 'ÉCHEC 7 — B A POSÉ UN FAVORI AU NOM DE A.';
  exception
    when insufficient_privilege then
      null;  -- 42501 : c'est le refus de la politique, et c'est ce qu'on attend
    when unique_violation then
      -- La ligne existe déjà (test 1) : le refus arriverait de toute façon, mais
      -- pas pour la bonne raison. On le dit plutôt que de laisser passer.
      raise exception 'ÉCHEC 7 — refus par la clé primaire et non par la RLS : '
                      'le test ne prouve rien tel quel.';
    when others then
      raise exception 'ÉCHEC 7 — refus inattendu (%) : %', sqlstate, sqlerrm;
  end;

  raise notice 'OK 7/9 — B ne peut pas écrire dans les favoris de A.';
end $$;

reset role;

-- -----------------------------------------------------------------------------
-- TEST 8 — mes_favoris() NE REND QUE LES MIENS
--
-- La fonction est SECURITY DEFINER : elle contourne la RLS de `favorites`, et
-- son seul garde-fou est le `where f.user_id = auth.uid()` de son corps. Si
-- quelqu'un l'enlève un jour, la RLS ne rattrapera rien — c'est pour cela que
-- ce test existe à côté du test 5.
-- -----------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims = '{"sub":"7e000020-0000-4000-a000-00000000000b","role":"authenticated"}';

do $$
declare
  c_salle  constant uuid := '7e000020-0000-4000-a000-000000000001';
  v_lignes integer;
begin
  select count(*) into v_lignes from public.mes_favoris();

  -- B a exactement un favori, sur une salle publiée : il doit le voir.
  if v_lignes <> 1 then
    raise exception 'ÉCHEC 8 — mes_favoris() rend % ligne(s) à B au lieu de 1. '
                    'Au-dessus de 1, elle rend les favoris d''autrui.', v_lignes;
  end if;

  if not exists (select 1 from public.mes_favoris() f where f.venue_id = c_salle) then
    raise exception 'ÉCHEC 8 — mes_favoris() ne rend pas la salle que B a aimée.';
  end if;

  raise notice 'OK 8/9 — mes_favoris() ne rend que les favoris de qui appelle.';
end $$;

reset role;

-- -----------------------------------------------------------------------------
-- TEST 9 — UN VISITEUR NON CONNECTÉ NE VOIT RIEN, ET N'ÉCRIT RIEN
-- -----------------------------------------------------------------------------

set local role anon;
set local request.jwt.claims = '';

do $$
declare
  c_salle  constant uuid := '7e000020-0000-4000-a000-000000000001';
  v_lignes integer;
begin
  select count(*) into v_lignes from public.favorites;
  if v_lignes <> 0 then
    raise exception 'ÉCHEC 9 — un inconnu non connecté lit % favori(s).', v_lignes;
  end if;

  -- mes_favoris() est révoquée pour anon : l'appel lui-même doit être refusé.
  begin
    perform public.mes_favoris();
    raise exception 'ÉCHEC 9 — un inconnu a pu appeler mes_favoris().';
  exception
    when insufficient_privilege then null;
    when others then
      raise exception 'ÉCHEC 9 — refus inattendu sur mes_favoris() (%) : %', sqlstate, sqlerrm;
  end;

  begin
    insert into public.favorites (user_id, venue_id)
    values ('7e000020-0000-4000-a000-00000000000a', c_salle);
    raise exception 'ÉCHEC 9 — un inconnu a pu poser un favori.';
  exception
    when insufficient_privilege then null;
    when others then
      raise exception 'ÉCHEC 9 — refus inattendu à l''insertion (%) : %', sqlstate, sqlerrm;
  end;

  raise notice 'OK 9/9 — non connecté : rien à lire, rien à écrire.';
end $$;

reset role;

do $$
begin
  raise notice '--------------------------------------------------------------';
  raise notice 'tests/020 — tout est passé. La transaction va être annulée.';
end $$;

rollback;
