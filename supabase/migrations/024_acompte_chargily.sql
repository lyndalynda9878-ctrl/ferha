-- =============================================================================
-- Ferha — 024_acompte_chargily.sql
-- Verser l'acompte : ce que la base dit, et ce qu'elle refuse (§4.2, CLI-06 ;
-- §7.2, create-checkout).
--
-- CE QUE CE FICHIER APPORTE
--
--   montant_acompte()       LE montant dû, en dinars ENTIERS — l'arrondi, à un
--                           seul endroit
--   acompte_a_verser()      l'écran 6 en un appel, et ses refus
--   enregistrer_checkout()  la ligne payments « pending », réservée au
--                           service_role de la Edge Function
--
-- L'ARRONDI SE FAIT ICI, ET NULLE PART AILLEURS. Chargily encaisse des dinars
-- entiers ; bookings.deposit_amount est un numeric(12,2), parce que 25 % d'un
-- devis tombe rarement rond — 205 333 DA donnent 51 333,25 DA d'acompte. Il
-- faut donc choisir un entier, et le choisir UNE fois : si l'écran arrondissait
-- de son côté et la fonction du sien, le bouton dirait « Payer 51 333 DA » et
-- la page Chargily en demanderait 51 334. montant_acompte() est cet endroit
-- unique ; l'écran affiche ce qu'elle rend, et le checkout est créé sur ce
-- qu'elle rend.
--
-- ELLE ARRONDIT AU DINAR SUPÉRIEUR. Les centimes ne circulent pas en Algérie :
-- il faut trancher, et l'acompte est un minimum convenu — le rogner de 99
-- centimes au client serait lui faire verser moins que ce que le propriétaire a
-- accepté. Le solde affiché (montant convenu − acompte) absorbe la différence,
-- et reste exact au centime.
--
-- AUCUNE SECONDE FORMULE DE PRIX. Le devis vient d'estimate_price(), l'acompte
-- de deposit_rate() appliqué par accepter_demande() (015). Ce fichier ne
-- calcule rien : il lit bookings.deposit_amount, déjà en base, et n'en change
-- que l'unité.
--
-- LA RÈGLE DE L'OPTION EST CELLE DE 023, APPELÉE ET NON RECOPIÉE.
-- tient_la_date() dit « option » ou ne le dit pas ; on ne relit ni le statut ni
-- l'échéance pour en juger autrement. C'est la même règle que le calendrier, la
-- recherche et l'acceptation — et c'est pour cela qu'elle n'a qu'un exemplaire.
--
-- LES CODES FERHA DE CE FICHIER
--
--   FE050  PT401  aucune session
--   FE051  PT403  cette réservation n'est pas la vôtre — ou n'existe pas
--   FE052  PT409  la demande n'est pas encore acceptée
--   FE053  PT409  l'option est échue, ou la demande n'est plus en course
--   FE054  PT409  l'acompte est déjà réglé
--   FE055  PT400  moyen de paiement inattendu
--
-- FE051 NE DISTINGUE PAS « inconnue » DE « pas la vôtre », et c'est délibéré :
-- deux phrases différentes diraient à un curieux que tel identifiant existe.
--
-- POURQUOI FE052, FE053 ET FE054 SONT TROIS CODES ET NON UN. Ils refusent la
-- même chose — « cette réservation n'attend pas d'acompte » — mais la suite à
-- faire n'est pas la même : attendre une réponse, refaire une demande, ou ne
-- rien faire du tout parce que c'est déjà payé. L'écran a trois phrases à dire ;
-- il lui faut trois codes.
--
-- AUCUNE ÉCRITURE CLIENTE SUR payments (§9, supabase/README.md). RLS est actif
-- sur la table et elle n'a aucune politique d'INSERT : enregistrer_checkout()
-- est SECURITY DEFINER et n'est donnée qu'au service_role, celui de la Edge
-- Function. Flutter ne peut pas l'appeler, et ne doit pas le pouvoir.
--
-- is_test EST VRAI, TOUJOURS (v2.0, CLI-06). La colonne a ce défaut depuis 004 ;
-- on l'écrit quand même en toutes lettres à l'insertion, parce que le jour du
-- passage en réel c'est cette ligne-là qu'on viendra chercher.
--
-- Rejouable : les fonctions sont remplacées (client_bookings droppée puis
-- recréée, son type de retour changeant), les droits repris.
-- Dépend de : 004 (bookings, booking_groups, payments), 006 (RLS, booking_contact),
--             013 (client_bookings, redéfinie ici),
--             015 (deposit_amount posée à l'acceptation), 023 (tient_la_date).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- montant_acompte — LE montant dû, en dinars entiers
--
-- Plomberie interne : aucun rôle ne l'appelle directement. Les deux fonctions
-- publiques de ce fichier passent par elle, et c'est tout l'intérêt — il n'y a
-- qu'un seul arrondi dans le projet.
--
-- STABLE : elle lit une table.
-- -----------------------------------------------------------------------------

create or replace function public.montant_acompte(p_group_id uuid)
returns integer
language sql
stable
set search_path = public
as $fn$
  select ceil(bg.deposit_amount)::integer
    from public.booking_groups bg
   where bg.group_id = p_group_id
     and bg.deposit_amount is not null;
$fn$;

comment on function public.montant_acompte(uuid) is
  'L''acompte dû pour une réservation, en dinars ENTIERS — l''unique arrondi du projet. '
  'Chargily n''encaisse pas de centimes ; bookings.deposit_amount en porte. Arrondi au dinar '
  'SUPÉRIEUR : l''acompte est un minimum convenu, et le solde du jour J absorbe la différence. '
  'Ne calcule aucun prix : deposit_amount est déjà en base, posée par accepter_demande() (015).';

revoke execute on function public.montant_acompte(uuid)
  from public, anon, authenticated;

-- =============================================================================
-- acompte_a_verser — l'écran 6, en un seul appel
--
-- SECURITY DEFINER pour la même raison que client_bookings() (013) : l'écran a
-- besoin du nom de la salle et de sa commune, et venues peut avoir été suspendue
-- depuis. Elle porte donc elle-même la condition que la politique porterait pour
-- elle — « client_id = auth.uid() », écrite en toutes lettres.
--
-- ELLE NE PARLE PAS À CHARGILY. Elle dit ce qui est dû, à qui, et jusqu'à quand ;
-- la page de paiement est l'affaire de la Edge Function. C'est ce qui permet à
-- l'écran de s'ouvrir, de se recharger et d'égrener son compte à rebours sans
-- qu'un seul checkout soit créé — on n'en crée un qu'au moment où l'on appuie
-- sur « Payer ».
--
-- checkout_id ET paiement_en_cours SORTENT D'ICI. Le premier sert à la Edge
-- Function, qui retrouve la page de paiement déjà ouverte au lieu d'en créer une
-- seconde (une seule page active par réservation). Le second sert à l'écran, au
-- retour de Chargily : une ligne payments « pending » existe, le webhook du J16
-- n'a pas encore parlé, et la seule phrase honnête est « paiement en cours de
-- vérification ». Revenir sur success_url ne confirme rien.
-- =============================================================================

create or replace function public.acompte_a_verser(p_booking_id uuid)
returns table (
  group_id          uuid,
  booking_id        uuid,
  venue_id          uuid,
  venue_name        text,
  commune           text,
  wilaya_name       text,
  event_date        date,
  requested_slot    text,
  guest_count       integer,
  event_type        text,
  event_label       text,
  owner_name        text,
  -- Le devis retenu par le propriétaire, au centime.
  montant_convenu   numeric,
  -- L'acompte, en dinars entiers : ce que dira le bouton, et ce que Chargily
  -- encaissera. Les deux, parce que c'est le même nombre.
  acompte           integer,
  -- Ce qui restera à régler sur place le jour J. Le complément exact de
  -- l'acompte arrondi : les deux additionnés font le montant convenu.
  solde             numeric,
  option_expires_at timestamptz,
  checkout_id       text,
  paiement_en_cours boolean
)
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  v_group   uuid;
  v_client  uuid;
  v_status  text;
  v_expires timestamptz;
  v_tenue   text;
  v_acompte integer;
begin
  if auth.uid() is null then
    raise exception 'Il faut être connecté pour verser un acompte.'
      using errcode = 'PT401', hint = 'FE050';
  end if;

  select b.group_id, b.client_id, b.status, b.option_expires_at
    into v_group, v_client, v_status, v_expires
    from public.bookings b
   where b.id = p_booking_id;

  -- Inconnue ou pas la sienne : même phrase, même code.
  if v_group is null or v_client is distinct from auth.uid() then
    raise exception 'Cette réservation n''est pas la vôtre.'
      using errcode = 'PT403', hint = 'FE051';
  end if;

  -- LA règle de 023, appelée. Trois refus, parce qu'il y a trois suites.
  v_tenue := public.tient_la_date(v_status, v_expires);

  if v_tenue = 'confirme' then
    raise exception 'L''acompte de cette réservation est déjà réglé.'
      using errcode = 'PT409', hint = 'FE054';
  end if;

  if v_tenue is distinct from 'option' then
    if v_status = 'pending' then
      raise exception 'Le propriétaire n''a pas encore répondu à cette demande.'
        using errcode = 'PT409', hint = 'FE052';
    end if;

    raise exception 'La date n''est plus tenue pour cette demande.'
      using errcode = 'PT409', hint = 'FE053';
  end if;

  v_acompte := public.montant_acompte(v_group);

  -- accepter_demande() pose toujours un acompte, et l'état « option » implique
  -- « accepted ». Si la colonne était vide malgré tout, mieux vaut le dire que
  -- proposer de payer zéro dinar.
  if v_acompte is null then
    raise exception 'Le montant de l''acompte n''a pas été fixé pour cette demande.'
      using errcode = 'PT409', hint = 'FE053';
  end if;

  return query
  select
    bg.group_id,
    b.id,
    bg.venue_id,
    v.name,
    v.commune,
    w.name_fr,
    bg.event_date,
    bg.requested_slot,
    bg.guest_count,
    bg.event_type,
    t.label_fr,
    pr.full_name,
    bg.quoted_amount,
    v_acompte,
    bg.quoted_amount - v_acompte,
    bg.option_expires_at,
    -- La page de paiement déjà ouverte, s'il y en a une.
    paie.checkout_id,
    paie.checkout_id is not null
  from public.booking_groups bg
  -- La ligne représentative du groupe, celle que booking_groups a retenue —
  -- même convention que client_bookings() (013).
  join public.bookings b
    on b.group_id = bg.group_id and b.slot = bg.slots[1]
  join public.venues v on v.id = bg.venue_id
  left join public.profiles     pr on pr.id = v.owner_id
  left join public.wilayas      w  on w.code = v.wilaya_code
  left join public.event_types  t  on t.code = bg.event_type
  left join lateral (
    select pa.checkout_id
      from public.payments pa
      join public.bookings pb on pb.id = pa.booking_id
     where pb.group_id = bg.group_id
       and pa.status = 'pending'
       and pa.checkout_id is not null
     order by pa.created_at desc
     limit 1
  ) paie on true
  where bg.group_id = v_group;
end;
$fn$;

comment on function public.acompte_a_verser(uuid) is
  'Écran 6 — « Verser l''acompte » (§4.2, CLI-06), en un appel. Refuse sans session (FE050), '
  'pour la réservation d''un autre (FE051), et quand tient_la_date() (023) ne dit pas « option » : '
  'demande encore en attente (FE052), date plus tenue (FE053), acompte déjà réglé (FE054). '
  'Le montant est celui de montant_acompte() — l''unique arrondi — et de nulle part ailleurs.';

revoke execute on function public.acompte_a_verser(uuid) from public, anon;
grant execute on function public.acompte_a_verser(uuid) to authenticated;

-- =============================================================================
-- enregistrer_checkout — la trace d'une page de paiement ouverte
--
-- APPELÉE PAR LA EDGE FUNCTION create-checkout, EN service_role, ET PAR ELLE
-- SEULE. Le §9 dit « aucune écriture cliente » sur payments : c'est pourquoi
-- cette fonction est retirée à anon et authenticated. L'application Flutter ne
-- peut pas l'atteindre.
--
-- LE MONTANT N'EST PAS UN PARAMÈTRE, ET C'EST LE POINT. La Edge Function a déjà
-- lu le montant pour créer le checkout ; si elle le repassait ici, un jour une
-- version de cette fonction enverrait autre chose et la trace comptable
-- mentirait. On relit donc montant_acompte() dans la base, à l'instant de
-- l'écriture.
--
-- ELLE REVÉRIFIE L'OPTION. La Edge Function l'a déjà fait, avec le jeton du
-- client ; entre les deux appels il s'est écoulé un aller-retour chez Chargily,
-- et une option peut s'éteindre pendant ce temps-là. La base tranche en dernier.
--
-- UNE SEULE PAGE ACTIVE PAR RÉSERVATION. Les lignes « pending » du même groupe
-- qui portent un AUTRE checkout passent à « failed » : ce sont des pages
-- abandonnées, et les laisser « pending » ferait croire à autant de paiements en
-- cours. « failed » est le mot le moins faux des quatre que permet la contrainte
-- de 004 — « abandonné » n'en fait pas partie, et l'ajouter pour ce seul cas
-- demanderait de rouvrir le §6.
--
-- IDEMPOTENTE sur checkout_id, comme le webhook du J16 devra l'être : rejouer
-- l'appel ne crée pas un second paiement. L'index partiel de 004 le garantit,
-- ON CONFLICT le rend silencieux.
-- =============================================================================

create or replace function public.enregistrer_checkout(
  p_booking_id  uuid,
  p_checkout_id text,
  p_method      text
)
returns public.payments
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_group    uuid;
  v_status   text;
  v_expires  timestamptz;
  v_acompte  integer;
  v_paiement public.payments;
begin
  -- « cash » n'est pas de ce fichier : le règlement en espèces n'a pas de
  -- checkout, et son parcours viendra à son étape.
  if p_method is null or p_method not in ('cib', 'edahabia') then
    raise exception 'Moyen de paiement inattendu : %.', coalesce(p_method, 'aucun')
      using errcode = 'PT400', hint = 'FE055';
  end if;

  if p_checkout_id is null or btrim(p_checkout_id) = '' then
    raise exception 'Un checkout sans identifiant ne se range pas.'
      using errcode = 'PT400', hint = 'FE055';
  end if;

  select b.group_id, b.status, b.option_expires_at
    into v_group, v_status, v_expires
    from public.bookings b
   where b.id = p_booking_id;

  if v_group is null then
    raise exception 'Cette réservation n''existe pas.'
      using errcode = 'PT403', hint = 'FE051';
  end if;

  if public.tient_la_date(v_status, v_expires) is distinct from 'option' then
    raise exception 'La date n''est plus tenue pour cette demande.'
      using errcode = 'PT409', hint = 'FE053';
  end if;

  v_acompte := public.montant_acompte(v_group);

  if v_acompte is null then
    raise exception 'Le montant de l''acompte n''a pas été fixé pour cette demande.'
      using errcode = 'PT409', hint = 'FE053';
  end if;

  -- Les pages abandonnées du même groupe ne restent pas « en cours ».
  update public.payments pa
     set status = 'failed'
    from public.bookings pb
   where pb.id = pa.booking_id
     and pb.group_id = v_group
     and pa.status = 'pending'
     and pa.checkout_id is distinct from p_checkout_id;

  insert into public.payments (booking_id, checkout_id, amount, method, status, is_test)
  values (p_booking_id, p_checkout_id, v_acompte, p_method, 'pending', true)
  on conflict (checkout_id) where checkout_id is not null
  do nothing
  returning * into v_paiement;

  -- Rejeu : la ligne existait déjà, on rend celle qui est en base.
  if v_paiement.id is null then
    select * into v_paiement
      from public.payments
     where checkout_id = p_checkout_id;
  end if;

  return v_paiement;
end;
$fn$;

comment on function public.enregistrer_checkout(uuid, text, text) is
  'Range une page de paiement Chargily ouverte, en « pending » (§6, §9). Réservée au service_role '
  'de la Edge Function create-checkout : aucune écriture cliente sur payments. Le montant n''est '
  'pas un paramètre — il est relu par montant_acompte(). Idempotente sur checkout_id, et éteint '
  'les pages abandonnées du même groupe : une seule page active par réservation.';

revoke execute on function public.enregistrer_checkout(uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.enregistrer_checkout(uuid, text, text)
  to service_role;

-- =============================================================================
-- client_bookings — VERSION COURANTE
--
-- CE QUI CHANGE : une colonne, `acompte_du`, et rien d'autre. Le corps est celui
-- de 013, mot pour mot, y compris booking_contact() appelée et non recopiée.
--
-- POURQUOI CETTE COLONNE EXISTE. L'écran « Mes réservations » porte désormais le
-- bouton « Verser l'acompte — 51 334 DA », et l'écran 6 affiche « Payer
-- 51 334 DA ». Les deux doivent dire LE MÊME NOMBRE, et ce nombre est un entier :
-- celui que Chargily encaissera. `deposit_amount` est un numeric(12,2) — 25 %
-- d'un devis de 205 333 DA font 51 333,25 DA — et l'arrondir à l'écran ferait
-- un second arrondi, au plus près plutôt qu'au dinar supérieur. Le bouton de la
-- liste dirait alors 51 333 et la caisse en demanderait 51 334.
--
-- UN DINAR D'ÉCART EST UN PETIT MENSONGE, ET C'EST LE PIRE MOMENT POUR EN FAIRE
-- UN : juste avant de payer. La liste lit donc montant_acompte(), comme l'écran
-- 6 et comme la Edge Function. Trois lecteurs, un seul arrondi.
--
-- `deposit_amount` RESTE DANS LA VUE : c'est le montant convenu au centime, et
-- c'est lui qui a valeur d'accord entre les deux parties. `acompte_du` n'est que
-- sa forme encaissable.
-- =============================================================================

-- DROP PUIS CREATE, ET NON « create or replace » : le type de retour change —
-- une colonne de plus —, et PostgreSQL refuse de remplacer une fonction dont la
-- signature de sortie bouge. Le DROP est conditionnel, donc rejouable.
drop function if exists public.client_bookings();

create function public.client_bookings()
returns table (
  group_id          uuid,
  booking_id        uuid,
  venue_id          uuid,
  venue_name        text,
  commune           text,
  wilaya_name       text,
  cover_photo       text,
  event_date        date,
  requested_slot    text,
  slots             text[],
  guest_count       integer,
  event_type        text,
  event_label       text,
  status            text,
  status_reason     text,
  quoted_amount     numeric,
  deposit_amount    numeric,
  -- L'acompte en dinars entiers — celui des boutons et de Chargily. NULL tant
  -- que le propriétaire n'a pas répondu, comme deposit_amount.
  acompte_du        integer,
  option_expires_at timestamptz,
  created_at        timestamptz,
  owner_name        text,
  owner_phone       text,
  phone_available   boolean
)
language plpgsql
stable
security definer
set search_path = public
as $fn$
begin
  if auth.uid() is null then
    raise exception 'Il faut être connecté pour voir ses réservations.'
      using errcode = 'PT401', hint = 'FE006';
  end if;

  return query
  select
    bg.group_id,
    b.id,
    bg.venue_id,
    v.name,
    v.commune,
    w.name_fr,
    (select p.storage_path
       from public.venue_photos p
      where p.venue_id = v.id
      order by p.is_cover desc, p.position asc
      limit 1),
    bg.event_date,
    bg.requested_slot,
    bg.slots,
    bg.guest_count,
    bg.event_type,
    t.label_fr,
    bg.status,
    b.status_reason,
    bg.quoted_amount,
    bg.deposit_amount,
    -- L'UNIQUE arrondi, appelé et non refait.
    public.montant_acompte(bg.group_id),
    bg.option_expires_at,
    bg.created_at,
    c.full_name,
    c.phone,
    c.phone_available
  from public.booking_groups bg
  join public.bookings b
    on b.group_id = bg.group_id and b.slot = bg.slots[1]
  join public.venues v on v.id = bg.venue_id
  left join public.wilayas    w on w.code = v.wilaya_code
  left join public.event_types t on t.code = bg.event_type
  -- LA règle du §9, appelée et non recopiée.
  cross join lateral public.booking_contact(b.id) c
  where bg.client_id = auth.uid()
  order by bg.created_at desc;
end;
$fn$;

comment on function public.client_bookings() is
  'Écran « Mes réservations » du client (§4.2, CLI-06), une ligne par réservation. '
  'Le téléphone du propriétaire vient de booking_contact() et de nulle part ailleurs : '
  'la règle du §9 n''a pas de second exemplaire ici. Depuis 024, « acompte_du » donne '
  'l''acompte en dinars entiers — montant_acompte(), le même arrondi que l''écran 6 et '
  'que la Edge Function : le bouton de la liste et la caisse disent le même nombre.';

revoke execute on function public.client_bookings() from public, anon;
grant execute on function public.client_bookings() to authenticated;
