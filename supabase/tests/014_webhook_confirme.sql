-- =============================================================================
-- Ferha — tests/014_webhook_confirme.sql
--
-- CE QU'ON VÉRIFIE : que confirmer_paiement_chargily() (025) fait ce qu'il faut
-- de chacune des neuf situations qu'un webhook peut lui apporter — et qu'elle
-- ne plante sur aucune.
--
-- POURQUOI CE FICHIER EXISTE À CÔTÉ DU BAC À SABLE. Le fichier 013 teste la
-- CHAÎNE ENTIÈRE : signature, Edge Function, base. Il est irremplaçable, et il
-- demande la clé secrète, une exécution manuelle et un nettoyage. Celui-ci teste
-- la seule partie qui DÉCIDE, en une transaction annulée à la fin — donc
-- rejouable autant qu'on veut, sans clé et sans laisser de trace.
--
-- LES DEUX CAS QUI FINISSENT MAL SONT LES TESTS 4 ET 7, et ce sont eux qui
-- justifient tout ce fichier :
--
--   * l'option a expiré pendant que le paiement voyageait. La date est repartie
--     à la vente, et le client a payé quand même.
--   * quelqu'un d'autre a confirmé le même créneau entre-temps. C'est l'index
--     uniq_booking_slot (§6.1) qui tranche, et il tranche en levant.
--
-- Dans les deux cas, l'argent est arrivé et la date n'est pas prise. La règle
-- est la même : on encaisse dans les livres, on NE confirme pas, on marque
-- « à rembourser », et on prévient les deux parties ET l'administration. Aucun
-- remboursement automatique — un programme qui rembourserait tout seul se
-- tromperait un jour sur une situation qu'il est le premier à découvrir.
--
-- LE TEST 7c EST LE PLUS FACILE À OUBLIER : Nadia, dont la date vient d'être
-- perdue, ne doit recevoir AUCUNE notification « réservation confirmée ». C'est
-- ce que garantit le sous-bloc d'exception de la fonction — une exception y
-- annule aussi les notifications que confirm_booking() venait de déposer.
--
-- LE TEST 8 N'ÉTAIT PAS DEMANDÉ, et il est arrivé avec les espèces : le client
-- verse en main propre, le propriétaire confirme, et la page Chargily qu'il
-- avait ouverte la veille aboutit quand même. Il a payé deux fois. Sans ce
-- garde-fou, le second paiement écraserait silencieusement le premier.
--
-- COMMENT LE LANCER : coller le fichier entier dans l'éditeur SQL de Supabase.
-- La dernière instruction est ROLLBACK : un « Success. No rows returned » sans
-- erreur rouge veut dire que tout est passé.
--
-- CE QU'IL LAISSE : rien.
--
-- Prérequis : migrations 001 à 025 appliquées.
-- =============================================================================

begin;

do $$
declare
  c_venue constant uuid := 'c0000014-0000-4000-a000-000000000001';
  c_owner constant uuid := 'c0000014-0000-4000-a000-000000000002';
  c_amina constant uuid := 'c0000014-0000-4000-a000-000000000003';
  c_nadia constant uuid := 'c0000014-0000-4000-a000-000000000004';
  c_admin constant uuid := 'c0000014-0000-4000-a000-000000000009';

  v_paid uuid; v_mont uuid; v_exp uuid; v_ech uuid;
  v_a    uuid; v_b    uuid; v_cash uuid;

  v_r     text;
  v_p     public.payments;
  v_st    text;
  v_n     integer;
  v_suite text;
begin
  -- ---------------------------------------------------------------------------
  -- Le décor : une salle, deux clientes, et un compte ADMINISTRATEUR.
  --
  -- Le compte administrateur n'est pas décoratif : c'est lui qui reçoit les
  -- alertes d'anomalie, et sans lui les tests 3d et 4c ne prouveraient rien.
  -- ---------------------------------------------------------------------------
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
  select '00000000-0000-0000-0000-000000000000', u, 'authenticated', 'authenticated',
         't14.' || u || '@ferha.test', '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb
  from unnest(array[c_owner, c_amina, c_nadia, c_admin]) u;

  insert into public.profiles (id, full_name, email, is_owner, is_admin) values
    (c_owner, 'Karim Propriétaire', 't14.owner@ferha.test', true,  false),
    (c_amina, 'Amina Haddad',       't14.amina@ferha.test', false, false),
    (c_nadia, 'Nadia Cherif',       't14.nadia@ferha.test', false, false),
    (c_admin, 'Administration',     't14.admin@ferha.test', false, true)
  on conflict (id) do update
    set is_admin = excluded.is_admin, is_owner = excluded.is_owner;

  insert into public.venues (id, owner_id, name, wilaya_code, commune,
                             capacity_seated, status)
  values (c_venue, c_owner, 'Salle de test 014', '31', 'Oran', 400, 'published');

  insert into public.venue_pricing (venue_id, slot, base_price, weekend_coef,
                                    high_season_coef, included_seats, extra_seat_price)
  values (c_venue, 'soir',    200000, 1.30, 1.20, 200, 800),
         (c_venue, 'midi',    100000, 1.30, 1.20, 200, 800),
         (c_venue, 'journee', 280000, 1.30, 1.20, 200, 800);

  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_amina, 'role', 'authenticated')::text, true);
  select b.id into v_paid from public.request_booking(c_venue, date '2099-11-07', 'soir', 250, '0770112233') b limit 1;
  select b.id into v_mont from public.request_booking(c_venue, date '2099-11-14', 'soir', 250, '0770112233') b limit 1;
  select b.id into v_exp  from public.request_booking(c_venue, date '2099-11-21', 'soir', 250, '0770112233') b limit 1;
  select b.id into v_ech  from public.request_booking(c_venue, date '2099-11-28', 'soir', 250, '0770112233') b limit 1;
  select b.id into v_a    from public.request_booking(c_venue, date '2099-12-05', 'soir', 250, '0770112233') b limit 1;
  select b.id into v_cash from public.request_booking(c_venue, date '2099-12-12', 'soir', 250, '0770112233') b limit 1;

  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_nadia, 'role', 'authenticated')::text, true);
  select b.id into v_b from public.request_booking(c_venue, date '2099-12-05', 'soir', 200, '0770998877') b limit 1;

  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_owner, 'role', 'authenticated')::text, true);
  perform public.accepter_demande(v_paid);
  perform public.accepter_demande(v_mont);
  perform public.accepter_demande(v_exp);
  perform public.accepter_demande(v_ech);
  perform public.accepter_demande(v_cash);

  -- LES DEUX CONCURRENTES DU 5 DÉCEMBRE SONT ACCEPTÉES DE FORCE. accepter_demande()
  -- refuserait la seconde depuis 023 — et c'est très bien ainsi. Mais l'état
  -- qu'on veut reproduire existe quand même : deux options ont pu naître avant
  -- 023, ou naître d'une course que la base n'a pas vue. Le webhook doit s'en
  -- sortir, et c'est ce que vérifie le test 7.
  update public.bookings
     set status = 'accepted', accepted_at = now(),
         option_expires_at = now() + interval '70 hours', deposit_amount = 50000
   where id in (v_a, v_b);

  -- Un acompte rond : les montants de ce fichier se lisent sans calcul.
  update public.bookings set deposit_amount = 50000
   where id in (v_paid, v_mont, v_exp, v_ech, v_cash);

  perform public.enregistrer_checkout(v_paid, 'c_paid',       'cib');
  perform public.enregistrer_checkout(v_mont, 'c_mont',       'cib');
  perform public.enregistrer_checkout(v_exp,  'c_exp',        'cib');
  perform public.enregistrer_checkout(v_ech,  'c_ech',        'edahabia');
  perform public.enregistrer_checkout(v_b,    'c_concurrent', 'cib');
  perform public.enregistrer_checkout(v_cash, 'c_double',     'cib');

  -- L'option meurt APRÈS l'ouverture de sa page : c'est le vrai ordre des
  -- choses, et enregistrer_checkout() refuserait une option déjà morte.
  update public.bookings set option_expires_at = now() - interval '2 hours'
   where id = v_exp;

  -- ===========================================================================
  -- Test 1 — LE CAS NORMAL : la date est prise
  -- ===========================================================================
  v_r := public.confirmer_paiement_chargily('c_paid', 'checkout.paid', 50000,
                                            '{"type":"checkout.paid"}'::jsonb);
  if v_r <> 'confirme' then
    raise exception 'ÉCHEC 1 — rend « % », attendu « confirme ».', v_r;
  end if;

  select b.status into v_st from public.bookings b where b.id = v_paid;
  if v_st <> 'confirmed' then
    raise exception 'ÉCHEC 1b — la réservation est « % » alors que l''acompte '
      'est encaissé.', v_st;
  end if;

  select p.* into v_p from public.payments p where p.checkout_id = 'c_paid';
  if v_p.status <> 'paid' or v_p.anomalie is not null then
    raise exception 'ÉCHEC 1c — le paiement est « % » / anomalie « % ».',
      v_p.status, coalesce(v_p.anomalie, '(aucune)');
  end if;

  if v_p.raw_webhook is null then
    raise exception 'ÉCHEC 1d — raw_webhook est vide. Le §6 le veut conservé '
      'pour le rapprochement comptable (§4.4, ADM-03).';
  end if;

  select count(*) into v_n from public.notifications n
   where n.type = 'booking_confirmed' and n.user_id in (c_owner, c_amina);
  if v_n <> 2 then
    raise exception 'ÉCHEC 1e — % notification(s), attendu 2 — une par partie.', v_n;
  end if;

  raise notice 'OK 1 — paiement reçu : la date est prise, les deux parties prévenues.';

  -- ===========================================================================
  -- Test 2 — LE MÊME ÉVÉNEMENT, REJOUÉ
  --
  -- Chargily renvoie un webhook qu'il croit non acquitté. Rien ne doit bouger —
  -- ni la réservation, ni une seconde notification, ni le raw_webhook, qui doit
  -- rester celui qui a DÉCIDÉ.
  -- ===========================================================================
  v_r := public.confirmer_paiement_chargily('c_paid', 'checkout.paid', 50000,
                                            '{"rejeu":true}'::jsonb);
  if v_r <> 'deja_traite' then
    raise exception 'ÉCHEC 2 — rend « % », attendu « deja_traite ».', v_r;
  end if;

  select count(*) into v_n from public.notifications n
   where n.type = 'booking_confirmed' and n.user_id in (c_owner, c_amina);
  if v_n <> 2 then
    raise exception 'ÉCHEC 2b — % notification(s) après rejeu, attendu 2. '
      'La cliente serait prévenue deux fois pour un seul paiement.', v_n;
  end if;

  select p.raw_webhook ->> 'rejeu' into v_st
    from public.payments p where p.checkout_id = 'c_paid';
  if v_st is not null then
    raise exception 'ÉCHEC 2c — le rejeu a écrasé raw_webhook. On garde celui '
      'du premier passage : c''est lui qui a décidé.';
  end if;

  raise notice 'OK 2 — rejeu : « deja_traite », et rien ne bouge.';

  -- ===========================================================================
  -- Test 3 — UN MONTANT QUI N'EST PAS LE NÔTRE
  --
  -- Rien n'est confirmé, la ligne est marquée à examiner, l'administration est
  -- prévenue — et payments.amount n'est PAS écrasé : il dit ce qu'on attendait,
  -- raw_webhook dit ce qui est arrivé.
  -- ===========================================================================
  v_r := public.confirmer_paiement_chargily('c_mont', 'checkout.paid', 49000,
                                            '{"t":"m"}'::jsonb);
  if v_r <> 'montant_different' then
    raise exception 'ÉCHEC 3 — rend « % », attendu « montant_different ».', v_r;
  end if;

  select b.status into v_st from public.bookings b where b.id = v_mont;
  if v_st <> 'accepted' then
    raise exception 'ÉCHEC 3b — LA RÉSERVATION A ÉTÉ CONFIRMÉE POUR UN MONTANT '
      'QUI N''EST PAS LE NÔTRE (« % »).', v_st;
  end if;

  select p.* into v_p from public.payments p where p.checkout_id = 'c_mont';
  if v_p.amount <> 50000 then
    raise exception 'ÉCHEC 3c — payments.amount a été écrasé (%). Il doit dire '
      'ce qu''on ATTENDAIT.', v_p.amount;
  end if;

  select count(*) into v_n from public.notifications n
   where n.type = 'payment_anomaly' and n.user_id = c_admin;
  if v_n <> 1 then
    raise exception 'ÉCHEC 3d — l''administration a été prévenue % fois, attendu 1.', v_n;
  end if;

  select x.suite into v_suite from public.paiements_a_examiner x where x.checkout_id = 'c_mont';
  if v_suite <> 'a_examiner' then
    raise exception 'ÉCHEC 3e — la vue dit « % », attendu « a_examiner ».',
      coalesce(v_suite, '(rien)');
  end if;

  raise notice 'OK 3 — montant différent : rien confirmé, à examiner, administration prévenue.';

  -- ===========================================================================
  -- Test 4 — L'OPTION A EXPIRÉ AVANT LE PAIEMENT
  --
  -- Le premier des deux cas qui finissent mal. Le statut dit encore
  -- « accepted » — le cron passe au quart d'heure — et confirm_booking() (004)
  -- ne regarde QUE ce statut : elle confirmerait une date repartie à la vente.
  -- C'est tient_la_date() (023) qui doit trancher, et elle est appelée AVANT.
  -- ===========================================================================
  v_r := public.confirmer_paiement_chargily('c_exp', 'checkout.paid', 50000,
                                            '{"t":"e"}'::jsonb);
  if v_r <> 'option_expiree' then
    raise exception 'ÉCHEC 4 — rend « % », attendu « option_expiree ».', v_r;
  end if;

  select b.status into v_st from public.bookings b where b.id = v_exp;
  if v_st <> 'accepted' then
    raise exception 'ÉCHEC 4b — UNE OPTION ÉCHUE A ÉTÉ CONFIRMÉE (« % »). '
      'Deux familles peuvent se retrouver au même mariage.', v_st;
  end if;

  select count(*) into v_n from public.notifications n
   where n.type = 'payment_to_refund' and n.user_id in (c_amina, c_owner, c_admin);
  if v_n <> 3 then
    raise exception 'ÉCHEC 4c — % notification(s), attendu 3 : la cliente, le '
      'propriétaire et l''administration.', v_n;
  end if;

  select x.suite into v_suite from public.paiements_a_examiner x where x.checkout_id = 'c_exp';
  if v_suite <> 'a_rembourser' then
    raise exception 'ÉCHEC 4d — la vue dit « % », attendu « a_rembourser ».',
      coalesce(v_suite, '(rien)');
  end if;

  raise notice 'OK 4 — option expirée : encaissé, non confirmé, à rembourser, trois prévenus.';

  -- ===========================================================================
  -- Test 5 — CARTE REFUSÉE : L'OPTION SURVIT
  --
  -- C'est le point. Une carte refusée ne retire pas les 72 h : le client peut
  -- réessayer, ou payer en espèces. Et un « canceled » derrière un « failed »
  -- ne doit pas renotifier.
  -- ===========================================================================
  v_r := public.confirmer_paiement_chargily('c_ech', 'checkout.failed', 50000,
                                            '{"t":"f"}'::jsonb);
  if v_r <> 'echec' then
    raise exception 'ÉCHEC 5 — rend « % », attendu « echec ».', v_r;
  end if;

  select b.status into v_st from public.bookings b where b.id = v_ech;
  if v_st <> 'accepted' then
    raise exception 'ÉCHEC 5b — une carte refusée a fait passer la réservation '
      'à « % ». L''option doit survivre.', v_st;
  end if;

  select p.status into v_st from public.payments p where p.checkout_id = 'c_ech';
  if v_st <> 'failed' then
    raise exception 'ÉCHEC 5c — le paiement est « % ».', v_st;
  end if;

  select count(*) into v_n from public.notifications n
   where n.type = 'payment_failed' and n.user_id = c_amina;
  if v_n <> 1 then
    raise exception 'ÉCHEC 5d — la cliente a été prévenue % fois.', v_n;
  end if;

  v_r := public.confirmer_paiement_chargily('c_ech', 'checkout.canceled', 50000,
                                            '{"t":"c"}'::jsonb);
  if v_r <> 'deja_traite' then
    raise exception 'ÉCHEC 5e — un « canceled » derrière un « failed » rend '
      '« % », attendu « deja_traite ».', v_r;
  end if;

  raise notice 'OK 5 — carte refusée : l''option survit, et l''idempotence tient.';

  -- ===========================================================================
  -- Test 6 — UN CHECKOUT QUE NOUS N'AVONS PAS OUVERT
  --
  -- Ne doit PAS lever : une exception ferait renvoyer l'événement par Chargily,
  -- indéfiniment, pour un paiement qui ne nous concerne pas.
  -- ===========================================================================
  v_r := public.confirmer_paiement_chargily('c_jamais_vu', 'checkout.paid', 50000,
                                            '{}'::jsonb);
  if v_r <> 'inconnu' then
    raise exception 'ÉCHEC 6 — rend « % », attendu « inconnu ».', v_r;
  end if;
  raise notice 'OK 6 — checkout inconnu : « inconnu », sans lever.';

  -- ===========================================================================
  -- Test 7 — LE CRÉNEAU A ÉTÉ PRIS PAR QUELQU'UN D'AUTRE
  --
  -- Le second cas qui finit mal, et le plus brutal : Nadia a payé, et Amina a
  -- la salle. L'index uniq_booking_slot (§6.1) lève, et le sous-bloc
  -- d'exception doit rattraper la levée SANS laisser derrière lui les
  -- notifications que confirm_booking() venait de déposer — c'est le 7c.
  -- ===========================================================================
  perform public.confirm_booking(v_a);

  v_r := public.confirmer_paiement_chargily('c_concurrent', 'checkout.paid', 50000,
                                            '{"t":"x"}'::jsonb);
  if v_r <> 'creneau_pris' then
    raise exception 'ÉCHEC 7 — rend « % », attendu « creneau_pris ».', v_r;
  end if;

  select b.status into v_st from public.bookings b where b.id = v_b;
  if v_st <> 'accepted' then
    raise exception 'ÉCHEC 7b — la réservation de Nadia est « % ».', v_st;
  end if;

  select count(*) into v_n from public.notifications n
   where n.type = 'booking_confirmed' and n.user_id = c_nadia;
  if v_n <> 0 then
    raise exception 'ÉCHEC 7c — NADIA A REÇU % NOTIFICATION(S) « RÉSERVATION '
      'CONFIRMÉE » ALORS QUE SA DATE EST PERDUE. Le sous-bloc d''exception n''a '
      'pas annulé ce que confirm_booking() avait déposé.', v_n;
  end if;

  select x.suite into v_suite from public.paiements_a_examiner x
   where x.checkout_id = 'c_concurrent';
  if v_suite <> 'a_rembourser' then
    raise exception 'ÉCHEC 7d — la vue dit « % », attendu « a_rembourser ».',
      coalesce(v_suite, '(rien)');
  end if;

  raise notice 'OK 7 — créneau pris : à rembourser, et aucune fausse confirmation.';

  -- ===========================================================================
  -- Test 8 — DÉJÀ PAYÉ EN ESPÈCES, ET LA CARTE ABOUTIT QUAND MÊME
  --
  -- Ce cas est né avec les espèces : le client verse en main propre, le
  -- propriétaire confirme, et la page Chargily ouverte la veille aboutit. Il a
  -- payé deux fois. Sans ce garde-fou, le second paiement passerait pour le
  -- premier et personne ne verrait rien.
  -- ===========================================================================
  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_amina, 'role', 'authenticated')::text, true);
  perform public.payer_en_especes(v_cash);

  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_owner, 'role', 'authenticated')::text, true);
  perform public.confirmer_encaissement_especes(v_cash);

  perform set_config('request.jwt.claims', '', true);

  v_r := public.confirmer_paiement_chargily('c_double', 'checkout.paid', 50000,
                                            '{"t":"d"}'::jsonb);
  if v_r <> 'deja_paye' then
    raise exception 'ÉCHEC 8 — rend « % », attendu « deja_paye ». Le client a '
      'payé deux fois et personne ne le voit.', v_r;
  end if;

  select x.suite into v_suite from public.paiements_a_examiner x where x.checkout_id = 'c_double';
  if v_suite <> 'a_rembourser' then
    raise exception 'ÉCHEC 8b — la vue dit « % », attendu « a_rembourser ».',
      coalesce(v_suite, '(rien)');
  end if;

  raise notice 'OK 8 — double paiement vu, et marqué à rembourser.';
  raise notice 'Les huit situations du webhook sont traitées, et aucune n''a levé.';
end $$;

rollback;
