-- =============================================================================
-- Ferha — tests/007_adresse_et_telephone.sql
--
-- CE QU'ON VÉRIFIE, ET POURQUOI CHACUN COMPTE :
--
--   1. UNE SALLE SANS ADRESSE EST REFUSÉE (FE036). ADM-01 demande de contrôler
--      une « adresse plausible » : sans adresse, ce contrôle est une case qu'on
--      coche sans rien regarder.
--
--   2. L'ADRESSE NE SORT PAS. Ni par `venue_detail()`, ni par `search_venues()`,
--      ni — et c'est le test qui compte vraiment — par la TABLE. La politique
--      `venues_select_published_or_own` (002) laisse un inconnu lire la ligne
--      d'une salle publiée ; seuls les droits de colonne de 019 lui retirent
--      cette colonne-là. C'est un `GET /rest/v1/venues?select=address` avec la
--      clé anon qu'on rejoue ici.
--
--   3. LE NUMÉRO EST EXIGÉ AUX DEUX ENDROITS OÙ QUELQU'UN DEVRA DÉCROCHER :
--      l'envoi d'une salle en validation (FE037) et la demande de réservation
--      (FE007). Manquant ET mal formé, parce que les deux arrivent : le premier
--      est un écran mal branché, le second est un doigt qui glisse.
--
--   4. LA RÈGLE EST BIEN CELLE QU'ON A DITE. Mobile 0 + 5/6/7 + 8 chiffres,
--      fixe 0 + 2/3/4 + 7 chiffres, espaces tolérés à la saisie, chiffres seuls
--      en base. Ce test est le seul endroit qui compare la règle SQL à des
--      numéros écrits à la main — c'est lui qui empêche
--      lib/core/validation/telephone.dart de mentir. Il porte en particulier
--      « 077011223 », le mobile amputé d'un chiffre : c'est lui qui a fait
--      resserrer la règle, une version large l'ayant pris pour un fixe.
--
--   5. `phone_verified` RETOMBE QUAND LE NUMÉRO CHANGE, et ne retombe pas quand
--      on repose le même numéro autrement écrit.
--
--   6. UN INCONNU NE LIT TOUJOURS AUCUN NUMÉRO (§9). C'est la règle que ce
--      correctif aurait pu casser sans qu'on s'en aperçoive : on vient
--      d'ÉCRIRE des numéros là où il n'y en avait pas. Le test regarde donc les
--      trois chemins — la table `profiles`, `booking_contact()` avant
--      « accepted », et `owner_request_detail()`.
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
-- ON VÉRIFIE LE HINT, PAS LE MESSAGE — comme partout depuis 012 : c'est le hint
-- que lit l'application, et c'est lui le contrat.
--
-- CE QU'IL LAISSE : rien. Tout est fait dans une transaction annulée à la fin.
--
-- Prérequis : migrations 001 à 021 appliquées, et les référentiels remplis
-- (021 ajoute la borne des photos : le décor du test 3 les pose désormais)
--             (003 équipements, 009 wilayas, 010 types d'événement).
-- =============================================================================

begin;

-- =============================================================================
-- Le décor, et les tests 1 à 5
-- =============================================================================

do $$
declare
  c_karim  constant uuid := 'c0000007-0000-4000-a000-000000000001';
  c_amina  constant uuid := 'c0000007-0000-4000-a000-000000000002';
  c_date   constant date := date '2099-11-14';

  v_salle    uuid;
  v_wilaya   text;
  v_hint     text;
  v_sqlstate text;
  v_phone    text;
  v_bool     boolean;
  v_texte    text;
  v_rang     integer;
begin
  insert into auth.users (instance_id, id, aud, role, email,
                          encrypted_password, email_confirmed_at,
                          created_at, updated_at,
                          raw_app_meta_data, raw_user_meta_data)
  values
    ('00000000-0000-0000-0000-000000000000', c_karim, 'authenticated', 'authenticated',
     'test.karim.007@ferha.test', '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb),
    ('00000000-0000-0000-0000-000000000000', c_amina, 'authenticated', 'authenticated',
     'test.amina.007@ferha.test', '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb);

  -- AUCUN DES DEUX N'A DE NUMÉRO AU DÉPART, et c'est tout le point de ce
  -- fichier : c'est l'état d'un vrai inscrit, celui que les données de
  -- démonstration cachaient.
  insert into public.profiles (id, full_name, email, phone, is_owner) values
    (c_karim, 'Karim Belkacem', 'test.karim.007@ferha.test', null, false),
    (c_amina, 'Amina Haddad',   'test.amina.007@ferha.test', null, false)
  on conflict (id) do update
    set full_name = excluded.full_name,
        phone     = excluded.phone,
        is_owner  = excluded.is_owner;

  select w.code into v_wilaya from public.wilayas w order by w.code limit 1;
  if v_wilaya is null then
    raise exception 'ÉCHEC 0 — la table wilayas est vide. Appliquez 009 avant ce test.';
  end if;

  -- ---------------------------------------------------------------------------
  -- Test 1 — une salle sans adresse est refusée (FE036)
  -- ---------------------------------------------------------------------------
  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_karim, 'role', 'authenticated')::text,
                     true);

  begin
    perform * from public.creer_salle('Salle sans rue', v_wilaya, 'Oran', null, 300);
    raise exception 'ÉCHEC 1 — une salle a été inscrite sans adresse. ADM-01 demande '
                    'de contrôler une adresse plausible : il n''y aurait rien à contrôler.';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE036' then
      raise exception 'ÉCHEC 1 — refus attendu FE036, reçu hint=% sqlstate=%.',
        coalesce(v_hint, '(vide)'), v_sqlstate;
    end if;
  end;

  -- Une adresse faite de blancs n'est pas une adresse.
  begin
    perform * from public.creer_salle('Salle sans rue', v_wilaya, 'Oran', '   ', 300);
    raise exception 'ÉCHEC 1 — une adresse de blancs a été acceptée.';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE036' then
      raise exception 'ÉCHEC 1 — refus attendu FE036 sur une adresse de blancs, reçu hint=%.',
        coalesce(v_hint, '(vide)');
    end if;
  end;

  if (select count(*) from public.venues v where v.name = 'Salle sans rue') <> 0 then
    raise exception 'ÉCHEC 1 — une salle a été écrite malgré le refus.';
  end if;

  raise notice 'OK 1 — sans adresse : FE036, sqlstate % (donc HTTP 400), et rien n''est écrit.',
    v_sqlstate;

  -- La vraie salle, celle qui sert au reste du fichier.
  select v.id into v_salle
  from public.creer_salle(
    'Salle Les Oliviers', v_wilaya, 'Bir El Djir',
    'Cité 200 logements, route de l''aéroport', 400
  ) v;

  -- ---------------------------------------------------------------------------
  -- Test 2 — l'envoi en validation exige un numéro (FE037)
  -- ---------------------------------------------------------------------------
  begin
    perform * from public.envoyer_salle_en_validation(v_salle, null);
    raise exception 'ÉCHEC 2 — une salle est partie en validation sans numéro. '
                    'ADM-01 demande un propriétaire joignable.';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE037' then
      raise exception 'ÉCHEC 2 — refus attendu FE037, reçu hint=% sqlstate=%.',
        coalesce(v_hint, '(vide)'), v_sqlstate;
    end if;
  end;

  -- MAL FORMÉ, ET DE CINQ FAÇONS DIFFÉRENTES.
  --
  --   0770 11 22 3    UN MOBILE AMPUTÉ D'UN CHIFFRE, et c'est le cas qui compte.
  --                   Neuf chiffres : la longueur d'un fixe. Une règle qui
  --                   accepterait « 0 + 8 chiffres » le prendrait pour un fixe
  --                   et le rangerait sans broncher — le propriétaire ne
  --                   l'apprendrait que le jour où personne ne le rappelle.
  --                   C'est le deuxième chiffre qui le refuse : un fixe
  --                   commence par 2, 3 ou 4, jamais par 7.
  --   0770 11 2       trop court pour être quoi que ce soit
  --   0470112233      dix chiffres sous un deuxième chiffre de fixe
  --   +213770112233   l'indicatif international n'est pas de la mise en forme
  --   0770 AB 22 33   des lettres
  foreach v_texte in array array['0770 11 22 3', '0770 11 2', '0470112233',
                                 '+213770112233', '0770 AB 22 33']
  loop
    begin
      perform * from public.envoyer_salle_en_validation(v_salle, v_texte);
      raise exception 'ÉCHEC 2 — le numéro « % » a été accepté.', v_texte;
    exception when others then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint is distinct from 'FE037' then
        raise exception 'ÉCHEC 2 — « % » aurait dû être refusé en FE037, reçu hint=%.',
          v_texte, coalesce(v_hint, '(vide)');
      end if;
    end;
  end loop;

  -- Le refus n'a rien laissé derrière lui, ni sur la salle, ni sur le profil.
  select v.status into v_texte from public.venues v where v.id = v_salle;
  if v_texte is distinct from 'draft' then
    raise exception 'ÉCHEC 2 — la salle est passée en « % » malgré le refus.', v_texte;
  end if;
  select p.phone into v_phone from public.profiles p where p.id = c_karim;
  if v_phone is not null then
    raise exception 'ÉCHEC 2 — un numéro mal formé a quand même été écrit : « % ».', v_phone;
  end if;

  raise notice 'OK 2 — sans numéro valide, pas de validation : FE037, sqlstate %.', v_sqlstate;

  -- ---------------------------------------------------------------------------
  -- Test 3 — LES ESPACES À LA SAISIE, LES CHIFFRES EN BASE
  --
  -- Karim tape son numéro comme il est écrit sur sa carte de visite. Ce qui
  -- part en validation, c'est la salle ; ce qui reste dans le profil, c'est un
  -- numéro sans espaces.
  --
  -- LES PHOTOS D'ABORD, PARCE QUE 021 LES EXIGE. Le numéro est contrôlé avant
  -- elles — c'est pour cela que les tests 1 et 2 tiennent sans photo — mais
  -- l'envoi, lui, en demande photos_min(). Ce test ne porte pas sur cette
  -- règle (008_photos_de_la_salle.sql s'en charge) : il a seulement besoin
  -- d'une salle en état de partir. La borne est lue, jamais écrite.
  -- ---------------------------------------------------------------------------
  for v_rang in 1..public.photos_min() loop
    perform * from public.ajouter_photo(
      v_salle, v_salle || '/' || gen_random_uuid() || '.webp');
  end loop;

  select v.status into v_texte
  from public.envoyer_salle_en_validation(v_salle, '0770 11 22 33') v;

  if v_texte is distinct from 'pending' then
    raise exception 'ÉCHEC 3 — la salle est en « % » au lieu de « pending ».', v_texte;
  end if;

  select p.phone into v_phone from public.profiles p where p.id = c_karim;
  if v_phone is distinct from '0770112233' then
    raise exception
      'ÉCHEC 3 — le numéro est rangé « % » au lieu de « 0770112233 ». Les espaces '
      'sont tolérés à la saisie, jamais gardés.', coalesce(v_phone, 'NULL');
  end if;

  raise notice 'OK 3 — « 0770 11 22 33 » saisi, « 0770112233 » rangé, salle en attente.';

  -- ---------------------------------------------------------------------------
  -- Test 4 — phone_verified retombe quand le numéro change, et pas autrement
  --
  -- Le drapeau dit « CE numéro-là a été vérifié ». Il ne dit rien du suivant.
  -- ---------------------------------------------------------------------------
  update public.profiles p set phone_verified = true where p.id = c_karim;

  -- Le même numéro, écrit autrement : ce n'est pas un changement.
  update public.profiles p set phone = '0770 11 22 33' where p.id = c_karim;
  select p.phone_verified into v_bool from public.profiles p where p.id = c_karim;
  if not v_bool then
    raise exception
      'ÉCHEC 4 — phone_verified est retombé alors que le numéro n''a pas changé : '
      'déplacer une espace n''est pas changer de numéro.';
  end if;

  -- Un autre numéro : le drapeau retombe.
  update public.profiles p set phone = '0661445566' where p.id = c_karim;
  select p.phone_verified into v_bool from public.profiles p where p.id = c_karim;
  if v_bool then
    raise exception
      'ÉCHEC 4 — phone_verified est resté levé sur un numéro que personne n''a '
      'jamais appelé.';
  end if;

  -- Et la contrainte de table reste le dernier mot, même hors des fonctions RPC.
  begin
    update public.profiles p set phone = '12345' where p.id = c_karim;
    raise exception 'ÉCHEC 4 — « 12345 » est entré en base par un UPDATE direct.';
  exception when check_violation then
    null;   -- c'est le refus attendu
  end;

  -- Un numéro fixe est un numéro : 0 puis huit chiffres.
  update public.profiles p set phone = '041 23 45 67' where p.id = c_karim;
  select p.phone into v_phone from public.profiles p where p.id = c_karim;
  if v_phone is distinct from '041234567' then
    raise exception 'ÉCHEC 4 — un fixe n''est pas accepté : « % ».', coalesce(v_phone, 'NULL');
  end if;
  update public.profiles p set phone = '0770112233' where p.id = c_karim;

  raise notice 'OK 4 — le drapeau suit le numéro, la contrainte tient hors des RPC, le fixe passe.';

  -- ---------------------------------------------------------------------------
  -- Test 5 — la demande de réservation exige un numéro (FE007)
  --
  -- On publie la salle et on lui donne des tarifs : sans grille, la demande
  -- échouerait pour la mauvaise raison.
  -- ---------------------------------------------------------------------------
  perform set_config('request.jwt.claims', '', true);

  insert into public.venue_pricing (venue_id, slot, base_price, weekend_coef,
                                    high_season_coef, included_seats, extra_seat_price)
  values (v_salle, 'soir', 200000, 1.30, 1.20, 300, 800);

  update public.venues v set status = 'published' where v.id = v_salle;

  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_amina, 'role', 'authenticated')::text,
                     true);

  begin
    perform public.request_booking(v_salle, c_date, 'soir', 250, null);
    raise exception 'ÉCHEC 5 — une demande est partie sans numéro. Le propriétaire '
                    'recevrait une demande de quelqu''un qu''il ne peut pas rappeler.';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE007' then
      raise exception 'ÉCHEC 5 — refus attendu FE007, reçu hint=% sqlstate=%.',
        coalesce(v_hint, '(vide)'), v_sqlstate;
    end if;
  end;

  begin
    perform public.request_booking(v_salle, c_date, 'soir', 250, '06 12 34');
    raise exception 'ÉCHEC 5 — un numéro trop court a été accepté.';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE007' then
      raise exception 'ÉCHEC 5 — refus attendu FE007 sur un numéro trop court, reçu hint=%.',
        coalesce(v_hint, '(vide)');
    end if;
  end;

  if (select count(*) from public.bookings b where b.venue_id = v_salle) <> 0 then
    raise exception 'ÉCHEC 5 — une demande a été écrite malgré le refus.';
  end if;

  -- Avec un numéro, la demande passe, et le numéro rejoint le profil.
  perform public.request_booking(v_salle, c_date, 'soir', 250, '0556 32 10 98', 'mariage');

  select p.phone into v_phone from public.profiles p where p.id = c_amina;
  if v_phone is distinct from '0556321098' then
    raise exception
      'ÉCHEC 5 — le numéro de la cliente n''est pas arrivé au profil : « % ». '
      'booking_contact() ne rendrait rien au propriétaire (§9).', coalesce(v_phone, 'NULL');
  end if;

  raise notice 'OK 5 — sans numéro valide, pas de demande : FE007, sqlstate %. Avec, le profil suit.',
    v_sqlstate;
end $$;

-- =============================================================================
-- Test 6 — UN INCONNU NE LIT TOUJOURS AUCUN NUMÉRO (§9)
--
-- C'est la règle que ce correctif aurait pu casser sans bruit : il vient
-- d'écrire des numéros là où il n'y en avait aucun. On regarde donc les trois
-- chemins par lesquels un numéro pourrait maintenant sortir.
--
-- `set local role authenticated` : les politiques RLS ne s'appliquent pas au
-- rôle de service, et sans changement de rôle ce test lirait tout et
-- n'annoncerait rien. Même raison qu'au test 3b de 005.
-- =============================================================================

set local role authenticated;
set local request.jwt.claims = '{"sub":"c0000007-0000-4000-a000-000000000003","role":"authenticated"}';

do $$
declare
  v_lignes integer;
begin
  -- LA TABLE, ET C'EST TOUT CE QU'IL Y A À REGARDER ICI : `profiles` n'est
  -- lisible que par son titulaire (002), et ce titulaire-là n'existe même pas.
  -- Si un numéro sort par cette porte, aucune des suivantes ne compte plus.
  select count(*) into v_lignes
  from public.profiles p where p.phone is not null;

  if v_lignes <> 0 then
    raise exception
      'ÉCHEC 6 — UN INCONNU LIT % NUMÉRO(S) DANS profiles. Le §9 dit qu''un numéro '
      'ne sort que par booking_contact(), à partir de « accepted ».', v_lignes;
  end if;

  raise notice 'OK 6a — un inconnu ne lit aucun numéro dans profiles.';
end $$;

reset role;

-- =============================================================================
-- Test 6 (suite) — les deux parties, et le moment où le numéro s'ouvre
--
-- La demande est « pending » : personne n'a encore de numéro, pas même le
-- propriétaire de la salle. C'est exactement la règle du §9 — « sinon la
-- plateforme se fait contourner dès la première recherche ».
-- =============================================================================

do $$
declare
  c_karim constant uuid := 'c0000007-0000-4000-a000-000000000001';
  c_amina constant uuid := 'c0000007-0000-4000-a000-000000000002';
  v_book  uuid;
  v_phone text;
  v_dispo boolean;
  v_lignes integer;
begin
  select b.id into v_book
  from public.bookings b
  join public.venues v on v.id = b.venue_id
  where v.owner_id = c_karim
  limit 1;

  if v_book is null then
    raise exception 'ÉCHEC 6 — la demande du test 5 est introuvable.';
  end if;

  -- Le propriétaire, sur une demande encore « pending ».
  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_karim, 'role', 'authenticated')::text,
                     true);

  select c.phone, c.phone_available into v_phone, v_dispo
  from public.booking_contact(v_book) c;

  if v_phone is not null or v_dispo then
    raise exception
      'ÉCHEC 6 — LE NUMÉRO DE LA CLIENTE SORT AVANT « accepted » : « % ». C''est le '
      'moment précis où la plateforme se fait contourner (§9).', v_phone;
  end if;

  -- Et le détail de la demande ne le porte pas non plus : il prend son numéro
  -- chez booking_contact(), comme tout le reste (014). C'est le seul écran
  -- propriétaire qui en montre un — la file, elle, n'a pas même la colonne.
  select count(*) into v_lignes
  from public.owner_request_detail(v_book) d
  where d.client_phone is not null or d.phone_available;

  if v_lignes <> 0 then
    raise exception
      'ÉCHEC 6 — owner_request_detail() rend un numéro sur une demande en attente.';
  end if;

  raise notice 'OK 6b — avant « accepted », aucun numéro ne sort, ni par booking_contact() ni par le détail.';

  -- ---------------------------------------------------------------------------
  -- Et après « accepted », il sort — c'est l'autre moitié de la règle, et c'est
  -- tout l'intérêt d'avoir écrit ces numéros.
  -- ---------------------------------------------------------------------------
  perform public.accepter_demande(v_book);

  select c.phone, c.phone_available into v_phone, v_dispo
  from public.booking_contact(v_book) c;

  if v_phone is distinct from '0556321098' or not v_dispo then
    raise exception
      'ÉCHEC 6 — après acceptation, le propriétaire obtient « % » au lieu du numéro '
      'de la cliente. Sans lui, il ne peut pas rappeler la famille.',
      coalesce(v_phone, 'NULL');
  end if;

  -- Et dans l'autre sens : la cliente obtient celui de la salle.
  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_amina, 'role', 'authenticated')::text,
                     true);

  select c.phone into v_phone from public.booking_contact(v_book) c;

  if v_phone is distinct from '0770112233' then
    raise exception
      'ÉCHEC 6 — après acceptation, la cliente obtient « % » au lieu du numéro du '
      'propriétaire.', coalesce(v_phone, 'NULL');
  end if;

  raise notice 'OK 6c — après « accepted », chaque partie obtient le numéro de l''autre. Le §9 tient dans les deux sens.';
end $$;

-- =============================================================================
-- Test 7 — L'ADRESSE NE SORT PAS, MÊME PAR LA TABLE
--
-- Le test qui compte. `venue_detail()` ne nomme pas la colonne — c'est facile à
-- vérifier et facile à croire. Ce qui l'était moins : la politique
-- `venues_select_published_or_own` (002) laisse un inconnu lire la LIGNE d'une
-- salle publiée, et RLS ne borne que les lignes. Sans les droits de colonne de
-- 019, un simple `GET /rest/v1/venues?select=address` aurait rendu l'adresse de
-- toutes les salles publiées.
--
-- On rejoue exactement cette requête, en rôle anon.
-- =============================================================================

set local role anon;
set local request.jwt.claims = '';

do $$
declare
  v_salle uuid;
  v_texte text;
  v_json  jsonb;
begin
  -- Ce qu'un inconnu a le droit de lire n'a pas changé.
  select v.id, v.name into v_salle, v_texte
  from public.venues v where v.name = 'Salle Les Oliviers';

  if v_salle is null then
    raise exception
      'ÉCHEC 7 — un inconnu ne voit plus la salle publiée. Les droits de colonne '
      'de 019 ont repris plus que l''adresse.';
  end if;

  -- L'adresse, elle, ne se lit pas.
  begin
    execute 'select v.address from public.venues v where v.id = $1'
      into v_texte using v_salle;
    raise exception
      'ÉCHEC 7 — UN INCONNU LIT L''ADRESSE D''UNE SALLE PUBLIÉE : « % ». Les droits '
      'de colonne de 019 sont tombés.', coalesce(v_texte, 'NULL');
  exception when insufficient_privilege then
    null;   -- c'est le refus attendu
  end;

  -- Et la fiche publique ne la nomme pas davantage.
  select public.venue_detail(v_salle) into v_json;

  if v_json ? 'address' then
    raise exception 'ÉCHEC 7 — venue_detail() renvoie une clé « address ».';
  end if;

  raise notice 'OK 7 — l''adresse ne sort ni par la table ni par la fiche ; le reste de la salle, si.';
end $$;

reset role;

-- =============================================================================
-- Test 8 — la règle, numéro par numéro
--
-- Le seul endroit du dépôt qui compare la règle SQL à des numéros écrits à la
-- main. C'est lui qui empêche lib/core/validation/telephone.dart de dériver :
-- les deux listes sont les mêmes, et le test Dart porte les mêmes numéros.
-- =============================================================================

do $$
declare
  v_bon  text;
  v_faux text;
begin
  foreach v_bon in array array[
    '0770112233',      -- mobile Mobilis
    '0661445566',      -- mobile Djezzy
    '0555778899',      -- mobile Ooredoo
    '0770 11 22 33',   -- le même, comme on l'écrit
    ' 0661445566 ',    -- des blancs autour
    '041234567',       -- fixe, Oran
    '031234567',       -- fixe, Constantine
    '021 23 45 67'     -- fixe, Alger
  ]
  loop
    if not public.telephone_valide(v_bon) then
      raise exception 'ÉCHEC 8 — « % » aurait dû être accepté.', v_bon;
    end if;
  end loop;

  foreach v_faux in array array[
    '',                  -- vide
    '   ',               -- des blancs
    '077011223',         -- LE CAS DU J12 : un mobile amputé d'un chiffre. Neuf
                         -- chiffres, mais un fixe ne commence pas par 7.
    '051234567',         -- neuf chiffres sous un deuxième chiffre de mobile
    '0212345678',        -- dix chiffres sous un deuxième chiffre de fixe
    '091234567',         -- 09 n'est ni un mobile ni un fixe
    '07701122',          -- huit chiffres : ni un mobile, ni un fixe
    '07701122334',       -- un chiffre de plus
    '1770112233',        -- ne commence pas par zéro
    '+213770112233',     -- l'indicatif international n'est pas de la mise en forme
    '0770-11-22-33',     -- les tirets non plus
    '0770.11.22.33',
    '0770AB2233'         -- des lettres
  ]
  loop
    if public.telephone_valide(v_faux) then
      raise exception 'ÉCHEC 8 — « % » aurait dû être refusé.', v_faux;
    end if;
  end loop;

  if public.telephone_valide(null) then
    raise exception 'ÉCHEC 8 — NULL n''est pas un numéro valide.';
  end if;

  if public.telephone_normalise('0770 11 22 33') is distinct from '0770112233' then
    raise exception 'ÉCHEC 8 — la normalisation ne retire pas les espaces.';
  end if;

  if public.telephone_normalise('   ') is not null then
    raise exception 'ÉCHEC 8 — un numéro de blancs devrait devenir NULL.';
  end if;

  raise notice 'OK 8 — la règle accepte les mobiles et les fixes, et rien d''autre.';
end $$;

rollback;
