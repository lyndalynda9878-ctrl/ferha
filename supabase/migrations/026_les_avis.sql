-- =============================================================================
-- Ferha — 026_les_avis.sql
-- Les avis : marquer honoré, déposer, répondre, lire (§5.4, §4.2 CLI-08,
-- §4.3 OWN-06 ; maquettes, écran 7).
--
-- CE QUI MANQUAIT, ET QUI EXPLIQUE L'ORDRE DE CE FICHIER. Les tables étaient
-- là depuis 004 — `reviews`, son trigger, la vue `venue_ratings` — et les
-- politiques depuis 006. Il manquait les DEUX BOUTS : personne n'appelait
-- `complete_booking()`, donc aucune réservation ne passait jamais « completed »,
-- donc aucun avis n'était possible ; et une fois l'avis possible, aucune
-- fonction ne l'écrivait avec des refus lisibles.
--
-- Ce fichier pose les deux bouts et rien entre : les règles du §5.4 étaient
-- déjà écrites en 004 et 006, et elles restent où elles sont.
--
-- =============================================================================
-- LA FENÊTRE DU §5.4 EST ÉCRITE UNE SEULE FOIS
--
-- « De J+1 à J+30 après l'événement » vivait en toutes lettres dans la
-- politique `reviews_insert_client` (006). Trois lecteurs s'ajoutent ici — la
-- liste « Mes réservations », l'écran de dépôt, la fonction qui écrit — et
-- quatre copies d'une même règle finissent toujours par diverger, comme le prix
-- finirait par diverger d'`estimate_price()`.
--
-- `fenetre_avis()` porte donc les deux bornes, `avis_dans_la_fenetre()` les
-- compare à aujourd'hui, et la politique de 006 est RÉÉCRITE pour les appeler
-- au lieu de les redire. Après ce fichier, J+1 et J+30 n'existent qu'à un seul
-- endroit du projet.
--
-- =============================================================================
-- L'ANONYMAT N'EST PAS UNE RÈGLE D'AFFICHAGE
--
-- La maquette de l'écran 7 écrit « Sarah B. », et ce n'est pas une abréviation
-- de confort : un avis est PUBLIC, lisible sans compte, et il dit qu'une
-- personne nommée s'est mariée tel jour dans telle salle. Le nom entier, l'e-mail
-- et le téléphone n'ont rien à y faire.
--
-- `profiles` reste donc fermée — sa politique de 002 ne laisse chacun lire que
-- sa propre ligne — et la seule chose qui en sort vers un avis passe par
-- `nom_abrege()`, à l'intérieur d'`avis_de_la_salle()`. Un écran qui voudrait
-- afficher le nom entier d'un client n'aurait rien à afficher : la colonne ne
-- traverse jamais la fonction.
--
-- =============================================================================
-- LA NOTE VIENT DE venue_ratings, ET DE NULLE PART AILLEURS
--
-- La moyenne bayésienne du §5.4 est écrite dans la vue depuis 004. Aucune
-- fonction de ce fichier ne recalcule une moyenne, et aucun écran ne le fera :
-- c'est la même règle que le prix, pour la même raison. Une salle avec un seul
-- 5/5 reste classée sous une salle à quarante 4,6, et c'est la vue qui le dit.
--
-- =============================================================================
-- LES CODES FERHA
--
-- La série reprend à 070, FE064 étant le dernier posé (025). Trois acteurs,
-- trois écrans, trois séries — comme FE050 (client, caisse) et FE060
-- (propriétaire, espèces) sont deux séries pour un même mot « connectez-vous ».
--
--   complete_booking() — le propriétaire marque l'événement honoré
--   FE070  PT401  il faut être connecté
--   FE071  PT403  cette réservation ne concerne pas vos salles
--   FE072  PT409  la réservation n'est pas confirmée
--   FE073  PT409  l'événement n'a pas encore eu lieu
--
--   avis_a_deposer() et deposer_avis() — le client écrit son avis
--   FE074  PT401  il faut être connecté
--   FE075  PT403  cette réservation n'est pas la vôtre — ou n'existe pas
--   FE076  PT409  la réservation n'est pas honorée
--   FE077  PT400  hors de la fenêtre J+1 → J+30
--   FE078  PT409  l'avis est figé : le propriétaire a répondu
--   FE079  PT400  la note globale manque, ou sort de 1 à 5
--
--   repondre_a_un_avis() — le droit de réponse (OWN-06)
--   FE080  PT401  il faut être connecté
--   FE081  PT403  cet avis ne porte pas sur une de vos salles
--   FE082  PT409  cet avis a déjà une réponse
--   FE083  PT400  la réponse est vide
--
-- FE075 NE DISTINGUE PAS « inconnue » DE « pas la vôtre », comme FE051 avant
-- lui : répondre « cette réservation n'existe pas » à qui essaie un identifiant
-- au hasard lui apprendrait lesquels existent.
--
-- Dépend de : 002 (can_read_venue, owns_venue, profiles fermée),
--             004 (reviews, reviews_guard, venue_ratings, complete_booking,
--                  notify_user, booking_groups),
--             006 (politiques de reviews, reviews_guard_actor),
--             013 / 024 (client_bookings, redéfinie ici),
--             023 (rien d'appelé, mais l'ordre des fichiers en dépend).
--
-- Rejouable : les fonctions sont remplacées, la politique et le trigger
-- supprimés avant d'être recréés, et client_bookings droppée puis recréée —
-- son type de retour change.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- fenetre_avis — les deux bornes du §5.4, et le seul endroit où elles existent
--
-- J+1 : avant, l'avis est prématuré — la salle n'est pas encore rangée et
-- personne n'a dormi. J+30 : après, il n'est plus de première main.
--
-- IMMUTABLE et non STABLE : elle ne regarde pas le calendrier, elle décale une
-- date. C'est `avis_dans_la_fenetre()`, juste en dessous, qui regarde l'heure —
-- et c'est pour cela que les deux sont séparées.
-- -----------------------------------------------------------------------------

create or replace function public.fenetre_avis(p_event_date date)
returns table (ouvre_le date, ferme_le date)
language sql
immutable
set search_path = public
as $$
  select p_event_date + 1, p_event_date + 30;
$$;

comment on function public.fenetre_avis(date) is
  'Les deux bornes de la fenêtre de dépôt d''un avis (§5.4) : J+1 et J+30. '
  'Écrites ici et nulle part ailleurs — la politique reviews_insert_client, '
  'client_bookings(), avis_a_deposer() et deposer_avis() les lisent toutes d''ici.';

-- Vrai quand on est dedans, aujourd'hui. STABLE : elle lit current_date.
create or replace function public.avis_dans_la_fenetre(p_event_date date)
returns boolean
language sql
stable
set search_path = public
as $$
  select current_date between f.ouvre_le and f.ferme_le
  from public.fenetre_avis(p_event_date) f;
$$;

comment on function public.avis_dans_la_fenetre(date) is
  'Vrai si la fenêtre de dépôt du §5.4 est ouverte aujourd''hui pour un événement '
  'de cette date. Les bornes viennent de fenetre_avis(), et d''elle seule.';

-- Plomberie interne : ce sont les fonctions publiques et la politique de 006
-- qui les citent, et elles s'exécutent en droits de leur propriétaire.
revoke execute on function public.fenetre_avis(date)        from public, anon;
revoke execute on function public.avis_dans_la_fenetre(date) from public, anon;
grant  execute on function public.fenetre_avis(date)        to authenticated;
grant  execute on function public.avis_dans_la_fenetre(date) to authenticated;

-- -----------------------------------------------------------------------------
-- nom_abrege — « Sarah Benali » devient « Sarah B. »
--
-- CE QU'ELLE NE PEUT PAS FAIRE, ET C'EST LE POINT : elle ne lit aucune table.
-- Elle reçoit un texte et en rend un autre. Impossible de s'en servir pour
-- retrouver le nom de quelqu'un — elle ne fait que le raccourcir.
--
-- Prénom entier, initiale du DERNIER mot. « Mohamed Tahar Belkacem » donne
-- « Mohamed B. » : c'est le nom de famille qu'on cache, pas le second prénom.
--
-- UN SEUL MOT RESTE ENTIER. « Sarah » seule n'a pas de nom de famille à cacher,
-- et « Sarah S. » inventerait une initiale.
--
-- VIDE DEVIENT « Client ». C'est le cas d'un compte fermé : l'anonymisation
-- prévue au §9 remplace full_name par une valeur neutre, et l'avis reste en
-- place — une réservation passée est une trace comptable. La carte doit donc
-- pouvoir s'afficher sans nom du tout.
-- -----------------------------------------------------------------------------

create or replace function public.nom_abrege(p_full_name text)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
  v_mots text[];
  v_fin  integer;
begin
  v_mots := regexp_split_to_array(btrim(coalesce(p_full_name, '')), '\s+');
  v_fin  := array_length(v_mots, 1);

  if v_fin is null or v_mots[1] = '' then
    return 'Client';
  end if;

  if v_fin = 1 then
    return v_mots[1];
  end if;

  return v_mots[1] || ' ' || upper(left(v_mots[v_fin], 1)) || '.';
end;
$$;

comment on function public.nom_abrege(text) is
  'Prénom entier et initiale du nom — « Sarah B. » (maquettes, écran 7). '
  'Ne lit aucune table : elle raccourcit un texte, elle ne retrouve personne. '
  'C''est par elle, et par elle seule, qu''un nom de client atteint un avis public (§9).';

-- =============================================================================
-- complete_booking — VERSION COURANTE
--
-- CE QUI CHANGE : les refus portent enfin un code Ferha et un SQLSTATE que
-- PostgREST sait traduire en 401, 403 ou 409. Le corps est celui de 004, à
-- l'ordre des contrôles près.
--
-- POURQUOI CE FICHIER LA REPREND. Elle existait depuis 004 et AUCUN ÉCRAN NE
-- L'APPELAIT : la réservation d'un mariage passé restait « confirmée » pour
-- toujours, et l'avis du §5.4 ne se débloquait jamais. Le geste arrive
-- maintenant côté propriétaire, sur le détail d'une demande — et un geste qui
-- s'affiche a besoin de refus qui s'affichent.
--
-- UNE SEULE PORTE VERS « completed », comme il n'y en a qu'une vers
-- « confirmed ». On ne pose pas une seconde fonction à côté de celle-ci : c'est
-- exactement ce que le §9 interdit en ne donnant aucune politique UPDATE à
-- `bookings`.
--
-- LA SESSION SE VÉRIFIE AVANT LA PROPRIÉTÉ, et c'est le seul vrai changement de
-- comportement. `owns_booking()` répond « non » à un appel sans session, ce qui
-- faisait dire « cette réservation ne concerne pas vos salles » à quelqu'un dont
-- le seul tort était d'avoir laissé sa session expirer.
--
-- CE QUI NE CHANGE PAS : on ne marque pas honoré ce qui n'a pas eu lieu
-- (FE073), le groupe entier bascule d'un bloc — une journée entière, c'est deux
-- lignes (§6.1) — et le client reçoit son invitation à déposer un avis.
-- =============================================================================

create or replace function public.complete_booking(p_booking_id uuid)
returns setof public.bookings
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group  uuid;
  v_client uuid;
  v_date   date;
  v_statut text;
begin
  if auth.uid() is null then
    raise exception 'Il faut être connecté pour marquer une réservation comme honorée.'
      using errcode = 'PT401', hint = 'FE070';
  end if;

  if not public.owns_booking(p_booking_id) then
    raise exception 'Cette réservation ne concerne pas vos salles.'
      using errcode = 'PT403', hint = 'FE071';
  end if;

  select b.group_id, b.client_id, b.event_date, b.status
    into v_group, v_client, v_date, v_statut
    from public.bookings b
   where b.id = p_booking_id;

  if v_statut is distinct from 'confirmed' then
    raise exception 'Seule une réservation confirmée peut être marquée comme honorée.'
      using errcode = 'PT409', hint = 'FE072';
  end if;

  -- Pas avant l'événement. Le jour même compte : un mariage du 14 août se
  -- marque honoré le 14 au soir, pas le 15.
  if v_date > current_date then
    raise exception 'L''événement n''a pas encore eu lieu.'
      using errcode = 'PT409', hint = 'FE073';
  end if;

  -- L'avis se débloque à J+1 (§5.4) ; l'invitation part dès maintenant.
  perform public.notify_user(
    v_client, 'review_invitation',
    jsonb_build_object('booking_id', p_booking_id, 'group_id', v_group)
  );

  return query
  with touched as (
    update public.bookings b
       set status = 'completed', completed_at = now()
     where b.group_id = v_group and b.status = 'confirmed'
    returning b.*
  )
  select t.* from touched t;
end;
$$;

comment on function public.complete_booking(uuid) is
  'Propriétaire : confirmed → completed, jamais avant la date de l''événement (§3, étape 6). '
  'Débloque l''avis (§5.4) et invite le client à le déposer. Le groupe entier bascule d''un bloc. '
  'Chaque refus porte son code Ferha dans son hint : FE070 non connecté, FE071 pas votre salle, '
  'FE072 réservation non confirmée, FE073 événement à venir.';

revoke execute on function public.complete_booking(uuid) from public, anon;
grant  execute on function public.complete_booking(uuid) to authenticated;

-- =============================================================================
-- avis_a_deposer — tout ce qu'il faut à l'écran de dépôt, en un seul appel
--
-- MÊME FORME QU'`acompte_a_verser()` (025), et pour les mêmes raisons : l'écran
-- s'ouvre d'un appel, la fonction vérifie elle-même à qui est la réservation, et
-- chaque refus porte son code.
--
-- ELLE N'ÉCRIT RIEN. On peut l'ouvrir, la recharger, quitter l'écran et y
-- revenir sans qu'un avis existe : c'est « Publier » qui écrit, et lui seul.
--
-- ELLE RENVOIE L'AVIS DÉJÀ DÉPOSÉ, s'il y en a un. C'est ce qui fait de cet
-- écran un écran de CORRECTION autant que de dépôt (§5.4) : les notes reviennent
-- cochées et le texte revient dans son champ.
--
-- LA FENÊTRE PASSÉE NE REFUSE PAS UN AVIS DÉJÀ ÉCRIT. Un client qui rouvre son
-- avis six mois plus tard doit pouvoir le relire — il ne peut simplement plus le
-- changer. FE077 ne sort donc que lorsqu'il n'y a rien à montrer.
-- =============================================================================

create or replace function public.avis_a_deposer(p_booking_id uuid)
returns table (
  group_id           uuid,
  booking_id         uuid,
  venue_id           uuid,
  venue_name         text,
  commune            text,
  wilaya_name        text,
  cover_photo        text,
  event_date         date,
  requested_slot     text,
  guest_count        integer,
  event_label        text,
  -- Les bornes du §5.4, pour que l'écran puisse écrire « jusqu'au 13 septembre »
  -- sans les recalculer.
  ouvre_le           date,
  ferme_le           date,
  fenetre_ouverte    boolean,
  -- L'avis déjà déposé, s'il existe. Tout NULL sinon.
  avis_id            uuid,
  rating             smallint,
  rating_cleanliness smallint,
  rating_service     smallint,
  rating_value       smallint,
  rating_accuracy    smallint,
  body               text,
  owner_reply        text,
  owner_replied_at   timestamptz,
  -- Vrai quand « Publier » a encore un sens : la fenêtre court ET le
  -- propriétaire n'a pas répondu.
  modifiable         boolean
)
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  v_group  uuid;
  v_client uuid;
  v_statut text;
  v_date   date;
  v_avis   public.reviews;
begin
  if auth.uid() is null then
    raise exception 'Il faut être connecté pour déposer un avis.'
      using errcode = 'PT401', hint = 'FE074';
  end if;

  select b.group_id, b.client_id, b.status, b.event_date
    into v_group, v_client, v_statut, v_date
    from public.bookings b
   where b.id = p_booking_id;

  if v_group is null or v_client is distinct from auth.uid() then
    raise exception 'Cette réservation n''est pas la vôtre.'
      using errcode = 'PT403', hint = 'FE075';
  end if;

  if v_statut is distinct from 'completed' then
    raise exception 'Un avis demande une réservation honorée par le propriétaire.'
      using errcode = 'PT409', hint = 'FE076';
  end if;

  select r.* into v_avis
    from public.reviews r
   where r.booking_group_id = v_group;

  -- Rien à montrer et rien à écrire : c'est le seul cas où l'on refuse.
  if v_avis.id is null and not public.avis_dans_la_fenetre(v_date) then
    raise exception 'La fenêtre de dépôt d''un avis n''est pas ouverte pour cet événement.'
      using errcode = 'PT400', hint = 'FE077';
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
    bg.guest_count,
    t.label_fr,
    f.ouvre_le,
    f.ferme_le,
    public.avis_dans_la_fenetre(bg.event_date),
    v_avis.id,
    v_avis.rating,
    v_avis.rating_cleanliness,
    v_avis.rating_service,
    v_avis.rating_value,
    v_avis.rating_accuracy,
    v_avis.body,
    v_avis.owner_reply,
    v_avis.owner_replied_at,
    public.avis_dans_la_fenetre(bg.event_date) and v_avis.owner_reply is null
  from public.booking_groups bg
  join public.bookings b
    on b.group_id = bg.group_id and b.slot = bg.slots[1]
  join public.venues v on v.id = bg.venue_id
  left join public.wilayas     w on w.code = v.wilaya_code
  left join public.event_types t on t.code = bg.event_type
  cross join lateral public.fenetre_avis(bg.event_date) f
  where bg.group_id = v_group;
end;
$fn$;

comment on function public.avis_a_deposer(uuid) is
  'Écran « Racontez votre soirée » (§4.2, CLI-08), en un seul appel : la réservation, '
  'les bornes du §5.4, et l''avis déjà déposé s''il existe — l''écran sert aussi à le corriger. '
  'N''écrit rien. Refus : FE074 non connecté, FE075 pas votre réservation, '
  'FE076 réservation non honorée, FE077 fenêtre fermée et aucun avis à relire.';

revoke execute on function public.avis_a_deposer(uuid) from public, anon;
grant  execute on function public.avis_a_deposer(uuid) to authenticated;

-- =============================================================================
-- deposer_avis — le dépôt, et la correction
--
-- UNE SEULE FONCTION POUR LES DEUX, parce que c'est un seul geste vu du client :
-- il appuie sur « Publier mon avis », et la deuxième fois il corrige. Deux
-- fonctions l'obligeraient à savoir laquelle appeler, c'est-à-dire à savoir s'il
-- a déjà déposé — une question à laquelle l'écran répond déjà, mais que la base
-- n'a pas besoin de lui reposer.
--
-- UN ÉVÉNEMENT, UN AVIS — Y COMPRIS UNE JOURNÉE ENTIÈRE. Une journée, c'est
-- DEUX lignes de `bookings` (§6.1), donc deux `booking_id` possibles pour un
-- seul mariage. La fonction remonte donc au GROUPE et écrit toujours sur sa
-- ligne représentative : appelée sur midi puis sur soir, elle corrige le même
-- avis au lieu d'en créer un second. La colonne `booking_group_id`, UNIQUE
-- depuis 004, est le filet sous ce choix.
--
-- L'AVIS EST FIGÉ APRÈS LA RÉPONSE (§5.4). `reviews_guard` (004) le refuse déjà,
-- mais avec un `check_violation` que personne ne sait traduire : on le refuse
-- donc ici d'abord, avec FE078, pour que l'écran puisse dire pourquoi.
--
-- LES POLITIQUES DE 006 RESTENT. Cette fonction est `SECURITY DEFINER` et passe
-- donc à travers elles ; elles protègent l'autre chemin — celui d'un client qui
-- écrirait dans `reviews` en direct. Ceinture et bretelles, et les deux
-- comparent les mêmes bornes depuis ce fichier.
-- =============================================================================

create or replace function public.deposer_avis(
  p_booking_id        uuid,
  p_rating            integer,
  p_rating_cleanliness integer default null,
  p_rating_service    integer default null,
  p_rating_value      integer default null,
  p_rating_accuracy   integer default null,
  p_body              text    default null
)
returns setof public.reviews
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_group        uuid;
  v_client       uuid;
  v_statut       text;
  v_date         date;
  v_venue        uuid;
  v_representant uuid;
  v_avis         public.reviews;
  v_texte        text;
begin
  if auth.uid() is null then
    raise exception 'Il faut être connecté pour déposer un avis.'
      using errcode = 'PT401', hint = 'FE074';
  end if;

  select b.group_id, b.client_id, b.status, b.event_date, b.venue_id
    into v_group, v_client, v_statut, v_date, v_venue
    from public.bookings b
   where b.id = p_booking_id;

  if v_group is null or v_client is distinct from auth.uid() then
    raise exception 'Cette réservation n''est pas la vôtre.'
      using errcode = 'PT403', hint = 'FE075';
  end if;

  if v_statut is distinct from 'completed' then
    raise exception 'Un avis demande une réservation honorée par le propriétaire.'
      using errcode = 'PT409', hint = 'FE076';
  end if;

  if not public.avis_dans_la_fenetre(v_date) then
    raise exception 'La fenêtre de dépôt d''un avis n''est pas ouverte pour cet événement.'
      using errcode = 'PT400', hint = 'FE077';
  end if;

  -- LA NOTE GLOBALE EST OBLIGATOIRE (§4.2, CLI-08). Les quatre sous-notes ne le
  -- sont pas — un avis reste publiable avec la seule note globale —, mais une
  -- sous-note donnée doit être une vraie note.
  if p_rating is null or p_rating not between 1 and 5 then
    raise exception 'La note globale est obligatoire, de 1 à 5 étoiles.'
      using errcode = 'PT400', hint = 'FE079';
  end if;

  if coalesce(p_rating_cleanliness, 3) not between 1 and 5
     or coalesce(p_rating_service,  3) not between 1 and 5
     or coalesce(p_rating_value,    3) not between 1 and 5
     or coalesce(p_rating_accuracy, 3) not between 1 and 5 then
    raise exception 'Une sous-note va de 1 à 5 étoiles, ou reste vide.'
      using errcode = 'PT400', hint = 'FE079';
  end if;

  -- Un commentaire réduit à des espaces n'est pas un commentaire.
  v_texte := nullif(btrim(coalesce(p_body, '')), '');

  select r.* into v_avis
    from public.reviews r
   where r.booking_group_id = v_group;

  if v_avis.id is not null and v_avis.owner_reply is not null then
    raise exception 'Votre avis n''est plus modifiable : le propriétaire y a répondu.'
      using errcode = 'PT409', hint = 'FE078';
  end if;

  if v_avis.id is not null then
    return query
    update public.reviews r
       set rating             = p_rating::smallint,
           rating_cleanliness = p_rating_cleanliness::smallint,
           rating_service     = p_rating_service::smallint,
           rating_value       = p_rating_value::smallint,
           rating_accuracy    = p_rating_accuracy::smallint,
           body               = v_texte
     where r.id = v_avis.id
    returning r.*;
    return;
  end if;

  -- La ligne représentative du groupe — bg.slots[1], la convention de 013, 014,
  -- 016 et 022. C'est elle qui portera l'avis, quel que soit le créneau par
  -- lequel le client est arrivé.
  select b.id into v_representant
    from public.booking_groups bg
    join public.bookings b
      on b.group_id = bg.group_id and b.slot = bg.slots[1]
   where bg.group_id = v_group;

  return query
  insert into public.reviews (
    booking_id, booking_group_id, venue_id,
    rating, rating_cleanliness, rating_service, rating_value, rating_accuracy,
    body
  )
  values (
    v_representant,
    -- Renseignée par reviews_guard (004), qui la relit depuis la réservation.
    -- La valeur donnée ici ne sert qu'à satisfaire le NOT NULL.
    v_group,
    v_venue,
    p_rating::smallint,
    p_rating_cleanliness::smallint,
    p_rating_service::smallint,
    p_rating_value::smallint,
    p_rating_accuracy::smallint,
    v_texte
  )
  returning *;
end;
$fn$;

comment on function public.deposer_avis(uuid, integer, integer, integer, integer, integer, text) is
  'Dépose l''avis d''une réservation honorée, ou le corrige tant que le propriétaire n''a pas '
  'répondu (§5.4, §4.2 CLI-08). Un événement, un avis : une journée entière, qui porte deux '
  'lignes de bookings (§6.1), n''en donne qu''un — la fonction écrit sur la ligne représentative '
  'du groupe. Refus : FE074 non connecté, FE075 pas votre réservation, FE076 non honorée, '
  'FE077 hors fenêtre, FE078 avis figé par la réponse, FE079 note globale absente ou hors 1–5.';

revoke execute on function public.deposer_avis(uuid, integer, integer, integer, integer, integer, text)
  from public, anon;
grant execute on function public.deposer_avis(uuid, integer, integer, integer, integer, integer, text)
  to authenticated;

-- =============================================================================
-- repondre_a_un_avis — le droit de réponse (§4.3, OWN-06)
--
-- UNE SEULE RÉPONSE, ET ELLE NE SE RÉÉCRIT PAS. C'est ce qui la rend crédible :
-- une réponse modifiable après coup permettrait de réécrire l'histoire une fois
-- l'avis figé — et l'avis, lui, est figé PAR elle (§5.4). Les deux vont
-- ensemble : c'est un échange, pas une conversation.
--
-- ELLE FIGE L'AVIS. Le client ne peut plus corriger sa note après cet appel, et
-- c'est voulu : sans cela la réponse deviendrait incompréhensible — « merci
-- d'avoir signalé la climatisation » sous un avis qui n'en parle plus.
--
-- `owner_replied_at` S'ÉCRIT TOUT SEUL, par `reviews_guard` (004). On ne le pose
-- pas ici : deux endroits qui horodatent le même geste finiraient par se
-- contredire d'une seconde.
-- =============================================================================

create or replace function public.repondre_a_un_avis(
  p_review_id uuid,
  p_reply     text
)
returns setof public.reviews
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_venue  uuid;
  v_reponse text;
  v_texte  text;
begin
  if auth.uid() is null then
    raise exception 'Il faut être connecté pour répondre à un avis.'
      using errcode = 'PT401', hint = 'FE080';
  end if;

  select r.venue_id, r.owner_reply into v_venue, v_reponse
    from public.reviews r
   where r.id = p_review_id;

  -- Inconnu ou pas à vous : une seule phrase, comme FE075. Essayer des
  -- identifiants au hasard n'apprend rien.
  if v_venue is null or not public.owns_venue(v_venue) then
    raise exception 'Cet avis ne porte pas sur une de vos salles.'
      using errcode = 'PT403', hint = 'FE081';
  end if;

  if v_reponse is not null then
    raise exception 'Vous avez déjà répondu à cet avis.'
      using errcode = 'PT409', hint = 'FE082';
  end if;

  v_texte := nullif(btrim(coalesce(p_reply, '')), '');

  if v_texte is null then
    raise exception 'Une réponse vide ne se publie pas.'
      using errcode = 'PT400', hint = 'FE083';
  end if;

  return query
  update public.reviews r
     set owner_reply = v_texte
   where r.id = p_review_id
  returning r.*;
end;
$fn$;

comment on function public.repondre_a_un_avis(uuid, text) is
  'Le droit de réponse du propriétaire (§4.3, OWN-06) : une seule réponse par avis, et elle '
  'ne se réécrit pas. Elle fige l''avis (§5.4). owner_replied_at est posé par reviews_guard (004). '
  'Refus : FE080 non connecté, FE081 pas votre salle, FE082 réponse déjà posée, FE083 réponse vide.';

revoke execute on function public.repondre_a_un_avis(uuid, text) from public, anon;
grant  execute on function public.repondre_a_un_avis(uuid, text) to authenticated;

-- =============================================================================
-- avis_de_la_salle — l'écran 7, en un seul appel
--
-- OUVERTE AUX VISITEURS. Un avis sert d'abord à celui qui n'a pas encore
-- réservé : c'est l'étape 2 du parcours du §3, et elle se fait sans compte.
--
-- SECURITY DEFINER POUR UNE SEULE RAISON : `profiles`. La table reste fermée —
-- chacun n'y lit que sa ligne (002) — et c'est ici, et nulle part ailleurs,
-- qu'un nom de client en sort vers un avis public. Il en sort raccourci par
-- `nom_abrege()` : jamais le nom entier, jamais l'e-mail, jamais le téléphone.
--
-- LA NOTE ET LES QUATRE SOUS-NOTES VIENNENT DE `venue_ratings`, et donc de la
-- formule du §5.4 écrite en 004. Aucune moyenne n'est calculée ici.
--
-- `can_read_venue()` BORNE CE QUI SORT. Une salle en brouillon n'a pas d'avis,
-- mais répondre « salle introuvable » plutôt que de confirmer son existence garde
-- la même frontière que le reste du projet (002).
--
-- AUCUNE SYNTHÈSE IA. Le bloc « ✦ Synthèse des 34 avis » de la maquette arrivera
-- au J21, avec l'index sémantique qui le rend possible. Un cadre vide en
-- attendant dirait au visiteur que l'application est inachevée.
-- =============================================================================

create or replace function public.avis_de_la_salle(p_venue_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  v_resultat jsonb;
begin
  select jsonb_build_object(
    'venue_id',           v.id,
    'venue_name',         v.name,

    -- La moyenne bayésienne du §5.4 : celle qui s'affiche, et la seule.
    'rating',             vr.bayesian_rating,
    'review_count',       coalesce(vr.review_count, 0),
    'rating_cleanliness', vr.rating_cleanliness,
    'rating_service',     vr.rating_service,
    'rating_value',       vr.rating_value,
    'rating_accuracy',    vr.rating_accuracy,

    -- Le plus récent en tête (maquettes, écran 7).
    'reviews', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id',                 r.id,
               'author',             public.nom_abrege(p.full_name),
               'rating',             r.rating,
               'rating_cleanliness', r.rating_cleanliness,
               'rating_service',     r.rating_service,
               'rating_value',       r.rating_value,
               'rating_accuracy',    r.rating_accuracy,
               'body',               r.body,
               'created_at',         r.created_at,
               'owner_reply',        r.owner_reply,
               'owner_replied_at',   r.owner_replied_at)
             order by r.created_at desc)
      from public.reviews  r
      join public.bookings b on b.id = r.booking_id
      join public.profiles p on p.id = b.client_id
      where r.venue_id = v.id
    ), '[]'::jsonb)
  )
  into v_resultat
  from public.venues v
  left join public.venue_ratings vr on vr.venue_id = v.id
  where v.id = p_venue_id
    and public.can_read_venue(v.id);

  if v_resultat is null then
    raise exception 'Salle introuvable.' using errcode = 'no_data_found';
  end if;

  return v_resultat;
end;
$fn$;

comment on function public.avis_de_la_salle(uuid) is
  'Écran 7 — les avis d''une salle en un seul appel : la note bayésienne de venue_ratings (§5.4), '
  'les quatre sous-notes, et la liste, le plus récent en tête. '
  'Le nom du client passe par nom_abrege() et par lui seul : « Sarah B. », jamais le nom entier, '
  'jamais l''e-mail, jamais le téléphone (§9). Aucune synthèse IA : elle viendra avec l''index sémantique.';

grant execute on function public.avis_de_la_salle(uuid) to anon, authenticated;

-- =============================================================================
-- reviews_insert_client — LA MÊME POLITIQUE, SANS LA FENÊTRE RECOPIÉE
--
-- Elle disait « current_date >= b.event_date + 1 and current_date <= b.event_date
-- + 30 », mot pour mot. Elle appelle maintenant `avis_dans_la_fenetre()`, comme
-- `deposer_avis()` : les deux gardiens du §5.4 comparent désormais les mêmes
-- bornes, et déplacer la fenêtre ne demande de toucher qu'un seul fichier.
--
-- LES TROIS AUTRES CONDITIONS NE BOUGENT PAS, et la quatrième — un seul avis par
-- réservation — reste portée par le schéma lui-même (`booking_id` UNIQUE).
-- =============================================================================

drop policy if exists reviews_insert_client on public.reviews;
create policy reviews_insert_client
  on public.reviews for insert
  to authenticated
  with check (
    exists (
      select 1 from public.bookings b
      where b.id        = booking_id
        and b.client_id = auth.uid()
        and b.status    = 'completed'
        and public.avis_dans_la_fenetre(b.event_date)
    )
  );

-- =============================================================================
-- client_bookings — VERSION COURANTE
--
-- CE QUI CHANGE : deux colonnes, et rien d'autre. Le corps est celui de 024,
-- mot pour mot.
--
-- POURQUOI ELLES EXISTENT. La carte de « Mes réservations » doit décider seule
-- s'il y a un avis à proposer, et quoi écrire sur le bouton. Trois questions se
-- posent, et aucune ne se répond en Dart :
--
--   * la fenêtre du §5.4 est-elle ouverte ? C'est une règle métier, et elle vit
--     dans `avis_dans_la_fenetre()`. La recalculer dans l'application en ferait
--     une deuxième définition — celle qui se trompera le jour où J+30 bougera.
--   * un avis existe-t-il déjà ? La table est publique en lecture, mais compter
--     depuis l'écran ferait une requête par carte.
--   * est-il encore modifiable ? Le propriétaire a peut-être répondu, et l'avis
--     est alors figé — proposer « Modifier » mènerait à un refus FE078.
--
-- `avis_depose` répond à la deuxième, `avis_possible` aux deux autres réunies :
-- il est vrai quand « Déposer » ou « Corriger » aboutira. Le bouton lit l'un pour
-- son libellé, l'autre pour son existence.
--
-- DROP PUIS CREATE : le type de retour change, et PostgreSQL refuse de remplacer
-- une fonction dont la signature de sortie bouge. Le DROP est conditionnel, donc
-- rejouable.
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
  -- Un avis existe pour cet événement — « Déposer » ou « Modifier » (§5.4).
  avis_depose       boolean,
  -- Écrire ou corriger aboutira : réservation honorée, fenêtre ouverte, et
  -- aucune réponse du propriétaire.
  avis_possible     boolean
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
                         and r.owner_reply is not null)
  from public.booking_groups bg
  join public.bookings b
    on b.group_id = bg.group_id and b.slot = bg.slots[1]
  join public.venues v on v.id = bg.venue_id
  left join public.wilayas     w on w.code = v.wilaya_code
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
  'la règle du §9 n''a pas de second exemplaire ici. « acompte_du » donne l''acompte en dinars '
  'entiers — montant_acompte(), le même arrondi que l''écran 6 et que la Edge Function. '
  'Depuis 026, « avis_depose » et « avis_possible » disent s''il y a un avis et si le déposer ou '
  'le corriger aboutira — la fenêtre du §5.4 se lit dans avis_dans_la_fenetre(), jamais en Dart.';

revoke execute on function public.client_bookings() from public, anon;
grant  execute on function public.client_bookings() to authenticated;
