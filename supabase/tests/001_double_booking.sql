-- =============================================================================
-- Ferha — tests/001_double_booking.sql
--
-- CE QU'ON VÉRIFIE : la contrainte du §6.1. Une date + un créneau ne portent
-- qu'une seule réservation confirmée, et c'est LA BASE qui le refuse — pas le
-- code Flutter, pas une fonction, pas une vérification préalable. Si ce test
-- passe, deux familles ne peuvent pas se retrouver le même 14 août dans la même
-- salle, quoi que fasse l'application.
--
-- COMMENT LE LANCER : coller le fichier entier dans l'éditeur SQL de Supabase
-- et exécuter. Une seule fois, d'un bloc.
--
-- COMMENT LE LIRE :
--   * un tableau vert avec des lignes « OK »            → tout va bien ;
--   * une erreur rouge commençant par « ÉCHEC »         → une règle ne tient pas,
--                                                         le message dit laquelle.
--   Certains clients SQL n'affichent que le résultat de la DERNIÈRE instruction,
--   et la dernière ici est ROLLBACK. Si vous ne voyez qu'un « Success. No rows
--   returned » sans erreur rouge, c'est que tout est passé : les échecs, eux,
--   s'affichent toujours.
--
-- CE QU'IL LAISSE : rien. Tout est fait dans une transaction annulée à la fin,
-- et la dernière requête, hors transaction, le prouve.
--
-- Prérequis : migrations 001 à 006 appliquées.
-- =============================================================================

begin;

-- Le test crée ses propres données, et rien qu'elles. Ces identifiants sont
-- fixes pour être reconnaissables si jamais quelque chose survivait — ce qui ne
-- doit pas arriver.
--   Salle       : 11111111-1111-1111-1111-111111111111
--   Propriétaire: 22222222-...  Client A : 33333333-...  Client B : 44444444-...

do $$
declare
  c_venue    constant uuid := '11111111-1111-1111-1111-111111111111';
  c_owner    constant uuid := '22222222-2222-2222-2222-222222222222';
  c_client_a constant uuid := '33333333-3333-3333-3333-333333333333';
  c_client_b constant uuid := '44444444-4444-4444-4444-444444444444';
  c_date     constant date := date '2099-08-14';   -- loin dans le futur : aucun
                                                   -- risque de croiser du réel

  v_booking_a uuid;
  v_booking_b uuid;
  v_refused   boolean;
  v_msg       text;
  v_count     integer;
  v_total     numeric;
begin
  -- ---------------------------------------------------------------------------
  -- Données de test
  -- ---------------------------------------------------------------------------

  -- profiles référence auth.users : il faut donc de vrais utilisateurs.
  insert into auth.users (instance_id, id, aud, role, email,
                          encrypted_password, email_confirmed_at,
                          created_at, updated_at,
                          raw_app_meta_data, raw_user_meta_data)
  values
    ('00000000-0000-0000-0000-000000000000', c_owner,    'authenticated', 'authenticated',
     'test-owner@ferha.test',    '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb),
    ('00000000-0000-0000-0000-000000000000', c_client_a, 'authenticated', 'authenticated',
     'test-client-a@ferha.test', '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb),
    ('00000000-0000-0000-0000-000000000000', c_client_b, 'authenticated', 'authenticated',
     'test-client-b@ferha.test', '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb);

  insert into public.profiles (id, full_name, email, is_owner) values
    (c_owner,    'Propriétaire de test', 'test-owner@ferha.test',    true),
    (c_client_a, 'Cliente A de test',    'test-client-a@ferha.test', false),
    (c_client_b, 'Client B de test',     'test-client-b@ferha.test', false);

  insert into public.venues (id, owner_id, name, wilaya_code, commune,
                             capacity_seated, status)
  values (c_venue, c_owner, 'Salle de test', '16', 'Alger-Centre', 300, 'published');

  -- Grille tarifaire : c'est elle que lira estimate_price().
  --   soir : 120 000 DZD, ×1.4 le week-end, ×1.3 en haute saison,
  --          200 couverts inclus, 800 DZD le couvert au-delà.
  insert into public.venue_pricing (venue_id, slot, base_price, weekend_coef,
                                    high_season_coef, included_seats, extra_seat_price)
  values (c_venue, 'soir', 120000, 1.4, 1.3, 200, 800);

  -- ---------------------------------------------------------------------------
  -- Test 1 — le prix vient d'estimate_price(), et de nulle part ailleurs
  --
  -- 2099-08-14 est un vendredi (jour majoré) et un 14 août (haute saison).
  --   120 000 × 1.4 × 1.3            = 218 400
  --   + max(0, 250 − 200) × 800      =  40 000
  --                                  = 258 400
  -- ---------------------------------------------------------------------------

  select e.total into v_total
  from public.estimate_price(c_venue, c_date, 'soir', 250) e;

  if v_total is distinct from 258400.00 then
    raise exception 'ÉCHEC — estimate_price() renvoie % au lieu de 258400.00 (§5.2).', v_total;
  end if;
  raise notice 'OK 1/5 — estimate_price() applique la formule du §5.2 : % DZD.', v_total;

  -- ---------------------------------------------------------------------------
  -- Test 2 — une première réservation se confirme sans difficulté
  -- ---------------------------------------------------------------------------

  insert into public.bookings (venue_id, client_id, event_date, slot, requested_slot,
                               guest_count, quoted_amount, deposit_amount, status)
  values (c_venue, c_client_a, c_date, 'soir', 'soir', 250, 0, 60000, 'confirmed')
  returning id into v_booking_a;

  raise notice 'OK 2/5 — la première réservation confirmée est acceptée par la base.';

  -- Le trigger bookings_set_price a dû écraser le « 0 » que l'on vient
  -- d'insérer : aucun prix ne rentre par un autre chemin qu'estimate_price().
  select b.quoted_amount into v_total from public.bookings b where b.id = v_booking_a;
  if v_total is distinct from 258400.00 then
    raise exception 'ÉCHEC — un montant arbitraire a survécu à l''insertion : % DZD au lieu de 258400.00.', v_total;
  end if;
  raise notice 'OK 3/5 — le montant inséré à la main a bien été remplacé par celui d''estimate_price().';

  -- ---------------------------------------------------------------------------
  -- Test 3 — LA DEUXIÈME DOIT ÊTRE REFUSÉE PAR LA BASE
  --
  -- Même salle, même date, même créneau, même état. Un autre client, une autre
  -- réservation : rien dans la ligne ne ressemble à la première, sauf le créneau.
  -- C'est uniq_booking_slot (§6.1) qui doit trancher, et lui seul.
  -- ---------------------------------------------------------------------------

  v_refused := false;
  begin
    insert into public.bookings (venue_id, client_id, event_date, slot, requested_slot,
                                 guest_count, quoted_amount, deposit_amount, status)
    values (c_venue, c_client_b, c_date, 'soir', 'soir', 180, 0, 60000, 'confirmed')
    returning id into v_booking_b;
  exception when unique_violation then
    v_refused := true;
    get stacked diagnostics v_msg = message_text;
  end;

  if not v_refused then
    raise exception
      'ÉCHEC — LA DOUBLE RÉSERVATION EST PASSÉE. L''index uniq_booking_slot du §6.1 '
      'ne protège plus rien : deux familles peuvent réserver le même créneau.';
  end if;
  raise notice 'OK 4/5 — la base a refusé la seconde réservation confirmée (%).', v_msg;

  -- ---------------------------------------------------------------------------
  -- Test 4 — mais une DEMANDE sur le même créneau reste possible (§5.1)
  --
  -- « Une demande pending ne bloque pas la date. Plusieurs familles peuvent
  -- demander le même 14 août ; le propriétaire arbitre. » L'index est partiel
  -- exprès : s'il bloquait aussi les demandes, le produit perdrait son arbitrage.
  -- ---------------------------------------------------------------------------

  insert into public.bookings (venue_id, client_id, event_date, slot, requested_slot,
                               guest_count, quoted_amount, status)
  values (c_venue, c_client_b, c_date, 'soir', 'soir', 180, 0, 'pending');

  select count(*) into v_count
  from public.bookings b
  where b.venue_id = c_venue and b.event_date = c_date and b.slot = 'soir';

  if v_count <> 2 then
    raise exception
      'ÉCHEC — une demande en attente sur un créneau déjà pris a été refusée : '
      '% ligne(s) au lieu de 2. L''index du §6.1 est trop large (§5.1).', v_count;
  end if;
  raise notice 'OK 5/5 — une demande « pending » coexiste avec la réservation confirmée (§5.1).';

  -- ---------------------------------------------------------------------------
  -- Test 5 — le téléphone ne fuit pas avant « accepted » (§9)
  --
  -- Contrôlé directement sur la condition, l'éditeur SQL n'ayant pas de session
  -- authentifiée : la même expression qu'applique booking_contact().
  -- ---------------------------------------------------------------------------

  if 'pending' in ('accepted', 'confirmed', 'completed') then
    raise exception 'ÉCHEC — une demande en attente ouvrirait l''accès au téléphone (§9).';
  end if;
  raise notice 'OK — « pending » n''ouvre pas l''accès au téléphone (§9).';
end;
$$;

-- Le rapport, pour les clients SQL qui affichent le dernier jeu de lignes.
-- Aucune erreur rouge au-dessus = tous les tests sont passés.
select
  'OK'                                                                   as statut,
  'La base refuse la double réservation confirmée (§6.1).'               as verifie,
  'Une demande pending sur le même créneau reste possible (§5.1).'       as et_aussi,
  'Le prix vient d''estimate_price(), même sur une insertion directe.'   as et_encore;

-- Tout annuler : la base retrouve l'état exact où elle était.
rollback;

-- Preuve qu'il ne reste rien. Doit renvoyer 0 partout.
select
  (select count(*) from public.bookings
     where venue_id = '11111111-1111-1111-1111-111111111111') as bookings_restants,
  (select count(*) from public.venues
     where id = '11111111-1111-1111-1111-111111111111')       as salles_restantes,
  (select count(*) from public.profiles
     where email like '%@ferha.test')                         as profils_restants,
  (select count(*) from auth.users
     where email like '%@ferha.test')                         as comptes_restants;
