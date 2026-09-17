-- =============================================================================
-- Ferha — tests/019_pas_de_telephone_en_demonstration.sql
--
-- CE QU'ON VÉRIFIE : que le déclencheur de la migration 038 rend IMPOSSIBLE le
-- dépôt d'un numéro de téléphone sur un compte de démonstration, sans rien
-- casser — ni le parcours du testeur, ni le produit pour un vrai client.
--
-- POURQUOI DES ASSERTIONS NÉGATIVES. « La requête ne renvoie rien » est le
-- genre de test qui passe aussi quand le décor n'a pas été posé. Chaque test
-- ci-dessous ÉCRIT d'abord un numéro, puis exige que la colonne soit NULL. Un
-- test qui ne poserait rien échouerait au test 4, qui attend l'inverse.
--
-- LE TEST 4 EST LE PLUS IMPORTANT. Les trois premiers vérifient que le numéro
-- ne se dépose pas ; le quatrième vérifie qu'il se dépose encore chez un vrai
-- client. Un correctif qui neutraliserait le téléphone pour tout le monde
-- passerait les tests 1 à 3 et casserait le produit en silence : sans le
-- test 4, on ne le saurait qu'en production, le jour où une salle ne pourrait
-- plus rappeler une famille.
--
-- LE TEST 5 PORTE SUR LE §9, ET SUR UNE NUANCE. `booking_contact()` doit
-- continuer à dire « le contact est ouvert » (`phone_available = true`) sur une
-- réservation confirmée, tout en ne rendant AUCUN numéro. Le mécanisme n'est
-- pas cassé : il n'a simplement rien à révéler. Si `phone_available` retombait
-- à false, l'écran afficherait « le téléphone vous sera donné après
-- acceptation » sur une réservation déjà confirmée — un mensonge de plus.
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
-- Prérequis : migrations 001 à 038, et les seeds 001 et 003 (pour Amina).
-- =============================================================================

begin;

do $$
declare
  -- Amina, telle que seed/003_demo_accounts.sql la pose. C'est le compte du
  -- bouton « Entrer comme Amina », donc celui de l'incident.
  c_amina    constant uuid := 'd0000000-0000-4000-a000-000000000010';

  -- Un vrai client et un vrai propriétaire, créés pour ce fichier. Leurs
  -- identifiants ne portent PAS le préfixe du décor : c'est tout le sujet.
  c_client   constant uuid := '7e000000-0000-4000-a000-000000000019';
  c_owner    constant uuid := '7e000000-0000-4000-a000-000000000029';
  c_venue    constant uuid := '7e000000-0000-4000-a000-000000000039';

  c_date     constant date := date '2027-10-16';
  c_numero   constant text := '0770 11 22 33';

  v_tel      text;
  v_verifie  boolean;
  v_booking  uuid;
  v_nb       integer;
  v_open     boolean;
  v_acompte  numeric;
begin
  -- ---------------------------------------------------------------------------
  -- Test 0 — le décor attendu est là
  -- ---------------------------------------------------------------------------
  if not exists (select 1 from public.profiles where id = c_amina) then
    raise exception 'ÉCHEC 0 — Amina absente. Lancez seed/003_demo_accounts.sql.';
  end if;

  if not exists (
    select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid
     where c.relname = 'profiles'
       and t.tgname = 'profiles_pas_de_telephone_en_demonstration') then
    raise exception 'ÉCHEC 0 — le déclencheur de 038 n''est pas en place.';
  end if;

  raise notice 'OK 0/5 — Amina et le déclencheur sont là.';

  -- ---------------------------------------------------------------------------
  -- Test 1 — un update direct : la colonne reste NULL
  --
  -- C'est la porte de `profiles_update_self` : un visiteur connecté comme Amina
  -- peut écrire sa propre ligne par PostgREST, sans passer par aucune RPC.
  -- ---------------------------------------------------------------------------
  update public.profiles set phone = c_numero where id = c_amina;

  select phone into v_tel from public.profiles where id = c_amina;

  if v_tel is not null then
    raise exception 'ÉCHEC 1 — un update direct a déposé le numéro % sur un compte de démonstration.',
      v_tel;
  end if;

  raise notice 'OK 1/5 — update direct : phone reste NULL.';

  -- ---------------------------------------------------------------------------
  -- Test 2 — le même update AVEC phone_verified = true
  --
  -- Le piège de `profiles_phone_verified_requires_phone` : mettre phone à NULL
  -- sans redescendre phone_verified ferait échouer l'écriture. On exige donc
  -- les deux valeurs ET l'absence d'erreur.
  -- ---------------------------------------------------------------------------
  begin
    update public.profiles
       set phone = c_numero, phone_verified = true
     where id = c_amina;
  exception when others then
    raise exception 'ÉCHEC 2 — l''écriture a été refusée (%), alors que le déclencheur doit forcer, pas refuser.',
      sqlerrm;
  end;

  select phone, phone_verified into v_tel, v_verifie
  from public.profiles where id = c_amina;

  if v_tel is not null then
    raise exception 'ÉCHEC 2 — phone vaut % au lieu de NULL.', v_tel;
  end if;

  if v_verifie then
    raise exception 'ÉCHEC 2 — phone_verified est resté à true sans numéro.';
  end if;

  raise notice 'OK 2/5 — phone NULL, phone_verified false, aucune erreur de contrainte.';

  -- ---------------------------------------------------------------------------
  -- Le décor des tests 3 à 5 : une vraie salle, un vrai propriétaire.
  --
  -- On ne réserve pas une salle du décor : sa disponibilité dépend de ce qu'un
  -- visiteur a fait avant nous. Une salle à nous rend le test indépendant.
  -- ---------------------------------------------------------------------------
  insert into auth.users (instance_id, id, aud, role, email,
                          encrypted_password, email_confirmed_at,
                          created_at, updated_at,
                          raw_app_meta_data, raw_user_meta_data)
  values
    ('00000000-0000-0000-0000-000000000000', c_owner,  'authenticated', 'authenticated',
     'test.owner.019@ferha.test',  '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb),
    ('00000000-0000-0000-0000-000000000000', c_client, 'authenticated', 'authenticated',
     'test.client.019@ferha.test', '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb);

  insert into public.profiles (id, full_name, email, is_owner) values
    (c_owner,  'Propriétaire de test 019', 'test.owner.019@ferha.test',  true),
    (c_client, 'Client de test 019',       'test.client.019@ferha.test', false)
  on conflict (id) do nothing;

  insert into public.venues (id, owner_id, name, wilaya_code, commune,
                             capacity_seated, status)
  values (c_venue, c_owner, 'Salle de test 019', '31', 'Oran', 400, 'published');

  insert into public.venue_pricing (venue_id, slot, base_price, weekend_coef,
                                    high_season_coef, included_seats, extra_seat_price)
  values
    (c_venue, 'midi',    100000, 1.30, 1.20, 200, 800),
    (c_venue, 'soir',    200000, 1.30, 1.20, 200, 800),
    (c_venue, 'journee', 280000, 1.30, 1.20, 200, 800);

  -- ---------------------------------------------------------------------------
  -- Test 3 — request_booking() sur un compte de DÉMONSTRATION
  --
  -- La demande doit ABOUTIR — c'est la raison pour laquelle le déclencheur
  -- force au lieu de refuser — et le numéro ne doit pas se déposer.
  -- ---------------------------------------------------------------------------
  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_amina, 'role', 'authenticated')::text,
                     true);

  select id into v_booking
  from public.request_booking(c_venue, c_date, 'soir', 250, c_numero);

  if v_booking is null then
    raise exception 'ÉCHEC 3 — la demande n''a pas abouti : le déclencheur refuse au lieu de forcer.';
  end if;

  select count(*) into v_nb from public.bookings where id = v_booking;
  if v_nb <> 1 then
    raise exception 'ÉCHEC 3 — la réservation % n''existe pas en base.', v_booking;
  end if;

  select phone into v_tel from public.profiles where id = c_amina;
  if v_tel is not null then
    raise exception 'ÉCHEC 3 — request_booking() a déposé % sur un compte de démonstration.', v_tel;
  end if;

  raise notice 'OK 3/5 — la demande existe (%), et phone reste NULL.', v_booking;

  -- ---------------------------------------------------------------------------
  -- Test 4 — le même appel sur un compte NORMAL : le numéro est bien écrit
  --
  -- LE TEST QUI PROTÈGE LE PRODUIT. Voir l'en-tête.
  -- ---------------------------------------------------------------------------
  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_client, 'role', 'authenticated')::text,
                     true);

  perform public.request_booking(c_venue, c_date, 'midi', 250, c_numero);

  select phone into v_tel from public.profiles where id = c_client;

  if v_tel is null then
    raise exception 'ÉCHEC 4 — le numéro d''un VRAI client n''a pas été écrit. Le correctif déborde.';
  end if;

  -- Normalisé : les espaces de la saisie ne sont pas gardés (020).
  if v_tel <> '0770112233' then
    raise exception 'ÉCHEC 4 — numéro attendu 0770112233, reçu %.', v_tel;
  end if;

  raise notice 'OK 4/5 — compte normal : le numéro % est bien écrit.', v_tel;

  -- ---------------------------------------------------------------------------
  -- Test 5 — booking_contact() sur une réservation CONFIRMÉE de démonstration
  --
  -- Le §9 n'est pas cassé : le contact est ouvert, il n'y a rien à révéler.
  --
  -- ON PASSE PAR LES VRAIES FONCTIONS, pas par un update de status. Les
  -- changements d'état d'une réservation passent par des fonctions SQL
  -- sécurisées : c'est la règle du projet, et c'est aussi le parcours exact du
  -- README — accepter, payer en espèces, confirmer l'encaissement.
  --
  -- Le taux vient de deposit_rate(), pas d'un nombre écrit ici : le montant ne
  -- doit pas être une seconde formule.
  -- ---------------------------------------------------------------------------
  select round(b.quoted_amount * public.deposit_rate(), 2) into v_acompte
  from public.bookings b where b.id = v_booking;

  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_owner, 'role', 'authenticated')::text,
                     true);
  perform public.accept_booking(v_booking, v_acompte);

  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_amina, 'role', 'authenticated')::text,
                     true);
  perform public.payer_en_especes(v_booking);

  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_owner, 'role', 'authenticated')::text,
                     true);
  perform public.confirmer_encaissement_especes(v_booking);

  if (select status from public.bookings where id = v_booking) <> 'confirmed' then
    raise exception 'ÉCHEC 5 — la réservation n''est pas passée en « confirmed ».';
  end if;

  -- Le propriétaire regarde la demande : c'est lui qui verrait le numéro.
  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_owner, 'role', 'authenticated')::text,
                     true);

  select phone, phone_available into v_tel, v_open
  from public.booking_contact(v_booking);

  if v_tel is not null then
    raise exception 'ÉCHEC 5 — booking_contact() a rendu le numéro % sur un compte de démonstration.',
      v_tel;
  end if;

  if not v_open then
    raise exception 'ÉCHEC 5 — phone_available est false sur une réservation confirmée : le §9 s''est inversé.';
  end if;

  raise notice 'OK 5/5 — §9 intact : contact ouvert (phone_available = true), aucun numéro rendu.';

  perform set_config('request.jwt.claims', '', true);

  raise notice '--- Les 5 tests passent. ---';
end $$;

rollback;
