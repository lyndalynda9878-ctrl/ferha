-- =============================================================================
-- Ferha — 013_mes_reservations.sql
-- Le suivi des réservations, côté client (§3 étapes 3 à 5, §4.2 CLI-06).
--
-- CE QUE CE FICHIER APPORTE
--
--   client_bookings()  la liste de l'écran « Mes réservations », en un appel
--   bookings dans la publication supabase_realtime, pour que l'écran apprenne
--   une acceptation sans la demander
--
-- LE TÉLÉPHONE N'EST PAS RECOPIÉ ICI. C'est le point le plus important du
-- fichier. La règle du §9 — « les numéros ne sont révélés qu'après passage à
-- accepted » — vit dans booking_contact() (006), et elle n'a pas de second
-- exemplaire. client_bookings() APPELLE booking_contact() pour chaque ligne,
-- en jointure latérale, et recopie sa réponse sans la relire. Écrire ici
-- « case when status in ('accepted', ...) » aurait fait deux endroits à tenir
-- d'accord, et c'est de cette façon qu'un numéro finit par fuiter : pas par une
-- faille, par une divergence.
--
-- Rejouable : la fonction est remplacée, la publication n'est touchée que si
-- la table n'y est pas déjà.
-- Dépend de : 004 (bookings, booking_groups), 006 (RLS, booking_contact).
-- =============================================================================

-- =============================================================================
-- client_bookings — « Mes réservations », en un seul appel
--
-- UNE LIGNE PAR RÉSERVATION, pas par créneau. Elle lit booking_groups (004) :
-- une journée entière occupe deux lignes de bookings mais n'est qu'une seule
-- demande, et son devis y est répété — jamais à sommer.
--
-- SECURITY DEFINER, et pourquoi. La fonction doit lire trois choses qu'un
-- client n'a pas le droit de lire directement :
--   * profiles, fermée à son seul titulaire (002) — via booking_contact() ;
--   * venues, dont la salle a pu être suspendue depuis la réservation. Sans
--     cela, une salle retirée du catalogue effacerait son nom de l'historique
--     du client, qui verrait une ligne anonyme à la place de son mariage.
--
-- Elle porte donc elle-même la condition que la politique de bookings porterait
-- pour elle : « client_id = auth.uid() », écrite en toutes lettres ci-dessous.
-- Elle ne sert QUE le client. Le propriétaire aura la sienne, qui ne montre pas
-- les mêmes colonnes.
--
-- Ce qu'elle ne renvoie pas : rien d'une autre réservation, rien d'un autre
-- client, et jamais le motif interne d'un blocage.
-- =============================================================================

create or replace function public.client_bookings()
returns table (
  group_id          uuid,
  -- Un identifiant de ligne du groupe, celui qu'attendent cancel_booking() et
  -- booking_contact() : les deux travaillent sur le groupe entier à partir de
  -- n'importe laquelle de ses lignes.
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
  option_expires_at timestamptz,
  created_at        timestamptz,
  -- Les coordonnées telles que booking_contact() les donne, sans retouche.
  owner_name        text,
  owner_phone       text,
  phone_available   boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
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
    -- La photo de couverture, et rien qu'elle : la galerie entière n'a rien à
    -- faire dans une liste.
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
    -- Le libellé du référentiel quand le code y figure. bookings.event_type est
    -- du texte libre depuis 004 : une valeur hors référentiel ressort donc sans
    -- libellé, et l'écran affichera son code plutôt que rien.
    t.label_fr,
    bg.status,
    b.status_reason,
    bg.quoted_amount,
    bg.deposit_amount,
    bg.option_expires_at,
    bg.created_at,
    c.full_name,
    c.phone,
    c.phone_available
  from public.booking_groups bg
  -- La ligne représentative du groupe : celle dont booking_groups a retenu les
  -- valeurs, c'est-à-dire la première par ordre de créneau.
  join public.bookings b
    on b.group_id = bg.group_id and b.slot = bg.slots[1]
  join public.venues v on v.id = bg.venue_id
  left join public.wilayas    w on w.code = v.wilaya_code
  left join public.event_types t on t.code = bg.event_type
  -- LA règle du §9, appelée et non recopiée.
  cross join lateral public.booking_contact(b.id) c
  where bg.client_id = auth.uid()
  -- La plus récente en haut : c'est celle dont on attend une réponse.
  order by bg.created_at desc;
end;
$$;

comment on function public.client_bookings() is
  'Écran « Mes réservations » du client (§4.2, CLI-06), une ligne par réservation. '
  'Le téléphone du propriétaire vient de booking_contact() et de nulle part ailleurs : '
  'la règle du §9 n''a pas de second exemplaire ici.';

revoke execute on function public.client_bookings() from public, anon;
grant execute on function public.client_bookings() to authenticated;

-- =============================================================================
-- Temps réel — bookings dans la publication
--
-- « Si le propriétaire accepte pendant que l'écran est ouvert, l'état change
-- tout seul. » Un rafraîchissement périodique ferait le contraire de ce qu'on
-- cherche : il coûterait du réseau toutes les X secondes pour n'apprendre
-- presque jamais rien, et sur une 4G algérienne (§7.3) c'est exactement la
-- dépense qu'on refuse ailleurs.
--
-- CE QUI PROTÈGE CETTE PUBLICATION, c'est la politique RLS de bookings (006).
-- Realtime évalue `bookings_select_parties` pour chaque abonné avant de lui
-- livrer une ligne : un client ne reçoit que ses réservations, un propriétaire
-- que celles de ses salles. Ouvrir la publication n'ouvre donc pas la table —
-- si un jour la politique de SELECT s'élargit, elle s'élargit ici aussi, et
-- c'est encore un seul endroit à surveiller.
--
-- L'abonnement Flutter pose en plus un filtre `client_id=eq.<uid>` : il ne
-- remplace pas la politique, il évite au serveur d'évaluer des lignes qui ne
-- partiront de toute façon pas.
-- =============================================================================

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename  = 'bookings'
  ) then
    alter publication supabase_realtime add table public.bookings;
  end if;
end $$;
