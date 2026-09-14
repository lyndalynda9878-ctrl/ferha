-- =============================================================================
-- Ferha — 033_options_dans_mes_reservations.sql
-- Les options retenues remontent avec la réservation.
--
-- POURQUOI CETTE COLONNE EXISTE
--
-- L'écran de confirmation d'une demande (§3, étape 3) montre un récapitulatif :
-- salle, date, créneau, invités, options, estimation. Il le tenait de l'écran
-- précédent, passé de main à main par `extra` de go_router — et `extra` ne
-- survit pas à un rechargement de page. Le client qui rafraîchissait sa
-- confirmation voyait « votre demande est partie » sans savoir LAQUELLE.
--
-- Le README l'écrit depuis le premier jour : une page doit survivre à un
-- rechargement et se partager. L'écran relit donc la réservation par sa
-- référence, et `client_bookings()` doit pouvoir la lui rendre entière. Six de
-- ses sept lignes y étaient déjà ; il manquait les options.
--
-- =============================================================================
-- DES LIBELLÉS, ET AUCUN PRIX
--
-- La colonne rend `text[]` — les libellés, et rien d'autre. C'est délibéré, et
-- c'est la règle du projet : le prix vient d'`estimate_price()`, et de nulle
-- part ailleurs. `quoted_amount`, déjà rendu par cette fonction, porte le
-- montant du groupe, options comprises ; faire remonter ici le prix de chaque
-- option ouvrirait un second chemin vers un montant, et deux chemins finissent
-- toujours par diverger.
--
-- L'écran de confirmation n'affiche d'ailleurs que les libellés, séparés par
-- une virgule. Il n'a jamais montré le prix d'une option.
--
-- =============================================================================
-- LE CORPS EST CELUI DE 026, MOT POUR MOT — ET C'EST LE PIÈGE DE CE FICHIER
--
-- `client_bookings()` a été redéfinie trois fois : 013 l'a créée, 024 lui a
-- ajouté `acompte_du`, 026 `avis_depose` et `avis_possible`. La version
-- courante est celle de 026, et c'est d'elle qu'on part.
--
-- Repartir de 013 — le fichier qui porte son nom, et donc celui qu'on ouvre en
-- premier — aurait silencieusement retiré les trois colonnes des deux
-- migrations suivantes : le bouton « Verser l'acompte » de la liste aurait
-- perdu son montant, et le bouton d'avis serait devenu invisible. Une fonction
-- qui se redéfinit d'une migration à l'autre se relit dans la DERNIÈRE qui la
-- touche, jamais dans celle qui l'a créée.
--
-- =============================================================================
-- LA SIGNATURE NE CHANGE PAS POUR SES APPELANTS
--
-- `client_bookings()` ne prend aucun paramètre : sa signature est
-- `client_bookings()`, et elle le reste. Ce qui change est le type de retour —
-- une colonne de plus, à la fin.
--
-- DROP PUIS CREATE, comme en 024 et en 026 : PostgreSQL refuse de remplacer une
-- fonction dont la signature de sortie bouge. Le DROP est conditionnel, donc
-- rejouable. Aucune vue ni aucune autre fonction ne l'appelle ; elle n'est lue
-- que par l'application, qui nomme ses colonnes une par une.
--
-- Côté Dart, `Reservation.depuisJson` lit des clés par leur nom : une colonne
-- ajoutée à la fin n'en déplace aucune, et une version de l'application qui ne
-- la connaît pas encore l'ignore.
--
-- Rejouable. Dépend de : 004 (bookings, booking_groups), 005 (venue_options),
-- 006 (RLS, booking_contact), 024 (montant_acompte), 026 (la version qu'elle
-- reprend, avis_dans_la_fenetre, reviews).
-- =============================================================================

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
  acompte_du        integer,
  option_expires_at timestamptz,
  created_at        timestamptz,
  owner_name        text,
  owner_phone       text,
  phone_available   boolean,
  avis_depose       boolean,
  avis_possible     boolean,
  -- Les libellés des options retenues. Voir l'en-tête : des libellés, et aucun
  -- prix.
  option_labels     text[]
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
    c.phone_available,
    exists (select 1 from public.reviews r
             where r.booking_group_id = bg.group_id),
    bg.status = 'completed'
      and public.avis_dans_la_fenetre(bg.event_date)
      and not exists (select 1 from public.reviews r
                       where r.booking_group_id = bg.group_id
                         and r.owner_reply is not null),
    -- LES OPTIONS DE LA LIGNE REPRÉSENTATIVE, et c'est la bonne : `option_ids`
    -- appartient au GROUPE, pas au créneau. request_booking() (012) écrit le
    -- même tableau sur les deux lignes d'une journée entière, comme il y répète
    -- le devis — répété, pas partagé (§6.1).
    --
    -- Dans l'ordre du catalogue de la salle, pour que deux lectures de la même
    -- réservation ne rendent pas les options dans deux ordres différents.
    --
    -- is_active N'EST PAS FILTRÉ, et c'est voulu : « une option retirée du
    -- catalogue reste lisible, les réservations passées la citent encore »
    -- (005). Une demande d'août ne perd pas sa ligne parce que le propriétaire
    -- a fermé l'option en septembre.
    (select array_agg(vo.label_fr order by vo.position, vo.label_fr)
       from public.venue_options vo
      where vo.id = any (b.option_ids))
  from public.booking_groups bg
  -- La ligne représentative du groupe : celle dont booking_groups a retenu les
  -- valeurs, c'est-à-dire la première par ordre de créneau.
  join public.bookings b
    on b.group_id = bg.group_id and b.slot = bg.slots[1]
  join public.venues v on v.id = bg.venue_id
  left join public.wilayas     w on w.code = v.wilaya_code
  left join public.event_types t on t.code = bg.event_type
  -- LA règle du §9, appelée et non recopiée.
  cross join lateral public.booking_contact(b.id) c
  where bg.client_id = auth.uid()
  -- La plus récente en haut : c'est celle dont on attend une réponse.
  order by bg.created_at desc;
end;
$fn$;

comment on function public.client_bookings() is
  'Écran « Mes réservations » du client (§4.2, CLI-06), une ligne par réservation. '
  'Le téléphone du propriétaire vient de booking_contact() et de nulle part ailleurs : '
  'la règle du §9 n''a pas de second exemplaire ici. « acompte_du » donne l''acompte en dinars '
  'entiers — montant_acompte(), le même arrondi que l''écran 6 et que la Edge Function. '
  'Depuis 026, « avis_depose » et « avis_possible » disent s''il y a un avis et si le déposer ou '
  'le corriger aboutira. Depuis 033, « option_labels » porte les libellés des options retenues, '
  'et eux seuls : le montant, options comprises, est quoted_amount, et il vient d''estimate_price().';

revoke execute on function public.client_bookings() from public, anon;
grant  execute on function public.client_bookings() to authenticated;
