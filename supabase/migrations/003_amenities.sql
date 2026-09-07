-- =============================================================================
-- Ferha — 003_amenities.sql
-- Référentiel des équipements (§6, table amenities).
--
-- Ce sont les seules données livrées avec le schéma : un référentiel, pas des
-- salles de démonstration. Chaque entrée correspond à un équipement réellement
-- cité dans le cahier des charges ou dans les maquettes — rien d'inventé.
--
-- Le parking n'est PAS un équipement : il est porté par venues.parking_spaces,
-- qui dit aussi combien de places. Une seule colonne, une seule vérité.
--
-- Les libellés arabes sont marqués « À RELIRE » : ils attendent une relecture
-- par un locuteur natif. `grep "À RELIRE"` sur ce fichier les liste tous.
--
-- Rejouable : ON CONFLICT met à jour les libellés plutôt que d'échouer, ce qui
-- fait aussi de ce fichier le moyen de corriger une traduction.
-- =============================================================================

insert into public.amenities (code, label_fr, label_ar, icon, category, position) values
  -- Confort
  ('climatisation',      'Climatisation',        'تكييف',              'ac_unit',       'confort',    10),  -- À RELIRE

  -- Espaces
  ('espace_femmes',      'Espace femmes',        'فضاء خاص بالنساء',   'woman',         'espaces',    10),  -- À RELIRE
  ('chambre_mariee',     'Chambre de la mariée', 'غرفة العروس',        'king_bed',      'espaces',    20),  -- À RELIRE
  ('cuisine_equipee',    'Cuisine équipée',      'مطبخ مجهز',          'kitchen',       'espaces',    30),  -- À RELIRE
  ('jardin',             'Jardin',               'حديقة',              'yard',          'espaces',    40),  -- À RELIRE

  -- Services
  ('traiteur_libre',     'Traiteur libre',       'حرية اختيار المطعم',  'restaurant',    'services',   10),  -- À RELIRE
  ('sono',               'Sono',                 'نظام صوتي',          'speaker',       'services',   20),  -- À RELIRE
  ('dj',                 'DJ',                   'دي جي',              'music_note',    'services',   30),  -- À RELIRE
  ('decoration_florale', 'Décoration florale',   'تزيين بالورود',      'local_florist', 'services',   40),  -- À RELIRE

  -- Logistique
  ('groupe_electrogene', 'Groupe électrogène',   'مولد كهربائي',       'bolt',          'logistique', 10)   -- À RELIRE
on conflict (code) do update set
  label_fr   = excluded.label_fr,
  label_ar   = excluded.label_ar,
  icon       = excluded.icon,
  category   = excluded.category,
  position   = excluded.position,
  updated_at = now();
