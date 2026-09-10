-- =============================================================================
-- Ferha — 015_repondre_a_une_demande.sql
-- Le propriétaire répond : accepter, ou refuser (§4.3, OWN-05 ; écran 9).
--
-- CE QUE CE FICHIER APPORTE
--
--   accepter_demande()  pending → accepted, option de 72 h posée
--   refuser_demande()   pending → refused, motif facultatif
--
-- CES DEUX FONCTIONS NE REFONT PAS LA TRANSITION — ELLES Y MÈNENT.
--
-- accept_booking() et refuse_booking() existent depuis 004. Elles vérifient
-- déjà qui appelle, travaillent sur le GROUPE et non sur une ligne, posent
-- l'option de 72 h du §5.1 et déposent la notification du §4.1. Réécrire tout
-- cela ici donnerait deux chemins pour faire passer une réservation de
-- « pending » à « accepted » — et le jour où l'un des deux changerait, le
-- produit aurait deux vérités. Les fonctions ci-dessous DÉLÈGUENT : elles
-- ajoutent ce que l'écran du propriétaire réclame et qui manquait, puis
-- appellent celles de 004.
--
-- Ce qu'elles ajoutent, et qui justifie leur existence :
--
--   1. UN CODE FERHA SUR CHAQUE REFUS. C'est le contrat inauguré par 012 : un
--      `PTxxx` en SQLSTATE, pour que PostgREST réponde 401, 403 ou 409 et non
--      500 ; un `FExxx` dans le hint, que l'application traduit en une phrase
--      française. accept_booking() lève des messages français en dur, qui ne
--      seront jamais traduits en arabe et que personne ne pensera à relire en
--      changeant un mot.
--
--   2. LE GARDE-FOU DU CRÉNEAU DÉJÀ VENDU (voir plus bas).
--
--   3. L'ACOMPTE PAR DÉFAUT. accept_booking() exige un montant ; l'écran 9 ne
--      le demande pas encore, faute de contre-proposition (§5.2, remise à plus
--      tard). On applique donc deposit_rate() — les 25 % du §5.3, à leur seul
--      endroit — au devis déjà en base. Aucune formule de prix n'est écrite
--      ici : le devis vient d'estimate_price(), on en prend une part.
--
-- LE GARDE-FOU DU CRÉNEAU, ET POURQUOI CE N'EST PAS L'INDEX.
--
-- L'index uniq_booking_slot du §6.1 est PARTIEL : il ne porte que sur
-- « confirmed » et « completed ». Une acceptation ne peut donc pas le
-- déclencher, et c'est voulu — le §5.1 dit qu'une demande acceptée pose une
-- option de 72 h, pas qu'elle prend la date. L'index se déclenche en
-- confirm_booking(), et là seulement.
--
-- Le danger existe pourtant, et il est réel : une demande peut avoir attendu
-- deux jours pendant qu'une AUTRE réservation était confirmée sur le même
-- créneau. L'accepter donnerait au propriétaire et à sa cliente une option de
-- 72 h sur une date déjà vendue — et l'index ne dirait rien, puisqu'il n'y
-- aurait toujours qu'une seule ligne confirmée. La vérification ci-dessous
-- regarde donc explicitement si le créneau est pris, et refuse avec la phrase
-- qu'il faut. Le filet `unique_violation` reste posé par-dessus, pour le jour
-- où quelqu'un rendrait l'index moins partiel.
--
-- CODES FERHA DE CE FICHIER — la série des réponses du propriétaire. Ils
-- commencent à 010 pour laisser à request_booking() (FE001–FE006) la place de
-- s'étendre sans se marcher dessus.
--
--   FE010  PT401  il faut être connecté
--   FE011  PT403  cette demande n'est pas la vôtre
--   FE012  PT409  cette demande n'est plus en attente
--   FE013  PT409  le créneau vient d'être vendu à quelqu'un d'autre
--
-- LA CONTRE-PROPOSITION N'EST PAS ICI. Le §5.2 autorise le propriétaire à
-- proposer un autre montant, et accept_booking() sait déjà le recevoir
-- (p_quoted_amount). C'est un geste à part, avec son écran et sa saisie ; il
-- viendra à son étape.
--
-- Rejouable : les deux fonctions sont remplacées.
-- Dépend de : 004 (bookings, accept_booking, refuse_booking, owns_booking,
--             notify_user), 012 (deposit_rate).
-- =============================================================================

-- =============================================================================
-- accepter_demande — pending → accepted, et l'option de 72 h du §5.1
-- =============================================================================

create or replace function public.accepter_demande(p_booking_id uuid)
returns setof public.bookings
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group   uuid;
  v_quoted  numeric;
  v_acompte numeric;
begin
  if auth.uid() is null then
    raise exception 'Il faut être connecté pour répondre à une demande.'
      using errcode = 'PT401', hint = 'FE010';
  end if;

  -- LA MÊME QUESTION QUE accept_booking(), POSÉE POUR UNE AUTRE RAISON. Celle
  -- de 004 protège la table et restera le dernier mot ; celle-ci existe pour
  -- que le refus porte un code, et donc une phrase française. Retirer l'une des
  -- deux ne rendrait rien de plus accessible — retirer celle-ci rendrait
  -- seulement le message illisible.
  if not public.owns_booking(p_booking_id) then
    raise exception 'Cette demande ne concerne pas une de vos salles.'
      using errcode = 'PT403', hint = 'FE011';
  end if;

  select b.group_id, b.quoted_amount into v_group, v_quoted
  from public.bookings b
  where b.id = p_booking_id and b.status = 'pending';

  if v_group is null then
    -- Le cas courant n'est pas une attaque : deux téléphones ouverts sur la
    -- même demande, ou le client qui vient d'annuler.
    raise exception 'Cette demande n''est plus en attente de réponse.'
      using errcode = 'PT409', hint = 'FE012';
  end if;

  -- Le créneau a-t-il été vendu pendant que la demande attendait ? Une journée
  -- entière occupe deux lignes : on les regarde toutes les deux.
  if exists (
    select 1
    from public.bookings mienne
    join public.bookings prise
      on  prise.venue_id   = mienne.venue_id
      and prise.event_date = mienne.event_date
      and prise.slot       = mienne.slot
      and prise.status in ('confirmed', 'completed')
    where mienne.group_id = v_group
  ) then
    raise exception 'Ce créneau a été confirmé entre-temps par une autre réservation.'
      using errcode = 'PT409', hint = 'FE013';
  end if;

  -- L'acompte que la plateforme propose (§5.3), appliqué au devis déjà en base.
  -- Le taux ne s'écrit pas ici : il vit dans deposit_rate(), et nulle part
  -- ailleurs.
  v_acompte := round(v_quoted * public.deposit_rate(), 2);

  begin
    return query
    select * from public.accept_booking(p_booking_id, v_acompte);
  exception when unique_violation then
    -- Le filet. Aujourd'hui l'index du §6.1 ne peut pas se déclencher sur une
    -- acceptation ; si sa clause partielle changeait un jour, le propriétaire
    -- lirait quand même une phrase et non une erreur Postgres.
    raise exception 'Ce créneau a été confirmé entre-temps par une autre réservation.'
      using errcode = 'PT409', hint = 'FE013';
  end;
end;
$$;

comment on function public.accepter_demande(uuid) is
  'Le propriétaire accepte une demande (§4.3, OWN-05) : pending → accepted, option de 72 h (§5.1). '
  'Délègue la transition à accept_booking() (004) ; ajoute les codes Ferha, le garde-fou du '
  'créneau déjà vendu, et l''acompte de deposit_rate() (§5.3).';

revoke execute on function public.accepter_demande(uuid) from public, anon;
grant  execute on function public.accepter_demande(uuid) to authenticated;

-- =============================================================================
-- refuser_demande — pending → refused
--
-- LE MOTIF EST DEMANDÉ, PAS EXIGÉ, et la valeur par défaut le dit. Un refus
-- sans explication reste un refus : obliger à écrire quelque chose produirait
-- des « non » et des points, pas des raisons. L'écran, lui, pose la question —
-- c'est là qu'elle a une chance d'obtenir une vraie réponse.
--
-- Le motif atterrit dans bookings.status_reason, que le client lit sur son
-- écran de suivi (013). Il est donc écrit pour être lu par la personne qu'il
-- concerne, et non pour une archive.
-- =============================================================================

create or replace function public.refuser_demande(
  p_booking_id uuid,
  p_motif      text default null
)
returns setof public.bookings
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group uuid;
begin
  if auth.uid() is null then
    raise exception 'Il faut être connecté pour répondre à une demande.'
      using errcode = 'PT401', hint = 'FE010';
  end if;

  if not public.owns_booking(p_booking_id) then
    raise exception 'Cette demande ne concerne pas une de vos salles.'
      using errcode = 'PT403', hint = 'FE011';
  end if;

  select b.group_id into v_group
  from public.bookings b
  where b.id = p_booking_id and b.status = 'pending';

  if v_group is null then
    raise exception 'Cette demande n''est plus en attente de réponse.'
      using errcode = 'PT409', hint = 'FE012';
  end if;

  -- Aucun garde-fou de créneau ici, et ce n'est pas un oubli : refuser ne prend
  -- aucune date. Une demande refusée le reste, que le créneau soit vendu ou non.
  return query
  select * from public.refuse_booking(p_booking_id, nullif(btrim(p_motif), ''));
end;
$$;

comment on function public.refuser_demande(uuid, text) is
  'Le propriétaire refuse une demande (§4.3, OWN-05) : pending → refused, motif facultatif. '
  'Délègue la transition à refuse_booking() (004) ; ajoute les codes Ferha.';

revoke execute on function public.refuser_demande(uuid, text) from public, anon;
grant  execute on function public.refuser_demande(uuid, text) to authenticated;
