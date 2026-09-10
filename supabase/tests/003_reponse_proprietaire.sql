-- =============================================================================
-- Ferha — tests/003_reponse_proprietaire.sql
--
-- CE QU'ON VÉRIFIE : qu'un propriétaire ne peut répondre qu'à SES demandes, et
-- qu'accepter un créneau déjà vendu échoue proprement.
--
-- Le premier point est le seul qui compte vraiment. `accepter_demande()` et
-- `refuser_demande()` sont SECURITY DEFINER : elles s'exécutent avec les droits
-- du propriétaire de la fonction, RLS comprise. Si leur garde-fou tombait,
-- n'importe quel compte connecté pourrait accepter la demande de n'importe qui
-- — et l'application Flutter, qui ne cache que des boutons, n'y verrait rien.
-- Ce fichier est ce qui empêche que cela passe inaperçu.
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
-- ON VÉRIFIE LE HINT, PAS LE MESSAGE. C'est le hint que lit l'application
-- (lib/features/owner/owner_messages.dart), et c'est lui le contrat ; le
-- message français, lui, peut être réécrit demain.
--
-- CE QU'IL LAISSE : rien. Tout est fait dans une transaction annulée à la fin.
--
-- Prérequis : migrations 001 à 015 appliquées.
-- =============================================================================

begin;

do $$
declare
  c_venue    constant uuid := 'c0000003-0000-4000-a000-000000000001';
  c_owner    constant uuid := 'c0000003-0000-4000-a000-000000000002';
  c_intrus   constant uuid := 'c0000003-0000-4000-a000-000000000003';
  c_client   constant uuid := 'c0000003-0000-4000-a000-000000000004';
  c_autre    constant uuid := 'c0000003-0000-4000-a000-000000000005';

  -- Loin dans le futur : aucun risque de croiser une donnée réelle.
  c_date     constant date := date '2099-08-14';
  c_date_2   constant date := date '2099-09-04';
  c_date_3   constant date := date '2099-09-11';
  c_date_4   constant date := date '2099-09-18';

  v_demande    uuid;
  v_journee    uuid;
  v_sqlstate   text;
  v_hint       text;
  v_statut     text;
  v_motif      text;
  v_option     timestamptz;
  v_acompte    numeric;
  v_devis      numeric;
  v_lignes     integer;
  v_notifs     integer;
begin
  -- ---------------------------------------------------------------------------
  -- Le décor : une salle, son propriétaire, un intrus, deux clientes
  -- ---------------------------------------------------------------------------
  insert into auth.users (instance_id, id, aud, role, email,
                          encrypted_password, email_confirmed_at,
                          created_at, updated_at,
                          raw_app_meta_data, raw_user_meta_data)
  values
    ('00000000-0000-0000-0000-000000000000', c_owner,  'authenticated', 'authenticated',
     'test.owner.003@ferha.test',  '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb),
    ('00000000-0000-0000-0000-000000000000', c_intrus, 'authenticated', 'authenticated',
     'test.intrus.003@ferha.test', '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb),
    ('00000000-0000-0000-0000-000000000000', c_client, 'authenticated', 'authenticated',
     'test.client.003@ferha.test', '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb),
    ('00000000-0000-0000-0000-000000000000', c_autre,  'authenticated', 'authenticated',
     'test.autre.003@ferha.test',  '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb);

  insert into public.profiles (id, full_name, email, is_owner) values
    (c_owner,  'Karim Propriétaire', 'test.owner.003@ferha.test',  true),
    (c_intrus, 'Intrus Malveillant', 'test.intrus.003@ferha.test', true),
    (c_client, 'Amina Cliente',      'test.client.003@ferha.test', false),
    (c_autre,  'Yacine Client',      'test.autre.003@ferha.test',  false)
  on conflict (id) do nothing;   -- le déclencheur de 007 a pu les créer

  insert into public.venues (id, owner_id, name, wilaya_code, commune,
                             capacity_seated, status)
  values (c_venue, c_owner, 'Salle de test 003', '31', 'Oran', 400, 'published');

  insert into public.venue_pricing (venue_id, slot, base_price, weekend_coef,
                                    high_season_coef, included_seats, extra_seat_price)
  values
    (c_venue, 'midi',    100000, 1.30, 1.20, 200, 800),
    (c_venue, 'soir',    200000, 1.30, 1.20, 200, 800),
    (c_venue, 'journee', 280000, 1.30, 1.20, 200, 800);

  -- La demande sur laquelle porteront les tests 1 à 4. Le trigger
  -- bookings_set_price écrira son montant : on ne l'invente pas.
  insert into public.bookings (venue_id, client_id, event_date, slot, requested_slot,
                               guest_count, quoted_amount, status)
  values (c_venue, c_client, c_date, 'soir', 'soir', 250, 0, 'pending')
  returning id into v_demande;

  select b.quoted_amount into v_devis from public.bookings b where b.id = v_demande;

  -- ---------------------------------------------------------------------------
  -- Test 1 — un propriétaire qui n'est pas le bon ne peut RIEN
  --
  -- L'intrus est lui aussi propriétaire (is_owner), et connecté. Ce qui doit
  -- l'arrêter n'est pas son rôle, c'est que la salle n'est pas la sienne.
  -- ---------------------------------------------------------------------------
  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_intrus, 'role', 'authenticated')::text,
                     true);

  begin
    perform public.accepter_demande(v_demande);
    raise exception 'ÉCHEC 1 — un inconnu a accepté la demande d''un autre propriétaire.';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE011' then
      raise exception 'ÉCHEC 1 — refus attendu FE011, reçu hint=% sqlstate=%.',
        coalesce(v_hint, '(vide)'), v_sqlstate;
    end if;
  end;

  begin
    perform public.refuser_demande(v_demande, 'Je refuse la demande de quelqu''un d''autre');
    raise exception 'ÉCHEC 1 — un inconnu a refusé la demande d''un autre propriétaire.';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE011' then
      raise exception 'ÉCHEC 1 — refus attendu FE011, reçu hint=% sqlstate=%.',
        coalesce(v_hint, '(vide)'), v_sqlstate;
    end if;
  end;

  -- Et la demande n'a pas bougé d'un pouce.
  select b.status into v_statut from public.bookings b where b.id = v_demande;
  if v_statut is distinct from 'pending' then
    raise exception 'ÉCHEC 1 — la demande est passée en « % » malgré le refus.', v_statut;
  end if;

  if (select count(*) from public.notifications
       where payload->>'booking_id' = v_demande::text) <> 0 then
    raise exception 'ÉCHEC 1 — une notification est partie alors que rien n''a été décidé.';
  end if;

  raise notice 'OK 1 — un propriétaire étranger est refusé (FE011, sqlstate %), et rien ne bouge.', v_sqlstate;

  -- ---------------------------------------------------------------------------
  -- Test 2 — sans session, rien non plus
  --
  -- Le cas n'est pas théorique : la clé anon suffit à appeler une fonction
  -- PostgREST, et c'est le SQL qui doit dire non.
  -- ---------------------------------------------------------------------------
  -- La chaîne vide plutôt que NULL : c'est ainsi que se présente une requête
  -- anonyme, et c'est ce que `auth.uid()` sait lire comme « personne ».
  perform set_config('request.jwt.claims', '', true);

  begin
    perform public.accepter_demande(v_demande);
    raise exception 'ÉCHEC 2 — une acceptation est passée sans session.';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE010' then
      raise exception 'ÉCHEC 2 — refus attendu FE010, reçu hint=% sqlstate=%.',
        coalesce(v_hint, '(vide)'), v_sqlstate;
    end if;
  end;

  raise notice 'OK 2 — sans session : FE010, sqlstate % (donc HTTP 401).', v_sqlstate;

  -- ---------------------------------------------------------------------------
  -- Test 3 — le propriétaire accepte : option de 72 h, acompte, notification
  -- ---------------------------------------------------------------------------
  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_owner, 'role', 'authenticated')::text,
                     true);

  perform public.accepter_demande(v_demande);

  select b.status, b.option_expires_at, b.deposit_amount
    into v_statut, v_option, v_acompte
  from public.bookings b where b.id = v_demande;

  if v_statut is distinct from 'accepted' then
    raise exception 'ÉCHEC 3 — la demande est en « % » au lieu de « accepted ».', v_statut;
  end if;

  -- Le §5.1 : 72 h, pas 48, pas 7 jours. On tolère la minute que met le test.
  if v_option is null
     or v_option < now() + interval '71 hours 55 minutes'
     or v_option > now() + interval '72 hours 5 minutes' then
    raise exception 'ÉCHEC 3 — l''option n''est pas à 72 h (§5.1) : %.', v_option;
  end if;

  -- L'acompte vient de deposit_rate(), et le devis d'estimate_price(). Aucune
  -- des deux valeurs n'est écrite dans ce test : on les relit.
  if v_acompte is distinct from round(v_devis * public.deposit_rate(), 2) then
    raise exception 'ÉCHEC 3 — acompte de % au lieu de % (% × %).',
      v_acompte, round(v_devis * public.deposit_rate(), 2), v_devis, public.deposit_rate();
  end if;

  select count(*) into v_notifs from public.notifications
   where user_id = c_client
     and type = 'booking_answered'
     and payload->>'booking_id' = v_demande::text
     and payload->>'status' = 'accepted';
  if v_notifs <> 1 then
    raise exception 'ÉCHEC 3 — % notification(s) pour la cliente au lieu d''une.', v_notifs;
  end if;

  raise notice 'OK 3 — acceptée : option à 72 h, acompte % DZD (% %% de %), une notification.',
    v_acompte, public.deposit_rate() * 100, v_devis;

  -- ---------------------------------------------------------------------------
  -- Test 4 — une demande déjà tranchée ne se répond pas deux fois
  --
  -- Le cas courant n'est pas une attaque : deux téléphones ouverts sur la même
  -- demande, ou un double appui.
  -- ---------------------------------------------------------------------------
  begin
    perform public.accepter_demande(v_demande);
    raise exception 'ÉCHEC 4 — une demande déjà acceptée a été acceptée une seconde fois.';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE012' then
      raise exception 'ÉCHEC 4 — refus attendu FE012, reçu hint=% sqlstate=%.',
        coalesce(v_hint, '(vide)'), v_sqlstate;
    end if;
  end;

  raise notice 'OK 4 — une demande tranchée est protégée (FE012, sqlstate %).', v_sqlstate;

  -- ---------------------------------------------------------------------------
  -- Test 5 — accepter un créneau vendu entre-temps échoue proprement
  --
  -- LE CAS EXACT QUE L'INDEX DU §6.1 NE COUVRE PAS. Il est PARTIEL — il ne
  -- porte que sur « confirmed » et « completed » — donc une acceptation, qui
  -- écrit « accepted », ne peut pas le déclencher. Sans le garde-fou de 015, le
  -- propriétaire poserait une option de 72 h sur une date déjà vendue, et
  -- personne ne dirait rien avant la confirmation.
  -- ---------------------------------------------------------------------------

  -- La date est vendue à quelqu'un d'autre.
  insert into public.bookings (venue_id, client_id, event_date, slot, requested_slot,
                               guest_count, quoted_amount, deposit_amount, status)
  values (c_venue, c_autre, c_date_2, 'soir', 'soir', 180, 0, 50000, 'confirmed');

  -- Et notre cliente avait demandé la même, avant.
  insert into public.bookings (venue_id, client_id, event_date, slot, requested_slot,
                               guest_count, quoted_amount, status)
  values (c_venue, c_client, c_date_2, 'soir', 'soir', 250, 0, 'pending')
  returning id into v_demande;

  begin
    perform public.accepter_demande(v_demande);
    raise exception
      'ÉCHEC 5 — UNE OPTION A ÉTÉ POSÉE SUR UN CRÉNEAU DÉJÀ VENDU. '
      'Le garde-fou de 015 est tombé, et l''index du §6.1 ne le rattrape pas : '
      'il est partiel sur confirmed/completed.';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE013' then
      raise exception 'ÉCHEC 5 — refus attendu FE013, reçu hint=% sqlstate=%.',
        coalesce(v_hint, '(vide)'), v_sqlstate;
    end if;
  end;

  select b.status into v_statut from public.bookings b where b.id = v_demande;
  if v_statut is distinct from 'pending' then
    raise exception 'ÉCHEC 5 — la demande est passée en « % » alors que l''acceptation a échoué.', v_statut;
  end if;

  raise notice 'OK 5 — créneau déjà vendu : FE013, sqlstate % (donc HTTP 409), demande intacte.', v_sqlstate;

  -- ---------------------------------------------------------------------------
  -- Test 6 — refuser, avec motif puis sans
  -- ---------------------------------------------------------------------------
  insert into public.bookings (venue_id, client_id, event_date, slot, requested_slot,
                               guest_count, quoted_amount, status)
  values (c_venue, c_client, c_date_3, 'soir', 'soir', 250, 0, 'pending')
  returning id into v_demande;

  perform public.refuser_demande(v_demande, 'La salle est en travaux cette semaine-là.');

  select b.status, b.status_reason into v_statut, v_motif
  from public.bookings b where b.id = v_demande;

  if v_statut is distinct from 'refused' then
    raise exception 'ÉCHEC 6 — la demande est en « % » au lieu de « refused ».', v_statut;
  end if;
  if v_motif is distinct from 'La salle est en travaux cette semaine-là.' then
    raise exception 'ÉCHEC 6 — le motif n''est pas arrivé au client : %.', coalesce(v_motif, '(vide)');
  end if;

  if (select count(*) from public.notifications
       where user_id = c_client and type = 'booking_answered'
         and payload->>'booking_id' = v_demande::text
         and payload->>'status' = 'refused') <> 1 then
    raise exception 'ÉCHEC 6 — le refus n''a pas notifié la cliente.';
  end if;

  -- Sans motif : le refus passe quand même. « Demandé, pas exigé. »
  insert into public.bookings (venue_id, client_id, event_date, slot, requested_slot,
                               guest_count, quoted_amount, status)
  values (c_venue, c_client, c_date_4, 'soir', 'soir', 250, 0, 'pending')
  returning id into v_demande;

  -- Des blancs ne sont pas un motif : ils doivent redevenir NULL, sans quoi
  -- l'écran du client afficherait un encart « Motif » vide.
  perform public.refuser_demande(v_demande, '   ');

  select b.status, b.status_reason into v_statut, v_motif
  from public.bookings b where b.id = v_demande;

  if v_statut is distinct from 'refused' then
    raise exception 'ÉCHEC 6 — un refus sans motif a été rejeté (statut « % »).', v_statut;
  end if;
  if v_motif is not null then
    raise exception 'ÉCHEC 6 — un motif fait de blancs a été enregistré : « % ».', v_motif;
  end if;

  raise notice 'OK 6 — refus avec motif, et sans : les deux passent, les blancs ne comptent pas.';

  -- ---------------------------------------------------------------------------
  -- Test 7 — une journée entière se répond d'un bloc
  --
  -- Deux lignes, un seul geste : accepter la moitié d'un mariage n'aurait pas
  -- de sens (§6.1).
  -- ---------------------------------------------------------------------------
  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_client, 'role', 'authenticated')::text,
                     true);

  select b.id into v_journee
  from public.request_booking(c_venue, date '2099-10-02', 'journee', 250) b
  limit 1;

  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_owner, 'role', 'authenticated')::text,
                     true);

  perform public.accepter_demande(v_journee);

  select count(*) into v_lignes
  from public.bookings b
  where b.group_id = (select g.group_id from public.bookings g where g.id = v_journee)
    and b.status = 'accepted';

  if v_lignes <> 2 then
    raise exception
      'ÉCHEC 7 — % ligne(s) acceptée(s) au lieu de 2 : une journée entière a été '
      'coupée en deux.', v_lignes;
  end if;

  raise notice 'OK 7 — une journée entière passe en « accepted » sur ses deux lignes.';

  raise notice 'Tous les tests passent. Le ROLLBACK qui suit efface tout.';
end $$;

rollback;
