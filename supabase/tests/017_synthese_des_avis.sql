-- =============================================================================
-- Ferha — tests/017_synthese_des_avis.sql
--
-- CE QU'ON VÉRIFIE : que la synthèse d'avis ne coûte rien pour rien, et qu'elle
-- ne promette jamais plus qu'elle n'a lu.
--
-- POURQUOI CE FICHIER EXISTE. Les deux règles de la synthèse échouent EN
-- SILENCE. Une salle retraitée chaque nuit sans que rien n'ait changé ne casse
-- rien : elle dépense un quota gratuit, une salle à la fois, jusqu'au jour où
-- la démonstration tombe en panne parce qu'il n'en reste plus. Une synthèse
-- écrite sur deux avis ne casse rien non plus : elle raconte deux soirées comme
-- si c'était une tendance. Ni l'une ni l'autre ne lève d'erreur, et c'est
-- exactement ce qu'un test doit attraper — rien d'autre ne le fera.
--
-- LES DEUX TESTS DEMANDÉS SONT LE 2 ET LE 4 :
--   * Test 2 — pas de synthèse sous trois avis ;
--   * Test 4 — une salle dont les avis n'ont pas bougé n'est pas retraitée.
--
-- Les autres ferment les portes latérales : une salle non publiée (test 3),
-- l'écriture qui revérifie ce que la lecture avait vu (test 5), la table fermée
-- en lecture directe (test 6), et le bloc que l'écran 7 reçoit (test 7).
--
-- LES AVIS ONT DU TEXTE, ET C'EST LE SUJET. Une note muette ne donne rien à
-- résumer ; le test 2b l'exerce explicitement, parce que c'est le piège naturel
-- — compter les avis plutôt que la matière.
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
-- Prérequis : migrations 001 à 032 appliquées.
-- =============================================================================

begin;

do $$
declare
  c_owner    constant uuid := 'c0000017-0000-4000-a000-000000000001';
  c_client   constant uuid := 'c0000017-0000-4000-a000-000000000002';

  -- Quatre avis porteurs de texte : elle a de quoi être résumée.
  c_riche    constant uuid := 'c0000017-0000-4000-a000-000000000003';
  -- Deux avis seulement : sous le seuil, et elle doit y rester.
  c_pauvre   constant uuid := 'c0000017-0000-4000-a000-000000000004';
  -- Trois avis dont un seul porte du texte : le piège du compteur.
  c_muette   constant uuid := 'c0000017-0000-4000-a000-000000000005';
  -- Quatre avis, mais en brouillon : elle n'existe pour personne.
  c_draft    constant uuid := 'c0000017-0000-4000-a000-000000000006';

  c_modele   constant text := 'modele-de-test-017';

  v_minimum   integer;
  v_lignes    integer;
  v_ecrites   integer;
  v_a_refaire boolean;
  v_hash1     text;
  v_hash2     text;
  v_nb        integer;
  v_basses    integer;
  v_avis      jsonb;
  v_json      jsonb;
  v_avis_id   uuid;
begin
  -- ---------------------------------------------------------------------------
  -- Le décor : un propriétaire, une cliente, quatre salles.
  -- ---------------------------------------------------------------------------
  insert into auth.users (instance_id, id, aud, role, email,
                          encrypted_password, email_confirmed_at,
                          created_at, updated_at,
                          raw_app_meta_data, raw_user_meta_data)
  values
    ('00000000-0000-0000-0000-000000000000', c_owner,  'authenticated',
     'authenticated', 'test.owner.017@ferha.test',  '', now(), now(), now(),
     '{}'::jsonb, '{}'::jsonb),
    ('00000000-0000-0000-0000-000000000000', c_client, 'authenticated',
     'authenticated', 'test.client.017@ferha.test', '', now(), now(), now(),
     '{}'::jsonb, '{}'::jsonb);

  insert into public.profiles (id, full_name, email, phone, is_owner) values
    (c_owner,  'Karim 017',  'test.owner.017@ferha.test',  '0770000017', true),
    -- LE NOM ENTIER EST ICI POUR LE TEST 1b : c'est lui qu'on cherchera dans ce
    -- que la base envoie au modèle.
    (c_client, 'Amina Haddad 017', 'test.client.017@ferha.test', '0770117711', false)
  on conflict (id) do update
    set full_name = excluded.full_name, is_owner = excluded.is_owner;

  insert into public.venues (id, owner_id, name, wilaya_code, commune,
                             capacity_seated, status)
  values
    (c_riche,  c_owner, 'Salle bien commentée 017', '31', 'Testville017', 400, 'published'),
    (c_pauvre, c_owner, 'Salle peu commentée 017',  '31', 'Testville017', 300, 'published'),
    (c_muette, c_owner, 'Salle aux notes muettes 017', '31', 'Testville017', 300, 'published'),
    (c_draft,  c_owner, 'Brouillon bien commenté 017', '31', 'Testville017', 300, 'draft');

  insert into public.venue_pricing (venue_id, slot, base_price, weekend_coef,
                                    high_season_coef, included_seats,
                                    extra_seat_price)
  select v.id, s.slot, 100000, 1.30, 1.20, 200, 800
  from (values (c_riche), (c_pauvre), (c_muette), (c_draft)) as v(id),
       (values ('midi'), ('soir'), ('journee')) as s(slot);

  -- ---------------------------------------------------------------------------
  -- Les réservations honorées, puis les avis.
  --
  -- ÉCRITS EN DIRECT, ET NON PAR deposer_avis() : celle-ci n'accepte qu'un avis
  -- par réservation, dans une fenêtre de trente jours, et pour le client
  -- connecté. Ce fichier ne teste pas ces règles-là — la 015 s'en charge — il
  -- teste ce qui se passe APRÈS, quand les avis existent.
  -- ---------------------------------------------------------------------------
  insert into public.bookings (venue_id, client_id, event_date, slot,
                               requested_slot, guest_count, event_type,
                               status, completed_at, deposit_amount)
  select v.id, c_client, current_date - n.jour, 'soir', 'soir', 250, 'mariage',
         'completed', now(), 50000
  from (values (c_riche), (c_pauvre), (c_muette), (c_draft)) as v(id),
       generate_series(3, 8) as n(jour);

  -- QUATRE AVIS AVEC DU TEXTE sur la salle riche, dont un tiède (3 étoiles) :
  -- c'est lui qui fait `notes_basses = 1`, et c'est de lui que dépend
  -- l'exigence de réserve côté Edge Function.
  insert into public.reviews (booking_id, venue_id, rating, body)
  select b.id, c_riche,
         case b.event_date when current_date - 3 then 3 else 5 end,
         case b.event_date
           when current_date - 3 then 'Le parking est un peu juste.'
           when current_date - 4 then 'Salle impeccable et personnel présent.'
           when current_date - 5 then 'Très belle soirée, rien à redire.'
           else 'La famille a beaucoup apprécié.'
         end
  from public.bookings b
  where b.venue_id = c_riche and b.event_date >= current_date - 6;

  -- DEUX AVIS SEULEMENT sur la salle pauvre : sous le seuil.
  insert into public.reviews (booking_id, venue_id, rating, body)
  select b.id, c_pauvre, 5, 'Deux phrases, et rien à résumer.'
  from public.bookings b
  where b.venue_id = c_pauvre and b.event_date >= current_date - 4;

  -- TROIS AVIS SUR LA SALLE MUETTE, MAIS UN SEUL PORTE DU TEXTE. Le compteur
  -- naïf dirait « trois » ; la matière, elle, tient en une phrase.
  insert into public.reviews (booking_id, venue_id, rating, body)
  select b.id, c_muette, 5,
         case b.event_date when current_date - 3 then 'La seule phrase écrite.'
                           else null end
  from public.bookings b
  where b.venue_id = c_muette and b.event_date >= current_date - 5;

  -- QUATRE AVIS SUR LE BROUILLON. Il ne doit jamais sortir.
  insert into public.reviews (booking_id, venue_id, rating, body)
  select b.id, c_draft, 5, 'Un avis sur une salle qui n''est pas en vente.'
  from public.bookings b
  where b.venue_id = c_draft and b.event_date >= current_date - 6;

  -- ===========================================================================
  -- Test 1 — CE QUE LA BASE ENVOIE AU MODÈLE, ET CE QU'ELLE NE LUI ENVOIE PAS
  --
  -- Le §8.5 préfère une donnée absente à un garde-fou, et un garde-fou à une
  -- consigne. Le modèle ne peut pas écrire « Amina H. a trouvé le parking
  -- juste » s'il n'a jamais lu de nom — encore faut-il qu'aucun ne parte.
  -- ===========================================================================
  select s.review_count, s.notes_basses, s.avis, s.source_hash
    into v_nb, v_basses, v_avis, v_hash1
    from public.avis_pour_synthese(c_modele) s
   where s.venue_id = c_riche;

  if v_nb is null then
    raise exception 'ÉCHEC 1 — la salle aux quatre avis n''est pas proposée à '
      'la synthèse.';
  end if;

  if v_nb <> 4 then
    raise exception 'ÉCHEC 1a — % avis porteurs de texte, attendu 4.', v_nb;
  end if;

  if jsonb_array_length(v_avis) <> 4 then
    raise exception 'ÉCHEC 1b — % textes envoyés au modèle, attendu 4.',
      jsonb_array_length(v_avis);
  end if;

  -- LE NOM DU CLIENT NE SORT PAS. Ni entier, ni abrégé.
  if v_avis::text ilike '%Amina%' or v_avis::text ilike '%Haddad%' then
    raise exception 'ÉCHEC 1c — UN NOM DE CLIENT PART VERS LE MODÈLE. Il ne '
      'peut nommer personne que parce qu''il ne lit aucun nom (§9).';
  end if;

  if v_avis::text like '%' || c_client::text || '%' then
    raise exception 'ÉCHEC 1d — l''identifiant du client part vers le modèle.';
  end if;

  -- LE FAIT QUI PORTE L'EXIGENCE DE RÉSERVE. Un avis à 3 étoiles sur les
  -- quatre : le modèle DEVRA déclarer une réserve, et c'est la base qui le sait.
  if v_basses <> 1 then
    raise exception 'ÉCHEC 1e — % avis à trois étoiles ou moins, attendu 1. '
      'C''est ce nombre qui rend une synthèse exclusivement flatteuse '
      'irrecevable.', v_basses;
  end if;

  raise notice 'OK 1 — quatre textes partent, aucun nom, et la base compte '
    'elle-même les avis tièdes.';

  -- ===========================================================================
  -- Test 2 — PAS DE SYNTHÈSE SOUS TROIS AVIS
  --
  -- « On ne résume pas deux phrases. » Le seuil vit dans
  -- synthese_avis_minimum(), et les deux gardiens le lisent — celui qui propose
  -- le travail, et celui qui accepte le résultat.
  -- ===========================================================================
  v_minimum := public.synthese_avis_minimum();

  if v_minimum <> 3 then
    raise exception 'ÉCHEC 2 — le seuil vaut %, attendu 3.', v_minimum;
  end if;

  -- LA PORTE D'ENTRÉE : elle n'est même pas proposée.
  select count(*) into v_lignes
    from public.avis_pour_synthese(c_modele) s
   where s.venue_id = c_pauvre;

  if v_lignes <> 0 then
    raise exception 'ÉCHEC 2a — UNE SALLE À DEUX AVIS EST PROPOSÉE À LA '
      'SYNTHÈSE. Elle coûterait un appel au modèle pour paraphraser deux '
      'phrases, et le résultat se lirait comme une tendance.';
  end if;

  -- LE PIÈGE DU COMPTEUR : trois avis, un seul texte. C'est le texte qui est la
  -- matière, donc c'est le texte qu'on compte.
  select count(*) into v_lignes
    from public.avis_pour_synthese(c_modele) s
   where s.venue_id = c_muette;

  if v_lignes <> 0 then
    raise exception 'ÉCHEC 2b — UNE SALLE À TROIS AVIS DONT UN SEUL PORTE DU '
      'TEXTE EST PROPOSÉE. Le compteur dit trois, le modèle recevrait une '
      'phrase — et promettrait « la synthèse des 3 avis ».';
  end if;

  -- LA PORTE DE SORTIE : même forcée, l'écriture refuse. C'est la ceinture sous
  -- la bretelle, et elle sert vraiment : une minute passe entre la lecture et
  -- l'écriture, et un avis peut être retiré entre-temps.
  v_ecrites := public.enregistrer_synthese_avis(
    c_pauvre, 'Une synthèse qui n''aurait jamais dû être écrite.',
    'hachage-invente', 2, c_modele);

  if v_ecrites <> 0 then
    raise exception 'ÉCHEC 2c — L''ÉCRITURE A ACCEPTÉ une synthèse sur deux '
      'avis. Le seuil ne tient que du côté de la lecture : un avis retiré entre '
      'les deux suffirait à le franchir.';
  end if;

  if exists (select 1 from public.venue_review_summaries
              where venue_id = c_pauvre) then
    raise exception 'ÉCHEC 2d — une ligne a été écrite malgré le refus.';
  end if;

  raise notice 'OK 2 — sous trois avis porteurs de texte, ni proposition ni '
    'écriture. Le seuil tient des deux côtés.';

  -- ===========================================================================
  -- Test 3 — UNE SALLE NON PUBLIÉE N'EST JAMAIS RÉSUMÉE
  --
  -- Même raison qu'au test 3 de la 016 pour l'index sémantique : une salle que
  -- son propriétaire n'a pas mise en vente ne doit apparaître nulle part. Une
  -- synthèse d'avis est un contenu public de plus.
  -- ===========================================================================
  select count(*) into v_lignes
    from public.avis_pour_synthese(c_modele) s
   where s.venue_id = c_draft;

  if v_lignes <> 0 then
    raise exception 'ÉCHEC 3 — UN BROUILLON EST PROPOSÉ À LA SYNTHÈSE.';
  end if;

  v_ecrites := public.enregistrer_synthese_avis(
    c_draft, 'Une synthèse sur une salle qui n''est pas en vente.',
    'hachage-invente', 4, c_modele);

  if v_ecrites <> 0 then
    raise exception 'ÉCHEC 3b — l''écriture a accepté une synthèse sur un '
      'brouillon. Entre la lecture et l''écriture, un propriétaire a le temps '
      'de dépublier.';
  end if;

  raise notice 'OK 3 — un brouillon n''est ni proposé ni accepté.';

  -- ===========================================================================
  -- Test 4 — UNE SALLE DONT LES AVIS N'ONT PAS BOUGÉ N'EST PAS RETRAITÉE
  --
  -- LE TEST DU QUOTA. Sans lui, chaque nuit rappellerait le modèle sur des
  -- textes identiques, et personne ne s'en apercevrait avant que le quota
  -- gratuit ne soit vide — c'est-à-dire le jour de la démonstration.
  -- ===========================================================================
  select s.a_refaire into v_a_refaire
    from public.avis_pour_synthese(c_modele) s
   where s.venue_id = c_riche;

  if not v_a_refaire then
    raise exception 'ÉCHEC 4 — une salle JAMAIS résumée n''est pas « à '
      'refaire ». Elle ne le serait alors jamais.';
  end if;

  v_ecrites := public.enregistrer_synthese_avis(
    c_riche,
    'Les invités saluent la propreté ; plusieurs trouvent le parking juste.',
    v_hash1, 4, c_modele);

  if v_ecrites <> 1 then
    raise exception 'ÉCHEC 4a — l''écriture a rendu %, attendu 1.', v_ecrites;
  end if;

  -- ET MAINTENANT, LE CŒUR DU TEST.
  select s.a_refaire into v_a_refaire
    from public.avis_pour_synthese(c_modele) s
   where s.venue_id = c_riche;

  if v_a_refaire then
    raise exception 'ÉCHEC 4b — UNE SALLE FRAÎCHEMENT RÉSUMÉE EST DÉJÀ « À '
      'REFAIRE ». Chaque nuit rappellerait le modèle sur des textes identiques, '
      'et le quota gratuit y passerait sans que rien ne le dise.';
  end if;

  -- La salle est TOUJOURS PROPOSÉE, avec a_refaire à faux : le journal doit
  -- pouvoir dire « quinze regardées, une écrite ».
  select count(*) into v_lignes
    from public.avis_pour_synthese(c_modele) s
   where s.venue_id = c_riche;

  if v_lignes <> 1 then
    raise exception 'ÉCHEC 4c — une salle à jour disparaît de la liste. Le '
      'journal ne pourrait plus dire combien de salles ont été regardées.';
  end if;

  -- UN AVIS CORRIGÉ REFAIT TOUT. C'est ce qu'un simple compteur d'avis aurait
  -- manqué : le nombre n'a pas bougé, le texte si. Le §5.4 laisse trente jours
  -- pour se relire, et ce cas-là arrive pour de bon.
  select r.id into v_avis_id
    from public.reviews r
   where r.venue_id = c_riche and r.rating = 3;

  update public.reviews
     set body = 'Le parking est vraiment trop petit les soirs de mariage.'
   where id = v_avis_id;

  select s.a_refaire, s.review_count into v_a_refaire, v_nb
    from public.avis_pour_synthese(c_modele) s
   where s.venue_id = c_riche;

  if not v_a_refaire then
    raise exception 'ÉCHEC 4d — UN AVIS CORRIGÉ N''A PAS DÉCLENCHÉ DE NOUVELLE '
      'SYNTHÈSE. Le nombre d''avis n''a pas changé — c''est précisément pour '
      'cela qu''on hache le texte plutôt que de le compter.';
  end if;

  if v_nb <> 4 then
    raise exception 'ÉCHEC 4e — le nombre d''avis a changé (%), alors que seul '
      'un texte a été corrigé. Le test 4d ne prouverait plus rien.', v_nb;
  end if;

  -- ET UN CHANGEMENT DE MODÈLE AUSSI, comme en 027 : changer de modèle, c'est
  -- changer ce qui serait écrit.
  update public.reviews
     set body = 'Le parking est un peu juste.'
   where id = v_avis_id;

  select s.a_refaire into v_a_refaire
    from public.avis_pour_synthese(c_modele) s
   where s.venue_id = c_riche;

  if v_a_refaire then
    raise exception 'ÉCHEC 4f — après retour en arrière, la salle reste « à '
      'refaire ». Le hachage dépend donc d''autre chose que du contenu — de '
      'l''ordre des lignes, sans doute.';
  end if;

  select s.a_refaire into v_a_refaire
    from public.avis_pour_synthese('un-autre-modele') s
   where s.venue_id = c_riche;

  if not v_a_refaire then
    raise exception 'ÉCHEC 4g — UN CHANGEMENT DE MODÈLE NE DÉCLENCHE PAS DE '
      'NOUVELLE SYNTHÈSE. Les anciens textes resteraient indéfiniment.';
  end if;

  -- LE HACHAGE EST STABLE À CONTENU ÉGAL. S'il changeait d'un appel à l'autre,
  -- tout se résumerait à chaque passage — et le test 4b passerait quand même,
  -- parce qu'il compare à ce qui vient d'être écrit.
  select s.source_hash into v_hash2
    from public.avis_pour_synthese(c_modele) s
   where s.venue_id = c_riche;

  if v_hash1 is distinct from v_hash2 then
    raise exception 'ÉCHEC 4h — deux appels donnent deux hachages : % puis %.',
      v_hash1, v_hash2;
  end if;

  raise notice 'OK 4 — rien ne se refait sans raison, et tout se refait quand '
    'un texte ou le modèle change.';

  -- ===========================================================================
  -- Test 5 — UN NOUVEL AVIS REMPLACE LA SYNTHÈSE, IL NE L'AJOUTE PAS
  --
  -- Une ligne par salle. Deux synthèses concurrentes seraient deux vérités, et
  -- l'écran en afficherait une au hasard.
  -- ===========================================================================
  select count(*) into v_lignes
    from public.venue_review_summaries where venue_id = c_riche;

  if v_lignes <> 1 then
    raise exception 'ÉCHEC 5 — % synthèses pour une salle, attendu 1.', v_lignes;
  end if;

  v_ecrites := public.enregistrer_synthese_avis(
    c_riche, 'Une seconde rédaction, qui doit écraser la première.',
    'un-autre-hachage', 4, c_modele);

  select count(*) into v_lignes
    from public.venue_review_summaries where venue_id = c_riche;

  if v_lignes <> 1 then
    raise exception 'ÉCHEC 5a — une seconde rédaction a créé une seconde '
      'ligne.';
  end if;

  -- UNE SYNTHÈSE VIDE NE S'ENREGISTRE PAS. Un modèle qui rend une chaîne vide
  -- effacerait sans bruit une synthèse correcte.
  begin
    perform public.enregistrer_synthese_avis(c_riche, '   ', 'h', 4, c_modele);
    raise exception 'ÉCHEC 5b — UNE SYNTHÈSE VIDE A ÉTÉ ACCEPTÉE. Elle '
      'remplacerait une synthèse correcte par du blanc.';
  exception when invalid_parameter_value then
    null;
  end;

  raise notice 'OK 5 — une ligne par salle, et jamais de texte vide.';

  -- ===========================================================================
  -- Test 6 — LA TABLE NE SE LIT PAS EN DIRECT, ET LES FONCTIONS NON PLUS
  --
  -- RLS active et aucune politique : la table est vide pour tout le monde sauf
  -- pour service_role et pour les fonctions SECURITY DEFINER. Elle ne sort que
  -- par avis_de_la_salle(), qui borne déjà ce qui se lit.
  -- ===========================================================================
  if not exists (
    select 1 from pg_class
     where oid = 'public.venue_review_summaries'::regclass and relrowsecurity
  ) then
    raise exception 'ÉCHEC 6 — RLS n''est pas active sur '
      'venue_review_summaries.';
  end if;

  select count(*) into v_lignes
    from pg_policies
   where schemaname = 'public' and tablename = 'venue_review_summaries';

  if v_lignes <> 0 then
    raise exception 'ÉCHEC 6a — % politique(s) sur venue_review_summaries. '
      'La table doit rester close : elle ne sort que par avis_de_la_salle().',
      v_lignes;
  end if;

  if has_function_privilege('anon',
       'public.avis_pour_synthese(text)', 'execute') then
    raise exception 'ÉCHEC 6b — un visiteur peut lire le texte brut de tous '
      'les avis de toutes les salles en un appel.';
  end if;

  if has_function_privilege('authenticated',
       'public.enregistrer_synthese_avis(uuid, text, text, integer, text)',
       'execute') then
    raise exception 'ÉCHEC 6c — UN COMPTE CONNECTÉ PEUT ÉCRIRE LA SYNTHÈSE '
      'D''UNE SALLE. Il écrirait ce qu''il veut sous les avis de n''importe qui.';
  end if;

  if has_function_privilege('authenticated',
       'public.declencher_synthese_avis()', 'execute') then
    raise exception 'ÉCHEC 6d — un compte connecté peut déclencher la tâche '
      'nocturne, et donc vider le quota gratuit quand il veut.';
  end if;

  -- ET CELLE QUI DOIT RESTER OUVERTE. Les avis se lisent sans compte (§3).
  if not has_function_privilege('anon',
       'public.avis_de_la_salle(uuid)', 'execute') then
    raise exception 'ÉCHEC 6e — un visiteur ne peut plus lire les avis d''une '
      'salle. C''est l''étape 2 du parcours du §3, et elle se fait sans compte.';
  end if;

  raise notice 'OK 6 — la table est close, les deux fonctions de travail aussi, '
    'et seule la lecture de l''écran 7 reste ouverte aux visiteurs.';

  -- ===========================================================================
  -- Test 7 — CE QUE L'ÉCRAN 7 REÇOIT
  --
  -- Trois champs qui vont ensemble ou pas du tout. Une synthèse sans sa date se
  -- lirait comme une vérité permanente ; un compte pris d'aujourd'hui
  -- promettrait des avis qu'elle n'a jamais lus.
  -- ===========================================================================
  v_json := public.avis_de_la_salle(c_riche);

  if v_json->>'summary' is null then
    raise exception 'ÉCHEC 7 — la synthèse ne remonte pas dans '
      'avis_de_la_salle(). L''écran 7 n''afficherait jamais le bloc.';
  end if;

  if v_json->>'summary_updated_at' is null then
    raise exception 'ÉCHEC 7a — la synthèse remonte SANS SA DATE. Le lecteur ne '
      'saurait pas qu''un avis déposé depuis n''y est pas encore.';
  end if;

  if (v_json->>'summary_count')::integer <> 4 then
    raise exception 'ÉCHEC 7b — le compte de la synthèse vaut %, attendu 4.',
      v_json->>'summary_count';
  end if;

  -- ET SUR UNE SALLE SANS SYNTHÈSE : les trois champs sont nuls, et l'écran ne
  -- dessine aucun cadre.
  v_json := public.avis_de_la_salle(c_pauvre);

  if v_json->>'summary' is not null
     or v_json->>'summary_count' is not null
     or v_json->>'summary_updated_at' is not null then
    raise exception 'ÉCHEC 7c — une salle sans synthèse en rend une. L''écran '
      'dessinerait un cadre vide.';
  end if;

  -- Les avis eux-mêmes n'ont pas bougé : la 026 tient toujours.
  if jsonb_array_length(v_json->'reviews') <> 2 then
    raise exception 'ÉCHEC 7d — la liste d''avis a changé de forme en même '
      'temps que la synthèse.';
  end if;

  raise notice 'OK 7 — le bloc arrive entier ou pas du tout, et la liste d''avis '
    'est intacte.';

  -- ===========================================================================
  -- Test 8 — LA TÂCHE NOCTURNE EST POSÉE
  --
  -- Une tâche créée à la main dans l'interface n'existe que dans CE projet : un
  -- projet recréé repartirait sans elle, avec des synthèses qui ne se
  -- rafraîchissent plus et personne pour s'en apercevoir.
  -- ===========================================================================
  select count(*) into v_lignes
    from cron.job where jobname = 'ferha-synthese-avis' and active;

  if v_lignes <> 1 then
    raise exception 'ÉCHEC 8 — la tâche « ferha-synthese-avis » n''est pas '
      'posée, ou n''est pas active.';
  end if;

  raise notice 'OK 8 — la tâche nocturne est posée par la migration, et active.';
end $$;

rollback;
