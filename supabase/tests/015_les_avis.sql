-- =============================================================================
-- Ferha — tests/015_les_avis.sql
--
-- CE QU'ON VÉRIFIE : qu'un avis reste ce que le §5.4 en dit — la trace d'une
-- soirée qui a eu lieu, écrite par celui qui l'a payée, dans le mois qui suit,
-- une seule fois, et figée dès que le propriétaire a répondu.
--
-- POURQUOI CE FICHIER EXISTE. Un avis est la seule chose de cette application
-- qu'un inconnu lit AVANT de décider. C'est donc la seule qu'il vaille la peine
-- de truquer, et chaque règle ci-dessous ferme une façon de le faire :
--
--   * sans réservation honorée, pas d'avis         — le faux avis de concurrent ;
--   * hors de J+1 → J+30, pas d'avis               — l'avis écrit d'avance ;
--   * un événement, un avis                        — la journée entière, qui
--     porte DEUX lignes de bookings (§6.1) et donnerait deux avis à qui s'en
--     tiendrait à la contrainte du §5.4 ;
--   * figé après la réponse                        — l'avis réécrit sous une
--     réponse qui ne veut alors plus rien dire.
--
-- LE TEST 8 EST LE PLUS IMPORTANT POUR LA VIE PRIVÉE. « Le nom entier ne sort
-- pas » : `profiles` est fermée, et `avis_de_la_salle()` est SECURITY DEFINER —
-- c'est-à-dire la seule fonction du projet qui puisse la lire pour le compte
-- d'un inconnu. Si elle laissait passer `full_name`, chaque avis publierait le
-- nom complet de quelqu'un qui s'est marié tel jour à tel endroit, et rien à
-- l'écran ne le signalerait.
--
-- LE TEST 9 EST LE PLUS IMPORTANT POUR LE CLASSEMENT. Une salle avec un seul
-- 5/5 ne doit pas dépasser une salle à quarante 4,6 : c'est écrit noir sur blanc
-- au §5.4, et une moyenne simple y contreviendrait sans qu'aucun écran ne
-- paraisse cassé.
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
-- LES DATES SONT RELATIVES À AUJOURD'HUI, contrairement aux autres fichiers de
-- ce dossier, qui réservent en 2099. Elles n'ont pas le choix : toute la règle
-- testée ici se compte en jours écoulés DEPUIS l'événement.
--
-- CE QU'IL LAISSE : rien. Tout est annulé à la fin.
--
-- Prérequis : migrations 001 à 026 appliquées.
-- =============================================================================

begin;

do $$
declare
  c_venue   constant uuid := 'c0000015-0000-4000-a000-000000000001';
  c_owner   constant uuid := 'c0000015-0000-4000-a000-000000000002';
  c_amina   constant uuid := 'c0000015-0000-4000-a000-000000000003';
  c_yasmine constant uuid := 'c0000015-0000-4000-a000-000000000004';
  c_karim2  constant uuid := 'c0000015-0000-4000-a000-000000000005';
  c_venue2  constant uuid := 'c0000015-0000-4000-a000-000000000006';

  -- Les deux salles du test de classement (§5.4).
  c_solo    constant uuid := 'c0000015-0000-4000-a000-000000000007';
  c_quar    constant uuid := 'c0000015-0000-4000-a000-000000000008';

  v_futur      uuid;
  v_accepte    uuid;
  v_hier       uuid;
  v_vieux      uuid;
  v_du_jour    uuid;
  v_midi       uuid;
  v_soir       uuid;
  v_groupe     uuid;
  v_avis       public.reviews;
  v_avis_id    uuid;
  v_hint       text;
  v_statut     text;
  v_lignes     integer;
  v_notifs     integer;
  v_json       jsonb;
  v_texte      text;
  v_auteur     text;
  v_note_solo  numeric;
  v_note_quar  numeric;
  v_brute_solo numeric;
  v_brute_quar numeric;
  v_rang_solo  integer;
  v_rang_quar  integer;
  v_ligne      record;
begin
  -- ---------------------------------------------------------------------------
  -- Le décor : une salle, son propriétaire, deux clientes, et deux intrus —
  -- une cliente qui n'a rien à voir, et le propriétaire d'une AUTRE salle.
  -- ---------------------------------------------------------------------------
  insert into auth.users (instance_id, id, aud, role, email,
                          encrypted_password, email_confirmed_at,
                          created_at, updated_at,
                          raw_app_meta_data, raw_user_meta_data)
  values
    ('00000000-0000-0000-0000-000000000000', c_owner,   'authenticated', 'authenticated',
     'test.owner.015@ferha.test',   '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb),
    ('00000000-0000-0000-0000-000000000000', c_amina,   'authenticated', 'authenticated',
     'test.amina.015@ferha.test',   '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb),
    ('00000000-0000-0000-0000-000000000000', c_yasmine, 'authenticated', 'authenticated',
     'test.yasmine.015@ferha.test', '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb),
    ('00000000-0000-0000-0000-000000000000', c_karim2,  'authenticated', 'authenticated',
     'test.karim2.015@ferha.test',  '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb);

  insert into public.profiles (id, full_name, email, phone, is_owner) values
    (c_owner,   'Karim Propriétaire', 'test.owner.015@ferha.test',   '0770000001', true),
    -- LE NOM ENTIER ET LE NUMÉRO SONT ICI POUR LE TEST 8 : c'est eux qu'on
    -- cherchera, en clair, dans ce que lit un inconnu.
    (c_amina,   'Amina Haddad',       'test.amina.015@ferha.test',   '0770112233', false),
    (c_yasmine, 'Yasmine Belkacem',   'test.yasmine.015@ferha.test', '0770445566', false),
    (c_karim2,  'Autre propriétaire', 'test.karim2.015@ferha.test',  '0770000002', true)
  on conflict (id) do update
    set full_name = excluded.full_name,
        phone     = excluded.phone,
        is_owner  = excluded.is_owner;

  insert into public.venues (id, owner_id, name, wilaya_code, commune,
                             capacity_seated, status)
  values
    (c_venue,  c_owner,  'Salle de test 015',   '31', 'Oran',        400, 'published'),
    (c_venue2, c_karim2, 'Salle d''un autre',   '31', 'Oran',        300, 'published'),
    (c_solo,   c_owner,  'Salle au seul 5 sur 5', '31', 'Testville015', 200, 'published'),
    (c_quar,   c_owner,  'Salle aux quarante avis', '31', 'Testville015', 200, 'published');

  insert into public.venue_pricing (venue_id, slot, base_price, weekend_coef,
                                    high_season_coef, included_seats, extra_seat_price)
  select v.id, s.slot, 100000, 1.30, 1.20, 200, 800
  from (values (c_venue), (c_venue2), (c_solo), (c_quar)) as v(id),
       (values ('midi'), ('soir'), ('journee')) as s(slot);

  -- ---------------------------------------------------------------------------
  -- Les réservations. Écrites en direct, et non par request_booking() : celle-ci
  -- refuse une date passée (FE003), et tout ce fichier parle d'événements qui ont
  -- déjà eu lieu. Le prix reste celui d'estimate_price() — le trigger de 005
  -- l'écrase à l'insertion, quel que soit le chemin.
  -- ---------------------------------------------------------------------------
  insert into public.bookings (venue_id, client_id, event_date, slot,
                               requested_slot, guest_count, event_type,
                               status, deposit_amount)
  values
    -- L'événement n'a pas encore eu lieu.
    (c_venue, c_amina, current_date + 30, 'soir', 'soir', 250, 'mariage', 'confirmed', 50000),
    -- Acceptée, jamais payée : rien à honorer.
    (c_venue, c_amina, current_date -  2, 'soir', 'soir', 250, 'mariage', 'accepted',  50000),
    -- Le mariage d'avant-hier : le cas nominal.
    (c_venue, c_amina, current_date -  3, 'soir', 'soir', 250, 'mariage', 'confirmed', 50000),
    -- Quarante jours : la fenêtre est passée.
    (c_venue, c_amina, current_date - 40, 'soir', 'soir', 250, 'mariage', 'confirmed', 50000),
    -- Ce soir : la fenêtre n'est pas encore ouverte.
    (c_venue, c_amina, current_date,      'soir', 'soir', 250, 'mariage', 'confirmed', 50000);

  select b.id into v_futur   from public.bookings b
   where b.client_id = c_amina and b.event_date = current_date + 30;
  select b.id into v_accepte from public.bookings b
   where b.client_id = c_amina and b.event_date = current_date - 2;
  select b.id into v_hier    from public.bookings b
   where b.client_id = c_amina and b.event_date = current_date - 3;
  select b.id into v_vieux   from public.bookings b
   where b.client_id = c_amina and b.event_date = current_date - 40;
  select b.id into v_du_jour from public.bookings b
   where b.client_id = c_amina and b.event_date = current_date;

  -- Les deux dernières sont honorées d'office : ce qu'on y teste est la fenêtre,
  -- pas la transition.
  update public.bookings set status = 'completed', completed_at = now()
   where id in (v_vieux, v_du_jour);

  -- LA JOURNÉE ENTIÈRE, EN DEUX LIGNES (§6.1). UN SEUL group_id, midi et soir —
  -- et il est tiré dans une variable, pas dans le SELECT : `gen_random_uuid()`
  -- est volatile, il donnerait un identifiant par ligne, donc deux groupes d'une
  -- ligne chacun. Le trigger bookings_check_journee (005) refuserait l'insertion,
  -- et il aurait raison.
  v_groupe := gen_random_uuid();

  insert into public.bookings (group_id, venue_id, client_id, event_date, slot,
                               requested_slot, guest_count, event_type,
                               status, deposit_amount)
  select v_groupe, c_venue, c_amina, current_date - 5, s.slot,
         'journee', 300, 'mariage', 'completed', 70000
  from (values ('midi'), ('soir')) as s(slot);

  select b.id into v_midi from public.bookings b
   where b.client_id = c_amina and b.event_date = current_date - 5 and b.slot = 'midi';
  select b.id into v_soir from public.bookings b
   where b.client_id = c_amina and b.event_date = current_date - 5 and b.slot = 'soir';

  -- ===========================================================================
  -- Test 1 — MARQUER HONORÉ : QUI, ET QUAND
  --
  -- Sans ce geste, aucun avis n'est possible : c'est le premier des deux bouts
  -- que la migration 026 recolle. Trois refus, puis le geste lui-même.
  -- ===========================================================================
  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_yasmine, 'role', 'authenticated')::text, true);
  begin
    perform public.complete_booking(v_hier);
    raise exception 'ÉCHEC 1 — UNE CLIENTE A MARQUÉ HONORÉE LA RÉSERVATION D''UNE '
      'AUTRE. Le geste appartient au propriétaire de la salle, et à lui seul.';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE071' then raise; end if;
  end;

  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_karim2, 'role', 'authenticated')::text, true);
  begin
    perform public.complete_booking(v_hier);
    raise exception 'ÉCHEC 1b — LE PROPRIÉTAIRE D''UNE AUTRE SALLE A MARQUÉ '
      'HONORÉE une réservation qui ne le concerne pas.';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE071' then raise; end if;
  end;

  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_owner, 'role', 'authenticated')::text, true);

  begin
    perform public.complete_booking(v_accepte);
    raise exception 'ÉCHEC 1c — une demande simplement acceptée a été marquée '
      'honorée. Personne n''a payé, et l''avis se débloquerait.';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE072' then raise; end if;
  end;

  begin
    perform public.complete_booking(v_futur);
    raise exception 'ÉCHEC 1d — UN MARIAGE À VENIR A ÉTÉ MARQUÉ HONORÉ. On ne '
      'marque pas honoré ce qui n''a pas eu lieu.';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE073' then raise; end if;
  end;

  perform public.complete_booking(v_hier);

  select b.status into v_statut from public.bookings b where b.id = v_hier;
  if v_statut is distinct from 'completed' then
    raise exception 'ÉCHEC 1e — la réservation est restée « % ».', v_statut;
  end if;

  select count(*) into v_notifs
  from public.notifications n
  where n.user_id = c_amina and n.type = 'review_invitation';

  if v_notifs <> 1 then
    raise exception 'ÉCHEC 1f — la cliente a reçu % invitation(s) à déposer un '
      'avis, attendu 1. Sans elle, personne ne lui demande rien.', v_notifs;
  end if;

  raise notice 'OK 1 — seul le propriétaire marque honoré, seulement une '
    'réservation confirmée, seulement après l''événement — et le client est '
    'invité une fois.';

  -- ===========================================================================
  -- Test 2 — PAS DE RÉSERVATION HONORÉE, PAS D'AVIS
  --
  -- La règle anti-faux-avis du §5.4. Sans elle, un concurrent note une salle où
  -- il n'a jamais mis les pieds.
  -- ===========================================================================
  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_amina, 'role', 'authenticated')::text, true);

  begin
    perform public.deposer_avis(v_accepte, 5);
    raise exception 'ÉCHEC 2 — UN AVIS A ÉTÉ DÉPOSÉ SUR UNE RÉSERVATION NON '
      'HONORÉE. C''est la règle anti-faux-avis du §5.4, et elle vient de tomber.';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE076' then raise; end if;
  end;

  -- Et pas davantage sur la réservation de quelqu'un d'autre.
  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_yasmine, 'role', 'authenticated')::text, true);
  begin
    perform public.deposer_avis(v_hier, 1);
    raise exception 'ÉCHEC 2b — UNE CLIENTE A NOTÉ LA SOIRÉE D''UNE AUTRE.';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE075' then raise; end if;
  end;

  raise notice 'OK 2 — pas de réservation honorée, pas d''avis ; et pas l''avis '
    'du voisin.';

  -- ===========================================================================
  -- Test 3 — LA FENÊTRE DE J+1 À J+30
  --
  -- Avant, l'avis est prématuré ; après, il n'est plus de première main. Les
  -- deux bornes viennent de fenetre_avis(), et d'elle seule depuis 026.
  -- ===========================================================================
  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_amina, 'role', 'authenticated')::text, true);

  begin
    perform public.deposer_avis(v_du_jour, 5);
    raise exception 'ÉCHEC 3 — UN AVIS A ÉTÉ DÉPOSÉ LE SOIR MÊME. La fenêtre du '
      '§5.4 s''ouvre à J+1 : la salle n''est même pas rangée.';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE077' then raise; end if;
  end;

  begin
    perform public.deposer_avis(v_vieux, 5);
    raise exception 'ÉCHEC 3b — un avis a été déposé quarante jours après. La '
      'fenêtre se ferme à J+30.';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE077' then raise; end if;
  end;

  -- L'ÉCRAN NE S'OUVRE PAS NON PLUS, et il dit pourquoi avec le même code.
  begin
    perform public.avis_a_deposer(v_vieux);
    raise exception 'ÉCHEC 3c — l''écran de dépôt s''ouvre sur un événement hors '
      'fenêtre et sans avis à relire. Il n''aurait rien à y montrer.';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE077' then raise; end if;
  end;

  -- LA POLITIQUE DE 006 TIENT LA MÊME LIGNE. Elle est la ceinture sous la
  -- fonction : les deux comparent les mêmes bornes depuis 026.
  if public.avis_dans_la_fenetre(current_date)
     or public.avis_dans_la_fenetre(current_date - 40) then
    raise exception 'ÉCHEC 3d — avis_dans_la_fenetre() dit oui le jour même ou '
      'quarante jours après. La politique reviews_insert_client s''appuie '
      'dessus : elle laisserait passer une écriture directe.';
  end if;

  if not public.avis_dans_la_fenetre(current_date - 3) then
    raise exception 'ÉCHEC 3e — avis_dans_la_fenetre() dit non trois jours '
      'après. Plus personne ne pourrait déposer d''avis.';
  end if;

  raise notice 'OK 3 — la fenêtre J+1 → J+30 tient des deux côtés, et la '
    'politique de 006 lit les mêmes bornes que la fonction.';

  -- ===========================================================================
  -- Test 4 — LA NOTE GLOBALE EST OBLIGATOIRE, LES QUATRE AUTRES NON
  -- ===========================================================================
  begin
    perform public.deposer_avis(v_hier, null);
    raise exception 'ÉCHEC 4 — un avis sans note globale est passé.';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE079' then raise; end if;
  end;

  begin
    perform public.deposer_avis(v_hier, 6);
    raise exception 'ÉCHEC 4b — une note de 6 sur 5 est passée.';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE079' then raise; end if;
  end;

  begin
    perform public.deposer_avis(v_hier, 4, 9);
    raise exception 'ÉCHEC 4c — une sous-note de 9 sur 5 est passée.';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE079' then raise; end if;
  end;

  -- La note globale seule suffit : les quatre sous-notes sont facultatives
  -- (§4.2, CLI-08).
  select * into v_avis from public.deposer_avis(v_hier, 4);

  if v_avis.rating <> 4 or v_avis.rating_cleanliness is not null then
    raise exception 'ÉCHEC 4d — l''avis à la seule note globale n''est pas '
      'ressorti tel quel.';
  end if;

  raise notice 'OK 4 — la note globale est exigée et bornée à 1–5, les quatre '
    'sous-notes restent facultatives.';

  -- ===========================================================================
  -- Test 5 — CORRIGER N'EST PAS DÉPOSER UN SECOND AVIS (§5.4)
  -- ===========================================================================
  select * into v_avis from public.deposer_avis(v_hier, 5, 5, 4, 4, 5,
                                '  Salle impeccable, le personnel a tout installé la veille.  ');
  v_avis_id := v_avis.id;

  select count(*) into v_lignes
  from public.reviews r
  join public.bookings b on b.id = r.booking_id
  where b.client_id = c_amina and b.event_date = current_date - 3;

  if v_lignes <> 1 then
    raise exception 'ÉCHEC 5 — % avis pour une seule soirée. Corriger a créé '
      'une seconde ligne.', v_lignes;
  end if;

  if v_avis.rating <> 5 or v_avis.rating_service <> 4 then
    raise exception 'ÉCHEC 5b — la correction n''a pas pris.';
  end if;

  if v_avis.body <> 'Salle impeccable, le personnel a tout installé la veille.' then
    raise exception 'ÉCHEC 5c — le commentaire n''a pas été détouré de ses '
      'espaces : « % ».', v_avis.body;
  end if;

  if v_avis.venue_id is distinct from c_venue then
    raise exception 'ÉCHEC 5d — L''AVIS PORTE SUR UNE AUTRE SALLE QUE SA '
      'RÉSERVATION. Le garde-fou de reviews_guard (004) ne tient plus.';
  end if;

  raise notice 'OK 5 — l''avis se corrige tant que personne n''a répondu, sans '
    'jamais se dédoubler.';

  -- ===========================================================================
  -- Test 6 — UN ÉVÉNEMENT, UN AVIS — Y COMPRIS UNE JOURNÉE ENTIÈRE
  --
  -- Une journée, c'est DEUX lignes de bookings (§6.1), donc deux booking_id
  -- pour un seul mariage. Qui s'en tiendrait au « booking_id UNIQUE » du §5.4
  -- laisserait passer deux avis sur la même fête.
  -- ===========================================================================
  select b.group_id into v_groupe from public.bookings b where b.id = v_midi;

  select * into v_avis from public.deposer_avis(v_midi, 5, null, null, null, null, 'Journée parfaite.');

  -- Le même geste, par l'autre créneau du même jour.
  select * into v_avis from public.deposer_avis(v_soir, 3, null, null, null, null, 'Tout compte fait, moyen.');

  select count(*) into v_lignes
  from public.reviews r where r.booking_group_id = v_groupe;

  if v_lignes <> 1 then
    raise exception 'ÉCHEC 6 — % avis pour UNE journée entière. Le mariage du '
      '% en a reçu un par créneau.', v_lignes, current_date - 5;
  end if;

  if v_avis.rating <> 3 then
    raise exception 'ÉCHEC 6b — le second appel n''a pas corrigé le premier.';
  end if;

  -- ET LA BASE LE REFUSE MÊME SANS PASSER PAR LA FONCTION. C'est
  -- booking_group_id, UNIQUE depuis 004, qui ferme la brèche : aucune politique
  -- ni aucune fonction ne peut la rouvrir.
  begin
    insert into public.reviews (booking_id, booking_group_id, venue_id, rating)
    values (v_soir, v_groupe, c_venue, 5);
    raise exception 'ÉCHEC 6c — UN SECOND AVIS EST ENTRÉ EN DIRECT SUR LA MÊME '
      'JOURNÉE. La contrainte UNIQUE de booking_group_id a disparu.';
  exception when unique_violation then
    null;
  end;

  raise notice 'OK 6 — une journée entière donne un avis et un seul, par la '
    'fonction comme par la table.';

  -- ===========================================================================
  -- Test 7 — LE DROIT DE RÉPONSE : UNE FOIS, PAR SON PROPRIÉTAIRE, ET APRÈS
  --          QUOI L'AVIS EST FIGÉ (§4.3 OWN-06, §5.4)
  -- ===========================================================================
  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_karim2, 'role', 'authenticated')::text, true);
  begin
    perform public.repondre_a_un_avis(v_avis_id, 'Merci pour votre visite.');
    raise exception 'ÉCHEC 7 — LE PROPRIÉTAIRE D''UNE AUTRE SALLE A RÉPONDU À '
      'UN AVIS QUI NE LE CONCERNE PAS. Il parlerait au nom d''un concurrent, '
      'sous sa signature.';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE081' then raise; end if;
  end;

  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_amina, 'role', 'authenticated')::text, true);
  begin
    perform public.repondre_a_un_avis(v_avis_id, 'Je me réponds à moi-même.');
    raise exception 'ÉCHEC 7b — LA CLIENTE A RÉPONDU À SON PROPRE AVIS, sous '
      'l''étiquette « Réponse du propriétaire ».';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE081' then raise; end if;
  end;

  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_owner, 'role', 'authenticated')::text, true);

  begin
    perform public.repondre_a_un_avis(v_avis_id, '    ');
    raise exception 'ÉCHEC 7c — une réponse vide a été publiée.';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE083' then raise; end if;
  end;

  select * into v_avis from public.repondre_a_un_avis(v_avis_id,
              'Merci Amina. Nous avons ajouté deux climatiseurs en septembre.');

  if v_avis.owner_replied_at is null then
    raise exception 'ÉCHEC 7d — la réponse n''est pas horodatée. C''est '
      'reviews_guard (004) qui s''en charge, et il ne l''a pas fait.';
  end if;

  begin
    perform public.repondre_a_un_avis(v_avis_id, 'Je me ravise.');
    raise exception 'ÉCHEC 7e — UNE SECONDE RÉPONSE A ÉTÉ PUBLIÉE. Le §4.3 en '
      'donne une, et une réponse réécrite après coup ne vaut rien.';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE082' then raise; end if;
  end;

  -- ET L'AVIS EST FIGÉ. Sans quoi la réponse deviendrait incompréhensible :
  -- « merci d'avoir signalé la climatisation » sous un avis qui n'en parle plus.
  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_amina, 'role', 'authenticated')::text, true);
  begin
    perform public.deposer_avis(v_hier, 1, null, null, null, null, 'Finalement non.');
    raise exception 'ÉCHEC 7f — L''AVIS A ÉTÉ RÉÉCRIT APRÈS LA RÉPONSE DU '
      'PROPRIÉTAIRE (§5.4).';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE078' then raise; end if;
  end;

  -- Et pas davantage en écrivant dans la table : reviews_guard (004) est la
  -- ceinture sous la fonction.
  begin
    update public.reviews set rating = 1 where id = v_avis_id;
    raise exception 'ÉCHEC 7g — un UPDATE direct a réécrit un avis figé.';
  exception when check_violation then
    null;
  end;

  raise notice 'OK 7 — une seule réponse, par le propriétaire de la salle, et '
    'l''avis est figé dès qu''elle est posée.';

  -- ===========================================================================
  -- Test 8 — L'ANONYMAT (§9 ; maquettes, écran 7)
  --
  -- « Sarah B. », jamais le nom entier, jamais l'e-mail, jamais le téléphone.
  -- On regarde le JSON ENTIER, en texte : c'est la seule façon d'attraper une
  -- clé ajoutée un jour « pour l'affichage » et oubliée ensuite.
  -- ===========================================================================
  perform set_config('request.jwt.claims', '', true);   -- un inconnu, non connecté

  v_json  := public.avis_de_la_salle(c_venue);
  v_texte := v_json::text;

  if v_texte like '%Amina Haddad%' then
    raise exception 'ÉCHEC 8 — LE NOM ENTIER D''UNE CLIENTE SORT DANS LES AVIS '
      'PUBLICS. Chaque avis publierait qui s''est marié, quand et où.';
  end if;

  if v_texte like '%test.amina.015@ferha.test%' or v_texte like '%0770112233%' then
    raise exception 'ÉCHEC 8b — UN E-MAIL OU UN TÉLÉPHONE DE CLIENTE SORT DANS '
      'LES AVIS PUBLICS (§9).';
  end if;

  select a ->> 'author' into v_auteur
  from jsonb_array_elements(v_json -> 'reviews') a
  where (a ->> 'id')::uuid = v_avis_id;

  if v_auteur is distinct from 'Amina H.' then
    raise exception 'ÉCHEC 8c — l''auteur s''affiche « % », attendu « Amina H. ».',
      coalesce(v_auteur, '(rien)');
  end if;

  -- LA LISTE EST BIEN CELLE DE LA SALLE, et la plus récente en tête.
  if jsonb_array_length(v_json -> 'reviews') <> 2 then
    raise exception 'ÉCHEC 8d — % avis rendus pour cette salle, attendu 2.',
      jsonb_array_length(v_json -> 'reviews');
  end if;

  if (v_json ->> 'review_count')::integer <> 2 then
    raise exception 'ÉCHEC 8e — review_count dit %, la liste en montre 2.',
      v_json ->> 'review_count';
  end if;

  -- LA RÉPONSE DU PROPRIÉTAIRE EST LÀ, SOUS SON AVIS.
  select a ->> 'owner_reply' into v_texte
  from jsonb_array_elements(v_json -> 'reviews') a
  where (a ->> 'id')::uuid = v_avis_id;

  if v_texte is null or v_texte not like 'Merci Amina%' then
    raise exception 'ÉCHEC 8f — la réponse du propriétaire ne ressort pas avec '
      'son avis.';
  end if;

  raise notice 'OK 8 — un inconnu lit « Amina H. » et la réponse du '
    'propriétaire, et rien d''autre de la cliente.';

  -- ===========================================================================
  -- Test 9 — UN SEUL 5/5 NE DÉPASSE PAS QUARANTE 4,6 (§5.4)
  --
  -- La moyenne est bayésienne, pas simple :
  --   note = (m × C + Σ notes) / (m + n),  m = 5, C = 4.0
  --
  -- Une salle à un seul 5/5 pèse donc (20 + 5) / 6 = 4,17 ; une salle à quarante
  -- 4,6 pèse (20 + 184) / 45 = 4,53. La première a la meilleure moyenne BRUTE et
  -- se classe pourtant derrière — c'est exactement ce que le §5.4 demande, et
  -- c'est ce qu'une moyenne simple casserait sans qu'aucun écran ne paraisse
  -- abîmé.
  -- ===========================================================================
  insert into public.bookings (venue_id, client_id, event_date, slot,
                               requested_slot, guest_count, event_type,
                               status, deposit_amount)
  select c_solo, c_yasmine, current_date - 10, 'soir', 'soir', 100, 'mariage',
         'completed', 10000;

  insert into public.reviews (booking_id, booking_group_id, venue_id, rating)
  select b.id, b.group_id, c_solo, 5
  from public.bookings b where b.venue_id = c_solo;

  -- Quarante soirées, vingt-quatre à 5 et seize à 4 : moyenne brute 4,60.
  insert into public.bookings (venue_id, client_id, event_date, slot,
                               requested_slot, guest_count, event_type,
                               status, deposit_amount)
  select c_quar, c_yasmine, current_date - 100 - g, 'soir', 'soir', 100,
         'mariage', 'completed', 10000
  from generate_series(1, 40) g;

  insert into public.reviews (booking_id, booking_group_id, venue_id, rating)
  select b.id, b.group_id, c_quar,
         case when row_number() over (order by b.event_date) <= 24 then 5 else 4 end
  from public.bookings b where b.venue_id = c_quar;

  select vr.bayesian_rating, vr.raw_rating into v_note_solo, v_brute_solo
  from public.venue_ratings vr where vr.venue_id = c_solo;

  select vr.bayesian_rating, vr.raw_rating into v_note_quar, v_brute_quar
  from public.venue_ratings vr where vr.venue_id = c_quar;

  if v_brute_quar is distinct from 4.60 then
    raise exception 'ÉCHEC 9 — le décor est faux : la moyenne brute des quarante '
      'avis est % et non 4,60.', v_brute_quar;
  end if;

  if not (v_brute_solo > v_brute_quar) then
    raise exception 'ÉCHEC 9b — le décor est faux : le seul 5/5 n''a pas la '
      'meilleure moyenne brute, le test ne prouverait rien.';
  end if;

  if not (v_note_quar > v_note_solo) then
    raise exception 'ÉCHEC 9c — UNE SALLE AVEC UN SEUL 5/5 (% affichée) PASSE '
      'DEVANT UNE SALLE À QUARANTE 4,6 (% affichée). La moyenne affichée n''est '
      'plus bayésienne (§5.4).', v_note_solo, v_note_quar;
  end if;

  -- ET LA RECHERCHE LE RESPECTE, parce qu'elle trie sur la même colonne.
  v_rang_solo := null;
  v_rang_quar := null;
  for v_ligne in
    select row_number() over () as rang, s.venue_id
    from public.search_venues(
           p_commune    => 'Testville015',
           p_event_date => current_date + 200,
           p_slot       => 'soir',
           p_order      => 'note') s
  loop
    if v_ligne.venue_id = c_solo then v_rang_solo := v_ligne.rang; end if;
    if v_ligne.venue_id = c_quar then v_rang_quar := v_ligne.rang; end if;
  end loop;

  if v_rang_solo is null or v_rang_quar is null then
    raise exception 'ÉCHEC 9d — le décor est faux : les deux salles ne sortent '
      'pas de la recherche (% et %).',
      coalesce(v_rang_solo, -1), coalesce(v_rang_quar, -1);
  end if;

  if v_rang_quar > v_rang_solo then
    raise exception 'ÉCHEC 9e — LA RECHERCHE CLASSE LE SEUL 5/5 DEVANT LES '
      'QUARANTE 4,6 (rangs % et %). C''est là que le §5.4 se voit vraiment : '
      'dans l''ordre des résultats.', v_rang_solo, v_rang_quar;
  end if;

  raise notice 'OK 9 — un seul 5/5 (%) reste derrière quarante 4,6 (%), dans la '
    'vue comme dans la recherche.', v_note_solo, v_note_quar;

  -- ===========================================================================
  -- Test 10 — LES DROITS SUR LES FONCTIONS
  --
  -- Un visiteur lit les avis sans compte — c'est l'étape 2 du parcours du §3 —
  -- mais il n'en dépose pas, et ne répond à rien.
  -- ===========================================================================
  if not has_function_privilege('anon', 'public.avis_de_la_salle(uuid)', 'execute') then
    raise exception 'ÉCHEC 10 — un visiteur non connecté ne peut pas lire les '
      'avis d''une salle. Un avis sert d''abord à qui n''a pas encore réservé.';
  end if;

  if has_function_privilege('anon',
       'public.deposer_avis(uuid, integer, integer, integer, integer, integer, text)',
       'execute') then
    raise exception 'ÉCHEC 10b — « anon » peut déposer un avis.';
  end if;

  if has_function_privilege('anon', 'public.repondre_a_un_avis(uuid, text)', 'execute') then
    raise exception 'ÉCHEC 10c — « anon » peut répondre à un avis.';
  end if;

  if has_function_privilege('anon', 'public.complete_booking(uuid)', 'execute') then
    raise exception 'ÉCHEC 10d — « anon » peut marquer une réservation honorée.';
  end if;

  if not has_function_privilege('authenticated',
       'public.deposer_avis(uuid, integer, integer, integer, integer, integer, text)',
       'execute') then
    raise exception 'ÉCHEC 10e — un client connecté ne peut pas déposer d''avis.';
  end if;

  -- LA TABLE reviews N'A TOUJOURS AUCUNE POLITIQUE DELETE (§4.4, ADM-02) : la
  -- modération est un geste de back-office, pas un bouton dans l'application.
  select count(*) into v_lignes
  from pg_policies
  where schemaname = 'public' and tablename = 'reviews' and cmd = 'DELETE';

  if v_lignes <> 0 then
    raise exception 'ÉCHEC 10f — % politique(s) DELETE sur reviews. Un avis '
      'gênant s''effacerait depuis l''application.', v_lignes;
  end if;

  raise notice 'OK 10 — lecture ouverte à tous, écriture aux seuls comptes '
    'connectés, et aucun avis ne s''efface depuis l''application.';

  perform set_config('request.jwt.claims', '', true);
end $$;

rollback;
