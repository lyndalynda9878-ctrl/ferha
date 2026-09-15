-- =============================================================================
-- Ferha — seed/004_demo_bookings.sql
-- De quoi remplir le tableau de bord de Karim : des demandes en attente, des
-- réservations tenues, des refus, et trois avis.
--
-- CE FICHIER N'EST PAS UNE MIGRATION. Il ne crée aucune table : il pose des
-- données de démonstration, et 002_reset_demo.sql sait les effacer.
--
-- POURQUOI IL EXISTE. Un tableau de bord sans réservation ne se vérifie pas :
-- on ne voit ni si le taux d'occupation est juste, ni si la variation change de
-- signe, ni si les demandes en attente passent bien devant les chiffres. Ces
-- lignes-là donnent à l'écran 9 de quoi être regardé.
--
-- AUCUN PRIX N'EST ÉCRIT ICI, et c'est la règle du projet : le trigger
-- bookings_set_price (005) écrase quoted_amount par estimate_price() à chaque
-- insertion. Les montants insérés ci-dessous valent 0 — ils seront remplacés.
-- L'acompte se calcule ensuite, à partir du devis obtenu et de deposit_rate()
-- (012), jamais d'un taux recopié.
--
-- LES ÉTATS SONT ÉCRITS DIRECTEMENT, ce qui n'est PAS ce que fait
-- l'application. Un client passe par request_booking(), un propriétaire par
-- accept_booking() et refuse_booking() (004) : ces fonctions vérifient qui
-- appelle, et elles exigent donc une session. Un fichier de seed n'en a pas.
-- On écrit ici l'état d'arrivée, avec ses horodatages, comme une base
-- restaurée : c'est le seul endroit du projet où cela se fait, et il ne part
-- pas en production.
--
-- REJOUABLE : les lignes de démonstration sont effacées puis réécrites. Elles
-- se reconnaissent à leur identifiant (b0000000-…), comme les salles à
-- 5a11e000-… et les personnes à d0000000-….
--
-- Prérequis : migrations 001 à 014, et seed/001_demo_venues.sql.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- Trois clientes et clients de plus
--
-- Amina (d…010) existe déjà et sert de compte de démonstration. Une file de
-- demandes où le même prénom revient trois fois ne ressemble à rien : voici
-- trois personnes de plus. On ne se connecte pas à ces comptes — ils ne portent
-- pas de mot de passe, ils portent des demandes.
-- -----------------------------------------------------------------------------

insert into auth.users (instance_id, id, aud, role, email,
                        encrypted_password, email_confirmed_at,
                        created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
values
  ('00000000-0000-0000-0000-000000000000', 'd0000000-0000-4000-a000-000000000011', 'authenticated', 'authenticated',
   'sofia.benali@demo.ferha.dz',  '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb),
  ('00000000-0000-0000-0000-000000000000', 'd0000000-0000-4000-a000-000000000012', 'authenticated', 'authenticated',
   'mehdi.larbi@demo.ferha.dz',   '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb),
  ('00000000-0000-0000-0000-000000000000', 'd0000000-0000-4000-a000-000000000013', 'authenticated', 'authenticated',
   'lila.zerrouki@demo.ferha.dz', '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb)
on conflict (id) do nothing;

-- Sans numéro, pour la raison écrite en tête de 001. Ceux-ci sont vus depuis
-- l'autre côté — c'est le propriétaire qui lit le contact d'une demande — mais
-- un numéro joignable l'est dans les deux sens.

insert into public.profiles (id, full_name, email, phone, is_owner) values
  ('d0000000-0000-4000-a000-000000000011', 'Sofia Benali',   'sofia.benali@demo.ferha.dz',  null, false),
  ('d0000000-0000-4000-a000-000000000012', 'Mehdi Larbi',    'mehdi.larbi@demo.ferha.dz',   null, false),
  ('d0000000-0000-4000-a000-000000000013', 'Lila Zerrouki',  'lila.zerrouki@demo.ferha.dz', null, false)
on conflict (id) do update set
  full_name = excluded.full_name,
  email     = excluded.email,
  phone     = excluded.phone,
  is_owner  = excluded.is_owner;

-- -----------------------------------------------------------------------------
-- Table rase — les avis d'abord, les réservations ensuite
--
-- reviews.booking_id est en RESTRICT : un avis publié ne s'efface pas en
-- supprimant sa réservation. C'est voulu (§5.4), et cela impose l'ordre.
-- -----------------------------------------------------------------------------

delete from public.reviews  where booking_id::text like 'b0000000-%';
delete from public.bookings where id::text         like 'b0000000-%';

-- -----------------------------------------------------------------------------
-- Les réservations
--
-- Deux salles de Karim : Salle El Bahia (…0001), qui tourne, et Résidence Les
-- Andalouses (…0002), qui n'a qu'une demande en attente — de quoi voir un
-- tableau de bord vide à côté d'un tableau de bord plein.
--
-- Les identifiants disent à quoi ils servent :
--   b0000000-0000-4000-a000-0000000000NN   une ligne de réservation
--   b0000000-0000-4000-b000-0000000000NN   le groupe qui la porte
--
-- Une journée entière occupe DEUX lignes du même groupe (§6.1) : le trigger
-- bookings_check_journee les exige toutes les deux dans la même instruction.
-- C'est pourquoi tout est inséré d'un seul coup ci-dessous.
--
-- Les dates d'événement sont fixes et lointaines (2026-2027) : elles ne
-- dépendent pas du jour où l'on lance le seed. Les dates de DEMANDE, elles, se
-- calculent en relatif — « il y a deux heures », « hier » — parce que c'est
-- exactement ce que la maquette affiche à côté de chaque demande en attente.
-- -----------------------------------------------------------------------------

-- TOUT NAÎT EN ATTENTE, comme dans l'application : la colonne status n'est pas
-- écrite ici, et sa valeur par défaut s'applique. Ce n'est pas une coquetterie
-- — la contrainte bookings_confirmed_requires_deposit interdit d'insérer une
-- réservation confirmée sans acompte, et l'acompte se déduit du devis, que le
-- trigger ne pose qu'une fois la ligne écrite. L'état d'arrivée se pose donc
-- juste après, en une instruction, à partir des horodatages ci-dessous.

insert into public.bookings (
  id, group_id, venue_id, client_id, event_date, slot, requested_slot,
  guest_count, event_type, client_message, quoted_amount,
  created_at, accepted_at, confirmed_at, completed_at, status_reason
) values

  -- === EN ATTENTE — la file de travail du jour ===============================
  ('b0000000-0000-4000-a000-000000000001', 'b0000000-0000-4000-b000-000000000001',
   '5a11e000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-000000000011',
   '2027-05-15', 'soir', 'soir', 320, 'mariage',
   'Bonjour, nous sommes une famille de 320 personnes environ. Est-ce que la '
   'salle peut accueillir un orchestre ? Merci d''avance.',
    0, now() - interval '2 hours', null, null, null, null),

  ('b0000000-0000-4000-a000-000000000002', 'b0000000-0000-4000-b000-000000000002',
   '5a11e000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-000000000012',
   '2026-11-06', 'midi', 'midi', 180, 'circoncision',
   null,
    0, now() - interval '1 day', null, null, null, null),

  -- Une journée entière : deux lignes, un seul groupe, une seule demande.
  ('b0000000-0000-4000-a000-000000000003', 'b0000000-0000-4000-b000-000000000003',
   '5a11e000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-000000000010',
   '2027-07-03', 'midi', 'journee', 400, 'mariage',
   'Nous aimerions la journée complète, avec le henné le midi.',
    0, now() - interval '3 days', null, null, null, null),
  ('b0000000-0000-4000-a000-000000000004', 'b0000000-0000-4000-b000-000000000003',
   '5a11e000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-000000000010',
   '2027-07-03', 'soir', 'journee', 400, 'mariage',
   'Nous aimerions la journée complète, avec le henné le midi.',
    0, now() - interval '3 days', null, null, null, null),

  -- L'autre salle, pour qu'elle ne soit pas vide non plus.
  ('b0000000-0000-4000-a000-000000000005', 'b0000000-0000-4000-b000-000000000004',
   '5a11e000-0000-4000-a000-000000000002', 'd0000000-0000-4000-a000-000000000013',
   '2026-12-19', 'soir', 'soir', 250, 'fiancailles',
   'Bonsoir, est-ce que le tarif comprend la décoration ?',
    0, now() - interval '5 hours', null, null, null, null),

  -- === SEPTEMBRE 2026 — le mois en cours =====================================
  -- Deux événements déjà passés (honorés), six à venir (confirmés).
  ('b0000000-0000-4000-a000-000000000010', 'b0000000-0000-4000-b000-000000000010',
   '5a11e000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-000000000011',
   '2026-09-05', 'soir', 'soir', 300, 'mariage', null,
    0, '2026-08-28 10:00+01', '2026-08-29 09:00+01', '2026-08-30 12:00+01', '2026-09-06 09:00+01', null),

  ('b0000000-0000-4000-a000-000000000011', 'b0000000-0000-4000-b000-000000000011',
   '5a11e000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-000000000012',
   '2026-09-06', 'midi', 'journee', 260, 'circoncision', null,
    0, '2026-09-01 09:30+01', '2026-09-01 18:00+01', '2026-09-02 10:00+01', '2026-09-07 09:00+01', null),
  ('b0000000-0000-4000-a000-000000000012', 'b0000000-0000-4000-b000-000000000011',
   '5a11e000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-000000000012',
   '2026-09-06', 'soir', 'journee', 260, 'circoncision', null,
    0, '2026-09-01 09:30+01', '2026-09-01 18:00+01', '2026-09-02 10:00+01', '2026-09-07 09:00+01', null),

  ('b0000000-0000-4000-a000-000000000013', 'b0000000-0000-4000-b000-000000000012',
   '5a11e000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-000000000013',
   '2026-09-12', 'soir', 'soir', 340, 'mariage', null,
    0, '2026-09-02 11:00+01', '2026-09-02 20:00+01', '2026-09-03 09:00+01', null, null),

  ('b0000000-0000-4000-a000-000000000014', 'b0000000-0000-4000-b000-000000000013',
   '5a11e000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-000000000010',
   '2026-09-13', 'soir', 'soir', 280, 'fiancailles', null,
    0, '2026-09-03 14:00+01', '2026-09-03 21:00+01', '2026-09-04 08:30+01', null, null),

  ('b0000000-0000-4000-a000-000000000015', 'b0000000-0000-4000-b000-000000000014',
   '5a11e000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-000000000011',
   '2026-09-19', 'soir', 'soir', 310, 'mariage', null,
    0, '2026-08-20 09:00+01', '2026-08-20 19:00+01', '2026-08-21 10:00+01', null, null),

  ('b0000000-0000-4000-a000-000000000016', 'b0000000-0000-4000-b000-000000000015',
   '5a11e000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-000000000012',
   '2026-09-20', 'midi', 'journee', 390, 'mariage', null,
    0, '2026-09-04 10:00+01', '2026-09-04 17:00+01', '2026-09-05 09:00+01', null, null),
  ('b0000000-0000-4000-a000-000000000017', 'b0000000-0000-4000-b000-000000000015',
   '5a11e000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-000000000012',
   '2026-09-20', 'soir', 'journee', 390, 'mariage', null,
    0, '2026-09-04 10:00+01', '2026-09-04 17:00+01', '2026-09-05 09:00+01', null, null),

  ('b0000000-0000-4000-a000-000000000018', 'b0000000-0000-4000-b000-000000000016',
   '5a11e000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-000000000013',
   '2026-09-26', 'soir', 'soir', 350, 'mariage', null,
    0, '2026-09-05 08:00+01', '2026-09-05 16:00+01', '2026-09-06 09:00+01', null, null),

  ('b0000000-0000-4000-a000-000000000019', 'b0000000-0000-4000-b000-000000000017',
   '5a11e000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-000000000010',
   '2026-09-27', 'midi', 'midi', 150, 'anniversaire', null,
    0, '2026-09-07 13:00+01', '2026-09-07 19:00+01', '2026-09-08 09:00+01', null, null),

  -- === AOÛT 2026 — le mois précédent, celui des variations ===================
  ('b0000000-0000-4000-a000-000000000020', 'b0000000-0000-4000-b000-000000000020',
   '5a11e000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-000000000011',
   '2026-08-01', 'soir', 'soir', 300, 'mariage', null,
    0, '2026-07-10 10:00+01', '2026-07-11 09:00+01', '2026-07-12 09:00+01', '2026-08-02 09:00+01', null),

  ('b0000000-0000-4000-a000-000000000021', 'b0000000-0000-4000-b000-000000000021',
   '5a11e000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-000000000012',
   '2026-08-08', 'soir', 'soir', 280, 'mariage', null,
    0, '2026-07-22 11:00+01', '2026-07-23 09:00+01', '2026-07-24 09:00+01', '2026-08-09 09:00+01', null),

  ('b0000000-0000-4000-a000-000000000022', 'b0000000-0000-4000-b000-000000000022',
   '5a11e000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-000000000013',
   '2026-08-15', 'midi', 'journee', 420, 'mariage', null,
    0, '2026-08-01 09:00+01', '2026-08-01 20:00+01', '2026-08-02 09:00+01', '2026-08-16 09:00+01', null),
  ('b0000000-0000-4000-a000-000000000023', 'b0000000-0000-4000-b000-000000000022',
   '5a11e000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-000000000013',
   '2026-08-15', 'soir', 'journee', 420, 'mariage', null,
    0, '2026-08-01 09:00+01', '2026-08-01 20:00+01', '2026-08-02 09:00+01', '2026-08-16 09:00+01', null),

  ('b0000000-0000-4000-a000-000000000024', 'b0000000-0000-4000-b000-000000000023',
   '5a11e000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-000000000010',
   '2026-08-22', 'soir', 'soir', 260, 'fiancailles', null,
    0, '2026-08-05 15:00+01', '2026-08-05 21:00+01', '2026-08-06 09:00+01', '2026-08-23 09:00+01', null),

  ('b0000000-0000-4000-a000-000000000025', 'b0000000-0000-4000-b000-000000000024',
   '5a11e000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-000000000011',
   '2026-08-29', 'soir', 'soir', 330, 'mariage', null,
    0, '2026-08-11 10:00+01', '2026-08-11 18:00+01', '2026-08-12 09:00+01', '2026-08-30 09:00+01', null),

  -- === REFUSÉES — sans elles, la part des demandes acceptées vaudrait 100 % ==
  ('b0000000-0000-4000-a000-000000000030', 'b0000000-0000-4000-b000-000000000030',
   '5a11e000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-000000000012',
   '2026-09-12', 'midi', 'midi', 500, 'mariage', null,
    0, '2026-09-06 09:00+01', null, null, null,
   'Nombre d''invités au-delà de la capacité de la salle.'),

  ('b0000000-0000-4000-a000-000000000031', 'b0000000-0000-4000-b000-000000000031',
   '5a11e000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-000000000013',
   '2026-10-03', 'soir', 'soir', 200, 'anniversaire', null,
    0, '2026-09-08 17:00+01', null, null, null,
   'Date déjà retenue pour un autre événement.'),

  ('b0000000-0000-4000-a000-000000000032', 'b0000000-0000-4000-b000-000000000032',
   '5a11e000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-000000000011',
   '2026-08-22', 'midi', 'midi', 240, 'anniversaire', null,
    0, '2026-08-03 12:00+01', null, null, null,
   'Salle indisponible ce midi-là.');

-- -----------------------------------------------------------------------------
-- L'état d'arrivée, et l'acompte qui va avec
--
-- L'état se DÉDUIT des horodatages, il ne se répète pas : une ligne qui porte
-- completed_at est honorée, une ligne qui porte confirmed_at est confirmée, une
-- ligne qui porte un motif a été refusée, et le reste attend une réponse. Écrire
-- les deux — l'état et sa date — c'était s'exposer à ce qu'ils se contredisent.
--
-- deposit_rate() (012) est le seul endroit où le taux d'acompte est écrit. On ne
-- recopie ni le taux ni le montant : on relit quoted_amount, que le trigger
-- vient de poser à partir d'estimate_price(), et on applique la fonction.
-- -----------------------------------------------------------------------------

update public.bookings
   set status = case
         when completed_at   is not null then 'completed'
         when confirmed_at   is not null then 'confirmed'
         when status_reason  is not null then 'refused'
         else 'pending'
       end,
       deposit_amount = case
         when accepted_at is not null
         then round(quoted_amount * public.deposit_rate(), 2)
       end
 where id::text like 'b0000000-%';

-- -----------------------------------------------------------------------------
-- Trois avis, pour que la note moyenne existe
--
-- Sur des réservations honorées d'août, et seulement sur Salle El Bahia :
-- Résidence Les Andalouses reste sans avis, parce que l'écran doit montrer un
-- tiret et non « 0,0 » quand personne n'a encore noté.
--
-- booking_group_id n'est pas écrit ici : c'est reviews_guard (004) qui le
-- renseigne, et c'est lui qui garantit un seul avis par événement.
-- -----------------------------------------------------------------------------

insert into public.reviews (booking_id, venue_id, rating,
                            rating_cleanliness, rating_service,
                            rating_value, rating_accuracy, body, created_at)
values
  ('b0000000-0000-4000-a000-000000000020', '5a11e000-0000-4000-a000-000000000001',
   5, 5, 5, 4, 5,
   'Tout était impeccable, le personnel très présent. La salle correspond '
   'exactement aux photos.', '2026-08-03 10:00+01'),
  ('b0000000-0000-4000-a000-000000000021', '5a11e000-0000-4000-a000-000000000001',
   4, 4, 5, 4, 4,
   'Belle soirée. Le parking est un peu juste quand tout le monde arrive en '
   'même temps.', '2026-08-10 21:00+01'),
  ('b0000000-0000-4000-a000-000000000024', '5a11e000-0000-4000-a000-000000000001',
   5, 5, 5, 5, 4,
   'Merci pour tout, la famille a beaucoup apprécié.', '2026-08-24 12:00+01');

commit;

-- -----------------------------------------------------------------------------
-- Contrôle — ce que le tableau de bord de Karim doit montrer
--
--   select * from public.owner_dashboard('5a11e000-0000-4000-a000-000000000001');
--
-- attendu, tant que la démonstration tourne en septembre 2026 :
--   occupation 10 créneaux sur 60, contre 6 sur 62 en août
--   demandes acceptées 6 sur 8 en septembre, 5 sur 6 en août — donc en baisse
--   note 3 avis, aucune sur la seconde salle
-- -----------------------------------------------------------------------------

select
  (select count(*) from public.bookings where id::text like 'b0000000-%')             as lignes,
  (select count(distinct group_id) from public.bookings where id::text like 'b0000000-%') as demandes,
  (select count(*) from public.bookings where id::text like 'b0000000-%' and status = 'pending') as en_attente,
  (select count(*) from public.reviews  where booking_id::text like 'b0000000-%')      as avis;
