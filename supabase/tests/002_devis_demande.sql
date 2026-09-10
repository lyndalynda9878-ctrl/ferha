-- =============================================================================
-- Ferha — tests/002_devis_demande.sql
-- Le devis de l'écran de demande, et les refus de request_booking().
--
-- Se colle tel quel dans l'éditeur SQL de Supabase. Il crée ses propres
-- données, vérifie six règles, et ANNULE TOUT par un ROLLBACK final : rien de
-- ce fichier ne reste en base. Une erreur rouge commençant par « ÉCHEC »
-- signale la règle qui ne tient plus.
--
-- CE QU'IL PROTÈGE, ET POURQUOI ÇA VAUT UN FICHIER
--
-- La règle du projet — « le prix vient d'estimate_price(), et de nulle part
-- ailleurs » — est facile à écrire et facile à trahir sans le vouloir : il
-- suffit qu'un jour booking_quote() « optimise » un total en le recomposant
-- elle-même. Le test 1 rend cette trahison visible : il compare, sur une même
-- demande, ce que dit estimate_price() et ce que dit booking_quote(). Les deux
-- doivent tomber au centime près, parce que ce sont les mêmes chiffres —
-- pas parce qu'ils ont été calculés deux fois pareil.
--
-- Prérequis : migrations 001 à 012 appliquées.
-- =============================================================================

begin;

do $$
declare
  c_owner  constant uuid := '55555555-5555-5555-5555-555555555555';
  c_client constant uuid := '66666666-6666-6666-6666-666666666666';
  c_venue  constant uuid := '77777777-7777-7777-7777-777777777777';

  -- Un vendredi de haute saison, et loin dans le futur : les deux majorations
  -- du §5.2 s'appliquent — la formule est exercée entière, pas dans son cas le
  -- plus simple — et aucune donnée réelle ne risque d'être croisée.
  c_date   constant date := date '2099-08-14';

  v_option_a uuid;
  v_option_b uuid;
  v_estime   numeric;
  v_devis    jsonb;
  v_taux     numeric;
  v_sqlstate text;
  v_hint     text;
begin
  -- ---------------------------------------------------------------------------
  -- Le décor
  -- ---------------------------------------------------------------------------
  insert into auth.users (instance_id, id, aud, role, email,
                          encrypted_password, email_confirmed_at,
                          created_at, updated_at,
                          raw_app_meta_data, raw_user_meta_data)
  values
    ('00000000-0000-0000-0000-000000000000', c_owner,  'authenticated', 'authenticated',
     'test.owner.002@ferha.test',  '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb),
    ('00000000-0000-0000-0000-000000000000', c_client, 'authenticated', 'authenticated',
     'test.client.002@ferha.test', '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb);

  insert into public.profiles (id, full_name, email, is_owner) values
    (c_owner,  'Propriétaire de test', 'test.owner.002@ferha.test',  true),
    (c_client, 'Cliente de test',      'test.client.002@ferha.test', false)
  on conflict (id) do nothing;   -- le déclencheur de 007 a pu les créer

  insert into public.venues (id, owner_id, name, wilaya_code, commune,
                             capacity_seated, status)
  values (c_venue, c_owner, 'Salle de test 002', '31', 'Oran', 400, 'published');

  -- Grille tarifaire : c'est elle que lira estimate_price().
  insert into public.venue_pricing (venue_id, slot, base_price, weekend_coef,
                                    high_season_coef, included_seats, extra_seat_price)
  values
    (c_venue, 'midi',    100000, 1.30, 1.20, 200, 800),
    (c_venue, 'soir',    200000, 1.30, 1.20, 200, 800),
    (c_venue, 'journee', 280000, 1.30, 1.20, 200, 800);

  -- Deux options : une payante, une incluse. La seconde existe pour vérifier
  -- qu'un forfait à zéro dinar reste une option retenue, et non une option
  -- ignorée — la maquette l'affiche « Incluse », pas absente.
  insert into public.venue_options (venue_id, code, label_fr, label_ar, price, "position")
  values
    (c_venue, 'decoration', 'Décoration', 'تزيين',      25000, 10),
    (c_venue, 'chambre',    'Chambre',    'غرفة العروس',    0, 20);

  select id into v_option_a from public.venue_options
   where venue_id = c_venue and code = 'decoration';
  select id into v_option_b from public.venue_options
   where venue_id = c_venue and code = 'chambre';

  -- ---------------------------------------------------------------------------
  -- Test 1 — booking_quote() ne s'écarte JAMAIS d'estimate_price()
  --
  -- La règle du projet en une assertion. Si un jour quelqu'un recompose un
  -- total dans booking_quote(), c'est ici que ça se voit.
  -- ---------------------------------------------------------------------------
  select e.total into v_estime
  from public.estimate_price(c_venue, c_date, 'soir', 250,
                             array[v_option_a, v_option_b]) e;

  v_devis := public.booking_quote(c_venue, c_date, 'soir', 250,
                                  array[v_option_a, v_option_b]);

  if (v_devis->>'total')::numeric is distinct from v_estime then
    raise exception 'ÉCHEC 1 — booking_quote() annonce % là où estimate_price() dit %.',
      v_devis->>'total', v_estime;
  end if;

  -- Et pas seulement le total : chaque poste doit être le même, sinon un
  -- récapitulatif juste au total pourrait mentir ligne par ligne.
  if (v_devis->>'slot_price')::numeric         is distinct from (select e.slot_price         from public.estimate_price(c_venue, c_date, 'soir', 250, array[v_option_a, v_option_b]) e)
  or (v_devis->>'extra_seats_amount')::numeric is distinct from (select e.extra_seats_amount from public.estimate_price(c_venue, c_date, 'soir', 250, array[v_option_a, v_option_b]) e)
  or (v_devis->>'options_amount')::numeric     is distinct from (select e.options_amount     from public.estimate_price(c_venue, c_date, 'soir', 250, array[v_option_a, v_option_b]) e)
  then
    raise exception 'ÉCHEC 1 bis — un poste du devis s''écarte d''estimate_price().';
  end if;

  raise notice 'OK 1/6 — booking_quote() rend exactement estimate_price() : % DZD.', v_estime;

  -- ---------------------------------------------------------------------------
  -- Test 2 — l'acompte vient de deposit_rate(), et de nulle part ailleurs
  -- ---------------------------------------------------------------------------
  v_taux := public.deposit_rate();

  if (v_devis->>'deposit_rate')::numeric is distinct from v_taux then
    raise exception 'ÉCHEC 2 — le devis annonce un taux de % au lieu de %.',
      v_devis->>'deposit_rate', v_taux;
  end if;

  if (v_devis->>'deposit_amount')::numeric is distinct from round(v_estime * v_taux, 2) then
    raise exception 'ÉCHEC 2 — acompte de % au lieu de % (% × %).',
      v_devis->>'deposit_amount', round(v_estime * v_taux, 2), v_estime, v_taux;
  end if;

  raise notice 'OK 2/6 — acompte = % DZD, soit % du devis.',
    v_devis->>'deposit_amount', v_taux;

  -- ---------------------------------------------------------------------------
  -- Test 3 — une option à zéro dinar est RETENUE, pas ignorée
  --
  -- Elle ne change pas le total, mais elle doit apparaître dans les options
  -- nommées : c'est le « ☑ Chambre de la mariée · Incluse » de la maquette. Un
  -- filtre « price > 0 » posé un jour par distraction la ferait disparaître de
  -- l'écran alors que la salle la propose.
  -- ---------------------------------------------------------------------------
  if jsonb_array_length(v_devis->'options') <> 2 then
    raise exception 'ÉCHEC 3 — % option(s) nommée(s) au lieu de 2 : une option incluse a été perdue.',
      jsonb_array_length(v_devis->'options');
  end if;

  raise notice 'OK 3/6 — l''option incluse est nommée, sans rien ajouter au total.';

  -- ---------------------------------------------------------------------------
  -- Test 4 — un identifiant d'option emprunté à une autre salle ne facture rien
  --
  -- estimate_price() filtre sur venue_id ; booking_quote() nomme avec le même
  -- filtre. Les deux doivent donc ignorer un identifiant étranger — et surtout
  -- ne pas en facturer le prix.
  -- ---------------------------------------------------------------------------
  v_devis := public.booking_quote(c_venue, c_date, 'soir', 250,
                                  array[gen_random_uuid()]);

  if (v_devis->>'options_amount')::numeric <> 0
  or jsonb_array_length(v_devis->'options') <> 0 then
    raise exception 'ÉCHEC 4 — une option étrangère à la salle a été comptée.';
  end if;

  raise notice 'OK 4/6 — une option qui n''est pas de cette salle ne rapporte rien.';

  -- ---------------------------------------------------------------------------
  -- Test 5 — le créneau bloqué par le propriétaire porte le code FE002
  --
  -- On vérifie le HINT, pas le message : c'est le hint que lit l'application
  -- (lib/features/booking/booking_messages.dart), et c'est lui le contrat.
  -- ---------------------------------------------------------------------------
  insert into public.venue_blackouts (venue_id, date, slot, reason)
  values (c_venue, c_date, 'soir', 'Travaux');

  -- request_booking() est SECURITY DEFINER mais lit auth.uid() : on se fait
  -- passer pour la cliente le temps de l'appel.
  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_client, 'role', 'authenticated')::text,
                     true);

  begin
    perform public.request_booking(c_venue, c_date, 'soir', 250, '0770 11 22 33');
    raise exception 'ÉCHEC 5 — un créneau bloqué a accepté une demande.';
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_hint = pg_exception_hint;
    if v_hint is distinct from 'FE002' then
      raise exception 'ÉCHEC 5 — refus attendu FE002, reçu hint=% sqlstate=%.',
        coalesce(v_hint, '(vide)'), v_sqlstate;
    end if;
  end;

  raise notice 'OK 5/6 — créneau bloqué : hint FE002, sqlstate % (donc HTTP 409).', v_sqlstate;

  -- ---------------------------------------------------------------------------
  -- Test 6 — la demande passe, et son montant vient d'estimate_price()
  --
  -- C'est le trigger bookings_set_price qui l'écrit : le client envoie 0, la
  -- base pose le vrai prix. Et sur une journée entière, DEUX lignes portent le
  -- même montant — celui du groupe, à ne jamais additionner (§6.1).
  -- ---------------------------------------------------------------------------
  delete from public.venue_blackouts where venue_id = c_venue;

  select e.total into v_estime
  from public.estimate_price(c_venue, c_date, 'journee', 250, array[v_option_a]) e;

  if (select count(*) from public.request_booking(
        c_venue, c_date, 'journee', 250, '0770 11 22 33',
        'mariage', null, array[v_option_a])) <> 2 then
    raise exception 'ÉCHEC 6 — une journée entière n''a pas produit deux lignes (§6.1).';
  end if;

  if (select count(distinct b.quoted_amount) from public.bookings b
       where b.venue_id = c_venue and b.event_date = c_date) <> 1
  or (select max(b.quoted_amount) from public.bookings b
       where b.venue_id = c_venue and b.event_date = c_date) is distinct from v_estime then
    raise exception 'ÉCHEC 6 — le montant écrit en base ne vient pas d''estimate_price() (% attendu).',
      v_estime;
  end if;

  if (select count(*) from public.bookings b
       where b.venue_id = c_venue and b.status <> 'pending') > 0 then
    raise exception 'ÉCHEC 6 — une demande ne naît pas en « pending ».';
  end if;

  raise notice 'OK 6/6 — demande posée en pending, % DZD sur ses deux lignes.', v_estime;

  raise notice 'Tous les tests passent. Le ROLLBACK qui suit efface tout.';
end $$;

rollback;
