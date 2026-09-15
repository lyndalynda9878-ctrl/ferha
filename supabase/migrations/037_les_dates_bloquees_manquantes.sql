-- =============================================================================
-- Ferha — 037_les_dates_bloquees_manquantes.sql
-- Cinquante dates bloquées que la base n'a jamais reçues (J26).
--
-- CE QUI S'EST PASSÉ, ET CE N'EST PAS UNE PANNE. seed/001_demo_venues.sql a été
-- lancé sur ce projet le 8 septembre 2026 à 20 h 26. Le commit ab4c247,
-- « feat(seed): cinquante dates de plus, presque toutes sur un seul créneau »,
-- a ajouté un second bloc de venue_blackouts le 9 septembre à 00 h 59 — quatre
-- heures et demie plus tard. Le fichier n'a jamais été relancé depuis. Rien n'a
-- échoué, rien n'a été avalé : ces lignes n'ont simplement jamais été jouées.
--
-- LE SOUPÇON EST LEVÉ, ET C'EST LE POINT IMPORTANT. Les deux blocs portent
-- `on conflict (venue_id, date, slot) do update set reason = excluded.reason` :
-- aucune ligne n'a été mangée en silence par un conflit. L'inventaire donne
-- 81 déclarées, 31 en base, 50 manquantes, sur sept salles —
--
--     El Bahia               21 déclarées,  3 en base, 18 manquantes
--     Résidence Les Andalouses 12 déclarées,  2 en base, 10 manquantes
--     Salle Ennour           11 déclarées,  1 en base, 10 manquantes
--     Espace Nour El Houda    4 déclarées,  1 en base,  3 manquantes
--     Salle Ibn Khaldoun      4 déclarées,  1 en base,  3 manquantes
--     Salle El Wiam           4 déclarées,  1 en base,  3 manquantes
--     Salle Rhumel            4 déclarées,  1 en base,  3 manquantes
--
-- Les huit autres salles sont complètes : toutes leurs dates étaient dans le
-- premier bloc.
--
-- POURQUOI ÇA COMPTE MAINTENANT. Le calendrier de la fiche salle est l'écran le
-- plus travaillé du projet, et le README le montre en capture. Avec 3 dates
-- bloquées sur 21, Salle El Bahia n'a presque rien à montrer : ni la densité
-- d'un vrai mois d'août, ni la journée entière bloquée sur ses DEUX créneaux —
-- le 12 août — ni deux salles voisines prises à l'inverse l'une de l'autre le
-- même jour, qui est ce qui rend la comparaison de deux salles utile.
--
-- POURQUOI PAS UN SIMPLE « RELANCER seed/001 ». Le fichier ne détruit pas les
-- salles : il les met à jour, `on conflict (id) do update`. La cascade de
-- venues.owner_id ne part donc pas, et ni les réservations, ni les avis, ni les
-- empreintes de la recherche sémantique ne risquent quoi que ce soit.
--
-- Ce qu'il fait, en revanche, c'est EFFACER ET RECRÉER venue_options, dont les
-- identifiants sont tirés au sort à chaque exécution. bookings.option_ids garde
-- ces identifiants dans un tableau, qu'aucune clé étrangère ne protège : après
-- un tel passage, une réservation portant une option désignerait des options
-- qui n'existent plus. Aucune n'en porte aujourd'hui — vérifié — mais faire
-- tourner 770 lignes pour en rattraper 50 crée ce risque sans rien gagner.
--
-- -----------------------------------------------------------------------------
-- L'ORDRE EST UN GARDE-FOU, PAS UNE PRÉFÉRENCE
--
-- menage_du_decor() EFFACE les dates bloquées absentes de l'empreinte. Ce n'est
-- pas une surveillance qui signale, c'est un ménage qui retire — voir
-- 036_les_personnes_du_decor.sql, lignes 444 à 449 :
--
--     delete from public.venue_blackouts vb
--      where vb.venue_id::text like '5a11e000-%'
--        and vb.created_at < now() - p_delai
--        and not exists (select 1 from public.decor_blackouts e ...)
--
-- Insérer ces 50 dates sans reprendre l'empreinte derrière, c'est les voir
-- disparaître à la première heure ronde passé le délai de deux heures — sans
-- message, sans erreur, et sans que personne comprenne pourquoi le calendrier
-- s'est vidé tout seul dans la nuit. L'insertion et la reprise de l'empreinte
-- se font donc dans CE fichier, insertion d'abord, empreinte ensuite.
-- -----------------------------------------------------------------------------
--
-- CE FICHIER EST ADDITIF, au sens strict :
--   * il n'efface aucune ligne ;
--   * il ne met à jour aucune ligne existante — `do nothing`, et non
--     `do update` : un motif corrigé à la main sur l'une des 31 lignes déjà
--     posées est respecté ;
--   * il ne touche à aucune salle, aucune option, aucune photo, aucun tarif ;
--   * il ne pose que des lignes dont la salle existe : la jointure sur venues
--     le garantit, et le fichier ne casse donc pas sur une base neuve.
--
-- REJOUABLE : le lancer deux fois n'insère rien la seconde fois et ne lève
-- aucune erreur.
--
-- LA LISTE CI-DESSOUS EST CELLE DE seed/001_demo_venues.sql — les 81 lignes de
-- ses deux blocs, motifs compris. Les deux fichiers racontent la même histoire ;
-- si l'un change, l'autre doit changer.
--
-- Dépend de : 001 (venue_blackouts), 035 et 036 (l'empreinte et le ménage), et
--             de seed/001 pour les salles.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- La liste déclarée
--
-- Une table temporaire plutôt qu'une liste `values` recopiée deux fois : elle
-- sert à l'insertion ET au bloc de preuve, et il faut que les deux portent sur
-- exactement le même ensemble.
-- -----------------------------------------------------------------------------

create temp table if not exists _dates_declarees (
  venue_id uuid not null,
  date     date not null,
  slot     text not null,
  reason   text,
  primary key (venue_id, date, slot)
);

delete from _dates_declarees;

insert into _dates_declarees (venue_id, date, slot, reason) values
  ('5a11e000-0000-4000-a000-000000000001', date '2027-07-03', 'soir', 'Mariage de famille'),
  ('5a11e000-0000-4000-a000-000000000001', date '2027-07-04', 'midi', 'Mariage de famille'),
  ('5a11e000-0000-4000-a000-000000000001', date '2027-08-14', 'soir', 'Réservation prise par téléphone'),
  ('5a11e000-0000-4000-a000-000000000002', date '2027-06-19', 'soir', 'Travaux de peinture'),
  ('5a11e000-0000-4000-a000-000000000002', date '2027-06-20', 'midi', 'Travaux de peinture'),
  ('5a11e000-0000-4000-a000-000000000003', date '2027-07-17', 'soir', 'Réservation prise par téléphone'),
  ('5a11e000-0000-4000-a000-000000000004', date '2027-06-05', 'midi', 'Réfection de la climatisation'),
  ('5a11e000-0000-4000-a000-000000000004', date '2027-06-05', 'soir', 'Réfection de la climatisation'),
  ('5a11e000-0000-4000-a000-000000000004', date '2027-07-31', 'soir', 'Réservation prise par téléphone'),
  ('5a11e000-0000-4000-a000-000000000004', date '2027-08-21', 'soir', 'Mariage de famille'),
  ('5a11e000-0000-4000-a000-000000000005', date '2027-07-10', 'soir', 'Réservation prise par téléphone'),
  ('5a11e000-0000-4000-a000-000000000005', date '2027-08-07', 'midi', 'Fermeture — Aïd'),
  ('5a11e000-0000-4000-a000-000000000006', date '2027-07-24', 'soir', 'Réservation prise par téléphone'),
  ('5a11e000-0000-4000-a000-000000000007', date '2027-06-26', 'soir', 'Mariage de famille'),
  ('5a11e000-0000-4000-a000-000000000007', date '2027-08-28', 'midi', 'Travaux de plomberie'),
  ('5a11e000-0000-4000-a000-000000000007', date '2027-08-28', 'soir', 'Travaux de plomberie'),
  ('5a11e000-0000-4000-a000-000000000008', date '2027-07-02', 'soir', 'Réservation prise par téléphone'),
  ('5a11e000-0000-4000-a000-000000000008', date '2027-07-03', 'soir', 'Réservation prise par téléphone'),
  ('5a11e000-0000-4000-a000-000000000009', date '2027-08-13', 'soir', 'Mariage de famille'),
  ('5a11e000-0000-4000-a000-000000000010', date '2027-06-12', 'soir', 'Réservation prise par téléphone'),
  ('5a11e000-0000-4000-a000-000000000010', date '2027-07-16', 'midi', 'Séminaire d''entreprise'),
  ('5a11e000-0000-4000-a000-000000000010', date '2027-08-06', 'soir', 'Réservation prise par téléphone'),
  ('5a11e000-0000-4000-a000-000000000011', date '2027-07-09', 'soir', 'Mariage de famille'),
  ('5a11e000-0000-4000-a000-000000000011', date '2027-08-20', 'soir', 'Fermeture annuelle'),
  ('5a11e000-0000-4000-a000-000000000012', date '2027-06-18', 'soir', 'Réservation prise par téléphone'),
  ('5a11e000-0000-4000-a000-000000000013', date '2027-07-23', 'soir', 'Réservation prise par téléphone'),
  ('5a11e000-0000-4000-a000-000000000013', date '2027-08-27', 'midi', 'Réfection du parquet'),
  ('5a11e000-0000-4000-a000-000000000013', date '2027-08-27', 'soir', 'Réfection du parquet'),
  ('5a11e000-0000-4000-a000-000000000014', date '2027-06-11', 'soir', 'Mariage de famille'),
  ('5a11e000-0000-4000-a000-000000000014', date '2027-07-30', 'soir', 'Réservation prise par téléphone'),
  ('5a11e000-0000-4000-a000-000000000015', date '2027-08-04', 'soir', 'Réservation prise par téléphone'),
  ('5a11e000-0000-4000-a000-000000000001', date '2027-07-10', 'midi', 'Réservation prise par téléphone'),
  ('5a11e000-0000-4000-a000-000000000001', date '2027-07-17', 'soir', 'Mariage de famille'),
  ('5a11e000-0000-4000-a000-000000000001', date '2027-07-24', 'midi', 'Séminaire d''entreprise'),
  ('5a11e000-0000-4000-a000-000000000001', date '2027-08-01', 'soir', 'Réservation prise par téléphone'),
  ('5a11e000-0000-4000-a000-000000000001', date '2027-08-02', 'midi', 'Réservation prise par téléphone'),
  ('5a11e000-0000-4000-a000-000000000001', date '2027-08-06', 'soir', 'Mariage de famille'),
  ('5a11e000-0000-4000-a000-000000000001', date '2027-08-07', 'midi', 'Réservation prise par téléphone'),
  ('5a11e000-0000-4000-a000-000000000001', date '2027-08-08', 'soir', 'Réservation prise par téléphone'),
  ('5a11e000-0000-4000-a000-000000000001', date '2027-08-09', 'midi', 'Fiançailles'),
  ('5a11e000-0000-4000-a000-000000000001', date '2027-08-12', 'midi', 'Fermeture — inventaire'),
  ('5a11e000-0000-4000-a000-000000000001', date '2027-08-12', 'soir', 'Fermeture — inventaire'),
  ('5a11e000-0000-4000-a000-000000000001', date '2027-08-13', 'soir', 'Réservation prise par téléphone'),
  ('5a11e000-0000-4000-a000-000000000001', date '2027-08-15', 'midi', 'Réservation prise par téléphone'),
  ('5a11e000-0000-4000-a000-000000000001', date '2027-08-20', 'soir', 'Mariage de famille'),
  ('5a11e000-0000-4000-a000-000000000001', date '2027-08-21', 'midi', 'Réservation prise par téléphone'),
  ('5a11e000-0000-4000-a000-000000000001', date '2027-08-22', 'soir', 'Réservation prise par téléphone'),
  ('5a11e000-0000-4000-a000-000000000001', date '2027-08-28', 'midi', 'Réservation prise par téléphone'),
  ('5a11e000-0000-4000-a000-000000000001', date '2027-08-29', 'soir', 'Mariage de famille'),
  ('5a11e000-0000-4000-a000-000000000002', date '2027-07-02', 'soir', 'Réservation prise par téléphone'),
  ('5a11e000-0000-4000-a000-000000000002', date '2027-07-09', 'midi', 'Séminaire d''entreprise'),
  ('5a11e000-0000-4000-a000-000000000002', date '2027-07-16', 'soir', 'Mariage de famille'),
  ('5a11e000-0000-4000-a000-000000000002', date '2027-07-23', 'midi', 'Réservation prise par téléphone'),
  ('5a11e000-0000-4000-a000-000000000002', date '2027-07-30', 'soir', 'Réservation prise par téléphone'),
  ('5a11e000-0000-4000-a000-000000000002', date '2027-08-06', 'midi', 'Réservation prise par téléphone'),
  ('5a11e000-0000-4000-a000-000000000002', date '2027-08-13', 'soir', 'Mariage de famille'),
  ('5a11e000-0000-4000-a000-000000000002', date '2027-08-14', 'midi', 'Réservation prise par téléphone'),
  ('5a11e000-0000-4000-a000-000000000002', date '2027-08-20', 'midi', 'Fiançailles'),
  ('5a11e000-0000-4000-a000-000000000002', date '2027-08-27', 'soir', 'Réservation prise par téléphone'),
  ('5a11e000-0000-4000-a000-000000000003', date '2027-06-25', 'soir', 'Réservation prise par téléphone'),
  ('5a11e000-0000-4000-a000-000000000003', date '2027-07-02', 'midi', 'Circoncision'),
  ('5a11e000-0000-4000-a000-000000000003', date '2027-07-09', 'soir', 'Mariage de famille'),
  ('5a11e000-0000-4000-a000-000000000003', date '2027-07-23', 'midi', 'Réservation prise par téléphone'),
  ('5a11e000-0000-4000-a000-000000000003', date '2027-07-31', 'soir', 'Réservation prise par téléphone'),
  ('5a11e000-0000-4000-a000-000000000003', date '2027-08-07', 'midi', 'Réservation prise par téléphone'),
  ('5a11e000-0000-4000-a000-000000000003', date '2027-08-14', 'soir', 'Mariage de famille'),
  ('5a11e000-0000-4000-a000-000000000003', date '2027-08-15', 'midi', 'Réservation prise par téléphone'),
  ('5a11e000-0000-4000-a000-000000000003', date '2027-08-21', 'soir', 'Réservation prise par téléphone'),
  ('5a11e000-0000-4000-a000-000000000003', date '2027-08-28', 'midi', 'Fiançailles'),
  ('5a11e000-0000-4000-a000-000000000006', date '2027-07-03', 'midi', 'Réservation prise par téléphone'),
  ('5a11e000-0000-4000-a000-000000000006', date '2027-08-07', 'soir', 'Mariage de famille'),
  ('5a11e000-0000-4000-a000-000000000006', date '2027-08-21', 'midi', 'Réservation prise par téléphone'),
  ('5a11e000-0000-4000-a000-000000000009', date '2027-07-10', 'midi', 'Séminaire d''entreprise'),
  ('5a11e000-0000-4000-a000-000000000009', date '2027-07-31', 'soir', 'Réservation prise par téléphone'),
  ('5a11e000-0000-4000-a000-000000000009', date '2027-08-27', 'midi', 'Réservation prise par téléphone'),
  ('5a11e000-0000-4000-a000-000000000012', date '2027-07-17', 'midi', 'Réservation prise par téléphone'),
  ('5a11e000-0000-4000-a000-000000000012', date '2027-08-08', 'soir', 'Mariage de famille'),
  ('5a11e000-0000-4000-a000-000000000012', date '2027-08-22', 'midi', 'Circoncision'),
  ('5a11e000-0000-4000-a000-000000000015', date '2027-06-26', 'midi', 'Réservation prise par téléphone'),
  ('5a11e000-0000-4000-a000-000000000015', date '2027-07-24', 'soir', 'Mariage de famille'),
  ('5a11e000-0000-4000-a000-000000000015', date '2027-08-18', 'midi', 'Réservation prise par téléphone');

-- -----------------------------------------------------------------------------
-- L'état avant, l'insertion, l'empreinte, l'état après
--
-- Tout dans un seul bloc : le compte « avant » n'existe plus une fois
-- l'insertion faite, et c'est lui qui rend le bloc de preuve lisible.
-- -----------------------------------------------------------------------------

create temp table if not exists _preuve_037 (
  declarees  integer,
  avant      integer,
  inserees   integer,
  apres      integer,
  manquantes integer
);

delete from _preuve_037;

do $$
declare
  v_declarees  integer;
  v_avant      integer;
  v_inserees   integer;
  v_apres      integer;
  v_manquantes integer;
begin
  select count(*) into v_declarees from _dates_declarees;

  select count(*) into v_avant
  from _dates_declarees d
  join public.venue_blackouts vb
    on vb.venue_id = d.venue_id and vb.date = d.date and vb.slot = d.slot;

  -- L'INSERTION. `do nothing` et non `do update` : les lignes déjà en place ne
  -- sont pas réécrites, motif compris.
  insert into public.venue_blackouts (venue_id, date, slot, reason)
  select d.venue_id, d.date, d.slot, d.reason
  from _dates_declarees d
  join public.venues v on v.id = d.venue_id
  on conflict (venue_id, date, slot) do nothing;

  get diagnostics v_inserees = row_count;

  -- L'EMPREINTE, APRÈS L'INSERTION ET JAMAIS AVANT. Voir l'en-tête : sans elle,
  -- menage_du_decor() retire ces lignes à la première heure ronde.
  --
  -- On ne la reprend que si elle existe déjà. Une empreinte vide veut dire que
  -- personne n'a encore capturé le décor ; la remplir depuis une migration
  -- serait prendre une décision qui appartient à seed/004.
  if to_regprocedure('public.capturer_le_decor()') is not null
     and exists (select 1 from public.decor_bookings) then
    perform public.capturer_le_decor();
    raise notice 'Empreinte du décor reprise après l''insertion.';
  else
    raise notice 'Pas d''empreinte en place : rien à reprendre. Lancez seed/004 le moment venu.';
  end if;

  select count(*) into v_apres
  from _dates_declarees d
  join public.venue_blackouts vb
    on vb.venue_id = d.venue_id and vb.date = d.date and vb.slot = d.slot;

  select count(*) into v_manquantes
  from _dates_declarees d
  where not exists (
    select 1 from public.venue_blackouts vb
     where vb.venue_id = d.venue_id and vb.date = d.date and vb.slot = d.slot);

  insert into _preuve_037 (declarees, avant, inserees, apres, manquantes)
  values (v_declarees, v_avant, v_inserees, v_apres, v_manquantes);

  raise notice 'Déclarées : %. En base avant : %. Insérées : %. En base après : %. Encore manquantes : %.',
    v_declarees, v_avant, v_inserees, v_apres, v_manquantes;
end $$;

-- -----------------------------------------------------------------------------
-- Le bloc de preuve. `manquantes` doit valoir 0.
-- -----------------------------------------------------------------------------

select declarees, avant, inserees, apres, manquantes from _preuve_037;
