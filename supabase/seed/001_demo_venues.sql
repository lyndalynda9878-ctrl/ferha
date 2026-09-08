-- =============================================================================
-- Ferha — seed/001_demo_venues.sql
-- Quinze salles de démonstration, quatre propriétaires, cinq wilayas.
--
-- CE FICHIER N'EST PAS UNE MIGRATION. Il ne crée aucune table et ne modifie
-- aucune contrainte : il ne fait que poser des données. Il vit dans seed/ et
-- non dans migrations/ pour qu'on puisse le lancer, l'effacer et le relancer
-- sans que le schéma bouge.
--
-- Ces salles n'existent pas. Les noms, les prix et les communes sont
-- vraisemblables, pas réels. AUCUNE de ces données ne doit apparaître ailleurs
-- que dans ce fichier — surtout pas dans le code Flutter, qui ne connaît que
-- des requêtes.
--
-- REJOUABLE : les comptes et les salles sont posés en ON CONFLICT, et les
-- tables filles (photos, équipements, tarifs, dates bloquées) sont effacées
-- puis réécrites. Relancer ce fichier ne crée aucun doublon et ramène les
-- quinze salles à l'état décrit ici.
--
-- POUR TOUT EFFACER : seed/002_reset_demo.sql.
--
-- Prérequis : migrations 001 à 006 appliquées.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Identifiants reconnaissables
--
-- Les UUID ne sont pas tirés au sort : ils portent une marque, pour qu'on
-- distingue d'un coup d'œil une donnée de démonstration d'une vraie.
--
--   propriétaires  d0000000-0000-4000-a000-0000000000NN   (d comme démo)
--   salles         5a11e000-0000-4000-a000-0000000000NN   (5a11e comme salle)
--
-- C'est aussi ce qui permet à 002_reset_demo.sql d'effacer ces données-là et
-- rien d'autre.
-- -----------------------------------------------------------------------------

begin;

-- -----------------------------------------------------------------------------
-- Les quatre propriétaires
--
-- Karim est celui des maquettes : 45 ans, peu à l'aise avec l'informatique,
-- publie ses photos depuis son téléphone. Il porte quatre salles, dont la plus
-- petite du jeu — de quoi vérifier que l'écran « Mes salles » tient avec autre
-- chose qu'une seule ligne.
--
-- profiles référence auth.users : il faut donc de vrais comptes. Le mot de
-- passe est vide : ces comptes ne servent qu'à porter des salles, on ne s'y
-- connecte pas. Pour s'y connecter, passer par l'inscription normale et
-- basculer is_owner.
--
-- Rachid n'a pas de téléphone : la colonne est nullable depuis la v2.0, et il
-- faut au moins un cas qui l'exerce.
-- -----------------------------------------------------------------------------

insert into auth.users (instance_id, id, aud, role, email,
                        encrypted_password, email_confirmed_at,
                        created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
values
  ('00000000-0000-0000-0000-000000000000', 'd0000000-0000-4000-a000-000000000001', 'authenticated', 'authenticated',
   'karim.belhadj@demo.ferha.dz', '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb),
  ('00000000-0000-0000-0000-000000000000', 'd0000000-0000-4000-a000-000000000002', 'authenticated', 'authenticated',
   'yacine.mokrani@demo.ferha.dz', '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb),
  ('00000000-0000-0000-0000-000000000000', 'd0000000-0000-4000-a000-000000000003', 'authenticated', 'authenticated',
   'nadia.cherifi@demo.ferha.dz', '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb),
  ('00000000-0000-0000-0000-000000000000', 'd0000000-0000-4000-a000-000000000004', 'authenticated', 'authenticated',
   'rachid.amrani@demo.ferha.dz', '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb)
on conflict (id) do nothing;

insert into public.profiles (id, full_name, email, phone, is_owner) values
  ('d0000000-0000-4000-a000-000000000001', 'Karim Belhadj',       'karim.belhadj@demo.ferha.dz',     '0770 11 22 33',   true),
  ('d0000000-0000-4000-a000-000000000002', 'Yacine Mokrani',      'yacine.mokrani@demo.ferha.dz',    '0661 44 55 66',   true),
  ('d0000000-0000-4000-a000-000000000003', 'Nadia Cherifi',       'nadia.cherifi@demo.ferha.dz',     '0555 77 88 99',   true),
  ('d0000000-0000-4000-a000-000000000004', 'Rachid Amrani',       'rachid.amrani@demo.ferha.dz',     null,              true)
on conflict (id) do update set
  full_name = excluded.full_name,
  email     = excluded.email,
  phone     = excluded.phone,
  is_owner  = excluded.is_owner;

-- -----------------------------------------------------------------------------
-- Les quinze salles
--
-- Trois par wilaya : Oran (31), Alger (16), Blida (09), Sétif (19),
-- Constantine (25). Les communes sont réelles.
--
-- TREIZE sont « published » et DEUX sont « pending » — Espace Nour El Houda
-- (Birtouta) et Salle El Wiam (El Eulma). Elles attendent la validation
-- humaine du §4.4 (ADM-01) : sans elles, l'écran de back-office n'aurait rien
-- à montrer. Une salle « pending » n'est visible que de son propriétaire (§9),
-- donc une recherche cliente doit en trouver treize, jamais quinze.
--
-- Salle El Wiam a sa superficie et son parking à NULL : une salle en cours
-- d'inscription est incomplète, et il faut un cas qui l'exerce.
-- Salle Ibn Khaldoun a parking_spaces = 0, ce qui n'est PAS la même chose :
-- zéro place, contre place non renseignée.
-- -----------------------------------------------------------------------------

insert into public.venues (id, owner_id, name, wilaya_code, commune, lat, lng,
                           capacity_seated, area_sqm, parking_spaces,
                           description, status) values
  ('5a11e000-0000-4000-a000-000000000001', 'd0000000-0000-4000-a000-000000000001',
   'Salle El Bahia', '31', 'Oran',
   35.6971, -0.6308, 450, 620, 80,
   'Une grande salle au cœur d''Oran, à dix minutes du front de mer. Deux entrées séparées, l''une pour les invités, l''autre pour le service : les plats ne traversent jamais la piste.',
   'published'),
  ('5a11e000-0000-4000-a000-000000000002', 'd0000000-0000-4000-a000-000000000001',
   'Résidence Les Andalouses', '31', 'Aïn El Turck',
   35.74, -0.77, 300, 400, 45,
   'À quinze minutes de la corniche. La terrasse donne sur le jardin, et les photos de fin de soirée se font dehors quand le temps le permet.',
   'published'),
  ('5a11e000-0000-4000-a000-000000000003', 'd0000000-0000-4000-a000-000000000001',
   'Salle Ennour', '31', 'Bir El Djir',
   35.71, -0.55, 180, 240, 20,
   'Une salle familiale, sans prétention, pour les fêtes de moins de deux cents personnes. Le traiteur est libre : beaucoup de familles viennent avec le leur.',
   'published'),
  ('5a11e000-0000-4000-a000-000000000004', 'd0000000-0000-4000-a000-000000000002',
   'Palais Dar El Feth', '16', 'Zéralda',
   36.71, 2.84, 700, 1100, 150,
   'Le plus grand de nos espaces : sept cents couverts sous un seul plafond, un parking de cent cinquante places et un jardin clos. Prestation complète, traiteur de la maison.',
   'published'),
  ('5a11e000-0000-4000-a000-000000000005', 'd0000000-0000-4000-a000-000000000002',
   'Salle Ryad El Djazaïr', '16', 'Chéraga',
   36.767, 2.956, 500, 700, 90,
   'Cinq cents couverts à vingt minutes du centre d''Alger. Chambre de la mariée à l''étage, avec son accès indépendant.',
   'published'),
  ('5a11e000-0000-4000-a000-000000000006', 'd0000000-0000-4000-a000-000000000002',
   'Espace Nour El Houda', '16', 'Birtouta',
   36.64, 3.0, 220, 300, 30,
   'Salle récente, ouverte en 2026. Climatisation neuve et cuisine entièrement équipée.',
   'pending'),
  ('5a11e000-0000-4000-a000-000000000007', 'd0000000-0000-4000-a000-000000000002',
   'Salle El Feth', '09', 'Boufarik',
   36.573, 2.908, 350, 480, 55,
   'Au centre de Boufarik, sur la route d''Alger. Groupe électrogène : les coupures de courant de l''été n''arrêtent pas la soirée.',
   'published'),
  ('5a11e000-0000-4000-a000-000000000008', 'd0000000-0000-4000-a000-000000000003',
   'Complexe Chréa', '09', 'Blida',
   36.47, 2.828, 260, 350, 35,
   'Adossé au piémont, avec une vue dégagée sur Chréa. Un espace femmes séparé au premier étage.',
   'published'),
  ('5a11e000-0000-4000-a000-000000000009', 'd0000000-0000-4000-a000-000000000001',
   'Salle Ibn Khaldoun', '09', 'Ouled Yaïch',
   36.51, 2.83, 150, 195, 0,
   'La plus petite et la plus abordable de nos salles. Pas de parking : les invités se garent sur la place, à cinquante mètres.',
   'published'),
  ('5a11e000-0000-4000-a000-000000000010', 'd0000000-0000-4000-a000-000000000003',
   'Palais El Amir', '19', 'Sétif',
   36.19, 5.41, 600, 850, 110,
   'Six cents couverts, un hall d''accueil de deux cents mètres carrés et un jardin d''hiver. La grande salle des mariages de Sétif.',
   'published'),
  ('5a11e000-0000-4000-a000-000000000011', 'd0000000-0000-4000-a000-000000000003',
   'Salle Aïn Fouara', '19', 'Sétif',
   36.19, 5.415, 320, 430, 40,
   'À deux pas de la fontaine. Sono et DJ compris dans le prix de base.',
   'published'),
  ('5a11e000-0000-4000-a000-000000000012', 'd0000000-0000-4000-a000-000000000003',
   'Salle El Wiam', '19', 'El Eulma',
   null, null, 200, null, null,
   'Salle en cours d''inscription : la superficie et le nombre de places de parking restent à renseigner.',
   'pending'),
  ('5a11e000-0000-4000-a000-000000000013', 'd0000000-0000-4000-a000-000000000004',
   'Salle Les Ponts', '25', 'Constantine',
   36.365, 6.6147, 400, 550, 60,
   'Dans la vieille ville, à portée de vue du pont de Sidi M''Cid. Décoration florale incluse.',
   'published'),
  ('5a11e000-0000-4000-a000-000000000014', 'd0000000-0000-4000-a000-000000000004',
   'Résidence Bab El Kantara', '25', 'El Khroub',
   36.263, 6.696, 480, 640, 75,
   'Quatre cent quatre-vingts couverts et un parking fermé. Le traiteur de la maison prépare aussi les repas de la veille.',
   'published'),
  ('5a11e000-0000-4000-a000-000000000015', 'd0000000-0000-4000-a000-000000000004',
   'Salle Rhumel', '25', 'Aïn Smara',
   36.267, 6.51, 240, 320, 28,
   'Une salle simple et bien tenue, à quinze minutes de Constantine. Cuisine équipée, traiteur libre.',
   'published')
on conflict (id) do update set
  owner_id        = excluded.owner_id,
  name            = excluded.name,
  wilaya_code     = excluded.wilaya_code,
  commune         = excluded.commune,
  lat             = excluded.lat,
  lng             = excluded.lng,
  capacity_seated = excluded.capacity_seated,
  area_sqm        = excluded.area_sqm,
  parking_spaces  = excluded.parking_spaces,
  description     = excluded.description,
  status          = excluded.status;

-- -----------------------------------------------------------------------------
-- Tables filles : on efface avant de réécrire
--
-- Un ON CONFLICT ne suffirait pas ici : si l'on retire une photo ou un
-- équipement de ce fichier, l'ancienne ligne resterait en base et le jeu de
-- démonstration cesserait de correspondre à ce qu'on lit. Effacer d'abord, sur
-- les seules salles de démonstration, est la seule façon d'être idempotent
-- dans les deux sens.
-- -----------------------------------------------------------------------------

delete from public.venue_photos    where venue_id in (select id from public.venues where id::text like '5a11e000-%');
delete from public.venue_amenities where venue_id in (select id from public.venues where id::text like '5a11e000-%');
delete from public.venue_pricing   where venue_id in (select id from public.venues where id::text like '5a11e000-%');
delete from public.venue_blackouts where venue_id in (select id from public.venues where id::text like '5a11e000-%');
delete from public.venue_event_types where venue_id in (select id from public.venues where id::text like '5a11e000-%');

-- -----------------------------------------------------------------------------
-- Grilles tarifaires — en dinars, §6 et §5.2
--
-- Trois lignes par salle : midi, soir, et journee. La journée est tarifée à
-- part, et volontairement en dessous de midi + soir — c'est ainsi que se vend
-- une salle, et c'est pour cela que le §6 lui donne sa propre ligne.
--
-- Les prix suivent la wilaya et la capacité : 90 000 DA le soir pour la petite
-- salle d'Ouled Yaïch, 400 000 DA pour le palais de Zéralda. Les coefficients
-- restent dans les bornes du §5.2 — jour de 1.0 à 1.4, saison de 1.0 à 1.3.
--
-- Ces montants sont des DONNÉES. La formule qui s'en sert vit dans
-- estimate_price() (005), et nulle part ailleurs.
-- -----------------------------------------------------------------------------

insert into public.venue_pricing (venue_id, slot, base_price, weekend_coef,
                                  high_season_coef, included_seats, extra_seat_price) values
  -- 1. Salle El Bahia (Oran, 450 couverts)
  ('5a11e000-0000-4000-a000-000000000001', 'midi',   150000, 1.30, 1.20, 300,  900),
  ('5a11e000-0000-4000-a000-000000000001', 'soir',   220000, 1.30, 1.20, 300,  900),
  ('5a11e000-0000-4000-a000-000000000001', 'journee', 340000, 1.30, 1.20, 300,  900),
  -- 2. Résidence Les Andalouses (Aïn El Turck, 300 couverts)
  ('5a11e000-0000-4000-a000-000000000002', 'midi',   115000, 1.25, 1.25, 200,  850),
  ('5a11e000-0000-4000-a000-000000000002', 'soir',   165000, 1.25, 1.25, 200,  850),
  ('5a11e000-0000-4000-a000-000000000002', 'journee', 255000, 1.25, 1.25, 200,  850),
  -- 3. Salle Ennour (Bir El Djir, 180 couverts)
  ('5a11e000-0000-4000-a000-000000000003', 'midi',    75000, 1.20, 1.10, 150,  700),
  ('5a11e000-0000-4000-a000-000000000003', 'soir',   105000, 1.20, 1.10, 150,  700),
  ('5a11e000-0000-4000-a000-000000000003', 'journee', 160000, 1.20, 1.10, 150,  700),
  -- 4. Palais Dar El Feth (Zéralda, 700 couverts)
  ('5a11e000-0000-4000-a000-000000000004', 'midi',   280000, 1.40, 1.30, 500, 1500),
  ('5a11e000-0000-4000-a000-000000000004', 'soir',   400000, 1.40, 1.30, 500, 1500),
  ('5a11e000-0000-4000-a000-000000000004', 'journee', 620000, 1.40, 1.30, 500, 1500),
  -- 5. Salle Ryad El Djazaïr (Chéraga, 500 couverts)
  ('5a11e000-0000-4000-a000-000000000005', 'midi',   195000, 1.35, 1.25, 350, 1200),
  ('5a11e000-0000-4000-a000-000000000005', 'soir',   285000, 1.35, 1.25, 350, 1200),
  ('5a11e000-0000-4000-a000-000000000005', 'journee', 440000, 1.35, 1.25, 350, 1200),
  -- 6. Espace Nour El Houda (Birtouta, 220 couverts)
  ('5a11e000-0000-4000-a000-000000000006', 'midi',   100000, 1.25, 1.15, 150,  950),
  ('5a11e000-0000-4000-a000-000000000006', 'soir',   145000, 1.25, 1.15, 150,  950),
  ('5a11e000-0000-4000-a000-000000000006', 'journee', 225000, 1.25, 1.15, 150,  950),
  -- 7. Salle El Feth (Boufarik, 350 couverts)
  ('5a11e000-0000-4000-a000-000000000007', 'midi',   110000, 1.25, 1.20, 250,  800),
  ('5a11e000-0000-4000-a000-000000000007', 'soir',   160000, 1.25, 1.20, 250,  800),
  ('5a11e000-0000-4000-a000-000000000007', 'journee', 245000, 1.25, 1.20, 250,  800),
  -- 8. Complexe Chréa (Blida, 260 couverts)
  ('5a11e000-0000-4000-a000-000000000008', 'midi',    88000, 1.20, 1.15, 180,  750),
  ('5a11e000-0000-4000-a000-000000000008', 'soir',   125000, 1.20, 1.15, 180,  750),
  ('5a11e000-0000-4000-a000-000000000008', 'journee', 195000, 1.20, 1.15, 180,  750),
  -- 9. Salle Ibn Khaldoun (Ouled Yaïch, 150 couverts)
  ('5a11e000-0000-4000-a000-000000000009', 'midi',    65000, 1.15, 1.10, 120,  600),
  ('5a11e000-0000-4000-a000-000000000009', 'soir',    90000, 1.15, 1.10, 120,  600),
  ('5a11e000-0000-4000-a000-000000000009', 'journee', 140000, 1.15, 1.10, 120,  600),
  -- 10. Palais El Amir (Sétif, 600 couverts)
  ('5a11e000-0000-4000-a000-000000000010', 'midi',   185000, 1.35, 1.25, 400, 1000),
  ('5a11e000-0000-4000-a000-000000000010', 'soir',   265000, 1.35, 1.25, 400, 1000),
  ('5a11e000-0000-4000-a000-000000000010', 'journee', 410000, 1.35, 1.25, 400, 1000),
  -- 11. Salle Aïn Fouara (Sétif, 320 couverts)
  ('5a11e000-0000-4000-a000-000000000011', 'midi',   105000, 1.25, 1.20, 220,  780),
  ('5a11e000-0000-4000-a000-000000000011', 'soir',   150000, 1.25, 1.20, 220,  780),
  ('5a11e000-0000-4000-a000-000000000011', 'journee', 230000, 1.25, 1.20, 220,  780),
  -- 12. Salle El Wiam (El Eulma, 200 couverts)
  ('5a11e000-0000-4000-a000-000000000012', 'midi',    78000, 1.20, 1.10, 150,  650),
  ('5a11e000-0000-4000-a000-000000000012', 'soir',   110000, 1.20, 1.10, 150,  650),
  ('5a11e000-0000-4000-a000-000000000012', 'journee', 170000, 1.20, 1.10, 150,  650),
  -- 13. Salle Les Ponts (Constantine, 400 couverts)
  ('5a11e000-0000-4000-a000-000000000013', 'midi',   130000, 1.30, 1.20, 280,  850),
  ('5a11e000-0000-4000-a000-000000000013', 'soir',   185000, 1.30, 1.20, 280,  850),
  ('5a11e000-0000-4000-a000-000000000013', 'journee', 285000, 1.30, 1.20, 280,  850),
  -- 14. Résidence Bab El Kantara (El Khroub, 480 couverts)
  ('5a11e000-0000-4000-a000-000000000014', 'midi',   145000, 1.30, 1.25, 320,  900),
  ('5a11e000-0000-4000-a000-000000000014', 'soir',   210000, 1.30, 1.25, 320,  900),
  ('5a11e000-0000-4000-a000-000000000014', 'journee', 325000, 1.30, 1.25, 320,  900),
  -- 15. Salle Rhumel (Aïn Smara, 240 couverts)
  ('5a11e000-0000-4000-a000-000000000015', 'midi',    85000, 1.20, 1.15, 170,  700),
  ('5a11e000-0000-4000-a000-000000000015', 'soir',   120000, 1.20, 1.15, 170,  700),
  ('5a11e000-0000-4000-a000-000000000015', 'journee', 185000, 1.20, 1.15, 170,  700);

-- -----------------------------------------------------------------------------
-- Équipements — 4 à 8 par salle, pris dans le référentiel de 003
--
-- Ils suivent le standing, et c'est le point de la variation : un palais à
-- 400 000 DA impose son traiteur et n'a donc PAS « traiteur_libre » ; une
-- petite salle à 90 000 DA le propose au contraire, parce que c'est là son
-- argument. Le parking n'est pas un équipement — il est dans
-- venues.parking_spaces.
-- -----------------------------------------------------------------------------

insert into public.venue_amenities (venue_id, amenity_code)
select v.venue_id, a.code
from (values
  -- 1. Salle El Bahia
  ('5a11e000-0000-4000-a000-000000000001'::uuid, array['climatisation', 'espace_femmes', 'chambre_mariee', 'cuisine_equipee', 'sono', 'groupe_electrogene']),
  -- 2. Résidence Les Andalouses
  ('5a11e000-0000-4000-a000-000000000002'::uuid, array['climatisation', 'jardin', 'chambre_mariee', 'sono', 'dj']),
  -- 3. Salle Ennour
  ('5a11e000-0000-4000-a000-000000000003'::uuid, array['climatisation', 'cuisine_equipee', 'traiteur_libre', 'sono']),
  -- 4. Palais Dar El Feth
  ('5a11e000-0000-4000-a000-000000000004'::uuid, array['climatisation', 'espace_femmes', 'chambre_mariee', 'cuisine_equipee', 'jardin', 'sono', 'dj', 'decoration_florale', 'groupe_electrogene']),
  -- 5. Salle Ryad El Djazaïr
  ('5a11e000-0000-4000-a000-000000000005'::uuid, array['climatisation', 'espace_femmes', 'chambre_mariee', 'cuisine_equipee', 'sono', 'dj', 'decoration_florale', 'groupe_electrogene']),
  -- 6. Espace Nour El Houda
  ('5a11e000-0000-4000-a000-000000000006'::uuid, array['climatisation', 'cuisine_equipee', 'traiteur_libre', 'sono']),
  -- 7. Salle El Feth
  ('5a11e000-0000-4000-a000-000000000007'::uuid, array['climatisation', 'espace_femmes', 'cuisine_equipee', 'sono', 'groupe_electrogene']),
  -- 8. Complexe Chréa
  ('5a11e000-0000-4000-a000-000000000008'::uuid, array['climatisation', 'espace_femmes', 'jardin', 'traiteur_libre', 'sono']),
  -- 9. Salle Ibn Khaldoun
  ('5a11e000-0000-4000-a000-000000000009'::uuid, array['cuisine_equipee', 'traiteur_libre', 'sono', 'espace_femmes']),
  -- 10. Palais El Amir
  ('5a11e000-0000-4000-a000-000000000010'::uuid, array['climatisation', 'espace_femmes', 'chambre_mariee', 'cuisine_equipee', 'jardin', 'sono', 'dj', 'decoration_florale']),
  -- 11. Salle Aïn Fouara
  ('5a11e000-0000-4000-a000-000000000011'::uuid, array['climatisation', 'espace_femmes', 'cuisine_equipee', 'sono', 'dj', 'decoration_florale']),
  -- 12. Salle El Wiam
  ('5a11e000-0000-4000-a000-000000000012'::uuid, array['climatisation', 'cuisine_equipee', 'traiteur_libre', 'sono']),
  -- 13. Salle Les Ponts
  ('5a11e000-0000-4000-a000-000000000013'::uuid, array['climatisation', 'chambre_mariee', 'cuisine_equipee', 'sono', 'dj', 'decoration_florale']),
  -- 14. Résidence Bab El Kantara
  ('5a11e000-0000-4000-a000-000000000014'::uuid, array['climatisation', 'espace_femmes', 'chambre_mariee', 'cuisine_equipee', 'sono', 'dj', 'groupe_electrogene']),
  -- 15. Salle Rhumel
  ('5a11e000-0000-4000-a000-000000000015'::uuid, array['climatisation', 'cuisine_equipee', 'traiteur_libre', 'sono', 'espace_femmes'])
) as v(venue_id, codes),
lateral unnest(v.codes) as a(code);

-- -----------------------------------------------------------------------------
-- Photos — EXCEPTION RÉSERVÉE À LA DÉMONSTRATION
--
-- storage_path porte ici une URL COMPLÈTE vers Unsplash, et non un chemin dans
-- le bucket Supabase. C'est une entorse assumée au §7.3, et elle ne vaut que
-- pour ce fichier : nous n'avons pas encore de photos réelles à téléverser, et
-- une application de salles des fêtes sans images ne se juge pas.
--
-- LA RÈGLE, côté Flutter : si storage_path commence par « http », on l'affiche
-- tel quel ; sinon on le résout dans le Storage. Deux lignes de code, et le
-- jour où les vraies photos arrivent, rien à changer — les nouvelles lignes
-- porteront un chemin, les anciennes disparaîtront avec le reset.
--
-- NE PAS écrire d'URL externe dans venue_photos en dehors de ce fichier. Une
-- photo de vraie salle passe par le bucket venue-photos, chemin
-- {venue_id}/{uuid}.webp, compressée côté client (§7.3).
--
-- Les images viennent d'Unsplash, sous licence Unsplash : usage libre, y
-- compris commercial, sans attribution obligatoire. Les identifiants ont été
-- vérifiés un par un — ils renvoient tous une image.
--
-- La première photo de chaque salle est la couverture (position 0, is_cover).
-- Le pool est partagé entre les salles : la même image peut servir deux fois,
-- ce qui est sans importance pour une démonstration et évite de multiplier les
-- vérifications.
-- -----------------------------------------------------------------------------

insert into public.venue_photos (venue_id, storage_path, "position", is_cover)
select
  v.venue_id,
  p.url,
  (p.pos - 1)::integer,   -- position : 0, 1, 2…
  p.pos = 1               -- couverture : la première, et une seule (index unique partiel)
from (values
  -- 1. Salle El Bahia
  ('5a11e000-0000-4000-a000-000000000001'::uuid, array[
    'https://images.unsplash.com/photo-1675247488725-22d1b78e75db?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1775918427144-51f0bf53f8c4?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1783314867628-220ab03cac99?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1773407377203-faf8b19a2142?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1519225421980-715cb0215aed?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1649615644622-6d83f48e69c5?auto=format&fit=crop&w=1600&q=80'
  ]),
  -- 2. Résidence Les Andalouses
  ('5a11e000-0000-4000-a000-000000000002'::uuid, array[
    'https://images.unsplash.com/photo-1762765684665-6b6855bb6fe6?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1761114905078-163aa92141c8?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1765947384834-3bdcffcaffff?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1562050344-f7ad946cee35?auto=format&fit=crop&w=1600&q=80'
  ]),
  -- 3. Salle Ennour
  ('5a11e000-0000-4000-a000-000000000003'::uuid, array[
    'https://images.unsplash.com/photo-1783314863884-be035ed5ed5c?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1717680281618-442cb9c12b6c?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1710587385270-08f30d66bf31?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1525441273400-056e9c7517b3?auto=format&fit=crop&w=1600&q=80'
  ]),
  -- 4. Palais Dar El Feth
  ('5a11e000-0000-4000-a000-000000000004'::uuid, array[
    'https://images.unsplash.com/photo-1786062841848-18177898b3a7?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1780337092331-6580fd9ccb47?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1786125493154-8a2bcedfef9b?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1769224751561-feca3f403d49?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1536392706976-e486e2ba97af?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1665072462642-f51a6b108f9a?auto=format&fit=crop&w=1600&q=80'
  ]),
  -- 5. Salle Ryad El Djazaïr
  ('5a11e000-0000-4000-a000-000000000005'::uuid, array[
    'https://images.unsplash.com/photo-1780593116478-c46838f86523?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1759477274116-e3cb02d2b9d8?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1768851142332-75f3d1b47452?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1502635385003-ee1e6a1a742d?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1520869578617-557561d7b114?auto=format&fit=crop&w=1600&q=80'
  ]),
  -- 6. Espace Nour El Houda
  ('5a11e000-0000-4000-a000-000000000006'::uuid, array[
    'https://images.unsplash.com/photo-1761116189895-9fa9541520d7?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1762765685319-fdaf8d22085d?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1511795409834-ef04bbd61622?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1561593367-66c79c2294e6?auto=format&fit=crop&w=1600&q=80'
  ]),
  -- 7. Salle El Feth
  ('5a11e000-0000-4000-a000-000000000007'::uuid, array[
    'https://images.unsplash.com/photo-1768508951405-10e83c4a2872?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1715782414430-e1f0f4df354e?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1762765684810-b734486c5eda?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1649615644613-758b850399c1?auto=format&fit=crop&w=1600&q=80'
  ]),
  -- 8. Complexe Chréa
  ('5a11e000-0000-4000-a000-000000000008'::uuid, array[
    'https://images.unsplash.com/photo-1781947486682-aafbb8427889?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1763231575952-98244918f99b?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1737682599438-319b61711b5f?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1473973916745-60839aebf06b?auto=format&fit=crop&w=1600&q=80'
  ]),
  -- 9. Salle Ibn Khaldoun
  ('5a11e000-0000-4000-a000-000000000009'::uuid, array[
    'https://images.unsplash.com/photo-1775492783040-9ebacb1f7861?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1647296020388-787fdae78e3c?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1519225421980-715cb0215aed?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1649615644622-6d83f48e69c5?auto=format&fit=crop&w=1600&q=80'
  ]),
  -- 10. Palais El Amir
  ('5a11e000-0000-4000-a000-000000000010'::uuid, array[
    'https://images.unsplash.com/photo-1675247488725-22d1b78e75db?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1783314867628-220ab03cac99?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1762765684665-6b6855bb6fe6?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1765947384834-3bdcffcaffff?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1562050344-f7ad946cee35?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1525441273400-056e9c7517b3?auto=format&fit=crop&w=1600&q=80'
  ]),
  -- 11. Salle Aïn Fouara
  ('5a11e000-0000-4000-a000-000000000011'::uuid, array[
    'https://images.unsplash.com/photo-1717680281618-442cb9c12b6c?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1780337092331-6580fd9ccb47?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1769224751561-feca3f403d49?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1665072462642-f51a6b108f9a?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1520869578617-557561d7b114?auto=format&fit=crop&w=1600&q=80'
  ]),
  -- 12. Salle El Wiam
  ('5a11e000-0000-4000-a000-000000000012'::uuid, array[
    'https://images.unsplash.com/photo-1759477274116-e3cb02d2b9d8?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1761116189895-9fa9541520d7?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1561593367-66c79c2294e6?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1737682599438-319b61711b5f?auto=format&fit=crop&w=1600&q=80'
  ]),
  -- 13. Salle Les Ponts
  ('5a11e000-0000-4000-a000-000000000013'::uuid, array[
    'https://images.unsplash.com/photo-1768508951405-10e83c4a2872?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1762765684810-b734486c5eda?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1763231575952-98244918f99b?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1647296020388-787fdae78e3c?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1775918427144-51f0bf53f8c4?auto=format&fit=crop&w=1600&q=80'
  ]),
  -- 14. Résidence Bab El Kantara
  ('5a11e000-0000-4000-a000-000000000014'::uuid, array[
    'https://images.unsplash.com/photo-1773407377203-faf8b19a2142?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1761114905078-163aa92141c8?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1783314863884-be035ed5ed5c?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1786062841848-18177898b3a7?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1710587385270-08f30d66bf31?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1536392706976-e486e2ba97af?auto=format&fit=crop&w=1600&q=80'
  ]),
  -- 15. Salle Rhumel
  ('5a11e000-0000-4000-a000-000000000015'::uuid, array[
    'https://images.unsplash.com/photo-1786125493154-8a2bcedfef9b?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1780593116478-c46838f86523?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1768851142332-75f3d1b47452?auto=format&fit=crop&w=1600&q=80',
    'https://images.unsplash.com/photo-1502635385003-ee1e6a1a742d?auto=format&fit=crop&w=1600&q=80'
  ])
) as v(venue_id, urls),
lateral unnest(v.urls) with ordinality as p(url, pos);

-- -----------------------------------------------------------------------------
-- Dates bloquées — été 2027
--
-- Pour que le calendrier de la fiche salle ne soit pas vide, et surtout pour
-- qu'il ne le soit pas au seul moment où on le regarde : juin, juillet et août
-- sont la saison des mariages, et c'est aussi la haute saison du §5.2.
--
-- Une journée entière bloquée s'écrit en DEUX lignes, midi et soir — même
-- découpage que les réservations (§6.1). On en trouvera ici plusieurs.
--
-- reason est le motif interne du propriétaire : il ne sort jamais de la table.
-- Le calendrier public lit la vue venue_availability, qui n'expose que
-- venue_id, date et slot (§9). Ces motifs sont donc aussi un test : si l'un
-- d'eux apparaît un jour dans l'application, c'est qu'une fuite s'est ouverte.
-- -----------------------------------------------------------------------------

insert into public.venue_blackouts (venue_id, date, slot, reason) values
  -- 1. Salle El Bahia
  ('5a11e000-0000-4000-a000-000000000001', date '2027-07-03', 'soir',   'Mariage de famille'),
  ('5a11e000-0000-4000-a000-000000000001', date '2027-07-04', 'midi',   'Mariage de famille'),
  ('5a11e000-0000-4000-a000-000000000001', date '2027-08-14', 'soir',   'Réservation prise par téléphone'),
  -- 2. Résidence Les Andalouses
  ('5a11e000-0000-4000-a000-000000000002', date '2027-06-19', 'soir',   'Travaux de peinture'),
  ('5a11e000-0000-4000-a000-000000000002', date '2027-06-20', 'midi',   'Travaux de peinture'),
  -- 3. Salle Ennour
  ('5a11e000-0000-4000-a000-000000000003', date '2027-07-17', 'soir',   'Réservation prise par téléphone'),
  -- 4. Palais Dar El Feth
  ('5a11e000-0000-4000-a000-000000000004', date '2027-06-05', 'midi',   'Réfection de la climatisation'),
  ('5a11e000-0000-4000-a000-000000000004', date '2027-06-05', 'soir',   'Réfection de la climatisation'),
  ('5a11e000-0000-4000-a000-000000000004', date '2027-07-31', 'soir',   'Réservation prise par téléphone'),
  ('5a11e000-0000-4000-a000-000000000004', date '2027-08-21', 'soir',   'Mariage de famille'),
  -- 5. Salle Ryad El Djazaïr
  ('5a11e000-0000-4000-a000-000000000005', date '2027-07-10', 'soir',   'Réservation prise par téléphone'),
  ('5a11e000-0000-4000-a000-000000000005', date '2027-08-07', 'midi',   'Fermeture — Aïd'),
  -- 6. Espace Nour El Houda
  ('5a11e000-0000-4000-a000-000000000006', date '2027-07-24', 'soir',   'Réservation prise par téléphone'),
  -- 7. Salle El Feth
  ('5a11e000-0000-4000-a000-000000000007', date '2027-06-26', 'soir',   'Mariage de famille'),
  ('5a11e000-0000-4000-a000-000000000007', date '2027-08-28', 'midi',   'Travaux de plomberie'),
  ('5a11e000-0000-4000-a000-000000000007', date '2027-08-28', 'soir',   'Travaux de plomberie'),
  -- 8. Complexe Chréa
  ('5a11e000-0000-4000-a000-000000000008', date '2027-07-02', 'soir',   'Réservation prise par téléphone'),
  ('5a11e000-0000-4000-a000-000000000008', date '2027-07-03', 'soir',   'Réservation prise par téléphone'),
  -- 9. Salle Ibn Khaldoun
  ('5a11e000-0000-4000-a000-000000000009', date '2027-08-13', 'soir',   'Mariage de famille'),
  -- 10. Palais El Amir
  ('5a11e000-0000-4000-a000-000000000010', date '2027-06-12', 'soir',   'Réservation prise par téléphone'),
  ('5a11e000-0000-4000-a000-000000000010', date '2027-07-16', 'midi',   'Séminaire d''entreprise'),
  ('5a11e000-0000-4000-a000-000000000010', date '2027-08-06', 'soir',   'Réservation prise par téléphone'),
  -- 11. Salle Aïn Fouara
  ('5a11e000-0000-4000-a000-000000000011', date '2027-07-09', 'soir',   'Mariage de famille'),
  ('5a11e000-0000-4000-a000-000000000011', date '2027-08-20', 'soir',   'Fermeture annuelle'),
  -- 12. Salle El Wiam
  ('5a11e000-0000-4000-a000-000000000012', date '2027-06-18', 'soir',   'Réservation prise par téléphone'),
  -- 13. Salle Les Ponts
  ('5a11e000-0000-4000-a000-000000000013', date '2027-07-23', 'soir',   'Réservation prise par téléphone'),
  ('5a11e000-0000-4000-a000-000000000013', date '2027-08-27', 'midi',   'Réfection du parquet'),
  ('5a11e000-0000-4000-a000-000000000013', date '2027-08-27', 'soir',   'Réfection du parquet'),
  -- 14. Résidence Bab El Kantara
  ('5a11e000-0000-4000-a000-000000000014', date '2027-06-11', 'soir',   'Mariage de famille'),
  ('5a11e000-0000-4000-a000-000000000014', date '2027-07-30', 'soir',   'Réservation prise par téléphone'),
  -- 15. Salle Rhumel
  ('5a11e000-0000-4000-a000-000000000015', date '2027-08-04', 'soir',   'Réservation prise par téléphone')
on conflict (venue_id, date, slot) do update set reason = excluded.reason;

-- -----------------------------------------------------------------------------
-- Types d'événement acceptés (§4.2, CLI-01)
--
-- Douze salles sur quinze acceptent tout ; trois refusent quelque chose, et
-- c'est le point. Un filtre qui ne retire jamais rien ne se distingue pas d'un
-- filtre cassé : il faut que cocher « Mariage » fasse visiblement disparaître
-- des lignes.
--
--   Palais Dar El Feth   mariages et fiançailles seulement — grand palais
--   Palais El Amir       ni circoncision ni anniversaire
--   Salle Ibn Khaldoun   150 couverts : ni mariage, ni fiançailles
--
-- Rappel de la règle posée en 010 : une salle SANS AUCUNE LIGNE ici accepte
-- tout. Ces quinze-là déclarent donc explicitement, y compris quand elles
-- acceptent les cinq types — sinon on ne testerait jamais le cas déclaré.
-- -----------------------------------------------------------------------------

insert into public.venue_event_types (venue_id, event_type)
select v.venue_id, t.code
from (values
  -- 1. Salle El Bahia
  ('5a11e000-0000-4000-a000-000000000001'::uuid, array['mariage', 'fiancailles', 'henne', 'circoncision', 'anniversaire']),
  -- 2. Résidence Les Andalouses
  ('5a11e000-0000-4000-a000-000000000002'::uuid, array['mariage', 'fiancailles', 'henne', 'circoncision', 'anniversaire']),
  -- 3. Salle Ennour
  ('5a11e000-0000-4000-a000-000000000003'::uuid, array['mariage', 'fiancailles', 'henne', 'circoncision', 'anniversaire']),
  -- 4. Palais Dar El Feth  — grand palais, uniquement mariages et fiançailles
  ('5a11e000-0000-4000-a000-000000000004'::uuid, array['mariage', 'fiancailles']),
  -- 5. Salle Ryad El Djazaïr
  ('5a11e000-0000-4000-a000-000000000005'::uuid, array['mariage', 'fiancailles', 'henne', 'circoncision', 'anniversaire']),
  -- 6. Espace Nour El Houda
  ('5a11e000-0000-4000-a000-000000000006'::uuid, array['mariage', 'fiancailles', 'henne', 'circoncision', 'anniversaire']),
  -- 7. Salle El Feth
  ('5a11e000-0000-4000-a000-000000000007'::uuid, array['mariage', 'fiancailles', 'henne', 'circoncision', 'anniversaire']),
  -- 8. Complexe Chréa
  ('5a11e000-0000-4000-a000-000000000008'::uuid, array['mariage', 'fiancailles', 'henne', 'circoncision', 'anniversaire']),
  -- 9. Salle Ibn Khaldoun  — 150 couverts : trop petite pour un mariage
  ('5a11e000-0000-4000-a000-000000000009'::uuid, array['henne', 'circoncision', 'anniversaire']),
  -- 10. Palais El Amir  — pas de circoncision ni d’anniversaire
  ('5a11e000-0000-4000-a000-000000000010'::uuid, array['mariage', 'fiancailles', 'henne']),
  -- 11. Salle Aïn Fouara
  ('5a11e000-0000-4000-a000-000000000011'::uuid, array['mariage', 'fiancailles', 'henne', 'circoncision', 'anniversaire']),
  -- 12. Salle El Wiam
  ('5a11e000-0000-4000-a000-000000000012'::uuid, array['mariage', 'fiancailles', 'henne', 'circoncision', 'anniversaire']),
  -- 13. Salle Les Ponts
  ('5a11e000-0000-4000-a000-000000000013'::uuid, array['mariage', 'fiancailles', 'henne', 'circoncision', 'anniversaire']),
  -- 14. Résidence Bab El Kantara
  ('5a11e000-0000-4000-a000-000000000014'::uuid, array['mariage', 'fiancailles', 'henne', 'circoncision', 'anniversaire']),
  -- 15. Salle Rhumel
  ('5a11e000-0000-4000-a000-000000000015'::uuid, array['mariage', 'fiancailles', 'henne', 'circoncision', 'anniversaire'])
) as v(venue_id, codes),
lateral unnest(v.codes) as t(code);

commit;

-- -----------------------------------------------------------------------------
-- Ce qui doit sortir
-- -----------------------------------------------------------------------------

select
  (select count(*) from public.venues          where id::text like '5a11e000-%')                        as salles,
  (select count(*) from public.venues          where id::text like '5a11e000-%' and status = 'published') as publiees,
  (select count(*) from public.venues          where id::text like '5a11e000-%' and status = 'pending')   as en_attente,
  (select count(*) from public.venue_pricing   where venue_id::text like '5a11e000-%')                  as lignes_tarifaires,
  (select count(*) from public.venue_photos    where venue_id::text like '5a11e000-%')                  as photos,
  (select count(*) from public.venue_amenities where venue_id::text like '5a11e000-%')                  as equipements,
  (select count(*) from public.venue_blackouts where venue_id::text like '5a11e000-%')                  as dates_bloquees,
  (select count(*) from public.venue_event_types where venue_id::text like '5a11e000-%')                as types_evenement;


-- Attendu : 15 salles, 13 publiées, 2 en attente, 45 lignes tarifaires,
--           71 photos, 86 équipements, 31 dates bloquées, 68 types d'événement.