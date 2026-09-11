-- =============================================================================
-- Ferha — tests/009_delais_et_alertes.sql
--
-- CE QU'ON VÉRIFIE, SEPT CHOSES.
--
--   1. UNE OPTION ÉCHUE S'ÉTEINT, ET REND LA DATE. C'est la règle du §5.1, et
--      c'est la seule du projet qui se déclenche toute seule, sans que personne
--      n'appuie sur rien. Personne ne la verra donc échouer en s'en servant :
--      elle n'a que ce test.
--
--   2. CE QUI N'EST PAS ÉCHU NE BOUGE PAS. Une option encore vivante et une
--      réservation confirmée traversent le passage du cron sans rien perdre.
--      C'est l'autre moitié de la règle, et la plus coûteuse à casser : une
--      réservation confirmée effacée, c'est un mariage annulé par un cron.
--
--   3. UNE JOURNÉE ENTIÈRE EXPIRE D'UN BLOC, ET NE PRÉVIENT QU'UNE FOIS. Deux
--      lignes en base, une seule réservation : deux notifications au total — une
--      par partie — et non quatre.
--
--   4. RELANCER NE NOTIFIE PAS DEUX FOIS. La tâche passe toutes les quinze
--      minutes ; si le second passage redéposait les notifications du premier,
--      la cliente recevrait 96 fois par jour l'annonce de la même expiration.
--
--   5. LE PAYLOAD SE SUFFIT À LUI-MÊME. Nom de la salle, date, créneau, et le
--      rôle du destinataire : c'est de là que viennent les textes de l'écran, et
--      rien n'est écrit en dur côté Flutter.
--
--   6. UN COMPTE NE LIT JAMAIS LES NOTIFICATIONS D'UN AUTRE. La seule partie de
--      ce fichier qui ne teste pas une fonction mais une SURFACE : la table est
--      publiée en Realtime, et c'est la politique RLS — elle seule — qui décide
--      de ce qui part vers un abonné.
--
--   7. CHAQUE CHANGEMENT D'ÉTAT NOTIFIE LA BONNE PERSONNE, UNE SEULE FOIS. Les
--      six gestes du §4.1 joués à la suite, et comptés un par un. C'est le seul
--      test qui attrape la notification EN TROP — celle qu'on ajoute « pour être
--      sûr », que personne n'a demandée, et qui ne casse rien en apparence.
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
-- POURQUOI LE TEST 6 CHANGE DE RÔLE. Les tests 1 à 5 appellent des fonctions ;
-- le 6 interroge une TABLE, et ce qui la protège est RLS — laquelle ne
-- s'applique pas au rôle de service avec lequel on colle ce fichier. Sans
-- changer de rôle, il lirait tout et passerait toujours.
--
-- ON N'APPELLE PAS pg_cron ICI. La tâche planifiée ne fait qu'un
-- « select public.expire_options(); » : ce qu'il y a à vérifier est dans la
-- fonction, et attendre quinze minutes pour le voir ne prouverait rien de plus.
-- Que la tâche existe et pointe au bon endroit se lit d'une requête, et le
-- test 0 la fait.
--
-- CE QU'IL LAISSE : rien. Tout est fait dans une transaction annulée à la fin.
--
-- Prérequis : migrations 001 à 022 appliquées.
-- =============================================================================

begin;

-- =============================================================================
-- Test 0 — LES DEUX TÂCHES pg_cron SONT LÀ
--
-- Hors de la transaction de décor : ce test ne regarde que ce qui est déjà en
-- base. Il ne vérifie pas que le cron « marche » — c'est l'affaire de pg_cron —
-- mais qu'il a quelque chose à faire, et que ce quelque chose est la bonne
-- fonction. Une tâche décrochée par erreur ne se voit nulle part ailleurs :
-- l'application continue de tourner, simplement les options n'expirent plus.
-- =============================================================================

do $$
declare
  v_schedule text;
  v_command  text;
begin
  select j.schedule, j.command into v_schedule, v_command
  from cron.job j where j.jobname = 'ferha-expire-options';

  if v_schedule is null then
    raise exception 'ÉCHEC 0a — la tâche « ferha-expire-options » n''existe pas. '
      'Les options de 72 h n''expirent plus (§5.1).';
  end if;

  if v_command not like '%expire_options%' then
    raise exception 'ÉCHEC 0a — « ferha-expire-options » appelle « % », et non expire_options().',
      v_command;
  end if;

  raise notice 'OK 0a — ferha-expire-options : % → %', v_schedule, v_command;

  select j.schedule into v_schedule
  from cron.job j where j.jobname = 'ferha-purge-cron-history';

  if v_schedule is null then
    raise exception 'ÉCHEC 0b — la tâche de purge n''existe pas : cron.job_run_details '
      'grossira sans fin.';
  end if;

  raise notice 'OK 0b — ferha-purge-cron-history : %', v_schedule;
end $$;

-- =============================================================================
-- Le décor, et les tests 1 à 5
--
-- Une salle, son propriétaire, deux clientes, et quatre réservations sur des
-- dates de 2099 — assez loin pour ne croiser aucune donnée réelle :
--
--   ÉCHUE      option de 72 h dépassée d'une heure      → doit expirer
--   VIVANTE    option de 72 h qui court encore          → ne doit pas bouger
--   CONFIRMÉE  acompte versé                            → ne doit pas bouger
--   JOURNÉE    option échue, mais sur les DEUX créneaux → une seule notification
--
-- Les états sont écrits directement, comme dans le seed : accept_booking() et
-- confirm_booking() exigent une session, et un fichier de test pose l'état
-- d'arrivée. Ce qui est testé est ce qui vient APRÈS.
-- =============================================================================

do $$
declare
  c_venue   constant uuid := 'c0000009-0000-4000-a000-000000000001';
  c_owner   constant uuid := 'c0000009-0000-4000-a000-000000000002';
  c_amina   constant uuid := 'c0000009-0000-4000-a000-000000000003';
  c_sofia   constant uuid := 'c0000009-0000-4000-a000-000000000004';

  c_echue     constant uuid := 'c0000009-0000-4000-b000-000000000001';
  c_vivante   constant uuid := 'c0000009-0000-4000-b000-000000000002';
  c_confirmee constant uuid := 'c0000009-0000-4000-b000-000000000003';
  c_journee   constant uuid := 'c0000009-0000-4000-b000-000000000004';

  -- Un jour par réservation : l'agenda se lit case par case, et deux
  -- réservations sur la même case se cacheraient l'une l'autre.
  c_mois      constant date := date '2099-06-01';
  c_j_echue   constant date := date '2099-06-05';
  c_j_vivante constant date := date '2099-06-12';
  c_j_confirm constant date := date '2099-06-19';
  c_j_journee constant date := date '2099-06-26';

  v_expirees integer;
  v_etat     text;
  v_lignes   integer;
  v_payload  jsonb;
begin
  -- ---------------------------------------------------------------------------
  -- Le décor
  -- ---------------------------------------------------------------------------
  insert into auth.users (instance_id, id, aud, role, email,
                          encrypted_password, email_confirmed_at,
                          created_at, updated_at,
                          raw_app_meta_data, raw_user_meta_data)
  values
    ('00000000-0000-0000-0000-000000000000', c_owner, 'authenticated', 'authenticated',
     'test.owner.009@ferha.test', '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb),
    ('00000000-0000-0000-0000-000000000000', c_amina, 'authenticated', 'authenticated',
     'test.amina.009@ferha.test', '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb),
    ('00000000-0000-0000-0000-000000000000', c_sofia, 'authenticated', 'authenticated',
     'test.sofia.009@ferha.test', '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb);

  insert into public.profiles (id, full_name, email, is_owner) values
    (c_owner, 'Karim Propriétaire', 'test.owner.009@ferha.test', true),
    (c_amina, 'Amina Haddad',       'test.amina.009@ferha.test', false),
    (c_sofia, 'Sofia Benali',       'test.sofia.009@ferha.test', false)
  on conflict (id) do update
    set full_name = excluded.full_name,
        is_owner  = excluded.is_owner;

  insert into public.venues (id, owner_id, name, wilaya_code, commune,
                             capacity_seated, status)
  values (c_venue, c_owner, 'Salle de test 009', '31', 'Oran', 500, 'published');

  insert into public.venue_pricing (venue_id, slot, base_price, weekend_coef,
                                    high_season_coef, included_seats, extra_seat_price)
  values
    (c_venue, 'midi',    100000, 1.30, 1.20, 200, 800),
    (c_venue, 'soir',    200000, 1.30, 1.20, 200, 800),
    (c_venue, 'journee', 280000, 1.30, 1.20, 200, 800);

  -- Tout naît en attente, comme dans l'application : quoted_amount est écrasé
  -- par le trigger bookings_set_price, donc par estimate_price().
  insert into public.bookings (
    group_id, venue_id, client_id, event_date, slot, requested_slot,
    guest_count, event_type, quoted_amount
  ) values
    (c_echue,     c_venue, c_amina, c_j_echue,   'soir', 'soir',    300, 'mariage', 0),
    (c_vivante,   c_venue, c_sofia, c_j_vivante, 'soir', 'soir',    250, 'mariage', 0),
    (c_confirmee, c_venue, c_amina, c_j_confirm, 'soir', 'soir',    280, 'mariage', 0),
    -- La journée entière : deux lignes, un seul groupe, une seule réservation.
    (c_journee,   c_venue, c_sofia, c_j_journee, 'midi', 'journee', 400, 'mariage', 0),
    (c_journee,   c_venue, c_sofia, c_j_journee, 'soir', 'journee', 400, 'mariage', 0);

  -- L'acompte se déduit du devis que le trigger vient de poser, et de
  -- deposit_rate() — jamais d'un taux recopié.
  update public.bookings b
     set status            = 'accepted',
         accepted_at       = now() - interval '73 hours',
         option_expires_at = now() - interval '1 hour',
         deposit_amount    = round(b.quoted_amount * public.deposit_rate(), 2)
   where b.group_id in (c_echue, c_journee);

  update public.bookings b
     set status            = 'accepted',
         accepted_at       = now() - interval '2 hours',
         option_expires_at = now() + interval '70 hours',
         deposit_amount    = round(b.quoted_amount * public.deposit_rate(), 2)
   where b.group_id = c_vivante;

  update public.bookings b
     set status            = 'confirmed',
         accepted_at       = now() - interval '80 hours',
         -- Une option dépassée SUR UNE RÉSERVATION DÉJÀ CONFIRMÉE. C'est le
         -- piège que ce décor tend à expire_options() : si elle filtrait sur la
         -- seule échéance, elle emporterait une date payée.
         option_expires_at = now() - interval '8 hours',
         confirmed_at      = now() - interval '70 hours',
         deposit_amount    = round(b.quoted_amount * public.deposit_rate(), 2)
   where b.group_id = c_confirmee;

  -- On part d'une ardoise propre : les notifications comptées plus bas doivent
  -- être celles de l'expiration, pas celles du décor.
  delete from public.notifications n
   where n.user_id in (c_owner, c_amina, c_sofia);

  -- ===========================================================================
  -- Test 1 — L'OPTION ÉCHUE S'ÉTEINT ET REND LA DATE
  -- ===========================================================================
  v_expirees := public.expire_options();

  -- Deux RÉSERVATIONS : l'échue et la journée entière. Pas trois lignes.
  if v_expirees <> 2 then
    raise exception 'ÉCHEC 1a — expire_options() rend % réservations expirées, attendu 2 '
      '(l''option échue et la journée entière). Un décompte par LIGNE en dirait 3.',
      v_expirees;
  end if;
  raise notice 'OK 1a — expire_options() a expiré 2 réservations.';

  select b.status into v_etat
  from public.bookings b where b.group_id = c_echue;

  if v_etat is distinct from 'expired' then
    raise exception 'ÉCHEC 1b — l''option échue est en « % », attendu « expired » (§5.1).',
      coalesce(v_etat, '(rien)');
  end if;
  raise notice 'OK 1b — l''option échue est passée en « expired ».';

  -- La date, vue du propriétaire : la case du 5 juin au soir doit être redevenue
  -- libre. owner_agenda() ne compte que pending, accepted, confirmed et
  -- completed — « expired » n'y prend plus rien.
  --
  -- Le JWT est posé le temps de l'appel : owner_agenda() lit auth.uid() et
  -- refuse un agenda qui n'est pas le sien (FE021). Le rôle SQL, lui, n'y change
  -- rien — c'est le test 6 qui en aura besoin.
  perform set_config('request.jwt.claims',
    json_build_object('sub', c_owner, 'role', 'authenticated')::text, true);

  select a.state into v_etat
  from public.owner_agenda(c_venue, c_mois) a
  where a.day = c_j_echue and a.slot = 'soir';

  perform set_config('request.jwt.claims', '', true);

  if v_etat is distinct from 'libre' then
    raise exception 'ÉCHEC 1c — le 5 juin au soir est « % » dans owner_agenda(), attendu '
      '« libre » : une option échue ne tient plus la date.', coalesce(v_etat, '(rien)');
  end if;
  raise notice 'OK 1c — owner_agenda() rend la case au propriétaire.';

  -- La date, vue du public. NUANCE À CONNAÎTRE : venue_calendar() ne marque
  -- « reserve » que sur confirmed et completed (§5.1 — « une demande pending ne
  -- bloque pas la date », et une option n'est pas un paiement). Ce jour-là
  -- n'apparaissait donc DÉJÀ pas comme pris. Ce qu'on vérifie ici est qu'il ne
  -- le devient pas en expirant : une expiration ne doit rien laisser derrière
  -- elle.
  select c.state into v_etat
  from public.venue_calendar(c_venue, 'soir', c_mois, c_mois + 40) c
  where c.day = c_j_echue;

  if v_etat is not null then
    raise exception 'ÉCHEC 1d — le 5 juin ressort « % » de venue_calendar() : une date '
      'expirée doit être libre pour tout le monde.', v_etat;
  end if;
  raise notice 'OK 1d — venue_calendar() laisse le 5 juin libre.';

  -- ===========================================================================
  -- Test 2 — CE QUI N'EST PAS ÉCHU NE BOUGE PAS
  -- ===========================================================================
  select b.status into v_etat
  from public.bookings b where b.group_id = c_vivante;

  if v_etat is distinct from 'accepted' then
    raise exception 'ÉCHEC 2a — une option qui court encore est passée en « % ». '
      'Le cron a mangé une réservation vivante.', coalesce(v_etat, '(rien)');
  end if;
  raise notice 'OK 2a — l''option encore vivante est intacte.';

  select b.status into v_etat
  from public.bookings b where b.group_id = c_confirmee;

  if v_etat is distinct from 'confirmed' then
    raise exception 'ÉCHEC 2b — une réservation CONFIRMÉE est passée en « % », alors que '
      'son option_expires_at était dépassé. C''est un mariage annulé par un cron.',
      coalesce(v_etat, '(rien)');
  end if;
  raise notice 'OK 2b — la réservation confirmée est intacte, échéance dépassée ou non.';

  select c.state into v_etat
  from public.venue_calendar(c_venue, 'soir', c_mois, c_mois + 40) c
  where c.day = c_j_confirm;

  if v_etat is distinct from 'reserve' then
    raise exception 'ÉCHEC 2c — le 19 juin est « % » dans venue_calendar(), attendu '
      '« reserve » : une date payée reste prise.', coalesce(v_etat, '(rien)');
  end if;
  raise notice 'OK 2c — la date confirmée reste marquée prise.';

  -- ===========================================================================
  -- Test 3 — UNE JOURNÉE ENTIÈRE EXPIRE D'UN BLOC, ET NE PRÉVIENT QU'UNE FOIS
  -- ===========================================================================
  select count(*) into v_lignes
  from public.bookings b
  where b.group_id = c_journee and b.status = 'expired';

  if v_lignes <> 2 then
    raise exception 'ÉCHEC 3a — % ligne(s) de la journée entière sont expirées, attendu 2. '
      'Une journée entière ne s''expire pas à moitié : le midi libéré et le soir tenu, '
      'c''est une date invendable.', v_lignes;
  end if;
  raise notice 'OK 3a — les deux créneaux de la journée entière ont expiré ensemble.';

  -- Deux lignes, UNE réservation : une notification pour la cliente, une pour le
  -- propriétaire. Quatre voudrait dire qu'on notifie par ligne.
  select count(*) into v_lignes
  from public.notifications n
  where n.type = 'booking_expired'
    and n.payload ->> 'group_id' = c_journee::text;

  if v_lignes <> 2 then
    raise exception 'ÉCHEC 3b — la journée entière a produit % notification(s), attendu 2 '
      '(la cliente et le propriétaire, une chacun). 4 = on notifie par ligne.', v_lignes;
  end if;
  raise notice 'OK 3b — la journée entière a prévenu chaque partie une seule fois.';

  -- Et les deux parties, pas deux fois la même.
  select count(*) into v_lignes
  from public.notifications n
  where n.type = 'booking_expired'
    and n.payload ->> 'group_id' = c_journee::text
    and n.user_id in (c_sofia, c_owner);

  if v_lignes <> 2 then
    raise exception 'ÉCHEC 3c — les deux notifications de la journée entière ne vont pas '
      'à la cliente ET au propriétaire. À l''expiration, la date repart à la vente : '
      'celui qui la vend doit l''apprendre.';
  end if;
  raise notice 'OK 3c — la cliente et le propriétaire ont été prévenus tous les deux.';

  -- ===========================================================================
  -- Test 4 — RELANCER NE NOTIFIE PAS DEUX FOIS
  -- ===========================================================================
  select count(*) into v_lignes
  from public.notifications n where n.type = 'booking_expired';

  v_expirees := public.expire_options();

  if v_expirees <> 0 then
    raise exception 'ÉCHEC 4a — un second passage a expiré % réservation(s), attendu 0.',
      v_expirees;
  end if;

  if (select count(*) from public.notifications n where n.type = 'booking_expired')
     <> v_lignes then
    raise exception 'ÉCHEC 4b — un second passage a déposé des notifications de plus. '
      'La tâche passe toutes les 15 minutes : la cliente en recevrait 96 par jour.';
  end if;
  raise notice 'OK 4 — relancer expire_options() ne dépose rien de plus.';

  -- ===========================================================================
  -- Test 5 — LE PAYLOAD SE SUFFIT À LUI-MÊME
  --
  -- C'est de lui que viennent les textes de l'écran. S'il ne portait que deux
  -- identifiants, l'application devrait aller rechercher le nom de la salle —
  -- une requête par ligne — ou l'écrire en dur.
  -- ===========================================================================
  select n.payload into v_payload
  from public.notifications n
  where n.type = 'booking_expired' and n.user_id = c_amina
  limit 1;

  if v_payload ->> 'venue_name' is distinct from 'Salle de test 009' then
    raise exception 'ÉCHEC 5a — le payload porte venue_name = « % », attendu le nom de la '
      'salle. Sans lui, l''écran ne sait pas de quelle salle il parle.',
      coalesce(v_payload ->> 'venue_name', '(absent)');
  end if;

  if (v_payload ->> 'event_date')::date is distinct from c_j_echue then
    raise exception 'ÉCHEC 5b — le payload porte event_date = « % », attendu %.',
      coalesce(v_payload ->> 'event_date', '(absent)'), c_j_echue;
  end if;

  if v_payload ->> 'requested_slot' is distinct from 'soir' then
    raise exception 'ÉCHEC 5c — le payload porte requested_slot = « % », attendu « soir ».',
      coalesce(v_payload ->> 'requested_slot', '(absent)');
  end if;
  raise notice 'OK 5a — le payload porte la salle, la date et le créneau.';

  -- Le rôle : c'est lui qui décide de l'écran d'arrivée. 'booking_confirmed'
  -- part aux DEUX parties ; sans cette clé, l'application devrait deviner
  -- laquelle des deux la touche.
  if v_payload ->> 'role' is distinct from 'client' then
    raise exception 'ÉCHEC 5d — la notification de la cliente porte role = « % », '
      'attendu « client ».', coalesce(v_payload ->> 'role', '(absent)');
  end if;

  select n.payload into v_payload
  from public.notifications n
  where n.type = 'booking_expired' and n.user_id = c_owner
  limit 1;

  if v_payload ->> 'role' is distinct from 'owner' then
    raise exception 'ÉCHEC 5e — la notification du propriétaire porte role = « % », '
      'attendu « owner ». C''est cette clé qui l''envoie sur le détail de la demande '
      'plutôt que sur « Mes réservations ».', coalesce(v_payload ->> 'role', '(absent)');
  end if;
  raise notice 'OK 5b — le rôle du destinataire est écrit dans le payload.';

  -- Et l'identifiant désigne bien une LIGNE existante du groupe — celle
  -- qu'attendent owner_request_detail(), accepter_demande() et refuser_demande().
  if not exists (
    select 1 from public.bookings b
    where b.id = (v_payload ->> 'booking_id')::uuid
      and b.group_id = (v_payload ->> 'group_id')::uuid
  ) then
    raise exception 'ÉCHEC 5f — booking_id ne désigne aucune ligne du groupe : '
      'la notification n''ouvrirait rien.';
  end if;
  raise notice 'OK 5c — booking_id désigne une ligne réelle du groupe.';
end $$;

-- =============================================================================
-- Test 6 — UN COMPTE NE LIT JAMAIS LES NOTIFICATIONS D'UN AUTRE
--
-- Ici on n'appelle plus de fonction de transition : on interroge la table comme
-- le ferait l'application, et c'est RLS qui doit répondre. D'où les changements
-- de rôle — sans eux, ce fichier s'exécute avec un rôle qui ignore RLS, lirait
-- tout et passerait toujours.
--
-- C'EST LE TEST LE PLUS IMPORTANT DU FICHIER. notifications est publiée en
-- Realtime depuis 022 : chaque ligne écrite est proposée à tous les abonnés, et
-- la politique notifications_select_own (006) est le seul filtre qui décide de
-- ce qui part. Une politique relâchée ne se verrait nulle part dans
-- l'application — chacun continuerait de voir sa liste — et enverrait pourtant
-- les demandes des uns sur le téléphone des autres.
-- =============================================================================

-- 6a — la cliente Amina ne voit que les siennes.
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0000009-0000-4000-a000-000000000003","role":"authenticated"}';

do $$
declare
  c_amina constant uuid := 'c0000009-0000-4000-a000-000000000003';
  v_total integer;
  v_autre integer;
begin
  select count(*) into v_total from public.notifications;
  select count(*) into v_autre from public.notifications n where n.user_id <> c_amina;

  if v_autre > 0 then
    raise exception 'ÉCHEC 6a — Amina lit % notification(s) qui ne sont pas les siennes.',
      v_autre;
  end if;

  if v_total = 0 then
    raise exception 'ÉCHEC 6a — Amina ne lit aucune notification, alors qu''elle vient d''en '
      'recevoir une. Le test ne prouverait rien.';
  end if;

  raise notice 'OK 6a — Amina lit ses % notification(s), et rien d''autre.', v_total;
end $$;

-- 6b — mes_notifications() ne déborde pas non plus, et son compteur ne compte
--      que les siennes. La fonction n'est PAS security definer : c'est la même
--      politique qui la borne.
do $$
declare
  c_amina  constant uuid := 'c0000009-0000-4000-a000-000000000003';
  v_lignes integer;
  v_compte bigint;
begin
  select count(*), max(m.non_lues) into v_lignes, v_compte
  from public.mes_notifications() m;

  if v_lignes = 0 then
    raise exception 'ÉCHEC 6b — mes_notifications() ne rend rien à Amina.';
  end if;

  if v_compte <> v_lignes then
    raise exception 'ÉCHEC 6b — mes_notifications() annonce % non lues pour % ligne(s) '
      'rendues. Le compteur déborde sur les notifications d''autrui.', v_compte, v_lignes;
  end if;

  raise notice 'OK 6b — mes_notifications() : % ligne(s), % non lue(s).', v_lignes, v_compte;
end $$;

-- 6c — marquer lu ne franchit pas la frontière non plus. Amina marque tout :
--      seules les siennes doivent changer.
do $$
declare
  c_amina constant uuid := 'c0000009-0000-4000-a000-000000000003';
  v_marquees integer;
begin
  v_marquees := public.marquer_notifications_lues();

  if v_marquees = 0 then
    raise exception 'ÉCHEC 6c — « Tout marquer comme lu » n''a rien marqué.';
  end if;

  if exists (select 1 from public.mes_notifications() m where m.read_at is null) then
    raise exception 'ÉCHEC 6c — Amina garde des non lues après avoir tout marqué.';
  end if;

  -- Idempotence : le second appel ne doit plus rien trouver.
  if public.marquer_notifications_lues() <> 0 then
    raise exception 'ÉCHEC 6c — un second « Tout marquer » réécrit des dates de lecture.';
  end if;

  raise notice 'OK 6c — Amina a marqué ses % notification(s), et pas une de plus.',
    v_marquees;
end $$;

reset role;

-- 6d — et le propriétaire, lui, a toujours la sienne, non lue. C'est la preuve
--      que le « tout marquer » d'Amina ne l'a pas touché.
do $$
declare
  c_owner constant uuid := 'c0000009-0000-4000-a000-000000000002';
  v_lignes integer;
begin
  select count(*) into v_lignes
  from public.notifications n
  where n.user_id = c_owner and n.read_at is null;

  if v_lignes = 0 then
    raise exception 'ÉCHEC 6d — le « Tout marquer comme lu » d''Amina a marqué lues les '
      'notifications du propriétaire.';
  end if;

  raise notice 'OK 6d — le propriétaire garde ses % notification(s) non lue(s).', v_lignes;
end $$;

-- 6e — un inconnu non connecté ne lit rien du tout.
set local role anon;
set local request.jwt.claims = '';

do $$
declare v_lignes integer;
begin
  select count(*) into v_lignes from public.notifications;

  if v_lignes <> 0 then
    raise exception 'ÉCHEC 6e — un visiteur non connecté lit % notification(s).', v_lignes;
  end if;

  raise notice 'OK 6e — un visiteur non connecté ne lit aucune notification.';
end $$;

reset role;

-- =============================================================================
-- Test 7 — L'AUDIT DES SIX CHANGEMENTS D'ÉTAT
--
-- « Chacun doit notifier la bonne personne, une seule fois. » Les six gestes du
-- §4.1 sont joués l'un après l'autre, comme l'application les enchaîne, et
-- chacun est compté juste après :
--
--   nouvelle demande     → le propriétaire, 1
--   acceptation          → la cliente,      1
--   contre-proposition   → la cliente,      1   (§5.2, accept_booking)
--   refus                → la cliente,      1
--   confirmation         → les DEUX,        1 chacun
--   annulation           → l'AUTRE partie,  1
--   expiration           → les DEUX,        1 chacun (test 3 ci-dessus)
--
-- DEUX PIÈGES QUE CE TEST TEND, ET QU'AUCUN AUTRE NE TEND :
--
--   * LE JOUR OÙ QUELQU'UN NOTIFIERA « POUR ÊTRE SÛR ». Prévenir aussi
--     l'auteur du geste — la cliente de sa propre demande, le propriétaire de
--     sa propre réponse — est l'erreur la plus naturelle du monde, et la plus
--     invisible : tout marche, il y a seulement une notification de trop, que
--     personne n'a demandée. Le compte l'attrape.
--
--   * LA JOURNÉE ENTIÈRE, ENCORE. request_booking() insère deux lignes ; le
--     propriétaire ne doit recevoir qu'une demande.
--
-- Le décor est effacé entre chaque geste : on compte ce que le geste vient de
-- produire, jamais l'accumulation depuis le début — c'est ce qui rend le nombre
-- attendu lisible en le relisant.
-- =============================================================================

do $$
declare
  c_venue constant uuid := 'c0000009-0000-4000-c000-000000000001';
  c_owner constant uuid := 'c0000009-0000-4000-c000-000000000002';
  c_amina constant uuid := 'c0000009-0000-4000-c000-000000000003';

  v_simple  uuid;  -- une demande sur le seul créneau du soir
  v_journee uuid;  -- une demande sur la journée entière : deux lignes
  v_refusee uuid;

  -- Compte les notifications d'un type pour CE décor, puis fait table rase.
  -- Écrit en toutes lettres à chaque geste plutôt que dans une fonction : un
  -- test qui appelle un assistant qu'il a lui-même écrit n'est plus tout à fait
  -- un test.
  v_n integer;
begin
  insert into auth.users (instance_id, id, aud, role, email,
                          encrypted_password, email_confirmed_at,
                          created_at, updated_at,
                          raw_app_meta_data, raw_user_meta_data)
  values
    ('00000000-0000-0000-0000-000000000000', c_owner, 'authenticated', 'authenticated',
     'test.audit.owner.009@ferha.test', '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb),
    ('00000000-0000-0000-0000-000000000000', c_amina, 'authenticated', 'authenticated',
     'test.audit.amina.009@ferha.test', '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb);

  insert into public.profiles (id, full_name, email, is_owner) values
    (c_owner, 'Karim Propriétaire', 'test.audit.owner.009@ferha.test', true),
    (c_amina, 'Amina Haddad',       'test.audit.amina.009@ferha.test', false)
  on conflict (id) do update
    set full_name = excluded.full_name, is_owner = excluded.is_owner;

  insert into public.venues (id, owner_id, name, wilaya_code, commune,
                             capacity_seated, status)
  values (c_venue, c_owner, 'Salle de l''audit', '31', 'Oran', 500, 'published');

  insert into public.venue_pricing (venue_id, slot, base_price, weekend_coef,
                                    high_season_coef, included_seats, extra_seat_price)
  values
    (c_venue, 'midi',    100000, 1.30, 1.20, 200, 800),
    (c_venue, 'soir',    200000, 1.30, 1.20, 200, 800),
    (c_venue, 'journee', 280000, 1.30, 1.20, 200, 800);

  delete from public.notifications n where n.user_id in (c_owner, c_amina);

  -- --- 1. NOUVELLE DEMANDE ---------------------------------------------------
  perform set_config('request.jwt.claims',
    json_build_object('sub', c_amina, 'role', 'authenticated')::text, true);

  select b.id into v_simple
  from public.request_booking(c_venue, current_date + 200, 'soir', 300,
                              '0770112233', 'mariage') b
  order by b.slot limit 1;

  select count(*) into v_n from public.notifications n
   where n.user_id = c_owner and n.type = 'booking_requested';
  if v_n <> 1 then
    raise exception 'ÉCHEC 7a — une nouvelle demande a produit % notification(s) pour le '
      'propriétaire, attendu 1.', v_n;
  end if;

  if exists (select 1 from public.notifications n
              where n.user_id = c_amina and n.type = 'booking_requested') then
    raise exception 'ÉCHEC 7a — la cliente a été prévenue de sa propre demande.';
  end if;
  raise notice 'OK 7a — nouvelle demande : le propriétaire, une fois.';

  delete from public.notifications n where n.user_id in (c_owner, c_amina);

  -- --- 1bis. LA MÊME, SUR UNE JOURNÉE ENTIÈRE --------------------------------
  select b.id into v_journee
  from public.request_booking(c_venue, current_date + 210, 'journee', 400,
                              '0770112233', 'mariage') b
  order by b.slot limit 1;

  select count(*) into v_n from public.notifications n
   where n.user_id = c_owner and n.type = 'booking_requested';
  if v_n <> 1 then
    raise exception 'ÉCHEC 7b — une journée entière a produit % notification(s), attendu 1. '
      'Deux lignes en base, mais une seule demande.', v_n;
  end if;
  raise notice 'OK 7b — une journée entière ne s''annonce qu''une fois.';

  delete from public.notifications n where n.user_id in (c_owner, c_amina);

  -- --- 2. ACCEPTATION --------------------------------------------------------
  perform set_config('request.jwt.claims',
    json_build_object('sub', c_owner, 'role', 'authenticated')::text, true);

  perform public.accepter_demande(v_simple);

  select count(*) into v_n from public.notifications n
   where n.user_id = c_amina and n.type = 'booking_answered'
     and n.payload ->> 'status' = 'accepted';
  if v_n <> 1 then
    raise exception 'ÉCHEC 7c — l''acceptation a produit % notification(s) pour la cliente, '
      'attendu 1.', v_n;
  end if;

  if exists (select 1 from public.notifications n
              where n.user_id = c_owner and n.type = 'booking_answered') then
    raise exception 'ÉCHEC 7c — le propriétaire a été prévenu de sa propre réponse.';
  end if;
  raise notice 'OK 7c — acceptation : la cliente, une fois.';

  delete from public.notifications n where n.user_id in (c_owner, c_amina);

  -- --- 3. CONTRE-PROPOSITION (§5.2) ------------------------------------------
  -- Elle n'a pas encore d'écran, mais elle a déjà son chemin : accept_booking()
  -- avec un montant. Elle passe donc par la même notification que l'acceptation
  -- — une seule, à la cliente — et ce test est là pour que cela reste vrai le
  -- jour où l'écran arrivera.
  perform public.accept_booking(v_journee, 50000, 190000);

  select count(*) into v_n from public.notifications n
   where n.user_id = c_amina and n.type = 'booking_answered';
  if v_n <> 1 then
    raise exception 'ÉCHEC 7d — la contre-proposition a produit % notification(s), attendu 1.',
      v_n;
  end if;
  raise notice 'OK 7d — contre-proposition : la cliente, une fois.';

  delete from public.notifications n where n.user_id in (c_owner, c_amina);

  -- --- 4. CONFIRMATION — LES DEUX PARTIES ------------------------------------
  perform public.confirm_booking(v_simple);

  select count(*) into v_n from public.notifications n
   where n.user_id in (c_owner, c_amina) and n.type = 'booking_confirmed';
  if v_n <> 2 then
    raise exception 'ÉCHEC 7e — la confirmation a produit % notification(s), attendu 2 — '
      'une par partie.', v_n;
  end if;

  if (select n.payload ->> 'role' from public.notifications n
       where n.user_id = c_owner and n.type = 'booking_confirmed') is distinct from 'owner'
  or (select n.payload ->> 'role' from public.notifications n
       where n.user_id = c_amina and n.type = 'booking_confirmed') is distinct from 'client'
  then
    raise exception 'ÉCHEC 7e — la confirmation part aux deux parties avec le même rôle : '
      'elles atterriraient sur le même écran, et l''une des deux sur le mauvais.';
  end if;
  raise notice 'OK 7e — confirmation : les deux parties, chacune avec son rôle.';

  delete from public.notifications n where n.user_id in (c_owner, c_amina);

  -- --- 5. REFUS --------------------------------------------------------------
  perform set_config('request.jwt.claims',
    json_build_object('sub', c_amina, 'role', 'authenticated')::text, true);

  select b.id into v_refusee
  from public.request_booking(c_venue, current_date + 220, 'soir', 200,
                              '0770112233', 'mariage') b limit 1;

  delete from public.notifications n where n.user_id in (c_owner, c_amina);

  perform set_config('request.jwt.claims',
    json_build_object('sub', c_owner, 'role', 'authenticated')::text, true);

  perform public.refuser_demande(v_refusee, 'La salle est déjà promise ce soir-là.');

  select count(*) into v_n from public.notifications n
   where n.user_id = c_amina and n.type = 'booking_answered'
     and n.payload ->> 'status' = 'refused';
  if v_n <> 1 then
    raise exception 'ÉCHEC 7f — le refus a produit % notification(s) pour la cliente, '
      'attendu 1.', v_n;
  end if;
  raise notice 'OK 7f — refus : la cliente, une fois.';

  delete from public.notifications n where n.user_id in (c_owner, c_amina);

  -- --- 6. ANNULATION — ON PRÉVIENT L'AUTRE, PAS CELUI QUI CLIQUE -------------
  perform set_config('request.jwt.claims',
    json_build_object('sub', c_amina, 'role', 'authenticated')::text, true);

  perform public.cancel_booking(v_journee, 'Changement de date.');

  select count(*) into v_n from public.notifications n
   where n.user_id in (c_owner, c_amina) and n.type = 'booking_cancelled';
  if v_n <> 1 then
    raise exception 'ÉCHEC 7g — l''annulation a produit % notification(s), attendu 1.', v_n;
  end if;

  if (select n.user_id from public.notifications n where n.type = 'booking_cancelled'
       and n.user_id in (c_owner, c_amina)) is distinct from c_owner then
    raise exception 'ÉCHEC 7g — l''annulation prévient la cliente qui vient d''annuler, et '
      'pas le propriétaire dont la date se libère.';
  end if;
  raise notice 'OK 7g — annulation : l''autre partie, une fois.';

  perform set_config('request.jwt.claims', '', true);
end $$;

rollback;
