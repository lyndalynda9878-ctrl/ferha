-- =============================================================================
-- Ferha — 025_paiement_confirme.sql
-- Le paiement confirme la réservation — et les cas où il ne le peut pas
-- (§3 étape 5, §4.2 CLI-06, §7.2 chargily-webhook).
--
-- CE QUE CE FICHIER APPORTE
--
--   payments.anomalie                 ce qui a mal tourné, quand quelque chose
--                                     a mal tourné
--   paiements_a_examiner              la liste que regarde un humain
--   confirmer_paiement_chargily()     le webhook, côté base — réservée au
--                                     service_role
--   payer_en_especes()                le troisième choix de l'écran 6
--   confirmer_encaissement_especes()  le propriétaire a reçu l'argent
--   owner_request_detail()            redéfinie : elle dit qu'un encaissement
--                                     en espèces attend
--   acompte_a_verser()                redéfinie : elle le dit au client aussi
--
-- LA DÉCISION EST EN SQL, PAS DANS LA EDGE FUNCTION. La fonction Deno vérifie
-- la signature, décode le JSON, et passe la main. Tout ce qui décide — le
-- montant, l'option, le créneau, l'idempotence — se joue ici, dans UNE
-- transaction. C'est la seule façon d'être sûr qu'un webhook rejoué pendant que
-- le premier tourne encore ne confirme pas deux fois : la ligne payments est
-- verrouillée (`for update`), et le second appel attend puis lit un état déjà
-- réglé.
--
-- QUATRE FAÇONS DE MAL FINIR, ET AUCUNE NE DOIT PLANTER
--
--   montant_different    Chargily annonce un montant qui n'est pas le nôtre.
--                        Rien n'est confirmé, un humain regarde.
--   option_expiree       l'argent est arrivé après les 72 h. La date est
--                        repartie à la vente ; le client a payé pour rien.
--   creneau_pris         quelqu'un d'autre a confirmé le même créneau pendant
--                        que le paiement voyageait. L'index du §6.1 tranche.
--   deja_paye            la réservation était déjà payée — en espèces, ou par
--                        une autre page. Le client a payé deux fois.
--
-- Les trois dernières veulent dire LA MÊME CHOSE POUR LE CLIENT : son argent
-- est parti et sa date n'est pas prise. D'où la vue `paiements_a_examiner`, et
-- sa colonne `suite` qui dit « a_rembourser » ou « a_examiner ».
--
-- AUCUN REMBOURSEMENT AUTOMATIQUE. La base marque, notifie, et s'arrête. Un
-- remboursement se décide en regardant, et il se fait depuis le tableau de bord
-- Chargily — pas par un programme qui aurait mal lu une situation qu'il est le
-- premier à découvrir.
--
-- LE PAIEMENT EST MARQUÉ « paid » MÊME QUAND LA RÉSERVATION NE L'EST PAS, et
-- c'est délibéré. Chargily affirme que l'argent a bougé ; l'écrire « pending »
-- dans nos livres parce que la suite nous déplaît serait tenir une comptabilité
-- fausse. C'est `anomalie` qui porte le « mais », et la réservation qui reste
-- « accepted ».
--
-- LES CODES FERHA DE CE FICHIER
--
--   FE050  PT401  aucune session                    (déjà posé en 024)
--   FE051  PT403  cette réservation n'est pas la vôtre
--   FE052  PT409  la demande n'est pas encore acceptée
--   FE053  PT409  l'option est échue
--   FE054  PT409  l'acompte est déjà réglé
--   FE060  PT401  aucune session, côté propriétaire
--   FE061  PT403  cette demande ne concerne pas vos salles
--   FE062  PT409  aucun encaissement en espèces n'attend
--   FE063  PT409  la réservation n'est plus sous option
--   FE064  PT409  le créneau a été confirmé entre-temps
--
-- Rejouable : colonne et contrainte posées si elles manquent, fonctions
-- remplacées, vue recréée.
-- Dépend de : 004 (payments, confirm_booking, notify_user, owns_booking),
--             006 (RLS), 014 (owner_request_detail, redéfinie ici),
--             022 (notifications.type), 023 (tient_la_date),
--             024 (montant_acompte, acompte_a_verser redéfinie ici).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- payments.anomalie — ce qui a mal tourné
--
-- UNE COLONNE PLUTÔT QUE DE NOUVELLES VALEURS DE `status`. Les quatre états du
-- §6 — pending, paid, failed, refunded — disent où en est L'ARGENT. Une
-- anomalie dit autre chose : l'argent est bien arrivé, et la réservation n'a
-- pas suivi. Mélanger les deux obligerait chaque lecteur de `status` à
-- connaître des valeurs qui ne parlent pas d'argent.
-- -----------------------------------------------------------------------------

alter table public.payments
  add column if not exists anomalie text;

alter table public.payments drop constraint if exists payments_anomalie_check;

alter table public.payments add constraint payments_anomalie_check
  check (anomalie is null or anomalie in (
    'montant_different',        -- à examiner : le montant reçu n'est pas le nôtre
    'option_expiree',           -- à rembourser : payé après les 72 h
    'creneau_pris',             -- à rembourser : un autre a confirmé avant
    'deja_paye',                -- à rembourser : la réservation était déjà réglée
    'confirmation_impossible'   -- à examiner : la base a refusé, sans qu'on sache
  ));

comment on column public.payments.anomalie is
  'Ce qui a empêché ce paiement de confirmer la réservation. NULL quand tout s''est bien passé. '
  'Aucun remboursement automatique : la colonne marque, un humain décide. Voir la vue '
  'paiements_a_examiner.';

create index if not exists payments_anomalie_idx
  on public.payments (anomalie) where anomalie is not null;

-- -----------------------------------------------------------------------------
-- paiements_a_examiner — la liste que regarde un humain
--
-- security_invoker = true, ET C'EST CE QUI LA PROTÈGE. La vue n'a pas de
-- politique à elle : elle lit `payments` avec les droits de celui qui
-- l'interroge, donc à travers `payments_select_parties` (006). Un administrateur
-- voit tout, les deux parties voient la leur, un inconnu ne voit rien. Une vue
-- en `security_definer` montrerait ici la comptabilité de tout le monde.
--
-- Ce n'est PAS le cas de venue_availability, qui est publique et sans RLS à
-- dessein : celle-ci expose des montants, et ils n'ont rien de public.
-- -----------------------------------------------------------------------------

drop view if exists public.paiements_a_examiner;

create view public.paiements_a_examiner
  with (security_invoker = true) as
  select
    p.id,
    p.booking_id,
    b.group_id,
    b.client_id,
    b.venue_id,
    p.checkout_id,
    p.amount,
    p.method,
    p.status,
    p.anomalie,
    -- La suite à donner, dite une fois ici plutôt que dans chaque écran.
    case p.anomalie
      when 'option_expiree' then 'a_rembourser'
      when 'creneau_pris'   then 'a_rembourser'
      when 'deja_paye'      then 'a_rembourser'
      else 'a_examiner'
    end                                as suite,
    b.status                           as booking_status,
    b.event_date,
    p.raw_webhook,
    p.created_at,
    p.updated_at
  from public.payments p
  join public.bookings b on b.id = p.booking_id
  where p.anomalie is not null;

comment on view public.paiements_a_examiner is
  'Les paiements qui n''ont pas confirmé leur réservation (§4.4, ADM-03). « suite » dit '
  'a_rembourser — l''argent est arrivé, la date n''est pas prise — ou a_examiner. '
  'Aucun remboursement automatique : cette vue existe pour qu''un humain regarde.';

grant select on public.paiements_a_examiner to authenticated;

-- -----------------------------------------------------------------------------
-- Les types de notification du paiement
--
-- Un type par PHRASE à écrire, comme 'booking_expired' en 022 : c'est le type
-- qui décide du texte, et un type qui voudrait dire deux choses obligerait
-- l'application à lire le payload pour choisir laquelle.
-- -----------------------------------------------------------------------------

alter table public.notifications drop constraint if exists notifications_type_check;

alter table public.notifications add constraint notifications_type_check
  check (type in ('booking_requested',   -- nouvelle demande, côté propriétaire
                  'booking_answered',    -- réponse du propriétaire, côté client
                  'booking_confirmed',   -- acompte reçu, les deux parties
                  'booking_cancelled',   -- une PERSONNE a annulé (§5.3)
                  'booking_expired',     -- l'option de 72 h est passée (§5.1)
                  'payment_failed',      -- paiement refusé ou abandonné, côté client
                  'payment_to_refund',   -- encaissé, mais la date n'est pas prise
                  'payment_anomaly',     -- à examiner, côté administration
                  'cash_pending',        -- espèces sur place, côté propriétaire
                  'reminder_j7',
                  'reminder_j1',
                  'review_invitation'));

-- =============================================================================
-- notifier_administration — prévenir ceux qui peuvent agir
--
-- ELLE PEUT NE PRÉVENIR PERSONNE, et ce n'est pas une panne : un projet sans
-- compte administrateur n'a personne à prévenir. La trace durable est la
-- colonne `anomalie` et la vue au-dessus ; la notification n'est qu'un rappel.
-- Lever ici ferait échouer un webhook — donc redemander à Chargily de le
-- renvoyer — pour un problème qui n'est pas le sien.
-- =============================================================================

create or replace function public.notifier_administration(
  p_type    text,
  p_payload jsonb default '{}'::jsonb
)
returns integer
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_admin  uuid;
  v_compte integer := 0;
begin
  for v_admin in select p.id from public.profiles p where p.is_admin loop
    perform public.notify_user(v_admin, p_type, p_payload);
    v_compte := v_compte + 1;
  end loop;

  return v_compte;
end;
$fn$;

comment on function public.notifier_administration(text, jsonb) is
  'Dépose une notification à chaque compte administrateur (§4.4, ADM-03). Rend le nombre de '
  'destinataires — zéro est un résultat possible, pas une erreur : la trace durable est '
  'payments.anomalie.';

revoke execute on function public.notifier_administration(text, jsonb)
  from public, anon, authenticated;

-- =============================================================================
-- confirmer_paiement_chargily — le webhook, côté base
--
-- RÉSERVÉE AU service_role, celui de la Edge Function chargily-webhook. Le §9
-- dit « aucune écriture cliente » sur payments, et cette fonction est
-- SECURITY DEFINER : la donner à `authenticated` laisserait n'importe qui se
-- déclarer payé.
--
-- ELLE NE VÉRIFIE PAS LA SIGNATURE. C'est le travail de la Edge Function, sur
-- le corps BRUT, avant tout décodage — une signature vérifiée après un
-- `json_decode` ne prouve plus rien sur ce qui a été signé. La base reçoit donc
-- des valeurs déjà authentifiées, et s'occupe de ce qu'elles veulent dire.
--
-- ELLE NE LÈVE JAMAIS SUR UN CAS MÉTIER. Un webhook qui échoue est un webhook
-- que Chargily renvoie ; renvoyer indéfiniment un événement dont le problème
-- est « cette date est déjà vendue » ne réglerait rien et remplirait les
-- journaux. Chaque issue a donc un nom, rendu en texte :
--
--   'confirme'          la réservation est prise
--   'echec'             paiement refusé ou abandonné, l'option court toujours
--   'deja_traite'       cet événement a déjà été traité (rejeu)
--   'inconnu'           aucun paiement ne porte ce checkout
--   'montant_different' à examiner
--   'option_expiree'    à rembourser
--   'creneau_pris'      à rembourser
--   'deja_paye'         à rembourser
--   'confirmation_impossible'  la base a refusé pour une autre raison
--
-- LE VERROU (`for update`) EST CE QUI REND L'IDEMPOTENCE VRAIE. Sans lui, deux
-- livraisons simultanées du même événement liraient toutes deux « pending » et
-- confirmeraient toutes deux. L'index uniq_booking_slot du §6.1 en rattraperait
-- une, mais par une exception — et l'autre aurait déjà notifié.
-- =============================================================================

create or replace function public.confirmer_paiement_chargily(
  p_checkout_id text,
  p_type        text,
  p_montant     numeric,
  p_brut        jsonb
)
returns text
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_paiement   public.payments;
  v_booking    public.bookings;
  v_owner      uuid;
  v_tenue      text;
  v_autre_paye boolean;
  v_charge     jsonb;
begin
  -- Le verrou : tout ce qui suit se lit et s'écrit sur une ligne que personne
  -- d'autre ne touche en même temps.
  select * into v_paiement
    from public.payments
   where checkout_id = p_checkout_id
   for update;

  if v_paiement.id is null then
    -- Un checkout que nous n'avons pas ouvert. On ne lève pas : Chargily
    -- renverrait l'événement en boucle. On répond, et la Edge Function
    -- journalise.
    return 'inconnu';
  end if;

  select * into v_booking
    from public.bookings where id = v_paiement.booking_id;

  select v.owner_id into v_owner
    from public.venues v where v.id = v_booking.venue_id;

  v_charge := jsonb_build_object(
    'booking_id', v_booking.id,
    'group_id',   v_booking.group_id,
    'payment_id', v_paiement.id
  );

  -- ---------------------------------------------------------------------------
  -- Idempotence : un événement déjà tranché ne se retranche pas
  --
  -- On compare l'état de la ligne à ce que l'événement demande. Un 'paid' sur
  -- une ligne déjà 'paid' est un rejeu ; un 'failed' sur une ligne 'failed'
  -- aussi. Le raw_webhook du PREMIER passage est conservé : c'est celui qui a
  -- décidé, et c'est lui qu'on voudra relire.
  -- ---------------------------------------------------------------------------
  if (p_type = 'checkout.paid'  and v_paiement.status = 'paid')
     or (p_type in ('checkout.failed', 'checkout.canceled')
         and v_paiement.status = 'failed') then
    return 'deja_traite';
  end if;

  -- ---------------------------------------------------------------------------
  -- Échec et annulation : rien ne bouge, et l'option court toujours
  --
  -- La réservation reste « accepted » — c'est le point. Une carte refusée ne
  -- retire pas les 72 h : le client peut réessayer, ou payer en espèces.
  -- ---------------------------------------------------------------------------
  if p_type in ('checkout.failed', 'checkout.canceled') then
    update public.payments
       set status = 'failed', raw_webhook = p_brut
     where id = v_paiement.id;

    perform public.notify_user(v_booking.client_id, 'payment_failed', v_charge);
    return 'echec';
  end if;

  if p_type is distinct from 'checkout.paid' then
    -- Un type que nous ne traitons pas encore. Rien à faire, et surtout pas
    -- d'erreur : Chargily est libre d'en ajouter.
    return 'ignore';
  end if;

  -- ---------------------------------------------------------------------------
  -- Le montant doit être le nôtre
  --
  -- Avant toute confirmation, et avant même de regarder l'option : une somme
  -- qui n'est pas celle qu'on a demandée ne confirme rien, quelle que soit la
  -- suite. payments.amount n'est PAS écrasé — il dit ce qu'on attendait ;
  -- raw_webhook garde ce qui est arrivé.
  -- ---------------------------------------------------------------------------
  if p_montant is distinct from v_paiement.amount then
    update public.payments
       set status = 'paid', anomalie = 'montant_different', raw_webhook = p_brut
     where id = v_paiement.id;

    perform public.notifier_administration(
      'payment_anomaly',
      v_charge || jsonb_build_object(
        'attendu', v_paiement.amount, 'recu', p_montant)
    );
    return 'montant_different';
  end if;

  -- ---------------------------------------------------------------------------
  -- La réservation était-elle déjà payée ?
  --
  -- Le cas arrive pour de bon depuis que les espèces existent : le client verse
  -- en main propre, le propriétaire confirme, et la page Chargily qu'il avait
  -- ouverte la veille aboutit quand même. Il a payé deux fois.
  -- ---------------------------------------------------------------------------
  select exists (
    select 1 from public.payments p
     join public.bookings b on b.id = p.booking_id
    where b.group_id = v_booking.group_id
      and p.id <> v_paiement.id
      and p.status = 'paid'
      and p.anomalie is null
  ) into v_autre_paye;

  if v_autre_paye then
    update public.payments
       set status = 'paid', anomalie = 'deja_paye', raw_webhook = p_brut
     where id = v_paiement.id;

    perform public.notify_user(v_booking.client_id, 'payment_to_refund', v_charge);
    perform public.notify_user(v_owner,             'payment_to_refund', v_charge);
    perform public.notifier_administration('payment_to_refund', v_charge);
    return 'deja_paye';
  end if;

  -- ---------------------------------------------------------------------------
  -- L'option tient-elle encore ?
  --
  -- LA RÈGLE DE 023, APPELÉE. Et c'est ici qu'elle compte le plus : le statut
  -- d'une option échue reste « accepted » jusqu'au passage du cron, qui est au
  -- quart d'heure. confirm_booking() (004) ne regarde QUE ce statut — elle
  -- confirmerait donc allègrement une date repartie à la vente. Sans cette
  -- vérification, deux familles se retrouveraient au même mariage.
  -- ---------------------------------------------------------------------------
  v_tenue := public.tient_la_date(v_booking.status, v_booking.option_expires_at);

  if v_tenue is distinct from 'option' then
    update public.payments
       set status = 'paid', anomalie = 'option_expiree', raw_webhook = p_brut
     where id = v_paiement.id;

    perform public.notify_user(v_booking.client_id, 'payment_to_refund', v_charge);
    perform public.notify_user(v_owner,             'payment_to_refund', v_charge);
    perform public.notifier_administration('payment_to_refund', v_charge);
    return 'option_expiree';
  end if;

  -- ---------------------------------------------------------------------------
  -- La confirmation — et l'index du §6.1, qui a le dernier mot
  --
  -- Le sous-bloc n'est pas décoratif : une exception y annule TOUT ce qu'il a
  -- fait, y compris les notifications déposées par confirm_booking(). Le
  -- gestionnaire repart donc d'un état propre, et peut écrire l'anomalie sans
  -- qu'une notification « réservation confirmée » traîne à côté.
  -- ---------------------------------------------------------------------------
  begin
    perform public.confirm_booking(v_booking.id);

    update public.payments
       set status = 'paid', raw_webhook = p_brut
     where id = v_paiement.id;

    return 'confirme';

  exception
    when unique_violation then
      update public.payments
         set status = 'paid', anomalie = 'creneau_pris', raw_webhook = p_brut
       where id = v_paiement.id;

      perform public.notify_user(v_booking.client_id, 'payment_to_refund', v_charge);
      perform public.notify_user(v_owner,             'payment_to_refund', v_charge);
      perform public.notifier_administration('payment_to_refund', v_charge);
      return 'creneau_pris';

    when others then
      -- Le filet. On ne sait pas ce qui s'est passé, et c'est précisément
      -- pourquoi il ne faut pas planter : l'argent est arrivé, et le perdre de
      -- vue serait pire que de l'écrire avec un point d'interrogation.
      update public.payments
         set status = 'paid', anomalie = 'confirmation_impossible',
             raw_webhook = p_brut
       where id = v_paiement.id;

      perform public.notifier_administration(
        'payment_anomaly',
        v_charge || jsonb_build_object('sqlstate', sqlstate, 'message', sqlerrm)
      );
      return 'confirmation_impossible';
  end;
end;
$fn$;

comment on function public.confirmer_paiement_chargily(text, text, numeric, jsonb) is
  'Le webhook Chargily, côté base (§7.2). Réservée au service_role : la signature est vérifiée '
  'par la Edge Function, sur le corps brut. Idempotente — la ligne payments est verrouillée, et '
  'un événement déjà tranché rend « deja_traite ». Ne lève jamais sur un cas métier : chaque '
  'issue a un nom. Aucun remboursement automatique.';

revoke execute on function public.confirmer_paiement_chargily(text, text, numeric, jsonb)
  from public, anon, authenticated;
grant execute on function public.confirmer_paiement_chargily(text, text, numeric, jsonb)
  to service_role;

-- =============================================================================
-- payer_en_especes — le troisième choix de l'écran 6
--
-- « L'option "espèces sur place" est offerte dès le MVP : elle sauve les
-- utilisateurs réticents au paiement en ligne. » (maquettes, écran 6)
--
-- ELLE NE CONFIRME RIEN, ET C'EST TOUT SON SENS. Choisir les espèces, c'est
-- annoncer une intention : la réservation reste « accepted », l'option de 72 h
-- continue de courir, et le propriétaire est prévenu qu'on va lui apporter
-- l'argent. C'est LUI qui confirmera, une fois les billets dans la main.
--
-- La ligne payments porte method = 'cash' et checkout_id NULL — un règlement en
-- espèces n'a pas de page de paiement. L'index partiel de 004 le permet
-- expressément : il ne porte que sur les checkout_id non nuls.
--
-- IDEMPOTENTE : rappuyer rend la ligne déjà posée. Deux intentions d'espèces
-- sur la même réservation ne veulent rien dire, et feraient deux notifications
-- au propriétaire pour un seul client.
--
-- ELLE N'ÉTEINT PAS UNE PAGE CHARGILY OUVERTE. Le client a pu ouvrir une carte
-- puis changer d'avis ; s'il la paie quand même, confirmer_paiement_chargily()
-- verra la réservation déjà réglée et marquera « deja_paye » — à rembourser.
-- Éteindre la page ici ne l'empêcherait pas d'être payée : Chargily ne nous
-- demande pas la permission.
-- =============================================================================

create or replace function public.payer_en_especes(p_booking_id uuid)
returns public.payments
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_booking  public.bookings;
  v_owner    uuid;
  v_tenue    text;
  v_acompte  integer;
  v_paiement public.payments;
begin
  if auth.uid() is null then
    raise exception 'Il faut être connecté pour choisir un moyen de paiement.'
      using errcode = 'PT401', hint = 'FE050';
  end if;

  select * into v_booking from public.bookings where id = p_booking_id;

  -- Inconnue ou pas la sienne : même phrase, même code qu'en 024.
  if v_booking.id is null or v_booking.client_id is distinct from auth.uid() then
    raise exception 'Cette réservation n''est pas la vôtre.'
      using errcode = 'PT403', hint = 'FE051';
  end if;

  v_tenue := public.tient_la_date(v_booking.status, v_booking.option_expires_at);

  if v_tenue = 'confirme' then
    raise exception 'L''acompte de cette réservation est déjà réglé.'
      using errcode = 'PT409', hint = 'FE054';
  end if;

  if v_tenue is distinct from 'option' then
    if v_booking.status = 'pending' then
      raise exception 'Le propriétaire n''a pas encore répondu à cette demande.'
        using errcode = 'PT409', hint = 'FE052';
    end if;

    raise exception 'La date n''est plus tenue pour cette demande.'
      using errcode = 'PT409', hint = 'FE053';
  end if;

  -- Une intention déjà posée : on rend la même, sans rien renotifier.
  select p.* into v_paiement
    from public.payments p
    join public.bookings b on b.id = p.booking_id
   where b.group_id = v_booking.group_id
     and p.method = 'cash'
     and p.status = 'pending'
   order by p.created_at desc
   limit 1;

  if v_paiement.id is not null then
    return v_paiement;
  end if;

  v_acompte := public.montant_acompte(v_booking.group_id);

  if v_acompte is null then
    raise exception 'Le montant de l''acompte n''a pas été fixé pour cette demande.'
      using errcode = 'PT409', hint = 'FE053';
  end if;

  insert into public.payments (booking_id, checkout_id, amount, method, status, is_test)
  values (v_booking.id, null, v_acompte, 'cash', 'pending', true)
  returning * into v_paiement;

  select v.owner_id into v_owner
    from public.venues v where v.id = v_booking.venue_id;

  perform public.notify_user(
    v_owner, 'cash_pending',
    jsonb_build_object('booking_id', v_booking.id,
                       'group_id',   v_booking.group_id,
                       'payment_id', v_paiement.id,
                       'amount',     v_acompte)
  );

  return v_paiement;
end;
$fn$;

comment on function public.payer_en_especes(uuid) is
  'Le client annonce qu''il versera l''acompte en main propre (§3, écran 6). Ne confirme RIEN : '
  'la réservation reste « accepted » et l''option de 72 h court toujours. Pose une ligne payments '
  'method = ''cash'' en « pending » et prévient le propriétaire, qui confirmera l''encaissement. '
  'Idempotente : rappuyer rend l''intention déjà posée.';

revoke execute on function public.payer_en_especes(uuid) from public, anon;
grant execute on function public.payer_en_especes(uuid) to authenticated;

-- =============================================================================
-- confirmer_encaissement_especes — le propriétaire a les billets
--
-- SECURITY DEFINER, ET ELLE VÉRIFIE QUI APPELLE. owns_booking() (004) répond
-- sur auth.uid() : c'est le propriétaire de la salle, et personne d'autre.
-- confirm_booking() revérifie la même chose derrière — deux gardes pour un
-- geste qui prend une date.
--
-- ELLE FAIT EXACTEMENT CE QUE FAIT CHARGILY, dans le même ordre : le paiement
-- passe « paid », puis la réservation est confirmée par confirm_booking(). Il
-- n'y a pas deux chemins vers « confirmed », il y en a un — et c'est pour cela
-- que l'index du §6.1 protège aussi bien celui-ci.
-- =============================================================================

create or replace function public.confirmer_encaissement_especes(p_booking_id uuid)
returns public.payments
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_booking  public.bookings;
  v_tenue    text;
  v_paiement public.payments;
begin
  if auth.uid() is null then
    raise exception 'Il faut être connecté pour confirmer un encaissement.'
      using errcode = 'PT401', hint = 'FE060';
  end if;

  if not public.owns_booking(p_booking_id) then
    raise exception 'Cette demande ne concerne pas vos salles.'
      using errcode = 'PT403', hint = 'FE061';
  end if;

  select * into v_booking from public.bookings where id = p_booking_id;

  -- L'intention du client, verrouillée : deux taps ne confirment pas deux fois.
  select p.* into v_paiement
    from public.payments p
    join public.bookings b on b.id = p.booking_id
   where b.group_id = v_booking.group_id
     and p.method = 'cash'
     and p.status = 'pending'
   order by p.created_at desc
   limit 1
   for update of p;

  if v_paiement.id is null then
    raise exception 'Aucun versement en espèces n''est annoncé pour cette réservation.'
      using errcode = 'PT409', hint = 'FE062';
  end if;

  v_tenue := public.tient_la_date(v_booking.status, v_booking.option_expires_at);

  if v_tenue is distinct from 'option' then
    raise exception 'La date n''est plus tenue pour cette demande.'
      using errcode = 'PT409', hint = 'FE063';
  end if;

  update public.payments
     set status = 'paid'
   where id = v_paiement.id
  returning * into v_paiement;

  begin
    perform public.confirm_booking(p_booking_id);
  exception when unique_violation then
    raise exception 'Ce créneau vient d''être confirmé par une autre réservation.'
      using errcode = 'PT409', hint = 'FE064';
  end;

  return v_paiement;
end;
$fn$;

comment on function public.confirmer_encaissement_especes(uuid) is
  'Le propriétaire confirme avoir reçu l''acompte en main propre (§3). Vérifie owns_booking(), '
  'passe le paiement « cash » en « paid », puis confirme par confirm_booking() — le même chemin '
  'que Chargily, et le même index du §6.1 pour dernier mot.';

revoke execute on function public.confirmer_encaissement_especes(uuid) from public, anon;
grant execute on function public.confirmer_encaissement_especes(uuid) to authenticated;

-- =============================================================================
-- owner_request_detail — VERSION COURANTE
--
-- CE QUI CHANGE : deux colonnes. `acompte_du`, l'entier de montant_acompte()
-- (024) — le propriétaire doit lire le MÊME nombre que son client, sans quoi il
-- comptera ses billets d'après un autre. Et `especes_en_attente`, qui dit qu'un
-- versement en main propre est annoncé et attend sa confirmation.
--
-- Le reste est celui de 014, mot pour mot, booking_contact() comprise.
-- =============================================================================

drop function if exists public.owner_request_detail(uuid);

create function public.owner_request_detail(p_booking_id uuid)
returns table (
  group_id           uuid,
  booking_id         uuid,
  venue_id           uuid,
  venue_name         text,
  client_name        text,
  client_phone       text,
  phone_available    boolean,
  event_date         date,
  requested_slot     text,
  slots              text[],
  guest_count        integer,
  event_type         text,
  event_label        text,
  client_message     text,
  options            jsonb,
  quoted_amount      numeric,
  deposit_amount     numeric,
  acompte_du         integer,
  especes_en_attente boolean,
  status             text,
  status_reason      text,
  created_at         timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  v_venue_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Il faut être connecté pour voir cette demande.'
      using errcode = 'PT401';
  end if;

  select b.venue_id into v_venue_id
  from public.bookings b where b.id = p_booking_id;

  if v_venue_id is null then
    raise exception 'Demande inconnue.' using errcode = 'no_data_found';
  end if;

  if not public.owns_venue(v_venue_id) then
    raise exception 'Cette demande ne concerne pas vos salles.'
      using errcode = 'PT403';
  end if;

  return query
  select
    bg.group_id,
    b.id,
    bg.venue_id,
    v.name,
    c.full_name,
    c.phone,
    c.phone_available,
    bg.event_date,
    bg.requested_slot,
    bg.slots,
    bg.guest_count,
    bg.event_type,
    t.label_fr,
    b.client_message,
    coalesce(
      (select jsonb_agg(
                jsonb_build_object(
                  'code',  o.code,
                  'label', o.label_fr,
                  'price', o.price)
                order by o.position, o.code)
         from public.venue_options o
        where o.id = any (b.option_ids)),
      '[]'::jsonb),
    bg.quoted_amount,
    bg.deposit_amount,
    -- L'UNIQUE arrondi (024) : propriétaire et client lisent le même nombre.
    public.montant_acompte(bg.group_id),
    exists (
      select 1
        from public.payments p
        join public.bookings pb on pb.id = p.booking_id
       where pb.group_id = bg.group_id
         and p.method = 'cash'
         and p.status = 'pending'
    ),
    bg.status,
    b.status_reason,
    bg.created_at
  from public.booking_groups bg
  join public.bookings b
    on b.group_id = bg.group_id and b.slot = bg.slots[1]
  join public.venues v on v.id = bg.venue_id
  left join public.event_types t on t.code = bg.event_type
  cross join lateral public.booking_contact(b.id) c
  where bg.group_id = (select g.group_id from public.bookings g
                        where g.id = p_booking_id);
end;
$fn$;

comment on function public.owner_request_detail(uuid) is
  'Le détail d''une demande, du point de vue du propriétaire (§4.3, OWN-05), en lecture seule. '
  'Le téléphone du client vient de booking_contact() : rien avant « accepted » (§9). Depuis 025, '
  '« acompte_du » donne l''acompte en dinars entiers — le même nombre que chez le client — et '
  '« especes_en_attente » dit qu''un versement en main propre attend sa confirmation.';

revoke execute on function public.owner_request_detail(uuid) from public, anon;
grant execute on function public.owner_request_detail(uuid) to authenticated;

-- =============================================================================
-- acompte_a_verser — VERSION COURANTE
--
-- CE QUI CHANGE : une colonne, `especes_en_attente`. Le troisième choix de
-- l'écran 6 n'est plus décoratif depuis ce fichier, et l'écran doit savoir
-- qu'une intention est déjà posée : la reproposer comme si de rien n'était
-- laisserait croire que le premier appui n'a rien fait, et le client
-- rappuierait — sans que rien de neuf ne se produise, puisque
-- payer_en_especes() est idempotente.
--
-- Le reste est celui de 024, mot pour mot, y compris les cinq refus.
--
-- DROP PUIS CREATE : le type de retour change.
-- =============================================================================

drop function if exists public.acompte_a_verser(uuid);

create function public.acompte_a_verser(p_booking_id uuid)
returns table (
  group_id           uuid,
  booking_id         uuid,
  venue_id           uuid,
  venue_name         text,
  commune            text,
  wilaya_name        text,
  event_date         date,
  requested_slot     text,
  guest_count        integer,
  event_type         text,
  event_label        text,
  owner_name         text,
  montant_convenu    numeric,
  acompte            integer,
  solde              numeric,
  option_expires_at  timestamptz,
  checkout_id        text,
  paiement_en_cours  boolean,
  -- Un versement en main propre est annonce et attend le proprietaire.
  especes_en_attente boolean
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

  if v_group is null or v_client is distinct from auth.uid() then
    raise exception 'Cette réservation n''est pas la vôtre.'
      using errcode = 'PT403', hint = 'FE051';
  end if;

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
    paie.checkout_id,
    paie.checkout_id is not null,
    exists (
      select 1
        from public.payments pc
        join public.bookings pb on pb.id = pc.booking_id
       where pb.group_id = bg.group_id
         and pc.method = 'cash'
         and pc.status = 'pending'
    )
  from public.booking_groups bg
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
  'Le montant est celui de montant_acompte() — l''unique arrondi. Depuis 025, '
  '« especes_en_attente » dit qu''un versement en main propre est annoncé et attend le '
  'propriétaire.';

revoke execute on function public.acompte_a_verser(uuid) from public, anon;
grant execute on function public.acompte_a_verser(uuid) to authenticated;
