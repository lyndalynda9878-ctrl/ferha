-- =============================================================================
-- Ferha — tests/004_agenda_proprietaire.sql
--
-- CE QU'ON VÉRIFIE, TROIS CHOSES, ET LA TROISIÈME EST LA PLUS IMPORTANTE :
--
--   1. LA PROPRIÉTÉ. owner_agenda(), bloquer_date() et debloquer_date() sont
--      SECURITY DEFINER : elles s'exécutent avec les droits du propriétaire de
--      la fonction, RLS comprise. Si leur garde-fou tombait, n'importe quel
--      compte connecté fermerait l'agenda de n'importe qui — et l'application
--      Flutter, qui ne cache que des boutons, n'y verrait rien.
--
--   2. LE REFUS DE FERMER UNE DATE VENDUE. Une option de 72 h ou une
--      réservation confirmée arrête bloquer_date() (FE022). C'est la règle qui
--      protège le client : on ne ferme pas une date sur la tête de quelqu'un qui
--      a versé son acompte.
--
--   3. LE MOTIF NE SORT PAS. venue_blackouts.reason est la note privée du
--      propriétaire — « travaux », « mariage de ma fille ». Ce test le vérifie
--      de trois façons : la vue venue_availability n'a pas la colonne, un client
--      connecté ne lit pas la table, un inconnu non plus. C'est la seule partie
--      de ce fichier qui ne teste pas une fonction mais une SURFACE : elle
--      resterait vraie si les trois fonctions disparaissaient, et elle doit être
--      vérifiée à chaque fois qu'on touche à la vue.
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
-- POURQUOI DES « set local role » DANS LA SECONDE MOITIÉ. Les tests 1 à 5
-- appellent des fonctions dont le garde-fou lit `auth.uid()` : poser le JWT
-- suffit, le rôle SQL n'y change rien. Le test 6, lui, interroge une TABLE, et
-- ce qui la protège est RLS — laquelle ne s'applique pas au rôle de service
-- avec lequel on colle ce fichier. Sans changer de rôle, le test lirait tout et
-- passerait toujours : il ne prouverait rien.
--
-- CE QU'IL LAISSE : rien. Tout est fait dans une transaction annulée à la fin.
--
-- Prérequis : migrations 001 à 016 appliquées.
-- =============================================================================

begin;

do $$
declare
  c_venue    constant uuid := 'c0000004-0000-4000-a000-000000000001';
  c_owner    constant uuid := 'c0000004-0000-4000-a000-000000000002';
  c_intrus   constant uuid := 'c0000004-0000-4000-a000-000000000003';
  c_client   constant uuid := 'c0000004-0000-4000-a000-000000000004';

  -- Loin dans le futur : aucun risque de croiser une donnée réelle. Le 1er est
  -- pris pour ancrer le mois — owner_agenda() tronque au mois, et un test qui
  -- se lance le 31 ne doit pas changer de résultat.
  c_mois     constant date := date '2099-08-01';
  c_libre    constant date := date '2099-08-05';
  c_ferme    constant date := date '2099-08-08';
  c_demande  constant date := date '2099-08-14';
  c_option   constant date := date '2099-08-21';
  c_confirme constant date := date '2099-08-28';

  v_sqlstate text;
  v_hint     text;
  v_etat     text;
  v_motif    text;
  v_lignes   integer;
  v_id       uuid;
begin
  -- ---------------------------------------------------------------------------
  -- Le décor : une salle, son propriétaire, un intrus qui en est un aussi,
  -- une cliente, et un mois d'août 2099 avec un exemplaire de chaque état.
  -- ---------------------------------------------------------------------------
  insert into auth.users (instance_id, id, aud, role, email,
                          encrypted_password, email_confirmed_at,
                          created_at, updated_at,
                          raw_app_meta_data, raw_user_meta_data)
  values
    ('00000000-0000-0000-0000-000000000000', c_owner,  'authenticated', 'authenticated',
     'test.owner.004@ferha.test',  '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb),
    ('00000000-0000-0000-0000-000000000000', c_intrus, 'authenticated', 'authenticated',
     'test.intrus.004@ferha.test', '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb),
    ('00000000-0000-0000-0000-000000000000', c_client, 'authenticated', 'authenticated',
     'test.client.004@ferha.test', '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb);

  insert into public.profiles (id, full_name, email, is_owner) values
    (c_owner,  'Karim Propriétaire', 'test.owner.004@ferha.test',  true),
    (c_intrus, 'Intrus Malveillant', 'test.intrus.004@ferha.test', true),
    (c_client, 'Amina Haddad',       'test.client.004@ferha.test', false)
  -- DO UPDATE, ET NON DO NOTHING. Le déclencheur de 007 crée déjà un profil à
  -- l'insertion dans auth.users, avec un nom déduit de l'e-mail — ici
  -- « test.client.004 ». Un DO NOTHING garderait celui-là, et le test 5, qui
  -- vérifie que le client apparaît abrégé en « Amina H. », échouerait sur le
  -- décor et non sur la règle.
  on conflict (id) do update
    set full_name = excluded.full_name,
        is_owner  = excluded.is_owner;

  insert into public.venues (id, owner_id, name, wilaya_code, commune,
                             capacity_seated, status)
  values (c_venue, c_owner, 'Salle de test 004', '31', 'Oran', 400, 'published');

  insert into public.venue_pricing (venue_id, slot, base_price, weekend_coef,
                                    high_season_coef, included_seats, extra_seat_price)
  values
    (c_venue, 'midi',    100000, 1.30, 1.20, 200, 800),
    (c_venue, 'soir',    200000, 1.30, 1.20, 200, 800),
    (c_venue, 'journee', 280000, 1.30, 1.20, 200, 800);

  -- ---------------------------------------------------------------------------
  -- Test 1 — un propriétaire qui n'est pas le bon ne peut RIEN
  --
  -- L'intrus est lui aussi propriétaire, et connecté. Ce qui doit l'arrêter
  -- n'est pas son rôle, c'est que la salle n'est pas la sienne.
  -- ---------------------------------------------------------------------------
  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_intrus, 'role', 'authenticated')::text,
                     true);

  begin
    perform * from public.owner_agenda(c_venue, c_mois);
    raise exception 'ÉCHEC 1 — un inconnu a lu l''agenda d''une salle qui n''est pas la sienne.';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE021' then
      raise exception 'ÉCHEC 1 — refus attendu FE021 sur owner_agenda, reçu hint=% sqlstate=%.',
        coalesce(v_hint, '(vide)'), v_sqlstate;
    end if;
  end;

  begin
    perform * from public.bloquer_date(c_venue, c_libre, 'soir', 'Je ferme la salle d''un autre');
    raise exception 'ÉCHEC 1 — UN INCONNU A FERMÉ UNE DATE DANS L''AGENDA D''UN AUTRE.';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE021' then
      raise exception 'ÉCHEC 1 — refus attendu FE021 sur bloquer_date, reçu hint=% sqlstate=%.',
        coalesce(v_hint, '(vide)'), v_sqlstate;
    end if;
  end;

  begin
    perform * from public.debloquer_date(c_venue, c_libre, 'soir');
    raise exception 'ÉCHEC 1 — un inconnu a rouvert une date dans l''agenda d''un autre.';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE021' then
      raise exception 'ÉCHEC 1 — refus attendu FE021 sur debloquer_date, reçu hint=% sqlstate=%.',
        coalesce(v_hint, '(vide)'), v_sqlstate;
    end if;
  end;

  if (select count(*) from public.venue_blackouts k where k.venue_id = c_venue) <> 0 then
    raise exception 'ÉCHEC 1 — une fermeture a été écrite malgré le refus.';
  end if;

  raise notice 'OK 1 — un propriétaire étranger est refusé partout (FE021, sqlstate %), et rien n''est écrit.',
    v_sqlstate;

  -- ---------------------------------------------------------------------------
  -- Test 2 — sans session, rien non plus
  --
  -- Le cas n'est pas théorique : la clé anon suffit à appeler une fonction
  -- PostgREST, et c'est le SQL qui doit dire non.
  -- ---------------------------------------------------------------------------
  perform set_config('request.jwt.claims', '', true);

  begin
    perform * from public.bloquer_date(c_venue, c_libre, 'soir', null);
    raise exception 'ÉCHEC 2 — une fermeture est passée sans session.';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE020' then
      raise exception 'ÉCHEC 2 — refus attendu FE020, reçu hint=% sqlstate=%.',
        coalesce(v_hint, '(vide)'), v_sqlstate;
    end if;
  end;

  raise notice 'OK 2 — sans session : FE020, sqlstate % (donc HTTP 401).', v_sqlstate;

  -- ---------------------------------------------------------------------------
  -- Le propriétaire prend la main, et remplit son mois d'août 2099.
  -- ---------------------------------------------------------------------------
  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_owner, 'role', 'authenticated')::text,
                     true);

  -- Une demande en attente : elle ne bloque rien (§5.1), mais elle se voit.
  insert into public.bookings (venue_id, client_id, event_date, slot, requested_slot,
                               guest_count, quoted_amount, status)
  values (c_venue, c_client, c_demande, 'soir', 'soir', 250, 0, 'pending');

  -- Une option de 72 h.
  insert into public.bookings (venue_id, client_id, event_date, slot, requested_slot,
                               guest_count, quoted_amount, deposit_amount, status,
                               option_expires_at)
  values (c_venue, c_client, c_option, 'soir', 'soir', 250, 0, 40000, 'accepted',
          now() + interval '72 hours');

  -- Une réservation confirmée.
  insert into public.bookings (venue_id, client_id, event_date, slot, requested_slot,
                               guest_count, quoted_amount, deposit_amount, status)
  values (c_venue, c_client, c_confirme, 'soir', 'soir', 250, 0, 50000, 'confirmed');

  -- ---------------------------------------------------------------------------
  -- Test 3 — fermer une date libre, la relire, la rouvrir
  -- ---------------------------------------------------------------------------
  perform * from public.bloquer_date(c_venue, c_ferme, 'soir', '  Travaux de peinture  ');

  select k.reason into v_motif
  from public.venue_blackouts k
  where k.venue_id = c_venue and k.date = c_ferme and k.slot = 'soir';

  -- btrim : les blancs autour d'un motif ne sont pas le motif.
  if v_motif is distinct from 'Travaux de peinture' then
    raise exception 'ÉCHEC 3 — motif enregistré « % » au lieu de « Travaux de peinture ».',
      coalesce(v_motif, '(vide)');
  end if;

  -- Refermer le même créneau corrige le motif, sans échouer.
  perform * from public.bloquer_date(c_venue, c_ferme, 'soir', 'Mariage de ma fille');

  select count(*), max(k.reason) into v_lignes, v_motif
  from public.venue_blackouts k
  where k.venue_id = c_venue and k.date = c_ferme and k.slot = 'soir';

  if v_lignes <> 1 then
    raise exception 'ÉCHEC 3 — % ligne(s) de fermeture pour un seul créneau.', v_lignes;
  end if;
  if v_motif is distinct from 'Mariage de ma fille' then
    raise exception 'ÉCHEC 3 — le motif n''a pas été corrigé : %.', coalesce(v_motif, '(vide)');
  end if;

  raise notice 'OK 3 — fermeture, motif nettoyé, et refermeture qui corrige au lieu d''échouer.';

  -- ---------------------------------------------------------------------------
  -- Test 4 — ON NE FERME PAS UNE DATE VENDUE
  --
  -- Le cœur du fichier avec le test 6. Une option de 72 h et une réservation
  -- confirmée arrêtent toutes deux la fermeture, et RIEN n'est écrit.
  -- ---------------------------------------------------------------------------
  begin
    perform * from public.bloquer_date(c_venue, c_confirme, 'soir', 'Travaux');
    raise exception
      'ÉCHEC 4 — UNE DATE CONFIRMÉE A ÉTÉ FERMÉE. Le client a versé son acompte, '
      'et la salle se dit fermée ce jour-là.';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE022' then
      raise exception 'ÉCHEC 4 — refus attendu FE022 sur une confirmée, reçu hint=% sqlstate=%.',
        coalesce(v_hint, '(vide)'), v_sqlstate;
    end if;
  end;

  begin
    perform * from public.bloquer_date(c_venue, c_option, 'soir', 'Travaux');
    raise exception 'ÉCHEC 4 — une date sous option de 72 h a été fermée.';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE022' then
      raise exception 'ÉCHEC 4 — refus attendu FE022 sur une option, reçu hint=% sqlstate=%.',
        coalesce(v_hint, '(vide)'), v_sqlstate;
    end if;
  end;

  -- Une JOURNÉE dont un seul créneau est vendu ne se ferme pas non plus — et
  -- surtout, elle ne se ferme pas À MOITIÉ. Le midi du 28 est libre ; si la
  -- fonction écrivait avant de vérifier, il resterait fermé après l'échec.
  begin
    perform * from public.bloquer_date(c_venue, c_confirme, 'journee', 'Travaux');
    raise exception 'ÉCHEC 4 — une journée dont le soir est vendu a été fermée.';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE022' then
      raise exception 'ÉCHEC 4 — refus attendu FE022 sur la journée, reçu hint=%.',
        coalesce(v_hint, '(vide)');
    end if;
  end;

  if (select count(*) from public.venue_blackouts k
       where k.venue_id = c_venue and k.date = c_confirme) <> 0 then
    raise exception
      'ÉCHEC 4 — la journée a été fermée à moitié : le midi porte une fermeture '
      'alors que l''appel a échoué sur le soir.';
  end if;

  -- Une demande EN ATTENTE, elle, n'empêche rien : elle n'a bloqué aucune date.
  perform * from public.bloquer_date(c_venue, c_demande, 'soir', 'Je ferme quand même');
  if (select count(*) from public.venue_blackouts k
       where k.venue_id = c_venue and k.date = c_demande and k.slot = 'soir') <> 1 then
    raise exception 'ÉCHEC 4 — une demande en attente a empêché une fermeture (§5.1).';
  end if;

  raise notice 'OK 4 — option et confirmée refusées (FE022, sqlstate %), journée non fermée à moitié, demande en attente sans effet.',
    v_sqlstate;

  -- ---------------------------------------------------------------------------
  -- Test 5 — l'agenda : une grille complète, cinq états, la bonne priorité
  -- ---------------------------------------------------------------------------

  -- Une ligne par jour et par créneau, août compris : 31 × 2.
  select count(*) into v_lignes from public.owner_agenda(c_venue, c_mois);
  if v_lignes <> 62 then
    raise exception 'ÉCHEC 5 — l''agenda rend % lignes au lieu de 62 (31 jours × 2 créneaux).',
      v_lignes;
  end if;

  -- Un jour sans rien est libre, et il l'est dans les deux créneaux.
  select a.state into v_etat from public.owner_agenda(c_venue, c_mois) a
   where a.day = c_libre and a.slot = 'soir';
  if v_etat is distinct from 'libre' then
    raise exception 'ÉCHEC 5 — un jour sans rien est « % » au lieu de « libre ».', v_etat;
  end if;

  select a.state, a.reason into v_etat, v_motif from public.owner_agenda(c_venue, c_mois) a
   where a.day = c_ferme and a.slot = 'soir';
  if v_etat is distinct from 'ferme' or v_motif is distinct from 'Mariage de ma fille' then
    raise exception 'ÉCHEC 5 — le créneau fermé est « % » (motif « % »).',
      v_etat, coalesce(v_motif, '(vide)');
  end if;
  -- Le midi du même jour n'a rien : on ne ferme pas plus que ce qu'on ferme.
  select a.state into v_etat from public.owner_agenda(c_venue, c_mois) a
   where a.day = c_ferme and a.slot = 'midi';
  if v_etat is distinct from 'libre' then
    raise exception 'ÉCHEC 5 — fermer le soir a fermé le midi (« % »).', v_etat;
  end if;

  select a.state, a.client_name into v_etat, v_motif from public.owner_agenda(c_venue, c_mois) a
   where a.day = c_option and a.slot = 'soir';
  if v_etat is distinct from 'option' then
    raise exception 'ÉCHEC 5 — l''option de 72 h est « % ».', v_etat;
  end if;
  -- Le nom du client est abrégé, comme dans la file du tableau de bord (014).
  if v_motif is distinct from 'Amina H.' then
    raise exception 'ÉCHEC 5 — le client apparaît comme « % » au lieu de « Amina H. ».',
      coalesce(v_motif, '(vide)');
  end if;

  select a.state, a.booking_id into v_etat, v_id from public.owner_agenda(c_venue, c_mois) a
   where a.day = c_confirme and a.slot = 'soir';
  if v_etat is distinct from 'confirme' then
    raise exception 'ÉCHEC 5 — la confirmée est « % ».', v_etat;
  end if;
  if v_id is null then
    raise exception 'ÉCHEC 5 — la confirmée ne porte pas d''identifiant : l''écran ne peut pas l''ouvrir.';
  end if;

  -- LA PRIORITÉ. Le 14 porte une demande en attente ET une fermeture (test 4).
  -- C'est « ferme » qui s'affiche — une décision déjà prise passe devant une
  -- demande qui n'engage rien — et la case n'ouvre donc rien.
  select a.state, a.booking_id into v_etat, v_id from public.owner_agenda(c_venue, c_mois) a
   where a.day = c_demande and a.slot = 'soir';
  if v_etat is distinct from 'ferme' then
    raise exception 'ÉCHEC 5 — un créneau fermé qui porte une demande s''affiche « % ».', v_etat;
  end if;
  if v_id is not null then
    raise exception 'ÉCHEC 5 — un créneau affiché « ferme » porte un identifiant de demande.';
  end if;

  -- On rouvre, et la demande reparaît : rien n'a été perdu en chemin.
  perform * from public.debloquer_date(c_venue, c_demande, 'soir');
  select a.state, a.booking_id into v_etat, v_id from public.owner_agenda(c_venue, c_mois) a
   where a.day = c_demande and a.slot = 'soir';
  if v_etat is distinct from 'demande' or v_id is null then
    raise exception 'ÉCHEC 5 — après réouverture, le créneau est « % » (id %).',
      v_etat, coalesce(v_id::text, 'null');
  end if;

  raise notice 'OK 5 — 62 lignes, cinq états, « ferme » devant « demande », et la demande retrouvée après réouverture.';

  -- Le décor du test 6 : une fermeture avec un motif bien reconnaissable.
  perform * from public.bloquer_date(c_venue, c_libre, 'soir',
                                     'MOTIF-SECRET-004 fête de famille');
end $$;

-- =============================================================================
-- Test 6 — LE MOTIF NE SORT PAS
--
-- Ici on n'appelle plus de fonction : on interroge la vue et la table comme le
-- ferait l'application, et c'est RLS qui doit répondre. D'où les changements de
-- rôle — sans eux, ce fichier s'exécute avec un rôle qui ignore RLS, lirait tout
-- et passerait toujours.
-- =============================================================================

-- 6a — la vue n'a pas la colonne. C'est la première ligne de défense, et la
-- seule qui tienne même si une politique était mal écrite un jour.
do $$
declare v_colonnes text;
begin
  select string_agg(c.column_name, ', ' order by c.ordinal_position) into v_colonnes
  from information_schema.columns c
  where c.table_schema = 'public' and c.table_name = 'venue_availability';

  if v_colonnes is distinct from 'venue_id, date, slot' then
    raise exception
      'ÉCHEC 6a — venue_availability expose « % ». Elle ne doit exposer que '
      'venue_id, date, slot : c''est une vue SANS RLS, tout ce qu''elle porte est public.',
      coalesce(v_colonnes, '(aucune)');
  end if;

  raise notice 'OK 6a — venue_availability n''expose que venue_id, date, slot.';
end $$;

-- 6b — un client connecté voit la date bloquée, jamais le motif.
set local role authenticated;
set local request.jwt.claims = '{"sub":"c0000004-0000-4000-a000-000000000004","role":"authenticated"}';

do $$
declare
  c_venue constant uuid := 'c0000004-0000-4000-a000-000000000001';
  v_vues  integer;
  v_lues  integer;
begin
  -- Ce qu'elle DOIT voir : le créneau est pris, c'est ce qu'elle vient chercher.
  select count(*) into v_vues from public.venue_availability a
   where a.venue_id = c_venue and a.date = date '2099-08-05';
  if v_vues <> 1 then
    raise exception
      'ÉCHEC 6b — la cliente ne voit pas que le 5 août est bloqué (% ligne(s)). '
      'La vue est censée être publique.', v_vues;
  end if;

  -- Ce qu'elle NE DOIT PAS voir : la table, et donc le motif.
  select count(*) into v_lues from public.venue_blackouts k where k.venue_id = c_venue;
  if v_lues <> 0 then
    raise exception
      'ÉCHEC 6b — UNE CLIENTE LIT venue_blackouts (% ligne(s)) : le motif du '
      'propriétaire est sorti.', v_lues;
  end if;

  raise notice 'OK 6b — connectée : la date bloquée se voit, le motif reste dans la table.';
end $$;

reset role;

-- 6c — un inconnu, non connecté : même chose.
set local role anon;
set local request.jwt.claims = '';

do $$
declare
  c_venue constant uuid := 'c0000004-0000-4000-a000-000000000001';
  v_vues  integer;
  v_lues  integer;
begin
  select count(*) into v_vues from public.venue_availability a
   where a.venue_id = c_venue and a.date = date '2099-08-05';
  if v_vues <> 1 then
    raise exception
      'ÉCHEC 6c — un visiteur non connecté ne voit pas le calendrier (% ligne(s)). '
      'La consultation se fait sans compte (§3).', v_vues;
  end if;

  select count(*) into v_lues from public.venue_blackouts k where k.venue_id = c_venue;
  if v_lues <> 0 then
    raise exception
      'ÉCHEC 6c — UN INCONNU LIT venue_blackouts (% ligne(s)).', v_lues;
  end if;

  raise notice 'OK 6c — anonyme : la date bloquée se voit, le motif reste dans la table.';
end $$;

reset role;

-- 6d — et le motif ne sort pas non plus par le calendrier client.
do $$
declare
  c_venue   constant uuid := 'c0000004-0000-4000-a000-000000000001';
  v_etat     text;
  v_resultat text;
begin
  perform set_config('request.jwt.claims',
                     '{"sub":"c0000004-0000-4000-a000-000000000004","role":"authenticated"}',
                     true);

  select c.state into v_etat
  from public.venue_calendar(c_venue, 'soir', date '2099-08-05', date '2099-08-05') c
  where c.day = date '2099-08-05';

  if v_etat is distinct from 'indisponible' then
    raise exception 'ÉCHEC 6d — venue_calendar() dit « % » pour un créneau fermé.',
      coalesce(v_etat, '(rien)');
  end if;

  -- Et elle ne rend QUE (day, state) : pas de colonne où un motif pourrait se
  -- glisser. On lit sa signature plutôt que de la supposer — une fonction n'a
  -- pas de ligne dans information_schema.columns, un test écrit là-dessus
  -- passerait toujours sans rien vérifier.
  select pg_get_function_result(p.oid) into v_resultat
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'venue_calendar';

  if v_resultat is distinct from 'TABLE(day date, state text)' then
    raise exception 'ÉCHEC 6d — venue_calendar() rend maintenant « % ».',
      coalesce(v_resultat, '(inconnue)');
  end if;

  raise notice 'OK 6d — venue_calendar() dit « indisponible », et ne rend que (day, state).';
end $$;

rollback;
