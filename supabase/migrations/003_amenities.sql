-- =============================================================================
-- Ferha — 003_amenities.sql
-- Référentiel des équipements (§6, table amenities).
--
-- Ce sont les seules données livrées avec le schéma : un référentiel, pas des
-- salles de démonstration. Chaque entrée correspond à un équipement réellement
-- cité dans le cahier des charges ou dans les maquettes — rien d'inventé.
--
-- Rejouable : ON CONFLICT met à jour les libellés plutôt que d'échouer, ce qui
-- fait aussi de ce fichier le moyen de corriger une traduction.
-- =============================================================================

insert into public.amenities (code, label_fr, label_ar, icon, category, position) values
  -- Confort
  ('climatisation',      'Climatisation',        'تكييف',              'ac_unit',        'confort',    10),

  -- Espaces
  ('espace_femmes',      'Espace femmes',        'فضاء خاص بالنساء',   'woman',          'espaces',    10),
  ('chambre_mariee',     'Chambre de la mariée', 'غرفة العروس',        'king_bed',       'espaces',    20),
  ('cuisine_equipee',    'Cuisine équipée',      'مطبخ مجهز',          'kitchen',        'espaces',    30),
  ('jardin',             'Jardin',               'حديقة',              'yard',           'espaces',    40),

  -- Services
  ('traiteur_libre',     'Traiteur libre',       'حرية اختيار المطعم',  'restaurant',     'services',   10),
  ('sono',               'Sono',                 'نظام صوتي',          'speaker',        'services',   20),
  ('dj',                 'DJ',                   'دي جي',              'music_note',     'services',   30),
  ('decoration_florale', 'Décoration florale',   'تزيين بالورود',      'local_florist',  'services',   40),

  -- Logistique
  ('parking',            'Parking',              'موقف سيارات',        'local_parking',  'logistique', 10),
  ('groupe_electrogene', 'Groupe électrogène',   'مولد كهربائي',       'bolt',           'logistique', 20)
on conflict (code) do update set
  label_fr   = excluded.label_fr,
  label_ar   = excluded.label_ar,
  icon       = excluded.icon,
  category   = excluded.category,
  position   = excluded.position,
  updated_at = now();
