-- =============================================================================
-- Ferha — tests/018_le_decor_se_remet_en_place.sql
--
-- CE QU'ON VÉRIFIE : que le ménage de la migration 035 efface ce qu'un visiteur
-- a fait sur la démonstration, remet ce qu'il a défait, et ne déborde jamais du
-- décor.
--
-- POURQUOI CE FICHIER EXISTE. Les trois façons dont ce ménage peut mal tourner
-- sont toutes SILENCIEUSES :
--   * il n'efface rien, et la démonstration se remplit — on le voit, mais tard ;
--   * il n'efface que, sans remettre, et le tableau de bord de l'écran 9 finit
--     vide alors que tous les voyants sont verts ;
--   * il efface trop, et emporte une réservation qui n'était pas du décor.
-- Le troisième est le seul irréversible, et c'est pour lui que les tests 1, 4
-- et 10 existent.
--
-- LE TEST TRAVAILLE SUR LE VRAI DÉCOR, celui des seeds, parce que le critère du
-- ménage est fait de préfixes fixes — `b0000000-`, `5a11e000-`, `d0000000-` —
-- et qu'un décor inventé pour l'occasion ne les porterait pas. Tout est dans
-- une transaction, et la dernière instruction est ROLLBACK : la démonstration
-- retrouve l'état exact où elle était, empreinte comprise.
--
-- IL N'ATTEND PAS UN DÉCOR INTACT. Sur une base déjà visitée il ne l'est
-- probablement plus — au 16 septembre 2026 les cinq demandes en attente avaient
-- toutes disparu. Chaque test pose donc l'état dont il a besoin, prend
-- l'empreinte, casse, puis vérifie qu'on revient à L'EMPREINTE, et non à des
-- valeurs écrites en dur ici. C'est aussi ce que le ménage promet.
--
-- LE DÉLAI PASSÉ EST NÉGATIF, ET C'EST LE PIÈGE DU FICHIER. Dans une
-- transaction unique, now() ne bouge pas : une ligne écrite trois lignes plus
-- haut porte updated_at = now() exactement, et un délai nul ne la rendrait
-- jamais éligible. `interval '-1 hour'` décale la borne dans l'autre sens. Le
-- test 4, lui, appelle le ménage AVEC SON DÉLAI PAR DÉFAUT, et c'est justement
-- ce qu'il vérifie.
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
-- Prérequis : migrations 001 à 035, et les seeds 001, 003 et 004.
-- =============================================================================

begin;

do $$
declare
  -- Le décor, tel que les seeds le posent.
  c_bahia    constant uuid := '5a11e000-0000-4000-a000-000000000001';
  c_karim    constant uuid := 'd0000000-0000-4000-a000-000000000001';
  c_amina    constant uuid := 'd0000000-0000-4000-a000-000000000010';
  c_demande  constant uuid := 'b0000000-0000-4000-a000-000000000001';
  c_journee1 constant uuid := 'b0000000-0000-4000-a000-000000000003';
  c_journee2 constant uuid := 'b0000000-0000-4000-a000-000000000004';

  -- Le hors-décor du test 10 : une salle qui ne porte aucun préfixe de
  -- démonstration, et une réservation dessus. Le ménage ne doit pas la voir.
  c_hors_prop  constant uuid := 'c0000018-0000-4000-a000-000000000001';
  c_hors_cli   constant uuid := 'c0000018-0000-4000-a000-000000000002';
  c_hors_salle constant uuid := 'c0000018-0000-4000-a000-000000000003';
  c_hors_resa  constant uuid := 'c0000018-0000-4000-a000-000000000004';

  -- Le délai du banc d'essai — voir l'en-tête.
  c_tout     constant interval := interval '-1 hour';

  v_visiteur  uuid;
  v_groupe    uuid;
  v_jour_grp  uuid;
  v_m         record;
  v_avant     integer;
  v_statut    text;
  v_message   text;
  v_creee     timestamptz;
  v_prix      numeric;
  v_motif     text;
  v_date      date;
begin
  -- ---------------------------------------------------------------------------
  -- Prérequis — sans décor, ce fichier ne prouve rien
  -- ---------------------------------------------------------------------------
  if not exists (select 1 from public.bookings where id::text like 'b0000000-%') then
    raise exception 'ÉCHEC 0 — aucune réservation de décor. Lancez seed/001, 003 puis 004.';
  end if;
  if not exists (select 1 from public.venues where id = c_bahia) then
    raise exception 'ÉCHEC 0 — Salle El Bahia absente. Lancez seed/001_demo_venues.sql.';
  end if;

  -- On remet la demande b…0001 EN ATTENTE avant toute capture. Sur une base
  -- déjà visitée elle ne l'est plus — c'est le dégât même que ce ménage répare —
  -- et les tests 5 et 12 ont besoin d'en avoir une.
  update public.bookings
     set status = 'pending', accepted_at = null, confirmed_at = null,
         completed_at = null, cancelled_at = null, cancelled_by = null,
         status_reason = null, option_expires_at = null, deposit_amount = null
   where id = c_demande;

  -- MISE À BLANC. Sur une base déjà visitée, il traîne des réservations de
  -- visiteurs, des dates bloquées de trop et des notifications — 19, 4 et 45 au
  -- 16 septembre 2026. Les tests qui suivent comptent des lignes à l'unité : ils
  -- ont besoin de partir d'un décor propre. On capture, on nettoie une fois, et
  -- on repart de là. Tout est annulé au ROLLBACK final.
  perform public.capturer_le_decor();
  perform public.menage_du_decor(c_tout);

  -- ---------------------------------------------------------------------------
  -- TEST 1 — sans empreinte, le ménage ne touche à RIEN
  --
  -- C'est le garde-fou principal : une empreinte vide ne veut pas dire « le
  -- décor est vide », elle veut dire « personne ne m'a dit à quoi il
  -- ressemblait ». Supprimer sur cette base-là serait exactement l'erreur que
  -- la migration cherche à éviter.
  -- ---------------------------------------------------------------------------
  perform public.vider_le_decor();

  v_visiteur := gen_random_uuid();
  v_groupe   := gen_random_uuid();
  insert into public.bookings (id, group_id, venue_id, client_id, event_date,
                               slot, requested_slot, guest_count, event_type,
                               quoted_amount)
  values (v_visiteur, v_groupe, c_bahia, c_amina, date '2029-03-17',
          'soir', 'soir', 200, 'mariage', 0);

  select count(*) into v_avant from public.bookings where id::text like 'b0000000-%';

  select * into v_m from public.menage_du_decor(c_tout);

  if v_m.reservations_de_visiteurs <> 0 or v_m.decor_remis
     or v_m.dates_bloquees_retirees <> 0 or v_m.notifications_purgees <> 0 then
    raise exception 'ÉCHEC 1 — sans empreinte, le ménage a agi : % supprimées, remis=%, '
                    'dates=%, notifications=%.',
      v_m.reservations_de_visiteurs, v_m.decor_remis,
      v_m.dates_bloquees_retirees, v_m.notifications_purgees;
  end if;
  if not exists (select 1 from public.bookings where id = v_visiteur) then
    raise exception 'ÉCHEC 1 — sans empreinte, le ménage a supprimé une réservation.';
  end if;
  if (select count(*) from public.bookings where id::text like 'b0000000-%') <> v_avant then
    raise exception 'ÉCHEC 1 — sans empreinte, le décor a bougé.';
  end if;
  -- Et la vue ne doit pas inventer de chiffre : « 35 dates bloquées en trop »
  -- quand il n'y a rien à quoi les comparer serait un mensonge, pas un
  -- avertissement.
  if (select dates_bloquees_en_trop from public.etat_du_decor) is not null
     or (select decor_detourne from public.etat_du_decor) is not null then
    raise exception 'ÉCHEC 1 — sans empreinte, etat_du_decor annonce des écarts qu''elle ne peut pas connaître.';
  end if;
  raise notice 'Test 1 OK — sans empreinte, le ménage ne touche à rien.';

  -- ---------------------------------------------------------------------------
  -- TEST 2 — l'empreinte se prend, et elle est complète
  --
  -- La réservation de visiteur du test 1 ne doit PAS y entrer : elle ne porte
  -- pas le préfixe du décor.
  -- ---------------------------------------------------------------------------
  perform public.capturer_le_decor();

  if (select count(*) from public.decor_bookings)
     <> (select count(*) from public.bookings where id::text like 'b0000000-%') then
    raise exception 'ÉCHEC 2 — l''empreinte ne compte pas le même nombre de réservations que le décor.';
  end if;
  if (select count(*) from public.decor_reviews)
     <> (select count(*) from public.reviews where booking_id::text like 'b0000000-%') then
    raise exception 'ÉCHEC 2 — l''empreinte ne compte pas le même nombre d''avis que le décor.';
  end if;
  if (select count(*) from public.decor_blackouts)
     <> (select count(*) from public.venue_blackouts where venue_id::text like '5a11e000-%') then
    raise exception 'ÉCHEC 2 — l''empreinte ne compte pas les mêmes dates bloquées.';
  end if;
  if exists (select 1 from public.decor_bookings where id = v_visiteur) then
    raise exception 'ÉCHEC 2 — une réservation de visiteur est entrée dans l''empreinte.';
  end if;
  raise notice 'Test 2 OK — l''empreinte est complète, et ne contient que le décor.';

  -- ---------------------------------------------------------------------------
  -- TEST 3 — une réservation de visiteur part, avec son paiement, par GROUPE
  --
  -- La journée entière est le cas qui compte : deux lignes, un groupe. N'en
  -- effacer qu'une laisserait une demi-journée vendue.
  -- ---------------------------------------------------------------------------
  v_jour_grp := gen_random_uuid();
  insert into public.bookings (group_id, venue_id, client_id, event_date, slot,
                               requested_slot, guest_count, event_type, quoted_amount)
  values (v_jour_grp, c_bahia, c_amina, date '2029-04-21', 'midi', 'journee', 300, 'mariage', 0),
         (v_jour_grp, c_bahia, c_amina, date '2029-04-21', 'soir', 'journee', 300, 'mariage', 0);

  insert into public.payments (booking_id, amount, method, status)
  select id, 1000, 'cash', 'paid' from public.bookings where id = v_visiteur;

  select * into v_m from public.menage_du_decor(c_tout);

  if v_m.reservations_de_visiteurs <> 3 then
    raise exception 'ÉCHEC 3 — 3 lignes de visiteur attendues, % supprimée(s).',
      v_m.reservations_de_visiteurs;
  end if;
  if v_m.paiements_de_visiteurs <> 1 then
    raise exception 'ÉCHEC 3 — le paiement du visiteur n''a pas été emporté (% supprimé(s)).',
      v_m.paiements_de_visiteurs;
  end if;
  if exists (select 1 from public.bookings where group_id = v_jour_grp) then
    raise exception 'ÉCHEC 3 — une ligne de la journée entière est restée.';
  end if;
  raise notice 'Test 3 OK — la réservation d''un visiteur part par groupe entier, paiement compris.';

  -- ---------------------------------------------------------------------------
  -- TEST 4 — LA BORNE DES DEUX HEURES PROTÈGE LE RÉCENT
  --
  -- Ici, et ici seulement, on appelle le ménage AVEC SON DÉLAI PAR DÉFAUT. Un
  -- visiteur qui teste dix minutes doit garder sous les yeux ce qu'il vient de
  -- faire.
  -- ---------------------------------------------------------------------------
  v_visiteur := gen_random_uuid();
  insert into public.bookings (id, group_id, venue_id, client_id, event_date,
                               slot, requested_slot, guest_count, event_type, quoted_amount)
  values (v_visiteur, gen_random_uuid(), c_bahia, c_amina, date '2029-05-05',
          'soir', 'soir', 150, 'fiancailles', 0);

  select * into v_m from public.menage_du_decor();   -- deux heures

  if not exists (select 1 from public.bookings where id = v_visiteur) then
    raise exception 'ÉCHEC 4 — une réservation créée à l''instant a été effacée malgré la borne.';
  end if;

  select * into v_m from public.menage_du_decor(c_tout);

  if exists (select 1 from public.bookings where id = v_visiteur) then
    raise exception 'ÉCHEC 4 — passé le délai, la réservation du visiteur est restée.';
  end if;
  raise notice 'Test 4 OK — la borne protège ce qui vient d''être fait, et seulement cela.';

  -- ---------------------------------------------------------------------------
  -- TEST 5 — LE CŒUR DU FICHIER : une demande refusée revient en attente
  --
  -- On passe par refuser_demande() (015), la vraie fonction, avec la session de
  -- Karim : c'est exactement ce qu'un visiteur entré comme Karim fait en un tap,
  -- et c'est ce qui a vidé la file d'attente de la démonstration.
  --
  -- On vérifie le retour à L'EMPREINTE : l'état, mais aussi le message du
  -- client et la date de la demande, que le tableau de bord affiche en clair
  -- (« il y a deux heures »).
  -- ---------------------------------------------------------------------------
  select e.status, e.client_message, e.created_at
    into v_statut, v_message, v_creee
  from public.decor_bookings e where e.id = c_demande;

  if v_statut is distinct from 'pending' then
    raise exception 'ÉCHEC 5 — l''empreinte devrait tenir b…0001 en attente, elle dit « % ».', v_statut;
  end if;

  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_karim, 'role', 'authenticated')::text,
                     true);
  perform public.refuser_demande(c_demande, 'Refusée pendant le banc d''essai 018.');
  perform set_config('request.jwt.claims', '', true);

  if (select status from public.bookings where id = c_demande) <> 'refused' then
    raise exception 'ÉCHEC 5 — la mise en scène a échoué : la demande n''est pas refusée.';
  end if;

  select * into v_m from public.menage_du_decor(c_tout);

  if not v_m.decor_remis then
    raise exception 'ÉCHEC 5 — le décor a été détourné et le ménage ne l''a pas remis.';
  end if;

  select b.status, b.client_message, b.created_at, b.status_reason
    into v_statut, v_message, v_creee, v_motif
  from public.bookings b where b.id = c_demande;

  if v_statut is distinct from 'pending' then
    raise exception 'ÉCHEC 5 — la demande devrait être revenue en attente, elle est « % ».', v_statut;
  end if;
  if v_motif is not null then
    raise exception 'ÉCHEC 5 — le motif de refus du visiteur est resté collé à la demande.';
  end if;
  if v_message is distinct from (select client_message from public.decor_bookings where id = c_demande) then
    raise exception 'ÉCHEC 5 — le message du client n''est pas celui de l''empreinte.';
  end if;
  if v_creee is distinct from (select created_at from public.decor_bookings where id = c_demande) then
    raise exception 'ÉCHEC 5 — la date de la demande a bougé : le tableau de bord mentira sur son âge.';
  end if;
  raise notice 'Test 5 OK — une demande refusée par un visiteur revient en attente, intacte.';

  -- ---------------------------------------------------------------------------
  -- TEST 6 — une ligne supprimée revient, et une journée entière revient ENTIÈRE
  --
  -- bookings_check_journee (005) exige les deux lignes d'une journée dans la
  -- même instruction. Si la restauration les insérait une par une, elle
  -- échouerait ici et nulle part ailleurs.
  -- ---------------------------------------------------------------------------
  delete from public.bookings where id in (c_journee1, c_journee2);

  select * into v_m from public.menage_du_decor(c_tout);

  if not v_m.decor_remis then
    raise exception 'ÉCHEC 6 — deux lignes du décor manquaient et le ménage n''a rien remis.';
  end if;
  if (select count(*) from public.bookings where id in (c_journee1, c_journee2)) <> 2 then
    raise exception 'ÉCHEC 6 — la journée entière n''est pas revenue en deux lignes.';
  end if;
  if (select count(distinct group_id) from public.bookings where id in (c_journee1, c_journee2)) <> 1 then
    raise exception 'ÉCHEC 6 — les deux lignes de la journée ne partagent plus leur groupe.';
  end if;
  if (select count(distinct slot) from public.bookings where id in (c_journee1, c_journee2)) <> 2 then
    raise exception 'ÉCHEC 6 — la journée est revenue avec deux fois le même créneau.';
  end if;
  raise notice 'Test 6 OK — une ligne disparue revient, et une journée entière revient entière.';

  -- ---------------------------------------------------------------------------
  -- TEST 7 — le prix revient d'estimate_price(), l'acompte de deposit_rate()
  --
  -- La règle du projet : aucun montant ne se recopie. L'empreinte ne porte ni
  -- prix ni acompte, et la restauration les fait recalculer par le trigger
  -- bookings_set_price puis par deposit_rate(). Un décor restauré après un
  -- changement de tarif doit porter le tarif du jour.
  -- ---------------------------------------------------------------------------
  select e.total into v_prix
  from public.bookings b
  join lateral public.estimate_price(b.venue_id, b.event_date, b.requested_slot,
                                     b.guest_count, b.option_ids) e on true
  where b.id = c_journee1;

  if (select quoted_amount from public.bookings where id = c_journee1) is distinct from v_prix then
    raise exception 'ÉCHEC 7 — le prix restauré ne vient pas d''estimate_price().';
  end if;

  if exists (
    select 1 from public.bookings b
     where b.id::text like 'b0000000-%'
       and b.deposit_amount is not null
       and b.deposit_amount is distinct from round(b.quoted_amount * public.deposit_rate(), 2)
  ) then
    raise exception 'ÉCHEC 7 — un acompte restauré ne suit pas deposit_rate().';
  end if;

  -- Une demande à laquelle personne n'a répondu ne porte pas d'acompte : c'est
  -- le propriétaire qui le fixe en acceptant (§3, étape 4).
  if exists (
    select 1 from public.bookings b
     where b.id::text like 'b0000000-%'
       and b.accepted_at is null
       and b.status not in ('confirmed', 'completed')
       and b.deposit_amount is not null
  ) then
    raise exception 'ÉCHEC 7 — une demande sans réponse porte un acompte.';
  end if;

  -- ET L'INVERSE, qui est le piège que ce banc d'essai a trouvé : une ligne
  -- honorée SANS accepted_at — il y en a une dans le décor réel, b…0099 — doit
  -- quand même porter un acompte, sinon bookings_confirmed_requires_deposit
  -- refuse la ligne et fait échouer toute la restauration en silence.
  if exists (
    select 1 from public.bookings b
     where b.id::text like 'b0000000-%'
       and b.status in ('confirmed', 'completed')
       and b.deposit_amount is null
  ) then
    raise exception 'ÉCHEC 7 — une réservation confirmée ou honorée est revenue sans acompte.';
  end if;
  raise notice 'Test 7 OK — le prix et l''acompte sont recalculés, jamais recopiés.';

  -- ---------------------------------------------------------------------------
  -- TEST 8 — les avis du décor reviennent, et un avis en trop s'en va
  -- ---------------------------------------------------------------------------
  select count(*) into v_avant from public.decor_reviews;
  if v_avant = 0 then
    raise notice 'Test 8 ignoré — le décor ne porte aucun avis à cette étape.';
  else
    delete from public.reviews where booking_id::text like 'b0000000-%';

    select * into v_m from public.menage_du_decor(c_tout);

    if (select count(*) from public.reviews where booking_id::text like 'b0000000-%') <> v_avant then
      raise exception 'ÉCHEC 8 — les avis du décor ne sont pas tous revenus (% sur %).',
        (select count(*) from public.reviews where booking_id::text like 'b0000000-%'), v_avant;
    end if;
    -- booking_group_id est renseigné par reviews_guard, pas par la restauration :
    -- s'il était nul, c'est que le trigger a été contourné.
    if exists (select 1 from public.reviews
                where booking_id::text like 'b0000000-%' and booking_group_id is null) then
      raise exception 'ÉCHEC 8 — un avis restauré n''est rattaché à aucun groupe.';
    end if;
    raise notice 'Test 8 OK — les avis du décor reviennent, rattachés à leur événement.';
  end if;

  -- ---------------------------------------------------------------------------
  -- TEST 9 — les dates bloquées : une en trop part, une manquante revient,
  --          un motif réécrit est corrigé
  --
  -- C'est le geste que le préfixe ne sait pas faire : venue_blackouts.id est
  -- tiré au sort, y compris pour le décor. La clé est (venue_id, date, slot).
  -- ---------------------------------------------------------------------------
  insert into public.venue_blackouts (venue_id, date, slot, reason)
  values (c_bahia, date '2029-06-09', 'soir', 'Bloquée pendant le banc d''essai 018.');

  select e.date into v_date from public.decor_blackouts e
   where e.venue_id = c_bahia order by e.date limit 1;

  delete from public.venue_blackouts
   where venue_id = c_bahia and date = v_date;

  update public.venue_blackouts vb
     set reason = 'Motif réécrit par le banc d''essai 018.'
    from public.decor_blackouts e
   where vb.venue_id = e.venue_id and vb.date = e.date and vb.slot = e.slot
     and vb.venue_id = c_bahia
     and vb.date = (select max(date) from public.decor_blackouts where venue_id = c_bahia);

  select * into v_m from public.menage_du_decor(c_tout);

  if exists (select 1 from public.venue_blackouts
              where venue_id = c_bahia and date = date '2029-06-09') then
    raise exception 'ÉCHEC 9 — la date bloquée par le visiteur est restée.';
  end if;
  if not exists (select 1 from public.venue_blackouts
                  where venue_id = c_bahia and date = v_date) then
    raise exception 'ÉCHEC 9 — la date bloquée du décor n''a pas été reposée.';
  end if;
  if exists (
    select 1 from public.venue_blackouts vb
    join public.decor_blackouts e
      on e.venue_id = vb.venue_id and e.date = vb.date and e.slot = vb.slot
   where vb.reason is distinct from e.reason
  ) then
    raise exception 'ÉCHEC 9 — un motif réécrit par un visiteur n''a pas été corrigé.';
  end if;
  raise notice 'Test 9 OK — les dates bloquées reviennent à l''empreinte, motifs compris.';

  -- ---------------------------------------------------------------------------
  -- TEST 10 — RIEN HORS DU DÉCOR
  --
  -- Une salle sans le préfixe `5a11e000-` n'est pas de la démonstration, et ce
  -- qui s'y passe ne regarde pas ce ménage. C'est l'arbitrage explicite de la
  -- migration, et le seul dégât irréversible qu'elle pourrait faire.
  -- ---------------------------------------------------------------------------
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
                          email_confirmed_at, created_at, updated_at,
                          raw_app_meta_data, raw_user_meta_data)
  values ('00000000-0000-0000-0000-000000000000', c_hors_prop, 'authenticated',
          'authenticated', 'test.prop.018@ferha.test', '', now(), now(), now(),
          '{}'::jsonb, '{}'::jsonb),
         ('00000000-0000-0000-0000-000000000000', c_hors_cli, 'authenticated',
          'authenticated', 'test.client.018@ferha.test', '', now(), now(), now(),
          '{}'::jsonb, '{}'::jsonb);

  -- handle_new_user (007) a déjà créé les deux profils en même temps que les
  -- comptes : on les complète, on ne les repose pas.
  insert into public.profiles (id, full_name, email, phone, is_owner) values
    (c_hors_prop, 'Propriétaire 018', 'test.prop.018@ferha.test',   '0770000018', true),
    (c_hors_cli,  'Cliente 018',      'test.client.018@ferha.test', '0770000118', false)
  on conflict (id) do update set
    full_name = excluded.full_name,
    email     = excluded.email,
    phone     = excluded.phone,
    is_owner  = excluded.is_owner;

  insert into public.venues (id, owner_id, name, wilaya_code, commune,
                             capacity_seated, status)
  values (c_hors_salle, c_hors_prop, 'Salle 018', '16', 'Alger-Centre', 300, 'published');

  insert into public.venue_pricing (venue_id, slot, base_price) values
    (c_hors_salle, 'midi', 100000), (c_hors_salle, 'soir', 150000),
    (c_hors_salle, 'journee', 200000);

  insert into public.bookings (id, group_id, venue_id, client_id, event_date, slot,
                               requested_slot, guest_count, event_type, quoted_amount)
  values (c_hors_resa, gen_random_uuid(), c_hors_salle, c_hors_cli, date '2029-07-14',
          'soir', 'soir', 200, 'mariage', 0);

  -- Et le pire cas : une demande posée par AMINA, un compte de démonstration,
  -- sur une salle qui n'en est pas une. Le ménage n'a pas à y toucher — c'est
  -- la vente d'un vrai propriétaire.
  insert into public.bookings (group_id, venue_id, client_id, event_date, slot,
                               requested_slot, guest_count, event_type, quoted_amount)
  values (gen_random_uuid(), c_hors_salle, c_amina, date '2029-08-18',
          'soir', 'soir', 180, 'fiancailles', 0);

  select * into v_m from public.menage_du_decor(c_tout);

  if not exists (select 1 from public.bookings where id = c_hors_resa) then
    raise exception 'ÉCHEC 10 — le ménage a effacé une réservation sur une salle hors décor.';
  end if;
  if (select count(*) from public.bookings where venue_id = c_hors_salle) <> 2 then
    raise exception 'ÉCHEC 10 — une demande d''Amina sur une salle hors décor a été effacée.';
  end if;
  raise notice 'Test 10 OK — hors des salles de démonstration, le ménage ne voit rien.';

  -- ---------------------------------------------------------------------------
  -- TEST 11 — les notifications des comptes de démonstration
  --
  -- Le décor n'en pose aucune : 004 écrit les états directement, sans passer par
  -- notify_user(). Toute notification d'un compte en `d0000000-` vient donc d'un
  -- visiteur. Celle du compte hors décor, elle, reste.
  -- ---------------------------------------------------------------------------
  insert into public.notifications (user_id, type, payload) values
    (c_amina,    'booking_answered', '{"test": "018"}'::jsonb),
    (c_hors_cli, 'booking_answered', '{"test": "018"}'::jsonb);

  select * into v_m from public.menage_du_decor();   -- délai par défaut : elles viennent de naître

  if not exists (select 1 from public.notifications
                  where user_id = c_amina and payload ->> 'test' = '018') then
    raise exception 'ÉCHEC 11 — une notification née à l''instant a été purgée malgré la borne.';
  end if;

  select * into v_m from public.menage_du_decor(c_tout);

  if exists (select 1 from public.notifications where user_id::text like 'd0000000-%') then
    raise exception 'ÉCHEC 11 — une notification de compte de démonstration a survécu au ménage.';
  end if;
  if not exists (select 1 from public.notifications where user_id = c_hors_cli) then
    raise exception 'ÉCHEC 11 — le ménage a purgé la notification d''un compte hors décor.';
  end if;
  raise notice 'Test 11 OK — les notifications de démonstration partent, les autres restent.';

  -- ---------------------------------------------------------------------------
  -- TEST 12 — le ménage est idempotent
  --
  -- Une seconde passe sur un décor propre ne doit RIEN remuer. Sans cela, le
  -- ménage se réveillerait toutes les heures pour effacer et réécrire le décor
  -- sous les yeux d'un visiteur.
  -- ---------------------------------------------------------------------------
  select * into v_m from public.menage_du_decor(c_tout);

  if v_m.reservations_de_visiteurs <> 0 or v_m.avis_de_visiteurs <> 0
     or v_m.paiements_de_visiteurs <> 0 or v_m.decor_remis
     or v_m.dates_bloquees_retirees <> 0 or v_m.dates_bloquees_reposees <> 0
     or v_m.notifications_purgees <> 0 then
    raise exception 'ÉCHEC 12 — le ménage n''est pas idempotent : resa=%, avis=%, paiements=%, '
                    'remis=%, dates -%/+%, notifications=%.',
      v_m.reservations_de_visiteurs, v_m.avis_de_visiteurs, v_m.paiements_de_visiteurs,
      v_m.decor_remis, v_m.dates_bloquees_retirees, v_m.dates_bloquees_reposees,
      v_m.notifications_purgees;
  end if;
  raise notice 'Test 12 OK — une seconde passe ne remue rien.';

  -- ---------------------------------------------------------------------------
  -- TEST 13 — etat_du_decor dit la vérité
  --
  -- C'est la vue qu'on lira le jour où la démonstration paraîtra vide. Si elle
  -- ment, personne ne s'en apercevra.
  -- ---------------------------------------------------------------------------
  -- « is distinct from » et non « <> » : ces compteurs valent NULL sans
  -- empreinte, et NULL <> 0 ne vaut pas vrai — l'assertion passerait sans rien
  -- vérifier.
  if (select decor_detourne from public.etat_du_decor) is distinct from 0
     or (select decor_disparu from public.etat_du_decor) is distinct from 0
     or (select dates_bloquees_en_trop from public.etat_du_decor) is distinct from 0
     or (select dates_bloquees_manquantes from public.etat_du_decor) is distinct from 0 then
    raise exception 'ÉCHEC 13 — le décor vient d''être remis et la vue le dit encore sale.';
  end if;
  if (select demandes_en_attente from public.etat_du_decor) = 0 then
    raise exception 'ÉCHEC 13 — plus aucune demande en attente : le tableau de bord n''a rien à montrer.';
  end if;

  -- On détourne à nouveau, et la vue doit le voir.
  update public.bookings set status = 'refused',
         status_reason = 'Détournée pour le test 13.'
   where id = c_demande;

  if (select decor_detourne from public.etat_du_decor) is distinct from 1 then
    raise exception 'ÉCHEC 13 — une demande détournée et la vue ne la compte pas.';
  end if;
  raise notice 'Test 13 OK — etat_du_decor voit ce qui est sale, et ne crie pas quand tout va bien.';

  raise notice '--------------------------------------------------------------';
  raise notice 'tests/018 — tout est passé. La transaction va être annulée.';
end;
$$;

rollback;
