-- =============================================================================
-- Ferha — tests/011_acompte_chargily.sql
--
-- CE QU'ON VÉRIFIE : que la caisse ne s'ouvre QUE pour celui qui doit payer,
-- QUE tant que l'option tient, et TOUJOURS pour le montant qui est en base.
--
-- POURQUOI CE FICHIER EXISTE. L'écran 6 est le seul de l'application où de
-- l'argent change de mains. Trois choses peuvent y mal tourner, et chacune a son
-- test ici :
--
--   * quelqu'un paie pour la réservation d'un autre — ou la regarde ;
--   * quelqu'un paie une date qui n'est plus tenue, et le découvre après ;
--   * la caisse encaisse un montant que personne n'a convenu.
--
-- ET UNE QUATRIÈME, PLUS SOURNOISE : deux pages de paiement ouvertes sur la même
-- réservation. Un double tap, un retour arrière, un onglet rouvert — et deux
-- checkouts courent, dont un seul sera honoré. Le test 6 est celui-là.
--
-- LE MONTANT EST LE CŒUR DU FICHIER (tests 5 et 9). Chargily encaisse des
-- dinars entiers ; `deposit_amount` en porte les centimes. L'arrondi n'a le
-- droit d'exister qu'à UN endroit — montant_acompte() —, et trois lecteurs
-- doivent en sortir le même nombre : l'écran 6 (acompte_a_verser), le bouton de
-- la liste (client_bookings), et l'écriture comptable (enregistrer_checkout).
-- Le test 9 les compare tous les trois sur un acompte à virgule, choisi exprès.
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
-- (lib/features/booking/acompte_messages.dart).
--
-- CE QU'IL LAISSE : rien. Tout est fait dans une transaction annulée à la fin.
--
-- Prérequis : migrations 001 à 024 appliquées.
-- =============================================================================

begin;

-- =============================================================================
-- Tests 1 à 9 — la caisse, ses refus et son montant
-- =============================================================================

do $$
declare
  c_venue   constant uuid := 'c0000011-0000-4000-a000-000000000001';
  c_owner   constant uuid := 'c0000011-0000-4000-a000-000000000002';
  c_amina   constant uuid := 'c0000011-0000-4000-a000-000000000003';
  c_yasmine constant uuid := 'c0000011-0000-4000-a000-000000000004';

  -- Loin dans le futur : aucun risque de croiser une donnée réelle.
  c_option constant date := date '2099-08-14';  -- option en cours, celle d'Amina
  c_echue  constant date := date '2099-08-21';  -- option échue, cron pas passé
  c_attente constant date := date '2099-08-28'; -- demande encore « pending »

  v_amina    uuid;   -- la ligne représentative de la demande acceptée
  v_echue    uuid;
  v_attente  uuid;
  v_groupe   uuid;

  v_hint     text;
  v_acompte  integer;
  v_solde    numeric;
  v_devis    numeric;
  v_depot    numeric;
  v_checkout text;
  v_encours  boolean;
  v_lignes   integer;
  v_statut   text;
  v_montant  numeric;
  v_test     boolean;
  v_methode  text;
  v_liste    integer;
begin
  -- ---------------------------------------------------------------------------
  -- Le décor : une salle à Oran, son propriétaire, deux clientes.
  -- ---------------------------------------------------------------------------
  insert into auth.users (instance_id, id, aud, role, email,
                          encrypted_password, email_confirmed_at,
                          created_at, updated_at,
                          raw_app_meta_data, raw_user_meta_data)
  values
    ('00000000-0000-0000-0000-000000000000', c_owner,   'authenticated', 'authenticated',
     'test.owner.011@ferha.test',   '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb),
    ('00000000-0000-0000-0000-000000000000', c_amina,   'authenticated', 'authenticated',
     'test.amina.011@ferha.test',   '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb),
    ('00000000-0000-0000-0000-000000000000', c_yasmine, 'authenticated', 'authenticated',
     'test.yasmine.011@ferha.test', '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb);

  insert into public.profiles (id, full_name, email, is_owner) values
    (c_owner,   'Karim Propriétaire', 'test.owner.011@ferha.test',   true),
    (c_amina,   'Amina Haddad',       'test.amina.011@ferha.test',   false),
    (c_yasmine, 'Yasmine Belkacem',   'test.yasmine.011@ferha.test', false)
  on conflict (id) do update
    set full_name = excluded.full_name,
        is_owner  = excluded.is_owner;

  insert into public.venues (id, owner_id, name, wilaya_code, commune,
                             capacity_seated, status)
  values (c_venue, c_owner, 'Salle de test 011', '31', 'Oran', 400, 'published');

  insert into public.venue_pricing (venue_id, slot, base_price, weekend_coef,
                                    high_season_coef, included_seats, extra_seat_price)
  values
    (c_venue, 'midi',    100000, 1.30, 1.20, 200, 800),
    (c_venue, 'soir',    200000, 1.30, 1.20, 200, 800),
    (c_venue, 'journee', 280000, 1.30, 1.20, 200, 800);

  -- Amina demande le 14 août au soir, Karim accepte : l'option court.
  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_amina, 'role', 'authenticated')::text, true);
  select b.id into v_amina
  from public.request_booking(c_venue, c_option, 'soir', 250, '0770112233') b
  order by b.slot limit 1;

  -- Une seconde demande, qui restera « pending » — le test 3.
  select b.id into v_attente
  from public.request_booking(c_venue, c_attente, 'soir', 200, '0770112233') b
  order by b.slot limit 1;

  -- Une troisième, acceptée puis vieillie de force — le test 4.
  select b.id into v_echue
  from public.request_booking(c_venue, c_echue, 'soir', 200, '0770112233') b
  order by b.slot limit 1;

  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_owner, 'role', 'authenticated')::text, true);
  perform public.accepter_demande(v_amina);
  perform public.accepter_demande(v_echue);

  -- L'échéance reculée dans le passé, SANS toucher au statut : c'est exactement
  -- l'état d'une option morte que le cron expire-options n'a pas encore rangée.
  -- Le cron passe au quart d'heure ; cet état-là dure donc jusqu'à quinze
  -- minutes en vrai, et c'est précisément la fenêtre qu'on teste.
  update public.bookings
     set option_expires_at = now() - interval '1 hour'
   where id = v_echue;

  select b.group_id into v_groupe from public.bookings b where b.id = v_amina;

  -- ===========================================================================
  -- Test 1 — SANS SESSION, RIEN
  --
  -- auth.uid() vaut null : la fonction ne doit pas aller plus loin. Elle est
  -- SECURITY DEFINER — sans ce garde-fou en tête, elle lirait la réservation de
  -- n'importe qui pour n'importe qui.
  -- ===========================================================================
  perform set_config('request.jwt.claims', '', true);

  begin
    perform public.acompte_a_verser(v_amina);
    raise exception 'ÉCHEC 1 — acompte_a_verser() a répondu SANS SESSION. '
      'La fonction est SECURITY DEFINER : sans session, elle ouvre la '
      'réservation de tout le monde à tout le monde.';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE050' then raise; end if;
  end;

  raise notice 'OK 1 — sans session, FE050.';

  -- ===========================================================================
  -- Test 2 — LA RÉSERVATION D'UNE AUTRE, NI PAYÉE NI MÊME REGARDÉE
  --
  -- Yasmine connaît l'identifiant d'Amina — il suffit d'une adresse copiée. Elle
  -- ne doit obtenir ni le montant, ni le nom de la salle, ni la date.
  --
  -- ET C'EST LE MÊME CODE QU'UNE RÉSERVATION INEXISTANTE (test 2b), à dessein :
  -- deux refus différents apprendraient à un curieux quels identifiants
  -- existent.
  -- ===========================================================================
  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_yasmine, 'role', 'authenticated')::text, true);

  begin
    perform public.acompte_a_verser(v_amina);
    raise exception 'ÉCHEC 2 — YASMINE A OBTENU L''ACOMPTE D''AMINA. '
      'N''importe qui pourrait lire — et payer — la réservation d''un autre.';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE051' then raise; end if;
  end;

  begin
    perform public.acompte_a_verser('c0000011-0000-4000-a000-0000000000ff'::uuid);
    raise exception 'ÉCHEC 2b — une réservation inexistante n''a pas été refusée.';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE051' then
      raise exception 'ÉCHEC 2b — une réservation INEXISTANTE rend « % » là où une '
        'réservation d''un autre rend FE051. Deux codes différents disent à un '
        'curieux lesquels de ses identifiants existent.', coalesce(v_hint, '(aucun)');
    end if;
  end;

  raise notice 'OK 2 — la réservation d''une autre, et une inconnue : FE051 pour les deux.';

  -- ===========================================================================
  -- Test 3 — UNE DEMANDE ENCORE EN ATTENTE N'A PAS D'ACOMPTE
  --
  -- Le propriétaire n'a pas répondu : il n'y a pas de montant convenu, et
  -- `deposit_amount` est NULL. Ouvrir une caisse ici encaisserait un prix que
  -- personne n'a accepté.
  -- ===========================================================================
  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_amina, 'role', 'authenticated')::text, true);

  begin
    perform public.acompte_a_verser(v_attente);
    raise exception 'ÉCHEC 3 — une demande ENCORE EN ATTENTE a ouvert la caisse. '
      'Le propriétaire n''a pas répondu : aucun montant n''est convenu.';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE052' then
      raise exception 'ÉCHEC 3 — une demande « pending » rend « % », attendu FE052. '
        'L''écran doit pouvoir dire « le propriétaire n''a pas encore répondu » '
        'plutôt que « le délai est passé ».', coalesce(v_hint, '(aucun)');
    end if;
  end;

  raise notice 'OK 3 — demande en attente : FE052, et pas un autre code.';

  -- ===========================================================================
  -- Test 4 — UNE OPTION ÉCHUE NE SE PAIE PLUS, TOUT DE SUITE
  --
  -- Le statut vaut encore « accepted » : le cron n'est pas passé. C'est
  -- tient_la_date() (023) qui tranche, en comparant à now() — et c'est pour cela
  -- qu'elle est appelée ici plutôt que recopiée. Payer une date repartie à la
  -- vente est la pire minute du parcours : l'argent part, et la salle est à
  -- quelqu'un d'autre.
  -- ===========================================================================
  begin
    perform public.acompte_a_verser(v_echue);
    raise exception 'ÉCHEC 4 — UNE OPTION ÉCHUE A OUVERT LA CAISSE. '
      'Le statut dit encore « accepted » parce que le cron passe au quart '
      'd''heure ; c''est tient_la_date() qui doit trancher, à la minute.';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE053' then
      raise exception 'ÉCHEC 4 — une option échue rend « % », attendu FE053.',
        coalesce(v_hint, '(aucun)');
    end if;
  end;

  raise notice 'OK 4 — option échue : FE053, sans attendre le cron.';

  -- ===========================================================================
  -- Test 5 — LE MONTANT EST CELUI DE LA BASE, ET LE SOLDE SON COMPLÉMENT
  -- ===========================================================================
  select bg.quoted_amount, bg.deposit_amount
    into v_devis, v_depot
  from public.booking_groups bg where bg.group_id = v_groupe;

  select a.acompte, a.solde, a.checkout_id, a.paiement_en_cours
    into v_acompte, v_solde, v_checkout, v_encours
  from public.acompte_a_verser(v_amina) a;

  if v_acompte is distinct from ceil(v_depot)::integer then
    raise exception 'ÉCHEC 5 — l''acompte annoncé est % alors que la base porte % '
      '(arrondi attendu : %). Le bouton et la caisse ne diraient pas le même '
      'nombre.', v_acompte, v_depot, ceil(v_depot)::integer;
  end if;

  if v_acompte + v_solde is distinct from v_devis then
    raise exception 'ÉCHEC 5b — acompte (%) + solde (%) font % et non le montant '
      'convenu (%). Le client paierait deux fois la même différence, ou jamais.',
      v_acompte, v_solde, v_acompte + v_solde, v_devis;
  end if;

  -- Aucune caisse n'a encore été ouverte : lire l'écran n'en crée pas.
  if v_checkout is not null or v_encours then
    raise exception 'ÉCHEC 5c — acompte_a_verser() annonce un paiement en cours '
      'alors qu''aucune page n''a été ouverte. Lire l''écran 6 ne doit rien créer.';
  end if;

  raise notice 'OK 5 — montant = acompte en base arrondi, solde = complément exact, '
    'aucune caisse ouverte par la simple lecture.';

  -- ===========================================================================
  -- Test 6 — UNE SEULE PAGE ACTIVE PAR RÉSERVATION
  --
  -- C'est la règle du double tap. Trois vérifications :
  --   6a  la première page s'écrit en « pending », en mode test, au bon montant ;
  --   6b  acompte_a_verser() la retrouve — c'est CE checkout_id que la Edge
  --       Function relit chez Chargily au lieu d'en créer un second ;
  --   6c  rejouer le MÊME checkout_id ne crée pas une seconde ligne ;
  --   6d  une page NEUVE éteint la précédente — jamais deux « pending ».
  -- ===========================================================================
  perform public.enregistrer_checkout(v_amina, 'test_011_checkout_a', 'cib');

  select p.status, p.amount, p.is_test, p.method
    into v_statut, v_montant, v_test, v_methode
  from public.payments p where p.checkout_id = 'test_011_checkout_a';

  if v_statut is distinct from 'pending' then
    raise exception 'ÉCHEC 6a — la ligne payments est « % », attendu « pending ». '
      'Seul le webhook a le droit de dire « paid ».', coalesce(v_statut, '(aucune)');
  end if;

  if v_montant is distinct from v_acompte::numeric then
    raise exception 'ÉCHEC 6a — la ligne payments porte % alors que la caisse '
      'encaisse %. La trace comptable mentirait (§4.4, ADM-03).',
      v_montant, v_acompte;
  end if;

  if not v_test then
    raise exception 'ÉCHEC 6a — is_test est faux. Un paiement de démonstration '
      'serait un jour compté comme un vrai encaissement (v2.0, CLI-06).';
  end if;

  if v_methode is distinct from 'cib' then
    raise exception 'ÉCHEC 6a — la méthode enregistrée est « % », attendu « cib ».',
      coalesce(v_methode, '(aucune)');
  end if;
  raise notice 'OK 6a — la page ouverte s''écrit « pending », en mode test, au montant de la base.';

  select a.checkout_id, a.paiement_en_cours into v_checkout, v_encours
  from public.acompte_a_verser(v_amina) a;

  if v_checkout is distinct from 'test_011_checkout_a' or not v_encours then
    raise exception 'ÉCHEC 6b — acompte_a_verser() ne retrouve pas la page déjà '
      'ouverte (checkout_id = %, en cours = %). Le second « Payer » en créerait '
      'une seconde au lieu de rendre la même URL.',
      coalesce(v_checkout, '(aucun)'), v_encours;
  end if;
  raise notice 'OK 6b — la page déjà ouverte est retrouvée : le second « Payer » rend la même.';

  perform public.enregistrer_checkout(v_amina, 'test_011_checkout_a', 'cib');

  select count(*) into v_lignes
  from public.payments p where p.checkout_id = 'test_011_checkout_a';

  if v_lignes <> 1 then
    raise exception 'ÉCHEC 6c — rejouer le même checkout a produit % lignes. '
      'L''écriture doit être idempotente, comme le webhook du J16.', v_lignes;
  end if;
  raise notice 'OK 6c — rejouer le même checkout ne crée pas un second paiement.';

  perform public.enregistrer_checkout(v_amina, 'test_011_checkout_b', 'edahabia');

  select count(*) into v_lignes
  from public.payments p
  join public.bookings b on b.id = p.booking_id
  where b.group_id = v_groupe and p.status = 'pending';

  if v_lignes <> 1 then
    raise exception 'ÉCHEC 6d — % paiements « pending » courent sur la même '
      'réservation. Une page abandonnée doit s''éteindre quand une neuve s''ouvre.',
      v_lignes;
  end if;

  select p.status into v_statut
  from public.payments p where p.checkout_id = 'test_011_checkout_a';
  if v_statut is distinct from 'failed' then
    raise exception 'ÉCHEC 6d — l''ancienne page est restée « % ».',
      coalesce(v_statut, '(disparue)');
  end if;
  raise notice 'OK 6d — une page neuve éteint la précédente : une seule active.';

  -- ===========================================================================
  -- Test 7 — enregistrer_checkout() REFUSE CE QU'ELLE DOIT REFUSER
  --
  -- Elle revérifie l'option, et elle a raison de le faire : entre la lecture par
  -- la Edge Function et son écriture, il s'est écoulé un aller-retour chez
  -- Chargily. Une option peut s'éteindre pendant ce temps-là.
  -- ===========================================================================
  begin
    perform public.enregistrer_checkout(v_amina, 'test_011_checkout_c', 'paypal');
    raise exception 'ÉCHEC 7 — un moyen de paiement inconnu a été accepté.';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE055' then raise; end if;
  end;

  begin
    perform public.enregistrer_checkout(v_amina, 'test_011_checkout_d', 'cash');
    raise exception 'ÉCHEC 7b — « cash » a été accepté ici. Le règlement en '
      'espèces n''a pas de checkout : il viendra avec son propre parcours.';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE055' then raise; end if;
  end;

  begin
    perform public.enregistrer_checkout(v_echue, 'test_011_checkout_e', 'cib');
    raise exception 'ÉCHEC 7c — UNE OPTION ÉCHUE A ÉTÉ ENCAISSÉE. La base est le '
      'dernier rempart : la Edge Function a lu l''option avant l''aller-retour '
      'chez Chargily, elle a pu s''éteindre depuis.';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE053' then raise; end if;
  end;

  raise notice 'OK 7 — moyen inconnu, « cash » et option échue : tous refusés.';

  -- ===========================================================================
  -- Test 8 — LE MONTANT N'EST PAS UN PARAMÈTRE
  --
  -- enregistrer_checkout() ne prend pas de montant : elle le relit. On le
  -- vérifie par sa signature — un paramètre ajouté un jour « pour éviter une
  -- lecture » rouvrirait la porte à un montant venu du dehors.
  -- ===========================================================================
  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'enregistrer_checkout'
      and pg_get_function_arguments(p.oid) ilike '%amount%'
  ) then
    raise exception 'ÉCHEC 8 — enregistrer_checkout() accepte un montant en '
      'paramètre. Le montant doit venir de la base, et d''elle seule.';
  end if;
  raise notice 'OK 8 — enregistrer_checkout() n''accepte aucun montant du dehors.';

  -- ===========================================================================
  -- Test 9 — UN SEUL ARRONDI, TROIS LECTEURS
  --
  -- On force un acompte à virgule — 25 % d'un devis qui ne tombe pas rond — et
  -- on vérifie que l'écran 6, le bouton de la liste et l'écriture comptable
  -- disent tous le MÊME entier. C'est le test qui empêche le « Payer 51 333 DA »
  -- suivi d'une caisse à 51 334.
  -- ===========================================================================
  update public.bookings
     set deposit_amount = 51333.25
   where group_id = v_groupe;

  select a.acompte into v_acompte from public.acompte_a_verser(v_amina) a;

  if v_acompte <> 51334 then
    raise exception 'ÉCHEC 9 — 51 333,25 DA d''acompte donnent % à l''écran 6, '
      'attendu 51 334. L''arrondi doit être au dinar SUPÉRIEUR : le client ne '
      'doit pas verser moins que ce que le propriétaire a accepté.', v_acompte;
  end if;

  select cb.acompte_du into v_liste
  from public.client_bookings() cb where cb.group_id = v_groupe;

  if v_liste is distinct from v_acompte then
    raise exception 'ÉCHEC 9b — le bouton de la liste annoncerait % et l''écran 6 %. '
      'Un dinar d''écart juste avant de payer est un petit mensonge au pire '
      'moment.', v_liste, v_acompte;
  end if;

  perform public.enregistrer_checkout(v_amina, 'test_011_checkout_f', 'cib');
  select p.amount into v_montant
  from public.payments p where p.checkout_id = 'test_011_checkout_f';

  if v_montant is distinct from v_acompte::numeric then
    raise exception 'ÉCHEC 9c — la caisse encaisserait % là où l''écran annonce %.',
      v_montant, v_acompte;
  end if;

  raise notice 'OK 9 — écran 6, bouton de la liste et trace comptable : le même entier.';

  perform set_config('request.jwt.claims', '', true);
end $$;

-- =============================================================================
-- Test 10 — AUCUNE ÉCRITURE CLIENTE SUR payments (§9)
--
-- LE TEST LE PLUS IMPORTANT DU FICHIER, et le seul qui ait besoin d'un vrai
-- changement de rôle : les blocs ci-dessus tournent avec un rôle qui ignore RLS,
-- et écriraient dans payments sans que personne s'y oppose.
--
-- Deux portes à tenir fermées, et non une :
--   10a  la table elle-même — RLS est actif, et il n'y a AUCUNE politique
--        d'INSERT. L'absence n'est pas un oubli, c'est la règle (006).
--   10b  la fonction — enregistrer_checkout() est SECURITY DEFINER : si elle
--        était donnée à « authenticated », l'application pourrait écrire des
--        paiements en passant par-dessus la table.
-- =============================================================================

set local role authenticated;
set local request.jwt.claims = '{"sub":"c0000011-0000-4000-a000-000000000003","role":"authenticated"}';

do $$
declare
  v_booking uuid;
begin
  select b.id into v_booking
  from public.bookings b
  where b.client_id = 'c0000011-0000-4000-a000-000000000003'::uuid
  limit 1;

  -- 10a — la table, en direct.
  begin
    insert into public.payments (booking_id, checkout_id, amount, method, status)
    values (v_booking, 'test_011_fraude', 1, 'cib', 'paid');
    raise exception 'ÉCHEC 10a — UNE CLIENTE A ÉCRIT DANS payments. Le §9 dit '
      '« aucune écriture cliente » : n''importe qui pourrait se déclarer payé.';
  exception
    when insufficient_privilege then null;
    when others then
      if sqlstate <> '42501' then raise; end if;
  end;

  -- 10b — la fonction, qui écrit pour de bon.
  if has_function_privilege('authenticated',
       'public.enregistrer_checkout(uuid, text, text)', 'execute') then
    raise exception 'ÉCHEC 10b — « authenticated » peut exécuter '
      'enregistrer_checkout(). Elle est SECURITY DEFINER : l''application '
      'écrirait alors des paiements en contournant la table.';
  end if;

  if has_function_privilege('anon',
       'public.enregistrer_checkout(uuid, text, text)', 'execute') then
    raise exception 'ÉCHEC 10b — « anon » peut exécuter enregistrer_checkout().';
  end if;

  if not has_function_privilege('service_role',
       'public.enregistrer_checkout(uuid, text, text)', 'execute') then
    raise exception 'ÉCHEC 10c — le service_role ne peut PAS exécuter '
      'enregistrer_checkout(). La Edge Function n''écrirait plus rien.';
  end if;

  raise notice 'OK 10 — payments est fermée en écriture au client, et la fonction '
    'n''est ouverte qu''au service_role.';
end $$;

reset role;

rollback;
