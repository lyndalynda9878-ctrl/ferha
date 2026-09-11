-- =============================================================================
-- Ferha — tests/013_webhook_bac_a_sable.sql
-- Le décor du test de webhook, et sa lecture.
--
-- POURQUOI CE FICHIER N'EST PAS COMME LES AUTRES : IL NE FAIT PAS DE ROLLBACK.
--
-- Tous les autres tests du dossier vivent dans une transaction annulée à la
-- fin. Celui-ci ne le peut pas : ce qu'il prépare doit être VU depuis un autre
-- processus — la Edge Function chargily-webhook, qui tourne chez Supabase et
-- ouvre sa propre connexion. Une transaction ouverte ici ne lui montrerait
-- rien. Le décor est donc écrit pour de bon, et la section 3 l'efface.
--
-- COMMENT ON S'EN SERT, DANS L'ORDRE :
--
--   1. Coller la SECTION 1 dans l'éditeur SQL de Supabase et l'exécuter.
--      Elle pose quatre réservations et leurs quatre pages de paiement.
--   2. Lancer supabase/tests/webhook_chargily.ps1 depuis PowerShell.
--      Il fabrique des événements SIGNÉS et les envoie à la fonction déployée.
--   3. Coller la SECTION 2 et l'exécuter. Elle dit ce que la base a compris.
--   4. Coller la SECTION 3 pour tout effacer.
--
-- POURQUOI CE DÉTOUR PLUTÔT QUE LA VRAIE PAGE CHARGILY. La page de paiement
-- n'est pas joignable depuis toutes les connexions algériennes, et un
-- développement ne peut pas dépendre de cela. Le webhook, lui, se teste
-- entièrement sans elle : il ne demande qu'un corps JSON et une signature
-- HMAC — et la signature se calcule avec la même clé, où qu'on soit.
--
-- CE N'EST PAS UNE SIMULATION AU RABAIS. Le script signe avec la VRAIE clé
-- secrète, la fonction déployée vérifie cette signature comme elle vérifiera
-- celle de Chargily, et la base traite l'événement par le même chemin. La seule
-- chose qu'on ne voit pas, c'est le formulaire de carte.
--
-- L'ACOMPTE EST FORCÉ À 50 000 DA sur les quatre réservations, pour que le
-- script n'ait pas à deviner un montant. C'est le seul artifice du décor.
--
-- Prérequis : migrations 001 à 025 appliquées.
-- =============================================================================


-- =============================================================================
-- SECTION 1 — POSER LE DÉCOR
--
-- Quatre réservations acceptées, quatre pages de paiement ouvertes, et un
-- compte administrateur pour recevoir les alertes d'anomalie.
--
--   wh_paid_001      option valide, montant juste   → doit confirmer
--   wh_montant_001   option valide, montant faux    → doit marquer « à examiner »
--   wh_expiree_001   option ÉCHUE                   → doit marquer « à rembourser »
--   wh_echec_001     option valide, paiement refusé → l'option doit survivre
-- =============================================================================

do $$
declare
  c_venue constant uuid := 'c0000013-0000-4000-a000-000000000001';
  c_owner constant uuid := 'c0000013-0000-4000-a000-000000000002';
  c_amina constant uuid := 'c0000013-0000-4000-a000-000000000003';
  c_admin constant uuid := 'c0000013-0000-4000-a000-000000000009';

  v_paid    uuid;
  v_montant uuid;
  v_expiree uuid;
  v_echec   uuid;
begin
  insert into auth.users (instance_id, id, aud, role, email,
                          encrypted_password, email_confirmed_at,
                          created_at, updated_at,
                          raw_app_meta_data, raw_user_meta_data)
  values
    ('00000000-0000-0000-0000-000000000000', c_owner, 'authenticated', 'authenticated',
     'test.owner.013@ferha.test', '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb),
    ('00000000-0000-0000-0000-000000000000', c_amina, 'authenticated', 'authenticated',
     'test.amina.013@ferha.test', '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb),
    ('00000000-0000-0000-0000-000000000000', c_admin, 'authenticated', 'authenticated',
     'test.admin.013@ferha.test', '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb)
  on conflict (id) do nothing;

  insert into public.profiles (id, full_name, email, is_owner, is_admin) values
    (c_owner, 'Karim Propriétaire', 'test.owner.013@ferha.test', true,  false),
    (c_amina, 'Amina Haddad',       'test.amina.013@ferha.test', false, false),
    (c_admin, 'Administration',     'test.admin.013@ferha.test', false, true)
  on conflict (id) do update
    set full_name = excluded.full_name,
        is_owner  = excluded.is_owner,
        is_admin  = excluded.is_admin;

  insert into public.venues (id, owner_id, name, wilaya_code, commune,
                             capacity_seated, status)
  values (c_venue, c_owner, 'Salle du bac à sable 013', '31', 'Oran', 400, 'published')
  on conflict (id) do nothing;

  insert into public.venue_pricing (venue_id, slot, base_price, weekend_coef,
                                    high_season_coef, included_seats, extra_seat_price)
  values
    (c_venue, 'midi',    100000, 1.30, 1.20, 200, 800),
    (c_venue, 'soir',    200000, 1.30, 1.20, 200, 800),
    (c_venue, 'journee', 280000, 1.30, 1.20, 200, 800)
  on conflict do nothing;

  -- Quatre demandes, quatre dates : l'index du §6.1 ne doit jamais s'en mêler.
  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_amina, 'role', 'authenticated')::text, true);

  select b.id into v_paid    from public.request_booking(c_venue, date '2099-10-03', 'soir', 250, '0770112233') b order by b.slot limit 1;
  select b.id into v_montant from public.request_booking(c_venue, date '2099-10-10', 'soir', 250, '0770112233') b order by b.slot limit 1;
  select b.id into v_expiree from public.request_booking(c_venue, date '2099-10-17', 'soir', 250, '0770112233') b order by b.slot limit 1;
  select b.id into v_echec   from public.request_booking(c_venue, date '2099-10-24', 'soir', 250, '0770112233') b order by b.slot limit 1;

  perform set_config('request.jwt.claims',
                     json_build_object('sub', c_owner, 'role', 'authenticated')::text, true);
  perform public.accepter_demande(v_paid);
  perform public.accepter_demande(v_montant);
  perform public.accepter_demande(v_expiree);
  perform public.accepter_demande(v_echec);

  -- L'acompte rond, pour que le script n'ait pas de calcul à faire.
  update public.bookings set deposit_amount = 50000
   where id in (v_paid, v_montant, v_expiree, v_echec);

  -- Les pages de paiement. Elles passent par enregistrer_checkout() (024) —
  -- donc par montant_acompte(), donc au bon montant, comme en vrai.
  perform public.enregistrer_checkout(v_paid,    'wh_paid_001',    'cib');
  perform public.enregistrer_checkout(v_montant, 'wh_montant_001', 'cib');
  perform public.enregistrer_checkout(v_expiree, 'wh_expiree_001', 'cib');
  perform public.enregistrer_checkout(v_echec,   'wh_echec_001',   'edahabia');

  -- L'option échue se pose APRÈS l'ouverture de sa page : enregistrer_checkout()
  -- refuserait une option déjà morte (FE053), et c'est bien ce qu'on veut
  -- d'elle. On simule donc le vrai ordre — la page s'ouvre, puis le temps
  -- passe.
  update public.bookings
     set option_expires_at = now() - interval '2 hours'
   where id = v_expiree;

  perform set_config('request.jwt.claims', '', true);

  raise notice 'Décor posé. Acompte attendu : 50000 DA sur les quatre.';
  raise notice 'Lancez maintenant supabase/tests/webhook_chargily.ps1';
end $$;


-- =============================================================================
-- SECTION 2 — CE QUE LA BASE A COMPRIS
--
-- À exécuter APRÈS le script PowerShell. Chaque ligne dit, pour une page de
-- paiement : où en est l'argent, ce qui a cloché, et où en est la réservation.
--
-- CE QU'ON DOIT LIRE :
--
--  checkout         status   anomalie            suite          booking
--  wh_paid_001      paid     (vide)              (vide)         confirmed
--  wh_montant_001   paid     montant_different   a_examiner     accepted
--  wh_expiree_001   paid     option_expiree      a_rembourser   accepted
--  wh_echec_001     failed   (vide)              (vide)         accepted
--
-- LES TROIS DERNIÈRES LIGNES SONT LE CŒUR DU TEST. Un paiement encaissé ne
-- confirme PAS tout seul : il confirme quand tout est en ordre, et laisse une
-- trace lisible quand il ne le peut pas. Et « accepted » sur la dernière ligne
-- veut dire que l'option a survécu à une carte refusée — le client peut
-- réessayer, ou payer en espèces.
-- =============================================================================

select
  p.checkout_id                       as checkout,
  p.status,
  coalesce(p.anomalie, '')            as anomalie,
  coalesce(x.suite, '')               as suite,
  b.status                            as booking,
  p.amount                            as montant_attendu,
  p.raw_webhook -> 'data' ->> 'amount' as montant_recu,
  (p.raw_webhook ->> 'type')          as evenement
from public.payments p
join public.bookings b on b.id = p.booking_id
left join public.paiements_a_examiner x on x.id = p.id
where p.checkout_id like 'wh\_%'
order by p.checkout_id;

-- Les notifications déposées par ces événements. « payment_to_refund » doit
-- partir aux DEUX parties plus l'administration ; « payment_anomaly » à
-- l'administration seule ; « payment_failed » au client seul.
select
  n.type,
  pr.full_name  as destinataire,
  case when pr.is_admin then 'administration'
       when pr.is_owner then 'propriétaire'
       else 'cliente' end as qui,
  n.payload ->> 'attendu' as attendu,
  n.payload ->> 'recu'    as recu
from public.notifications n
join public.profiles pr on pr.id = n.user_id
where n.type in ('payment_failed', 'payment_to_refund', 'payment_anomaly')
  and n.user_id in ('c0000013-0000-4000-a000-000000000002'::uuid,
                    'c0000013-0000-4000-a000-000000000003'::uuid,
                    'c0000013-0000-4000-a000-000000000009'::uuid)
order by n.type, qui;


-- =============================================================================
-- SECTION 3 — TOUT EFFACER
--
-- Dans cet ordre, et pas un autre : bookings.client_id et bookings.venue_id
-- sont en RESTRICT (voir CLAUDE.md — c'est le filet qui garantit qu'on écrira
-- une anonymisation plutôt qu'une suppression). Il faut donc retirer ce qui
-- pend AVANT ce à quoi cela pend.
--
-- Ces comptes-là sont des comptes de test, créés par la section 1 : les
-- supprimer est légitime. Un vrai compte, lui, s'anonymise.
-- =============================================================================

delete from public.payments p
 where p.booking_id in (select b.id from public.bookings b
                         where b.venue_id = 'c0000013-0000-4000-a000-000000000001'::uuid);

delete from public.notifications n
 where n.user_id in ('c0000013-0000-4000-a000-000000000002'::uuid,
                     'c0000013-0000-4000-a000-000000000003'::uuid,
                     'c0000013-0000-4000-a000-000000000009'::uuid);

delete from public.bookings b
 where b.venue_id = 'c0000013-0000-4000-a000-000000000001'::uuid;

delete from public.venue_pricing vp
 where vp.venue_id = 'c0000013-0000-4000-a000-000000000001'::uuid;

delete from public.venues v
 where v.id = 'c0000013-0000-4000-a000-000000000001'::uuid;

delete from public.profiles p
 where p.id in ('c0000013-0000-4000-a000-000000000002'::uuid,
                'c0000013-0000-4000-a000-000000000003'::uuid,
                'c0000013-0000-4000-a000-000000000009'::uuid);

delete from auth.users u
 where u.id in ('c0000013-0000-4000-a000-000000000002'::uuid,
                'c0000013-0000-4000-a000-000000000003'::uuid,
                'c0000013-0000-4000-a000-000000000009'::uuid);
