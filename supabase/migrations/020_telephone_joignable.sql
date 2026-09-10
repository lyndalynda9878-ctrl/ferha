-- =============================================================================
-- Ferha — 020_telephone_joignable.sql
-- Un numéro de téléphone, une seule règle, et deux endroits où on le demande.
--
-- CE QUE CE FICHIER APPORTE
--
--   telephone_normalise()             les espaces à la saisie, les chiffres en base
--   telephone_valide()                LA règle, écrite une fois
--   profiles_phone_format             la contrainte, dernier mot de la table
--   profiles_normalise_telephone      le trigger qui normalise, et qui dévérifie
--   handle_new_user()      REDÉFINIE  une inscription ne casse pas sur un numéro
--   envoyer_salle_en_validation() ─┐  elles reçoivent le numéro, l'écrivent,
--   request_booking()             ─┘  et refusent sans lui
--
-- LE TROU QUE CE FICHIER BOUCHE. `booking_contact()` (006) donne à chaque
-- partie le numéro de l'autre à partir de « accepted » — c'est le §9, et c'est
-- le seul chemin vers le téléphone d'un tiers. Or AUCUN écran ne permettait de
-- saisir `profiles.phone` : l'inscription se fait par e-mail (v2.0), et le
-- champ restait à NULL pour tout inscrit réel. `booking_contact()` rendait donc
-- fidèlement... rien, des deux côtés. Le propriétaire acceptait une demande
-- sans pouvoir rappeler la famille, et la famille ne pouvait pas rappeler la
-- salle. Les données de démonstration cachaient le trou : elles écrivent des
-- numéros à la main.
--
-- ON LE DEMANDE AU MOMENT OÙ IL SERT, PAS À L'INSCRIPTION. Deux instants, et
-- deux seulement : quand le propriétaire envoie sa salle à la validation
-- (ADM-01 : « propriétaire joignable »), et quand le client envoie sa demande.
-- Ce sont les deux gestes après lesquels quelqu'un devra décrocher. Le réclamer
-- à l'inscription ferait payer un champ de plus à quelqu'un qui vient seulement
-- regarder des salles.
--
-- LA RÈGLE, EN TOUTES LETTRES
--
--   * mobile : 0, puis 5, 6 ou 7, puis 8 chiffres  → 0770112233  (10 chiffres)
--   * fixe   : 0, puis 2, 3 ou 4, puis 7 chiffres  → 041234567   (9 chiffres)
--   * les espaces sont tolérés À LA SAISIE ; la base ne garde que les chiffres.
--   * si le numéro change, `phone_verified` retombe à faux.
--
-- ELLE EST ÉCRITE UNE FOIS ICI, et une fois côté Flutter
-- (lib/core/validation/telephone.dart). Deux exemplaires, pas trois : la
-- contrainte de table, les deux fonctions RPC et le trigger appellent tous
-- `telephone_valide()`. Le jour où l'Algérie ouvre un préfixe, il y a UNE ligne
-- à changer de ce côté-ci.
--
-- LA CONTRAINTE APPELLE UNE FONCTION, et c'est délibéré. La règle recopiée dans
-- un CHECK serait une seconde règle, qui dirait un jour autre chose que la
-- première — exactement ce qu'on refuse pour le prix (§5.2). Le prix à payer
-- est connu : une contrainte qui appelle une fonction demande, lors d'une
-- restauration par pg_dump, que la fonction existe avant la table. Les
-- migrations de ce dépôt s'appliquent dans l'ordre, et ce fichier crée la
-- fonction avant la contrainte.
--
-- LE §9 NE BOUGE PAS D'UN POUCE. Un numéro ne sort toujours que par
-- `booking_contact()`, à partir de « accepted ». Ce fichier ÉCRIT des numéros ;
-- il n'en fait lire aucun de plus. `profiles` reste lisible par son seul
-- titulaire (002), et les deux fonctions ci-dessous ne renvoient jamais le
-- numéro qu'elles viennent d'écrire — il est déjà chez celui qui l'a tapé.
--
-- CODES FERHA DE CE FICHIER — chacun dans la série de sa fonction :
--
--   FE007  PT400  la demande de réservation sans numéro valide  (série de 012)
--   FE037  PT400  l'envoi en validation sans numéro valide      (série de 017)
--
-- Rejouable : fonctions, trigger et contrainte se reposent sans erreur.
-- Dépend de : 001 (profiles), 004 (bookings), 006 (booking_contact), 007
--             (handle_new_user, dont ce fichier porte la version courante),
--             012 (request_booking, idem), 017 et 019
--             (envoyer_salle_en_validation, idem).
-- =============================================================================

-- =============================================================================
-- La règle
-- =============================================================================

-- -----------------------------------------------------------------------------
-- telephone_normalise — ce qu'on tape, et ce qu'on garde
--
-- « 0770 11 22 33 » est la façon dont un numéro s'écrit sur une carte de visite
-- en Algérie, et c'est ainsi qu'on le tape. Ce n'est pas ainsi qu'on le range :
-- deux fois le même numéro, l'un avec des espaces et l'autre sans, seraient
-- deux valeurs différentes en base — donc deux profils qu'on ne saurait pas
-- rapprocher, et un `phone_verified` qui retomberait à faux parce qu'on a
-- déplacé une espace.
--
-- SEULS LES BLANCS SONT RETIRÉS. Ni les points, ni les tirets, ni un « +213 »
-- : ceux-là ne sont pas de la mise en forme, ce sont d'autres façons d'écrire
-- le numéro, et les accepter en silence reviendrait à deviner. Le refus est
-- plus honnête — l'écran dit la forme attendue avant que le doigt se pose.
-- -----------------------------------------------------------------------------

create or replace function public.telephone_normalise(p_phone text)
returns text
language sql
immutable
-- `set search_path` sur une fonction qui ne touche aucune table : ce n'est pas
-- du zèle, c'est ce que réclame le linter de Supabase, et ce que porte déjà
-- chaque fonction de ce dépôt qui lit quoi que ce soit. Ici elle ne protège
-- rien de plus — il n'y a pas une seule référence non qualifiée dans ces trois
-- fonctions — mais un avertissement qu'on laisse traîner finit par cacher le
-- suivant.
set search_path = public
as $$
  select nullif(regexp_replace(coalesce(p_phone, ''), '\s', '', 'g'), '');
$$;

comment on function public.telephone_normalise(text) is
  'Retire les blancs d''un numéro saisi et rend NULL sur du vide. '
  'La base ne garde que les chiffres ; les espaces n''existent qu''à la saisie.';

grant execute on function public.telephone_normalise(text) to anon, authenticated;

-- -----------------------------------------------------------------------------
-- telephone_valide — LA règle, et le seul endroit où elle est écrite en SQL
--
-- Mobile : 0, puis 5, 6 ou 7, puis huit chiffres — les trois opérateurs.
-- Fixe   : 0, puis 2, 3 ou 4, puis sept chiffres — 021 pour Alger, 041 pour
--          Oran, 031 pour Constantine.
--
-- LE DEUXIÈME CHIFFRE FAIT TOUT LE TRAVAIL, et c'est pour lui que la règle
-- distingue deux formes plutôt que d'accepter « 0 et huit chiffres ». La
-- version large laissait passer « 077011223 » — un mobile auquel il manque un
-- chiffre, qui a exactement la longueur d'un fixe. Le propriétaire l'aurait
-- enregistré sans rien voir, et l'aurait découvert le jour où personne ne
-- l'aurait rappelé. Un mobile commence par 5, 6 ou 7 ; un fixe par 2, 3 ou 4 ;
-- amputé d'un chiffre, un mobile ne ressemble donc plus à rien.
--
-- ON NE VA PAS PLUS LOIN : pas de liste des indicatifs de wilaya. « 049 » n'est
-- attribué à personne, et cette fonction l'accepte — la refuser demanderait de
-- tenir les 58 indicatifs à jour ici ET côté Flutter, pour attraper une faute
-- de frappe que le propriétaire verra lui-même. On borne la FORME, pas
-- l'annuaire.
--
-- Un numéro absent n'est pas un numéro invalide : la fonction rend `false` sur
-- NULL, et c'est à l'appelant de dire si l'absence est permise. La contrainte
-- de `profiles` la permet (un compte qui n'a pas encore réservé n'a pas de
-- numéro) ; les deux fonctions RPC ne la permettent pas.
-- -----------------------------------------------------------------------------

create or replace function public.telephone_valide(p_phone text)
returns boolean
language sql
immutable
set search_path = public
as $$
  select coalesce(
    public.telephone_normalise(p_phone) ~ '^(0[567][0-9]{8}|0[234][0-9]{7})$',
    false
  );
$$;

comment on function public.telephone_valide(text) is
  'Vrai pour un numéro algérien : mobile 0 + 5/6/7 + 8 chiffres (10 en tout), '
  'ou fixe 0 + 2/3/4 + 7 chiffres (9 en tout). Borne la forme, pas l''annuaire : '
  'aucune liste d''indicatifs de wilaya. '
  'Les espaces sont tolérés. Faux sur NULL — l''absence se juge chez l''appelant. '
  'SEULE écriture SQL de la règle : contrainte, trigger et fonctions RPC passent toutes par ici.';

grant execute on function public.telephone_valide(text) to anon, authenticated;

-- =============================================================================
-- Les numéros déjà en base
--
-- Les profils de démonstration portent « 0770 11 22 33 ». Ils sont normalisés
-- ici, avant que la contrainte n'arrive — sinon elle refuserait de s'appliquer
-- sur une table qui la viole déjà, et la migration s'arrêterait là.
--
-- `phone_verified` ne bouge pas pour autant : retirer une espace ne change pas
-- le numéro, et le trigger qui suit compare des valeurs déjà normalisées. Les
-- fichiers de supabase/seed/ ont été corrigés dans le même mouvement : ils
-- écrivent désormais des chiffres seuls, et relancer un seed ne défait rien.
-- =============================================================================

update public.profiles p
   set phone = public.telephone_normalise(p.phone)
 where p.phone is distinct from public.telephone_normalise(p.phone);

-- Un numéro déjà en base qui ne suivrait pas la règle empêcherait la contrainte
-- de s'installer. On le dit plutôt que de le corriger en silence : un numéro
-- mal formé est peut-être un vrai numéro mal saisi, et l'effacer perdrait le
-- seul moyen de joindre quelqu'un.
do $$
declare
  v_mauvais integer;
begin
  select count(*) into v_mauvais
  from public.profiles p
  where p.phone is not null and not public.telephone_valide(p.phone);

  if v_mauvais > 0 then
    raise exception
      '% profil(s) portent un numéro qui ne suit pas la règle (mobile 0 + 5/6/7 + 8 '
      'chiffres, ou fixe 0 + 2/3/4 + 7 chiffres). Corrigez-les avant d''appliquer cette '
      'migration : les effacer ici ferait perdre le seul moyen de joindre ces '
      'personnes.', v_mauvais;
  end if;
end;
$$;

-- =============================================================================
-- La contrainte — le dernier mot de la table
-- =============================================================================

alter table public.profiles
  drop constraint if exists profiles_phone_format;
alter table public.profiles
  add  constraint profiles_phone_format
  check (phone is null or public.telephone_valide(phone));

comment on column public.profiles.phone is
  'Numéro algérien, chiffres seuls : mobile 0 + 5/6/7 + 8 chiffres, ou fixe 0 + 2/3/4 + 7 chiffres. '
  'Écrit par envoyer_salle_en_validation() et request_booking(), au moment où il servira. '
  'Ne sort que par booking_contact(), à partir de « accepted » (§9).';

-- =============================================================================
-- profiles_normalise_telephone — normaliser, et dévérifier
--
-- DEUX GESTES DANS UN SEUL TRIGGER, parce qu'ils sont le même geste vu de deux
-- côtés : on ne peut décider qu'un numéro a changé qu'après l'avoir normalisé.
-- Deux triggers séparés dépendraient de leur ordre alphabétique pour être
-- justes — c'est le genre de dépendance qu'on ne remarque qu'une fois cassée.
--
-- POURQUOI phone_verified RETOMBE. Le drapeau dit « ce numéro-là a été vérifié
-- par SMS ». Il ne dit rien du numéro suivant. Le laisser levé après un
-- changement ferait passer pour vérifié un numéro que personne n'a jamais
-- appelé — et la vérification par SMS (§4.1) arrivera un jour se poser sur ce
-- drapeau. Il retombe donc ici, dans la base, plutôt que dans chacun des
-- écrans qui écrivent un numéro : un écran qu'on ajoute demain oublierait.
--
-- LE TRIGGER NE REFUSE RIEN : il met en forme. La contrainte refuse, les
-- fonctions RPC donnent la phrase. Trois rôles, trois endroits.
-- =============================================================================

create or replace function public.profiles_normalise_telephone()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.phone := public.telephone_normalise(new.phone);

  if tg_op = 'UPDATE' and new.phone is distinct from old.phone then
    new.phone_verified := false;
  end if;

  return new;
end;
$$;

comment on function public.profiles_normalise_telephone() is
  'Trigger BEFORE INSERT OR UPDATE : range le numéro en chiffres seuls, et fait retomber '
  'phone_verified dès que le numéro change — un drapeau de vérification ne suit pas un numéro '
  'jusqu''au suivant.';

drop trigger if exists profiles_normalise_telephone on public.profiles;
create trigger profiles_normalise_telephone
  before insert or update on public.profiles
  for each row execute function public.profiles_normalise_telephone();

-- =============================================================================
-- handle_new_user — VERSION COURANTE
--
-- Identique à celle de 007, à une ligne près, et cette ligne est un garde-fou
-- contre ce fichier lui-même. 007 pose une règle en tête de son fichier : « la
-- fonction ne doit JAMAIS lever d'exception sur une inscription légitime — une
-- erreur ici fait échouer la création du compte ». Chaque valeur y est
-- normalisée plutôt que confiée aux CHECK de `profiles`.
--
-- La contrainte ajoutée plus haut vient d'inventer une façon nouvelle de faire
-- échouer une inscription : un `phone` mal formé dans les métadonnées du compte
-- ferait maintenant tomber le profil, donc le compte, avec un 500 illisible.
-- L'inscription v2.0 ne demande pas de numéro — mais le champ existe dans les
-- métadonnées, et une porte qu'on laisse ouverte parce que personne ne
-- l'emprunte finit par servir.
--
-- ON ÉCARTE DONC LE NUMÉRO PLUTÔT QUE DE REFUSER LE COMPTE. Ce n'est pas une
-- perte : ce numéro-là n'a de toute façon jamais servi à personne, et les deux
-- écrans qui en demandent un le redemanderont au moment où il comptera.
--
-- ⚠ C'est cette version-ci qui fait foi, pas celle de 007.
-- =============================================================================

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_meta   jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  v_email  text;
  v_name   text;
  v_phone  text;
  v_locale text;
begin
  -- L'inscription v2.0 se fait par e-mail (§4.1, CORE-01), donc new.email est
  -- toujours renseigné. Le repli n'est là que pour qu'une inscription par
  -- téléphone, si elle arrivait un jour, ne fasse pas échouer la création du
  -- compte — profiles.email est NOT NULL et porte un CHECK de forme.
  v_email := coalesce(new.email, new.id::text || '@sans-email.ferha');

  v_name := nullif(btrim(coalesce(v_meta ->> 'full_name', '')), '');
  v_name := coalesce(v_name, nullif(split_part(v_email, '@', 1), ''), 'Utilisateur');

  -- Un numéro qui ne suit pas la règle est écarté, pas refusé : la contrainte
  -- profiles_phone_format (020) ferait autrement échouer la création du compte.
  v_phone := public.telephone_normalise(v_meta ->> 'phone');
  if v_phone is not null and not public.telephone_valide(v_phone) then
    v_phone := null;
  end if;

  -- Toute autre valeur que fr ou ar est ignorée : la contrainte de profiles ne
  -- doit pas pouvoir faire échouer une inscription.
  v_locale := lower(btrim(coalesce(v_meta ->> 'locale', '')));
  if v_locale not in ('fr', 'ar') then
    v_locale := 'fr';
  end if;

  insert into public.profiles (id, full_name, email, phone, locale)
  values (new.id, v_name, v_email, v_phone, v_locale)
  -- Le profil peut déjà exister : les données de démonstration écrivent
  -- auth.users et profiles côte à côte. On ne l'écrase pas.
  on conflict (id) do nothing;

  return new;
end;
$$;

comment on function public.handle_new_user() is
  'Crée la ligne profiles qui accompagne un compte auth.users. Écarte un numéro mal formé '
  'plutôt que de faire échouer l''inscription (020). '
  'Sans elle, un compte existe sans profil et plus aucune clé étrangère du projet ne résout.';

revoke execute on function public.handle_new_user() from public, anon, authenticated;

-- =============================================================================
-- envoyer_salle_en_validation — VERSION COURANTE
--
-- ADM-01 demande trois choses avant qu'une salle soit visible : des photos
-- réelles, une adresse plausible, et un PROPRIÉTAIRE JOIGNABLE. L'adresse est
-- arrivée en 019 ; le numéro arrive ici, au même endroit du parcours — le
-- dernier écran, celui où l'on s'engage.
--
-- LE NUMÉRO EST UN PARAMÈTRE, ET IL EST ÉCRIT DANS LE PROFIL. Pas dans la
-- salle : c'est le propriétaire qu'on rappelle, pas le bâtiment, et un
-- propriétaire de quatre salles n'a pas quatre numéros. Le champ de l'écran est
-- prérempli depuis `profiles.phone`, et le renvoyer tel quel ne réécrit rien —
-- on ne touche la ligne que si le numéro a changé.
--
-- ⚠ LA VERSION DE 017 EST SUPPRIMÉE, pas seulement remplacée : la signature
-- change, et les deux cohabiteraient. PostgREST choisirait alors celle qui
-- correspond au corps JSON reçu — donc l'ancienne, sans numéro, dès qu'un
-- client oublierait le champ.
-- =============================================================================

drop function if exists public.envoyer_salle_en_validation(uuid);

create or replace function public.envoyer_salle_en_validation(
  p_venue_id uuid,
  p_phone    text
)
returns setof public.venues
language plpgsql
security definer
set search_path = public
as $$
declare
  v_statut text;
  v_phone  text := public.telephone_normalise(p_phone);
begin
  if auth.uid() is null then
    raise exception 'Il faut être connecté pour envoyer une salle en validation.'
      using errcode = 'PT401', hint = 'FE030';
  end if;

  -- LE NUMÉRO D'ABORD, avant même de regarder la salle. Un refus qui parle du
  -- numéro pendant que le vrai problème est ailleurs perdrait le propriétaire ;
  -- l'ordre inverse, lui, ne coûte rien.
  if not public.telephone_valide(v_phone) then
    raise exception
      'Un numéro de téléphone valide est nécessaire : mobile 05, 06 ou 07 suivi de '
      '8 chiffres, ou fixe 02, 03 ou 04 suivi de 7 chiffres.'
      using errcode = 'PT400', hint = 'FE037',
            detail  = 'ADM-01 demande un propriétaire joignable avant toute publication.';
  end if;

  if not public.owns_venue(p_venue_id) then
    -- Le même message qu'une salle inexistante, et c'est volontaire : répondre
    -- « elle n'est pas à vous » sur un identifiant tiré au hasard confirmerait
    -- qu'il existe.
    raise exception 'Cette salle n''est pas la vôtre.'
      using errcode = 'PT403', hint = 'FE034';
  end if;

  select v.status into v_statut
  from public.venues v where v.id = p_venue_id;

  if v_statut is distinct from 'draft' then
    raise exception 'Cette salle n''est plus un brouillon : elle est « % ».', v_statut
      using errcode = 'PT409', hint = 'FE035';
  end if;

  -- On n'écrit que si le numéro change : reposer la même valeur ferait bouger
  -- `updated_at` sans raison, et le trigger de normalisation ferait retomber
  -- `phone_verified` sur un numéro qui n'a pas bougé.
  update public.profiles p
     set phone = v_phone
   where p.id = auth.uid() and p.phone is distinct from v_phone;

  return query
  update public.venues v
     set status = 'pending'
   where v.id = p_venue_id
  returning v.*;
end;
$$;

comment on function public.envoyer_salle_en_validation(uuid, text) is
  'Le propriétaire envoie son brouillon à la validation humaine (§4.4, ADM-01) : draft → pending. '
  'Reçoit le numéro auquel le joindre et l''écrit dans profiles.phone ; refuse sans lui (FE037). '
  'Le statut est écrit en dur — publier reste une décision d''administration.';

revoke execute on function public.envoyer_salle_en_validation(uuid, text) from public, anon;
grant  execute on function public.envoyer_salle_en_validation(uuid, text) to authenticated;

-- =============================================================================
-- request_booking — VERSION COURANTE
--
-- Identique à celle de 012, au numéro près. Tout ce que 012 explique reste vrai
-- mot pour mot : les six refus et leurs codes Ferha, les deux lignes d'une
-- journée entière insérées en une seule instruction, et le prix qui vient du
-- trigger `bookings_set_price`, donc d'`estimate_price()`, et de nulle part
-- ailleurs.
--
-- POURQUOI LE CLIENT DONNE SON NUMÉRO ICI. Le propriétaire qui accepte a
-- 48 heures pour répondre et un devis à discuter ; `booking_contact()` lui
-- ouvre le numéro du client dès « accepted » (§9). Sans numéro dans le profil,
-- cette ouverture ne donnait rien — la salle recevait une demande de quelqu'un
-- qu'elle ne pouvait pas rappeler. C'est le geste après lequel on décroche : le
-- champ est donc là, et pas plus tôt.
--
-- LE NUMÉRO N'EST PAS UNE COLONNE DE `bookings`. Il va dans le profil, une
-- fois, et `booking_contact()` le lit de là. Le recopier sur chaque réservation
-- ferait autant de numéros à corriger le jour où le client change de puce — et
-- surtout, un numéro posé sur une ligne de `bookings` échapperait au §9 : ce
-- sont les politiques de `profiles` qui le tiennent fermé.
--
-- ⚠ LA VERSION DE 012 EST SUPPRIMÉE, pas seulement remplacée : la signature
-- change, et deux versions cohabiteraient sous deux jeux d'arguments — dont
-- l'ancienne, qui laisserait poser une demande sans numéro.
-- =============================================================================

drop function if exists public.request_booking(
  uuid, date, text, integer, text, text, uuid[]
);

create or replace function public.request_booking(
  p_venue_id     uuid,
  p_event_date   date,
  p_slot         text,
  p_guest_count  integer,
  p_phone        text,
  p_event_type   text    default null,
  p_message      text    default null,
  p_option_ids   uuid[]  default '{}'::uuid[]
)
returns setof public.bookings
language plpgsql
security definer
set search_path = public
as $$
declare
  v_client uuid := auth.uid();
  v_owner  uuid;
  v_group  uuid := gen_random_uuid();
  v_slots  text[];
  v_phone  text := public.telephone_normalise(p_phone);
begin
  if v_client is null then
    raise exception 'Il faut être connecté pour demander une réservation.'
      using errcode = 'PT401', hint = 'FE006';
  end if;

  -- LE NUMÉRO AVANT LA DATE ET LE CRÉNEAU, parce que c'est le seul de ces
  -- refus que le client répare sans quitter l'écran. Lui dire d'abord que sa
  -- date est prise, puis que son numéro est mal formé, ferait deux voyages.
  if not public.telephone_valide(v_phone) then
    raise exception
      'Un numéro de téléphone valide est nécessaire : mobile 05, 06 ou 07 suivi de '
      '8 chiffres, ou fixe 02, 03 ou 04 suivi de 7 chiffres.'
      using errcode = 'PT400', hint = 'FE007',
            detail  = 'C''est par ce numéro que la salle rappelle après acceptation (§9).';
  end if;

  if p_slot not in ('midi', 'soir', 'journee') then
    raise exception 'Créneau inconnu : %. Attendu midi, soir ou journee.', p_slot
      using errcode = 'invalid_parameter_value';
  end if;

  if p_event_date < current_date then
    raise exception 'On ne réserve pas une date passée.'
      using errcode = 'PT400', hint = 'FE003';
  end if;

  -- Une demande ne se pose que sur une salle publiée : un brouillon n'est pas
  -- en vente, même si son propriétaire en connaît l'identifiant.
  select v.owner_id into v_owner
  from public.venues v
  where v.id = p_venue_id and v.status = 'published';

  if v_owner is null then
    raise exception 'Cette salle n''est pas ouverte à la réservation.'
      using errcode = 'PT409', hint = 'FE004';
  end if;

  if v_owner = v_client then
    raise exception 'On ne réserve pas sa propre salle.'
      using errcode = 'PT403', hint = 'FE005';
  end if;

  -- Une journée entière occupe midi ET soir (§6.1).
  v_slots := case when p_slot = 'journee' then array['midi', 'soir'] else array[p_slot] end;

  -- Le propriétaire a bloqué le créneau (travaux, fête de famille) : inutile de
  -- lui envoyer une demande qu'il refusera.
  if exists (
    select 1 from public.venue_blackouts vb
    where vb.venue_id = p_venue_id
      and vb.date     = p_event_date
      and vb.slot     = any (v_slots)
  ) then
    raise exception 'Ce créneau est bloqué par le propriétaire.'
      using errcode = 'PT409', hint = 'FE002';
  end if;

  -- Le créneau est déjà pris. Ce contrôle est un CONFORT, pas la garantie : une
  -- demande pending ne bloque rien (§5.1), et c'est l'index uniq_booking_slot
  -- (§6.1) qui arbitre pour de bon, au moment de la confirmation.
  --
  -- C'est lui, en pratique, qui attrape le cas de la maquette : le client a
  -- ouvert le calendrier quand la date était libre, quelqu'un d'autre a confirmé
  -- entre-temps, et il appuie sur « Envoyer ». D'où un code à lui, FE001 : ce
  -- refus-là n'est pas une erreur du client, c'est une course qu'il a perdue, et
  -- l'écran doit le lui dire en français.
  if exists (
    select 1 from public.bookings b
    where b.venue_id   = p_venue_id
      and b.event_date = p_event_date
      and b.slot       = any (v_slots)
      and b.status in ('confirmed', 'completed')
  ) then
    raise exception 'Ce créneau est déjà réservé.'
      using errcode = 'PT409', hint = 'FE001';
  end if;

  -- Le numéro par lequel la salle rappellera. On n'écrit que s'il change : voir
  -- envoyer_salle_en_validation(), même raison.
  update public.profiles p
     set phone = v_phone
   where p.id = v_client and p.phone is distinct from v_phone;

  perform public.notify_user(
    v_owner, 'booking_requested',
    jsonb_build_object('venue_id', p_venue_id, 'group_id', v_group,
                       'event_date', p_event_date, 'slot', p_slot)
  );

  -- CTE : plpgsql ne sait pas renvoyer directement un INSERT ... RETURNING.
  -- Les deux lignes d'une journée entière partent dans UNE seule instruction —
  -- c'est ce que vérifie le trigger bookings_check_journee (§6.1).
  return query
  with created as (
    insert into public.bookings (
      group_id, venue_id, client_id, event_date, slot, requested_slot,
      guest_count, event_type, client_message, option_ids,
      -- Valeur de façade : le trigger bookings_set_price l'écrase par
      -- estimate_price(). Elle n'est là que parce que la colonne est NOT NULL.
      quoted_amount, status
    )
    select
      v_group, p_venue_id, v_client, p_event_date, s, p_slot,
      p_guest_count, p_event_type, p_message, coalesce(p_option_ids, '{}'::uuid[]),
      0, 'pending'
    from unnest(v_slots) as s
    returning public.bookings.*
  )
  select c.* from created c;
end;
$$;

comment on function public.request_booking(uuid, date, text, integer, text, text, text, uuid[]) is
  'Pose une demande (§3, étape 3). Insère les deux lignes d''une journée entière en une instruction (§6.1). '
  'Reçoit le numéro auquel la salle rappellera et l''écrit dans profiles.phone ; refuse sans lui (FE007). '
  'Le montant vient du trigger bookings_set_price, donc d''estimate_price() — aucune règle de prix ici. '
  'Chaque refus porte son code Ferha dans son hint : FE001 créneau pris, FE002 bloqué, '
  'FE003 date passée, FE004 salle fermée, FE005 sa propre salle, FE006 non connecté, '
  'FE007 numéro manquant ou mal formé. '
  'Le SQLSTATE PTxxx, lui, ne sert qu''à donner son code HTTP à PostgREST.';

revoke execute on function public.request_booking(uuid, date, text, integer, text, text, text, uuid[])
  from public, anon;
grant execute on function public.request_booking(uuid, date, text, integer, text, text, text, uuid[])
  to authenticated;
