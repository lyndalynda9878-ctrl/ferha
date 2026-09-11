-- =============================================================================
-- Ferha — tests/012_especes_sur_place.sql
--
-- CE QU'ON VÉRIFIE : que l'acompte en main propre prend la date aussi
-- sérieusement que Chargily — et qu'il ne la prend que pour celui qui a le
-- droit de le dire.
--
-- POURQUOI CE FICHIER EXISTE. « L'option espèces sur place est offerte dès le
-- MVP : elle sauve les utilisateurs réticents au paiement en ligne »
-- (maquettes, écran 6). C'est donc un vrai chemin vers « confirmed », pas une
-- politesse — et tout ce qui protège le chemin Chargily doit le protéger lui
-- aussi : la propriété de la salle, l'option qui court encore, l'index du §6.1,
-- et l'impossibilité de confirmer deux fois.
--
-- LE TEST 3 EST LE PLUS IMPORTANT. « Un autre compte ne peut pas confirmer un
-- encaissement » : sans lui, n'importe quel utilisateur connecté prendrait la
-- date de n'importe quelle salle en appelant une fonction. Ce n'est pas une
-- fuite de données, c'est un vol de créneau.
--
-- ANNONCER N'EST PAS PAYER (test 1). C'est la règle qui fait tenir tout le
-- reste : choisir « espèces » laisse la réservation « accepted » et l'option de
-- 72 h continue de courir. Une implémentation qui confirmerait dès le choix
-- offrirait la date à qui la demande, sans qu'un dinar ait bougé.
--
-- COMMENT LE LANCER : coller le fichier entier dans l'éditeur SQL de Supabase
-- et exécuter. Une seule fois, d'un bloc.
--
-- COMMENT LE LIRE :
--   * des « NOTICE ... OK » et aucune erreur rouge   → tout va bien ;
--   * une erreur rouge commençant par « ÉCHEC »      → une règle ne tient pas.
--   La dernière instruction est ROLLBACK : un « Success. No rows returned »
--   sans erreur rouge veut dire que tout est passé.
--
-- ON VÉRIFIE LE HINT, PAS LE MESSAGE — c'est le hint que lit l'application.
--
-- CE QU'IL LAISSE : rien. Tout est annulé à la fin.
--
-- Prérequis : migrations 001 à 025 appliquées.
-- =============================================================================

begin;

do $$
declare
  c_venue   constant uuid := 'c0000012-0000-4000-a000-000000000001';
  c_owner   constant uuid := 'c0000012-0000-4000-a000-000000000002';
  c_amina   constant uuid := 'c0000012-0000-4000-a000-000000000003';
  c_yasmine constant uuid := 'c0000012-0000-4000-a000-000000000004';
  c_karim2  constant uuid := 'c0000012-0000-4000-a000-000000000005';

  c_jour    constant date := date '2099-08-14';
  c_autre   constant date := date '2099-08-21';

  v_amina    uuid;
  v_autre    uuid;
  v_groupe   uuid;
  v_paiement public.payments;
  v_premier  uuid;
  v_hint     text;
  v_statut   text;
  v_lignes   integer;
  v_acompte  integer;
  v_notifs   integer;
begin
  -- ---------------------------------------------------------------------------
  -- Le décor : une salle, son propriétaire, une cliente, et deux intrus —
  -- une cliente qui n'a rien à voir, et un propriétaire d'une AUTRE salle.
  -- ---------------------------------------------------------------------------
  insert into auth.users (instance_id, id, aud, role, email,
                          encrypted_password, email_confirmed_at,
                          created_at, updated_at,
                          raw_app_meta_data, raw_user_meta_data)
  values
    ('00000000-0000-0000-0000-000000000000', c_owner,   'authenticated', 'authenticated',
     'test.owner.012@ferha.test',   '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb),
    ('00000000-0000-0000-0000-000000000000', c_amina,   'authenticated', 'authenticated',
     'test.amina.012@ferha.test',   '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb),
    ('00000000-0000-0000-0000-000000000000', c_yasmine, 'authenticated', 'authenticated',
     'test.yasmine.012@ferha.test', '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb),
    ('00000000-0000-0000-0000-000000000000', c_karim2,  'authenticated', 'authenticated',
     'test.karim2.012@ferha.test',  '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb);

  insert into public.profiles (id, full_name, email, is_owner) values
    (c_owner,   'Karim Propriétaire',  'test.owner.012@ferha.test',   true),
    (c_amina,   'Amina Haddad',        'test.amina.012@ferha.test',   false),
    (c_yasmine, 'Yasmine Belkacem',    'test.yasmine.012@ferha.test', false),
    (c_karim2,  'Autre propriétaire',  'test.karim2.012@ferha.test',  true)
  on conflict (id) do update
    set full_name = excluded.full_name, is_owner = excluded.is_owner;

  insert into public.venues (id, owner_id, name, wilaya_code, commune,
                             capacity_seated, status)
  values (c_venue, c_owner, 'Salle de test 012', '31', 'Oran', 400, 'published');

  insert into public.venue_pricing (venue_id, slot, base_price, weekend_coef,
                                    high_season_coef, included_seats, extra_seat_price)
  values
    (c_venue, 'midi',    100000, 1.30, 1.20, 200, 800),
    (c_venue, 'soir',    200000, 1.30, 1.20, 200, 800),
    (c_venue, 'journee', 280000, 1.30, 1.20, 200, 800);

  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_amina, 'role', 'authenticated')::text, true);
  select b.id into v_amina
  from public.request_booking(c_venue, c_jour, 'soir', 250, '0770112233') b
  order by b.slot limit 1;

  select b.id into v_autre
  from public.request_booking(c_venue, c_autre, 'soir', 200, '0770112233') b
  order by b.slot limit 1;

  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_owner, 'role', 'authenticated')::text, true);
  perform public.accepter_demande(v_amina);
  perform public.accepter_demande(v_autre);

  select b.group_id into v_groupe from public.bookings b where b.id = v_amina;
  v_acompte := public.montant_acompte(v_groupe);

  -- ===========================================================================
  -- Test 1 — ANNONCER N'EST PAS PAYER
  --
  -- La réservation reste « accepted », l'option continue de courir, et le
  -- propriétaire est prévenu. Si ce test tombait, une date se donnerait sans
  -- qu'un dinar ait bougé.
  -- ===========================================================================
  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_amina, 'role', 'authenticated')::text, true);

  v_paiement := public.payer_en_especes(v_amina);

  if v_paiement.method is distinct from 'cash'
     or v_paiement.status is distinct from 'pending' then
    raise exception 'ÉCHEC 1 — la ligne payments est « % / % », attendu « cash / pending ».',
      coalesce(v_paiement.method, '(aucune)'), coalesce(v_paiement.status, '(aucun)');
  end if;

  if v_paiement.checkout_id is not null then
    raise exception 'ÉCHEC 1b — un règlement en espèces porte un checkout_id (%). '
      'Il n''a pas de page de paiement, et l''index partiel de 004 compte '
      'là-dessus.', v_paiement.checkout_id;
  end if;

  if v_paiement.amount is distinct from v_acompte::numeric then
    raise exception 'ÉCHEC 1c — la ligne porte % alors que l''acompte dû est %. '
      'Le propriétaire compterait ses billets d''après un autre nombre que son '
      'client.', v_paiement.amount, v_acompte;
  end if;

  select b.status into v_statut from public.bookings b where b.id = v_amina;
  if v_statut is distinct from 'accepted' then
    raise exception 'ÉCHEC 1d — LA RÉSERVATION EST PASSÉE À « % » SUR UNE SIMPLE '
      'ANNONCE. Choisir « espèces » n''est pas payer : la date se donnerait à '
      'qui la demande.', v_statut;
  end if;

  select count(*) into v_notifs
  from public.notifications n
  where n.user_id = c_owner and n.type = 'cash_pending';

  if v_notifs <> 1 then
    raise exception 'ÉCHEC 1e — le propriétaire a reçu % notification(s) '
      '« cash_pending », attendu 1. Sans elle, personne ne l''attend avec '
      'les billets.', v_notifs;
  end if;

  raise notice 'OK 1 — annoncer ne confirme rien : la réservation reste accepted, '
    'l''option court, et le propriétaire est prévenu une fois.';

  -- ===========================================================================
  -- Test 2 — RAPPUYER NE POSE PAS UNE SECONDE INTENTION
  --
  -- Deux lignes « cash » en attente sur la même réservation ne veulent rien
  -- dire, et feraient deux notifications au propriétaire pour un seul client.
  -- ===========================================================================
  v_premier := v_paiement.id;
  v_paiement := public.payer_en_especes(v_amina);

  if v_paiement.id is distinct from v_premier then
    raise exception 'ÉCHEC 2 — un second appel a créé une seconde intention.';
  end if;

  select count(*) into v_lignes
  from public.payments p
  join public.bookings b on b.id = p.booking_id
  where b.group_id = v_groupe and p.method = 'cash';

  if v_lignes <> 1 then
    raise exception 'ÉCHEC 2b — % lignes « cash » pour une réservation.', v_lignes;
  end if;

  select count(*) into v_notifs
  from public.notifications n
  where n.user_id = c_owner and n.type = 'cash_pending';

  if v_notifs <> 1 then
    raise exception 'ÉCHEC 2c — le propriétaire a été prévenu % fois pour une '
      'seule intention.', v_notifs;
  end if;

  raise notice 'OK 2 — idempotente : une intention, une notification.';

  -- ===========================================================================
  -- Test 3 — UN AUTRE COMPTE NE CONFIRME PAS UN ENCAISSEMENT
  --
  -- LE TEST LE PLUS IMPORTANT DU FICHIER. confirmer_encaissement_especes() est
  -- SECURITY DEFINER : sans owns_booking() en tête, n'importe quel compte
  -- connecté prendrait la date de n'importe quelle salle. Ce n'est pas une
  -- fuite, c'est un vol de créneau.
  --
  -- Trois intrus, parce qu'ils échouent pour trois raisons différentes : la
  -- cliente elle-même (elle a payé, elle ne constate pas), une inconnue, et un
  -- propriétaire — d'une AUTRE salle, qui est le cas qu'on oublie.
  -- ===========================================================================

  -- 3a — la cliente. C'est elle qui verse, ce n'est pas elle qui constate.
  begin
    perform public.confirmer_encaissement_especes(v_amina);
    raise exception 'ÉCHEC 3a — LA CLIENTE A CONFIRMÉ SON PROPRE ENCAISSEMENT. '
      'Elle prendrait la date sans qu''un dinar ait bougé.';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE061' then raise; end if;
  end;

  -- 3b — une inconnue.
  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_yasmine, 'role', 'authenticated')::text, true);
  begin
    perform public.confirmer_encaissement_especes(v_amina);
    raise exception 'ÉCHEC 3b — UNE INCONNUE A CONFIRMÉ L''ENCAISSEMENT.';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE061' then raise; end if;
  end;

  -- 3c — un propriétaire, mais pas celui-là. Le cas qu'on oublie : « est-ce un
  -- propriétaire » et « est-ce SA salle » sont deux questions.
  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_karim2, 'role', 'authenticated')::text, true);
  begin
    perform public.confirmer_encaissement_especes(v_amina);
    raise exception 'ÉCHEC 3c — UN PROPRIÉTAIRE A CONFIRMÉ L''ENCAISSEMENT '
      'D''UNE SALLE QUI N''EST PAS LA SIENNE. La fonction vérifie « est-ce un '
      'propriétaire » au lieu de « est-ce SA salle ».';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE061' then raise; end if;
  end;

  -- 3d — et sans session du tout.
  perform set_config('request.jwt.claims', '', true);
  begin
    perform public.confirmer_encaissement_especes(v_amina);
    raise exception 'ÉCHEC 3d — un appel SANS SESSION a confirmé l''encaissement.';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE060' then raise; end if;
  end;

  -- Et la réservation n'a pas bougé d'un pouce pendant ces quatre tentatives.
  select b.status into v_statut from public.bookings b where b.id = v_amina;
  if v_statut is distinct from 'accepted' then
    raise exception 'ÉCHEC 3e — la réservation est passée à « % » alors que '
      'les quatre tentatives ont été refusées.', v_statut;
  end if;

  raise notice 'OK 3 — cliente, inconnue, propriétaire d''une autre salle, et '
    'sans session : les quatre refusés, et rien n''a bougé.';

  -- ===========================================================================
  -- Test 4 — LE PROPRIÉTAIRE, LUI, CONFIRME — ET LA DATE EST PRISE
  --
  -- Le contrôle positif du test 3. Sans lui, « permission refusée » ne
  -- distinguerait pas une fonction qui travaille d'une fonction qui refuse tout
  -- le monde.
  -- ===========================================================================
  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_owner, 'role', 'authenticated')::text, true);

  v_paiement := public.confirmer_encaissement_especes(v_amina);

  if v_paiement.status is distinct from 'paid' then
    raise exception 'ÉCHEC 4 — le paiement est resté « % ».',
      coalesce(v_paiement.status, '(aucun)');
  end if;

  -- LES DEUX lignes d'un groupe, pas une : une journée entière se confirme d'un
  -- bloc. Ici le groupe n'en a qu'une, mais on compte quand même ce qui est
  -- passé à « confirmed ».
  select count(*) into v_lignes
  from public.bookings b where b.group_id = v_groupe and b.status = 'confirmed';

  if v_lignes <> 1 then
    raise exception 'ÉCHEC 4b — % ligne(s) confirmée(s), attendu 1.', v_lignes;
  end if;

  -- Les deux parties sont prévenues, comme par Chargily : c'est confirm_booking()
  -- qui s'en charge, et c'est pour cela qu'il n'y a qu'un chemin.
  select count(*) into v_notifs
  from public.notifications n
  where n.type = 'booking_confirmed' and n.user_id in (c_owner, c_amina);

  if v_notifs <> 2 then
    raise exception 'ÉCHEC 4c — % notification(s) « booking_confirmed », '
      'attendu 2 — une par partie.', v_notifs;
  end if;

  raise notice 'OK 4 — le propriétaire confirme, la date est prise, les deux '
    'parties sont prévenues.';

  -- ===========================================================================
  -- Test 5 — UNE RÉSERVATION DÉJÀ CONFIRMÉE NE SE RECONFIRME PAS
  --
  -- Le double tap du propriétaire, ou deux téléphones. Sans ce refus,
  -- confirm_booking() serait rappelée sur une réservation qui n'est plus
  -- « accepted » — et déposerait une seconde paire de notifications
  -- « réservation confirmée » pour un seul encaissement.
  -- ===========================================================================
  begin
    perform public.confirmer_encaissement_especes(v_amina);
    raise exception 'ÉCHEC 5 — une réservation déjà confirmée s''est '
      'reconfirmée.';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    -- FE062 : il n'y a plus d'intention « pending » à confirmer — la première
    -- est passée à « paid ». C'est le bon refus, et il arrive avant FE063.
    if v_hint is distinct from 'FE062' then
      raise exception 'ÉCHEC 5 — une reconfirmation rend « % », attendu FE062.',
        coalesce(v_hint, '(aucun)');
    end if;
  end;

  select count(*) into v_notifs
  from public.notifications n
  where n.type = 'booking_confirmed' and n.user_id in (c_owner, c_amina);

  if v_notifs <> 2 then
    raise exception 'ÉCHEC 5b — % notification(s) après la seconde tentative, '
      'attendu 2. Un encaissement, une annonce.', v_notifs;
  end if;

  raise notice 'OK 5 — pas de seconde confirmation, pas de seconde notification.';

  -- ===========================================================================
  -- Test 6 — ON N'ANNONCE PAS D'ESPÈCES SUR UNE DATE DÉJÀ RÉGLÉE
  -- ===========================================================================
  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_amina, 'role', 'authenticated')::text, true);
  begin
    perform public.payer_en_especes(v_amina);
    raise exception 'ÉCHEC 6 — une réservation confirmée accepte encore une '
      'annonce d''espèces.';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE054' then
      raise exception 'ÉCHEC 6 — rend « % », attendu FE054.',
        coalesce(v_hint, '(aucun)');
    end if;
  end;

  -- Et pas davantage sur une option échue.
  update public.bookings
     set option_expires_at = now() - interval '1 hour'
   where id = v_autre;

  begin
    perform public.payer_en_especes(v_autre);
    raise exception 'ÉCHEC 6b — une option échue accepte encore une annonce '
      'd''espèces. Le client irait porter des billets pour une date repartie '
      'à la vente.';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE053' then
      raise exception 'ÉCHEC 6b — rend « % », attendu FE053.',
        coalesce(v_hint, '(aucun)');
    end if;
  end;

  raise notice 'OK 6 — ni sur une date réglée, ni sur une option échue.';

  -- ===========================================================================
  -- Test 7 — LE CLIENT NE CONFIRME PAS, ET LA BASE RESTE FERMÉE
  --
  -- Les droits, vérifiés sur la fonction elle-même : les deux fonctions du
  -- parcours espèces sont ouvertes à « authenticated » — elles vérifient
  -- elles-mêmes qui appelle —, mais confirmer_paiement_chargily(), elle, ne
  -- doit toujours l'être qu'au service_role.
  -- ===========================================================================
  if has_function_privilege('authenticated',
       'public.confirmer_paiement_chargily(text, text, numeric, jsonb)', 'execute') then
    raise exception 'ÉCHEC 7 — « authenticated » peut exécuter '
      'confirmer_paiement_chargily(). N''importe qui se déclarerait payé.';
  end if;

  if has_function_privilege('anon',
       'public.confirmer_paiement_chargily(text, text, numeric, jsonb)', 'execute') then
    raise exception 'ÉCHEC 7b — « anon » peut exécuter confirmer_paiement_chargily().';
  end if;

  if not has_function_privilege('service_role',
       'public.confirmer_paiement_chargily(text, text, numeric, jsonb)', 'execute') then
    raise exception 'ÉCHEC 7c — le service_role ne peut PAS exécuter '
      'confirmer_paiement_chargily() : le webhook n''écrirait plus rien.';
  end if;

  if not has_function_privilege('authenticated',
       'public.payer_en_especes(uuid)', 'execute') then
    raise exception 'ÉCHEC 7d — un client connecté ne peut pas annoncer un '
      'versement en espèces.';
  end if;

  if has_function_privilege('anon', 'public.payer_en_especes(uuid)', 'execute') then
    raise exception 'ÉCHEC 7e — « anon » peut annoncer un versement en espèces.';
  end if;

  raise notice 'OK 7 — le webhook reste au service_role, le parcours espèces '
    'aux comptes connectés.';

  perform set_config('request.jwt.claims', '', true);
end $$;

rollback;
