-- =============================================================================
-- Ferha — tests/010_une_option_tient_la_date.sql
--
-- CE QU'ON VÉRIFIE : qu'une option de 72 h TIENT la date (§5.1), partout et de
-- la même façon — et qu'une option ÉCHUE ne tient plus rien, tout de suite.
--
-- POURQUOI CE FICHIER EXISTE. L'écran 6 promet au client « la date vous est
-- réservée pendant 71 h ». Avant 023, c'était faux : le calendrier montrait la
-- date libre, la recherche proposait la salle, une nouvelle demande passait, et
-- le propriétaire pouvait accepter une SECONDE famille sur le même créneau.
-- Deux options couraient alors côte à côte, et la première qui payait gagnait.
-- L'autre famille l'apprenait en appelant la salle, après avoir prévenu la
-- sienne. Ce test est ce qui empêche que cela revienne.
--
-- LES DEUX MOITIÉS DU TEST SONT AUSSI IMPORTANTES L'UNE QUE L'AUTRE :
--
--   * une option EN COURS ferme la date à tout le monde ;
--   * une option ÉCHUE la rouvre À LA MINUTE, sans attendre le cron
--     expire-options, qui ne passe que tous les quarts d'heure. Une règle qui
--     n'attendrait pas serait trop stricte quinze minutes par heure — et c'est
--     justement le moment où une autre famille regarde.
--
-- Et une troisième, qui garde la première de trop en faire : LES DEMANDES
-- « pending » NE BLOQUENT TOUJOURS RIEN (§5.1). Plusieurs familles peuvent
-- demander le même 14 août ; le propriétaire arbitre.
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
-- ON VÉRIFIE LE HINT, PAS LE MESSAGE — c'est le hint que lit l'application
-- (lib/features/booking/booking_messages.dart, lib/features/owner/owner_messages.dart).
--
-- CE QU'IL LAISSE : rien. Tout est fait dans une transaction annulée à la fin.
--
-- Prérequis : migrations 001 à 023 appliquées.
-- =============================================================================

begin;

do $$
declare
  c_venue   constant uuid := 'c0000010-0000-4000-a000-000000000001';
  c_owner   constant uuid := 'c0000010-0000-4000-a000-000000000002';
  c_amina   constant uuid := 'c0000010-0000-4000-a000-000000000003';
  c_yasmine constant uuid := 'c0000010-0000-4000-a000-000000000004';
  c_nadia   constant uuid := 'c0000010-0000-4000-a000-000000000005';

  -- Loin dans le futur : aucun risque de croiser une donnée réelle.
  c_option   constant date := date '2099-08-14';  -- option de 72 h en cours
  c_echue    constant date := date '2099-08-21';  -- option échue, cron pas passé
  c_echue_2  constant date := date '2099-08-22';  -- idem, pour la fermeture
  c_journee  constant date := date '2099-09-05';  -- journée entière sous option
  c_libre    constant date := date '2099-09-12';  -- deux demandes en attente

  v_amina   uuid;
  v_nadia   uuid;
  v_reprise uuid;

  v_etat     text;
  v_hint     text;
  v_sqlstate text;
  v_statut   text;
  v_lignes   integer;
  v_index    text;
begin
  -- ---------------------------------------------------------------------------
  -- Le décor : une salle à Oran, son propriétaire, trois clientes.
  -- ---------------------------------------------------------------------------
  insert into auth.users (instance_id, id, aud, role, email,
                          encrypted_password, email_confirmed_at,
                          created_at, updated_at,
                          raw_app_meta_data, raw_user_meta_data)
  values
    ('00000000-0000-0000-0000-000000000000', c_owner,   'authenticated', 'authenticated',
     'test.owner.010@ferha.test',   '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb),
    ('00000000-0000-0000-0000-000000000000', c_amina,   'authenticated', 'authenticated',
     'test.amina.010@ferha.test',   '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb),
    ('00000000-0000-0000-0000-000000000000', c_yasmine, 'authenticated', 'authenticated',
     'test.yasmine.010@ferha.test', '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb),
    ('00000000-0000-0000-0000-000000000000', c_nadia,   'authenticated', 'authenticated',
     'test.nadia.010@ferha.test',   '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb);

  insert into public.profiles (id, full_name, email, is_owner) values
    (c_owner,   'Karim Propriétaire', 'test.owner.010@ferha.test',   true),
    (c_amina,   'Amina Haddad',       'test.amina.010@ferha.test',   false),
    (c_yasmine, 'Yasmine Belkacem',   'test.yasmine.010@ferha.test', false),
    (c_nadia,   'Nadia Cherif',       'test.nadia.010@ferha.test',   false)
  on conflict (id) do update
    set full_name = excluded.full_name,
        is_owner  = excluded.is_owner;

  insert into public.venues (id, owner_id, name, wilaya_code, commune,
                             capacity_seated, status)
  values (c_venue, c_owner, 'Salle de test 010', '31', 'Oran', 400, 'published');

  insert into public.venue_pricing (venue_id, slot, base_price, weekend_coef,
                                    high_season_coef, included_seats, extra_seat_price)
  values
    (c_venue, 'midi',    100000, 1.30, 1.20, 200, 800),
    (c_venue, 'soir',    200000, 1.30, 1.20, 200, 800),
    (c_venue, 'journee', 280000, 1.30, 1.20, 200, 800);

  -- ===========================================================================
  -- Test 0 — L'INDEX DU §6.1 N'A PAS BOUGÉ
  --
  -- On le vérifie AVANT tout le reste, et c'est volontaire. La tentation, en
  -- rendant les options bloquantes, est d'élargir uniq_booking_slot à
  -- « accepted » : ce serait la pire des corrections. L'index doit rester
  -- partiel — une option échue doit pouvoir laisser passer la confirmation
  -- d'une autre réservation, sans qu'un index s'y oppose pour toujours.
  -- ===========================================================================
  select i.indexdef into v_index
  from pg_indexes i
  where i.schemaname = 'public' and i.indexname = 'uniq_booking_slot';

  if v_index is null then
    raise exception 'ÉCHEC 0 — uniq_booking_slot a disparu. C''est la garantie du §6.1.';
  end if;
  if v_index like '%accepted%' or v_index like '%option_expires_at%' then
    raise exception
      'ÉCHEC 0 — uniq_booking_slot porte maintenant sur les options : %. '
      'Il doit rester partiel, sur confirmed et completed (§6.1).', v_index;
  end if;
  if v_index not like '%confirmed%' or v_index not like '%completed%' then
    raise exception 'ÉCHEC 0 — uniq_booking_slot ne porte plus sur confirmed et completed : %.',
      v_index;
  end if;

  raise notice 'OK 0 — uniq_booking_slot est intact : confirmed et completed, rien d''autre.';

  -- ===========================================================================
  -- LE DÉCOR DES TESTS 1 À 4 : deux familles ont demandé le 14 août au soir,
  -- et Karim a dit oui à la première.
  -- ===========================================================================
  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_amina, 'role', 'authenticated')::text, true);
  select b.id into v_amina
  from public.request_booking(c_venue, c_option, 'soir', 250, '0770112233') b
  order by b.slot limit 1;

  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_nadia, 'role', 'authenticated')::text, true);
  select b.id into v_nadia
  from public.request_booking(c_venue, c_option, 'soir', 180, '0661223344') b
  order by b.slot limit 1;

  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_owner, 'role', 'authenticated')::text, true);
  perform public.accepter_demande(v_amina);

  -- ---------------------------------------------------------------------------
  -- Test 1 — LE CALENDRIER PUBLIC DIT « RÉSERVÉ », ET NE DIT QUE CELA
  --
  -- C'est la promesse de l'écran 6 rendue vraie : la date d'Amina disparaît du
  -- calendrier des autres. Et elle en disparaît sous le MÊME mot qu'une date
  -- payée — « reserve ». Un mot à part apprendrait à un inconnu qu'une famille
  -- hésite, donc qu'il y a peut-être une place à prendre dans trois jours.
  -- ---------------------------------------------------------------------------
  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_yasmine, 'role', 'authenticated')::text, true);

  select c.state into v_etat
  from public.venue_calendar(c_venue, 'soir', c_option, c_option) c
  where c.day = c_option;

  if v_etat is distinct from 'reserve' then
    raise exception
      'ÉCHEC 1 — LE CALENDRIER MONTRE LA DATE « % » ALORS QU''UNE OPTION DE 72 H '
      'COURT DESSUS. L''écran 6 a promis à Amina que la date lui était réservée.',
      coalesce(v_etat, 'libre');
  end if;

  raise notice 'OK 1 — une date sous option s''affiche « reserve », comme une date payée.';

  -- ---------------------------------------------------------------------------
  -- Test 2 — LA RECHERCHE N'AVANCE PLUS LA SALLE POUR CETTE DATE
  --
  -- Sinon Yasmine ouvrirait la fiche, remplirait le formulaire, et se ferait
  -- refuser trois écrans plus loin par request_booking(). Le bon endroit pour
  -- dire non est le premier.
  -- ---------------------------------------------------------------------------
  select count(*) into v_lignes
  from public.search_venues(p_query => 'Salle de test 010', p_event_date => c_option,
                            p_slot => 'soir') s
  where s.venue_id = c_venue;

  if v_lignes <> 0 then
    raise exception 'ÉCHEC 2 — la recherche propose encore la salle le 14 août au soir.';
  end if;

  -- Et sans date, elle est toujours au catalogue : on n'a pas retiré la salle,
  -- on a retiré UNE date.
  select count(*) into v_lignes
  from public.search_venues(p_query => 'Salle de test 010') s
  where s.venue_id = c_venue;

  if v_lignes <> 1 then
    raise exception
      'ÉCHEC 2 — la salle a disparu du catalogue entier (% ligne(s)) alors qu''une '
      'seule de ses dates est prise.', v_lignes;
  end if;

  raise notice 'OK 2 — la salle sort des résultats pour cette date, et pour elle seule.';

  -- ---------------------------------------------------------------------------
  -- Test 3 — UNE NOUVELLE DEMANDE EST REFUSÉE (FE001)
  --
  -- Le même code qu'une date vendue, et c'est voulu : du côté de Yasmine, c'est
  -- la même chose. Lui dire « une option court jusqu'à jeudi 14 h » lui
  -- apprendrait qu'une autre famille hésite, et l'inviterait à attendre son
  -- échec.
  -- ---------------------------------------------------------------------------
  begin
    perform * from public.request_booking(c_venue, c_option, 'soir', 200, '0550998877');
    raise exception
      'ÉCHEC 3 — UNE DEMANDE EST PASSÉE SUR UN CRÉNEAU SOUS OPTION. C''est la '
      'deuxième famille sur le même 14 août.';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE001' then
      raise exception 'ÉCHEC 3 — refus attendu FE001, reçu hint=% sqlstate=%.',
        coalesce(v_hint, '(vide)'), v_sqlstate;
    end if;
  end;

  raise notice 'OK 3 — une nouvelle demande sur une date sous option : FE001, sqlstate %.',
    v_sqlstate;

  -- ---------------------------------------------------------------------------
  -- Test 4 — KARIM NE PEUT PAS DIRE OUI DEUX FOIS (FE014)
  --
  -- LE CŒUR DU FICHIER. La demande de Nadia est arrivée AVANT que Karim
  -- n'accepte celle d'Amina : elle est toujours en attente, et son bouton
  -- « Accepter » est toujours là. Avant 023, il marchait — le garde-fou de 015
  -- ne regardait que « confirmed » et « completed ».
  --
  -- ET LE CODE N'EST PAS FE013. Personne n'a rien confirmé : c'est Karim
  -- lui-même qui s'est engagé, et lui seul peut décider d'attendre l'échéance
  -- ou de refuser tout de suite. Lui dire « quelqu'un d'autre a confirmé »
  -- serait faux, et lui cacherait la seule chose qui change ce qu'il peut faire.
  -- ---------------------------------------------------------------------------
  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_owner, 'role', 'authenticated')::text, true);

  begin
    perform public.accepter_demande(v_nadia);
    raise exception
      'ÉCHEC 4 — UNE DEUXIÈME OPTION A ÉTÉ POSÉE SUR LE MÊME CRÉNEAU. Deux familles '
      'ont maintenant chacune leur option de 72 h sur le 14 août au soir.';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_hint = 'FE013' then
      raise exception
        'ÉCHEC 4 — refus attendu FE014, reçu FE013 : la base dit à Karim que la date '
        'a été confirmée par quelqu''un d''autre, alors que c''est lui qui l''a promise.';
    end if;
    if v_hint is distinct from 'FE014' then
      raise exception 'ÉCHEC 4 — refus attendu FE014, reçu hint=% sqlstate=%.',
        coalesce(v_hint, '(vide)'), v_sqlstate;
    end if;
  end;

  -- Et la demande de Nadia n'a pas bougé : elle reste répondable le jour où
  -- l'option d'Amina expire.
  select b.status into v_statut from public.bookings b where b.id = v_nadia;
  if v_statut is distinct from 'pending' then
    raise exception 'ÉCHEC 4 — la demande de Nadia est passée en « % » malgré le refus.',
      v_statut;
  end if;

  raise notice 'OK 4 — la deuxième acceptation est refusée (FE014, sqlstate %), et la demande reste en attente.',
    v_sqlstate;

  -- ===========================================================================
  -- Test 5 — UNE OPTION ÉCHUE NE TIENT PLUS RIEN, ET TOUT DE SUITE
  --
  -- Le cron expire-options (022) passe tous les quarts d'heure. Entre deux
  -- passages, la ligne est encore « accepted » avec une échéance dépassée : la
  -- règle doit déjà la lire comme morte. Sans cela, une date libre resterait
  -- « prise » jusqu'à quinze minutes — et c'est exactement le moment où une
  -- autre famille regarde.
  --
  -- On écrit donc la ligne à la main, sans faire tourner le cron : c'est l'état
  -- réel de la base pendant ces quinze minutes.
  -- ===========================================================================
  insert into public.bookings (venue_id, client_id, event_date, slot, requested_slot,
                               guest_count, quoted_amount, deposit_amount, status,
                               option_expires_at)
  values
    (c_venue, c_amina, c_echue,   'soir', 'soir', 250, 0, 40000, 'accepted',
     now() - interval '2 hours'),
    (c_venue, c_amina, c_echue_2, 'soir', 'soir', 250, 0, 40000, 'accepted',
     now() - interval '2 hours');

  -- Le cron n'est pas passé : la ligne est encore « accepted ». C'est la
  -- prémisse du test, et on la vérifie plutôt que de la supposer.
  select b.status into v_statut
  from public.bookings b
  where b.venue_id = c_venue and b.event_date = c_echue and b.slot = 'soir';
  if v_statut is distinct from 'accepted' then
    raise exception
      'ÉCHEC 5 — la ligne est déjà en « % » : le test ne vérifie plus rien. Il doit '
      'porter sur une option échue que le cron n''a PAS encore rangée.', v_statut;
  end if;

  -- 5a — le calendrier la rend à la vente.
  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_yasmine, 'role', 'authenticated')::text, true);

  select c.state into v_etat
  from public.venue_calendar(c_venue, 'soir', c_echue, c_echue) c
  where c.day = c_echue;

  if v_etat is not null then
    raise exception
      'ÉCHEC 5a — le calendrier dit « % » sur une option ÉCHUE. La date est à vendre, '
      'et elle le reste jusqu''au prochain passage du cron.', v_etat;
  end if;

  -- 5b — la recherche aussi.
  select count(*) into v_lignes
  from public.search_venues(p_query => 'Salle de test 010', p_event_date => c_echue,
                            p_slot => 'soir') s
  where s.venue_id = c_venue;
  if v_lignes <> 1 then
    raise exception 'ÉCHEC 5b — la recherche cache encore la salle sur une option échue.';
  end if;

  -- 5c — et une demande passe.
  select b.id into v_reprise
  from public.request_booking(c_venue, c_echue, 'soir', 200, '0550998877') b
  order by b.slot limit 1;

  if v_reprise is null then
    raise exception 'ÉCHEC 5c — la demande de Yasmine n''a rien rendu.';
  end if;

  -- 5d — le propriétaire peut l'accepter : la vieille option ne lui oppose plus
  --      ni FE013 ni FE014.
  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_owner, 'role', 'authenticated')::text, true);
  perform public.accepter_demande(v_reprise);

  select b.status into v_statut from public.bookings b where b.id = v_reprise;
  if v_statut is distinct from 'accepted' then
    raise exception 'ÉCHEC 5d — la demande reprise est en « % » au lieu de « accepted ».',
      v_statut;
  end if;

  -- 5e — et il peut fermer l'autre date échue : on ne ferme pas une date sur la
  --      tête d'un client, mais une option morte n'a plus de client.
  perform * from public.bloquer_date(c_venue, c_echue_2, 'soir', 'Travaux');
  if (select count(*) from public.venue_blackouts k
       where k.venue_id = c_venue and k.date = c_echue_2 and k.slot = 'soir') <> 1 then
    raise exception 'ÉCHEC 5e — une option échue empêche encore la fermeture de la date.';
  end if;

  raise notice 'OK 5 — option échue, cron pas passé : date libre au calendrier, à la recherche, à la demande, à l''acceptation et à la fermeture.';

  -- ===========================================================================
  -- Test 6 — UNE JOURNÉE ENTIÈRE TIENT SES DEUX CRÉNEAUX
  --
  -- Une réservation « journee » occupe midi ET soir (§6.1), en deux lignes.
  -- Une règle écrite sur une seule des deux laisserait vendre la moitié d'une
  -- journée déjà promise — et c'est le genre de trou qui ne se voit qu'au
  -- moment où deux familles se croisent devant la salle.
  -- ===========================================================================
  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_amina, 'role', 'authenticated')::text, true);
  select b.id into v_amina
  from public.request_booking(c_venue, c_journee, 'journee', 250, '0770112233') b
  order by b.slot limit 1;

  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_owner, 'role', 'authenticated')::text, true);
  perform public.accepter_demande(v_amina);

  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_yasmine, 'role', 'authenticated')::text, true);

  -- Les deux créneaux, et la journée entière, sont « reserve » au calendrier.
  select c.state into v_etat
  from public.venue_calendar(c_venue, 'midi', c_journee, c_journee) c
  where c.day = c_journee;
  if v_etat is distinct from 'reserve' then
    raise exception 'ÉCHEC 6 — le MIDI d''une journée sous option est « % ».',
      coalesce(v_etat, 'libre');
  end if;

  select c.state into v_etat
  from public.venue_calendar(c_venue, 'soir', c_journee, c_journee) c
  where c.day = c_journee;
  if v_etat is distinct from 'reserve' then
    raise exception 'ÉCHEC 6 — le SOIR d''une journée sous option est « % ».',
      coalesce(v_etat, 'libre');
  end if;

  -- Et aucune demande ne passe, sur aucun des trois créneaux.
  begin
    perform * from public.request_booking(c_venue, c_journee, 'midi', 200, '0550998877');
    raise exception 'ÉCHEC 6 — le midi d''une journée sous option a été redemandé.';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE001' then
      raise exception 'ÉCHEC 6 — refus attendu FE001 sur le midi, reçu hint=%.',
        coalesce(v_hint, '(vide)');
    end if;
  end;

  begin
    perform * from public.request_booking(c_venue, c_journee, 'soir', 200, '0550998877');
    raise exception 'ÉCHEC 6 — le soir d''une journée sous option a été redemandé.';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE001' then
      raise exception 'ÉCHEC 6 — refus attendu FE001 sur le soir, reçu hint=%.',
        coalesce(v_hint, '(vide)');
    end if;
  end;

  -- Et le propriétaire ne ferme pas cette journée-là.
  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_owner, 'role', 'authenticated')::text, true);
  begin
    perform * from public.bloquer_date(c_venue, c_journee, 'journee', 'Travaux');
    raise exception 'ÉCHEC 6 — une journée sous option de 72 h a été fermée.';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE022' then
      raise exception 'ÉCHEC 6 — refus attendu FE022 sur la journée, reçu hint=%.',
        coalesce(v_hint, '(vide)');
    end if;
  end;

  raise notice 'OK 6 — une journée entière sous option tient ses deux créneaux.';

  -- ===========================================================================
  -- Test 7 — LES DEMANDES « pending » NE BLOQUENT TOUJOURS RIEN (§5.1)
  --
  -- Ce test garde les six autres de trop en faire. « Plusieurs familles peuvent
  -- demander le même 14 août ; le propriétaire arbitre. » Rendre les options
  -- bloquantes ne doit pas, par glissement, rendre les demandes bloquantes : ce
  -- serait donner la date à la première qui clique, et vider l'arbitrage de
  -- Karim de son sens.
  -- ===========================================================================
  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_amina, 'role', 'authenticated')::text, true);
  perform * from public.request_booking(c_venue, c_libre, 'soir', 250, '0770112233');

  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_nadia, 'role', 'authenticated')::text, true);
  perform * from public.request_booking(c_venue, c_libre, 'soir', 180, '0661223344');

  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_yasmine, 'role', 'authenticated')::text, true);

  -- Une troisième passe encore.
  perform * from public.request_booking(c_venue, c_libre, 'soir', 200, '0550998877');

  -- Le calendrier ne dit rien de cette date : elle est libre.
  select c.state into v_etat
  from public.venue_calendar(c_venue, 'soir', c_libre, c_libre) c
  where c.day = c_libre;
  if v_etat is not null then
    raise exception
      'ÉCHEC 7 — le calendrier dit « % » sur une date qui ne porte que des demandes '
      'en attente. Une demande pending ne bloque pas la date (§5.1).', v_etat;
  end if;

  -- Et la recherche la propose toujours.
  select count(*) into v_lignes
  from public.search_venues(p_query => 'Salle de test 010', p_event_date => c_libre,
                            p_slot => 'soir') s
  where s.venue_id = c_venue;
  if v_lignes <> 1 then
    raise exception 'ÉCHEC 7 — trois demandes en attente ont retiré la salle des résultats.';
  end if;

  raise notice 'OK 7 — trois demandes en attente sur la même date, et la date reste libre (§5.1).';

  raise notice 'TOUT EST PASSÉ — une option de 72 h tient la date, et la rend à la minute.';
end $$;

rollback;
