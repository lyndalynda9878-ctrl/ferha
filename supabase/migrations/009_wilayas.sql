-- =============================================================================
-- Ferha — 009_wilayas.sql
-- Référentiel des wilayas.
--
-- POURQUOI CE FICHIER EXISTE
--
-- venues.wilaya_code porte « 16 » ou « 31 » depuis 001, avec un CHECK de forme
-- et aucune table en face. Tant que rien n'affichait ces codes, cela suffisait.
-- L'écran de recherche, lui, doit écrire « Oran » sur une puce — et ce nom
-- devait venir de quelque part.
--
-- Il ne viendra pas du Dart : une liste de wilayas recopiée dans l'application
-- serait une donnée de plus à tenir à jour dans deux endroits, et le premier
-- écran à s'en écarter le ferait sans que personne le voie.
--
-- Les 58 wilayas, dans l'ordre officiel, y compris les dix créées en 2019
-- (49 à 58). Les libellés arabes sont marqués « À RELIRE », comme ceux du
-- référentiel des équipements : ils attendent une relecture par un locuteur
-- natif. `grep "À RELIRE"` sur le dépôt les liste tous.
--
-- Rejouable : ON CONFLICT met à jour les libellés plutôt que d'échouer, ce qui
-- fait aussi de ce fichier le moyen de corriger une traduction.
-- =============================================================================

create table if not exists public.wilayas (
  -- Deux chiffres, « 01 » à « 58 » : le même format que venues.wilaya_code, et
  -- le zéro de tête en fait partie.
  code       text primary key check (code ~ '^(0[1-9]|[1-4][0-9]|5[0-8])$'),
  name_fr    text        not null check (length(btrim(name_fr)) > 0),
  name_ar    text        not null check (length(btrim(name_ar)) > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table  public.wilayas is 'Référentiel des 58 wilayas d''Algérie.';
comment on column public.wilayas.code is
  'Deux chiffres, « 01 » à « 58 ». Même format que venues.wilaya_code.';

drop trigger if exists wilayas_set_updated_at on public.wilayas;
create trigger wilayas_set_updated_at
  before update on public.wilayas
  for each row execute function public.set_updated_at();

-- Référentiel : lisible par tous, écrit par le seul rôle de service. L'absence
-- de politique d'écriture ferme la table, comme pour amenities (002).
alter table public.wilayas enable row level security;

drop policy if exists wilayas_select_all on public.wilayas;
create policy wilayas_select_all
  on public.wilayas for select
  to anon, authenticated
  using (true);

insert into public.wilayas (code, name_fr, name_ar) values
  ('01', 'Adrar',              'أدرار'),          -- À RELIRE
  ('02', 'Chlef',              'الشلف'),          -- À RELIRE
  ('03', 'Laghouat',           'الأغواط'),        -- À RELIRE
  ('04', 'Oum El Bouaghi',     'أم البواقي'),     -- À RELIRE
  ('05', 'Batna',              'باتنة'),          -- À RELIRE
  ('06', 'Béjaïa',             'بجاية'),          -- À RELIRE
  ('07', 'Biskra',             'بسكرة'),          -- À RELIRE
  ('08', 'Béchar',             'بشار'),           -- À RELIRE
  ('09', 'Blida',              'البليدة'),        -- À RELIRE
  ('10', 'Bouira',             'البويرة'),        -- À RELIRE
  ('11', 'Tamanrasset',        'تمنراست'),        -- À RELIRE
  ('12', 'Tébessa',            'تبسة'),           -- À RELIRE
  ('13', 'Tlemcen',            'تلمسان'),         -- À RELIRE
  ('14', 'Tiaret',             'تيارت'),          -- À RELIRE
  ('15', 'Tizi Ouzou',         'تيزي وزو'),       -- À RELIRE
  ('16', 'Alger',              'الجزائر'),        -- À RELIRE
  ('17', 'Djelfa',             'الجلفة'),         -- À RELIRE
  ('18', 'Jijel',              'جيجل'),           -- À RELIRE
  ('19', 'Sétif',              'سطيف'),           -- À RELIRE
  ('20', 'Saïda',              'سعيدة'),          -- À RELIRE
  ('21', 'Skikda',             'سكيكدة'),         -- À RELIRE
  ('22', 'Sidi Bel Abbès',     'سيدي بلعباس'),    -- À RELIRE
  ('23', 'Annaba',             'عنابة'),          -- À RELIRE
  ('24', 'Guelma',             'قالمة'),          -- À RELIRE
  ('25', 'Constantine',        'قسنطينة'),        -- À RELIRE
  ('26', 'Médéa',              'المدية'),         -- À RELIRE
  ('27', 'Mostaganem',         'مستغانم'),        -- À RELIRE
  ('28', 'M''Sila',            'المسيلة'),        -- À RELIRE
  ('29', 'Mascara',            'معسكر'),          -- À RELIRE
  ('30', 'Ouargla',            'ورقلة'),          -- À RELIRE
  ('31', 'Oran',               'وهران'),          -- À RELIRE
  ('32', 'El Bayadh',          'البيض'),          -- À RELIRE
  ('33', 'Illizi',             'إليزي'),          -- À RELIRE
  ('34', 'Bordj Bou Arreridj', 'برج بوعريريج'),   -- À RELIRE
  ('35', 'Boumerdès',          'بومرداس'),        -- À RELIRE
  ('36', 'El Tarf',            'الطارف'),         -- À RELIRE
  ('37', 'Tindouf',            'تندوف'),          -- À RELIRE
  ('38', 'Tissemsilt',         'تيسمسيلت'),       -- À RELIRE
  ('39', 'El Oued',            'الوادي'),         -- À RELIRE
  ('40', 'Khenchela',          'خنشلة'),          -- À RELIRE
  ('41', 'Souk Ahras',         'سوق أهراس'),      -- À RELIRE
  ('42', 'Tipaza',             'تيبازة'),         -- À RELIRE
  ('43', 'Mila',               'ميلة'),           -- À RELIRE
  ('44', 'Aïn Defla',          'عين الدفلى'),     -- À RELIRE
  ('45', 'Naâma',              'النعامة'),        -- À RELIRE
  ('46', 'Aïn Témouchent',     'عين تموشنت'),     -- À RELIRE
  ('47', 'Ghardaïa',           'غرداية'),         -- À RELIRE
  ('48', 'Relizane',           'غليزان'),         -- À RELIRE
  ('49', 'Timimoun',           'تيميمون'),        -- À RELIRE
  ('50', 'Bordj Badji Mokhtar','برج باجي مختار'), -- À RELIRE
  ('51', 'Ouled Djellal',      'أولاد جلال'),     -- À RELIRE
  ('52', 'Béni Abbès',         'بني عباس'),       -- À RELIRE
  ('53', 'In Salah',           'عين صالح'),       -- À RELIRE
  ('54', 'In Guezzam',         'عين قزام'),       -- À RELIRE
  ('55', 'Touggourt',          'تقرت'),           -- À RELIRE
  ('56', 'Djanet',             'جانت'),           -- À RELIRE
  ('57', 'El M''Ghair',        'المغير'),         -- À RELIRE
  ('58', 'El Meniaa',          'المنيعة')         -- À RELIRE
on conflict (code) do update set
  name_fr = excluded.name_fr,
  name_ar = excluded.name_ar;

-- -----------------------------------------------------------------------------
-- wilayas_avec_salles — celles qui ont quelque chose à montrer
--
-- Cinquante-huit puces sur un écran d'accueil ne se lisent pas. Les maquettes
-- en montrent cinq, et ce sont précisément celles où il y a des salles.
--
-- security_invoker = true, contrairement à venue_availability (002) : cette vue
-- n'a rien à contourner. Elle compte des salles publiées, que tout le monde a
-- déjà le droit de lire, et hérite donc simplement de la politique de venues.
-- -----------------------------------------------------------------------------

create or replace view public.wilayas_avec_salles
  with (security_invoker = true) as
  select
    w.code,
    w.name_fr,
    w.name_ar,
    count(v.id) as venue_count
  from public.wilayas w
  join public.venues v
    on v.wilaya_code = w.code and v.status = 'published'
  group by w.code, w.name_fr, w.name_ar;

comment on view public.wilayas_avec_salles is
  'Wilayas comptant au moins une salle publiée, avec leur nombre. '
  'Alimente les puces de l''écran de recherche.';

grant select on public.wilayas_avec_salles to anon, authenticated;
