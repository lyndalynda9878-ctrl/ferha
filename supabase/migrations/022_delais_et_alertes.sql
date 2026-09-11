-- =============================================================================
-- Ferha — 022_delais_et_alertes.sql
-- Les délais et les alertes (§5.1, §4.1 CORE-04, §7.2).
--
-- CE QUE CE FICHIER APPORTE
--
--   notify_user()                 enrichi : une notification se suffit à
--                                 elle-même, nom de salle et date compris
--   'booking_expired'             un type à part pour l'option échue
--   request_booking()             notifie APRÈS l'insertion, avec l'identifiant
--                                 de la demande — sans lui, la notification du
--                                 propriétaire n'ouvrait rien
--                                 ⚠ VERSION COURANTE DANS 023 : son garde-fou
--                                 de créneau passe par creneau_est_pris(), et
--                                 une option de 72 h en cours refuse désormais
--                                 la demande (FE001, §5.1)
--   expire_options()              une journée entière expire d'un bloc et ne
--                                 prévient qu'une fois, les DEUX parties
--   deux tâches pg_cron           l'expiration toutes les 15 min, la purge de
--                                 l'historique une fois par nuit
--   mes_notifications()           la liste de l'écran, et le compteur de la
--                                 cloche, en un seul appel
--   marquer_notifications_lues()  une notification, ou toutes
--   notifications dans supabase_realtime
--
-- CE QU'IL N'APPORTE PAS, ET CE N'EST PAS UN OUBLI. Les demandes « pending »
-- n'expirent pas. Le §5.1 pose une échéance sur l'option de 72 h et sur elle
-- seule : « une demande pending ne bloque pas la date », elle ne coûte donc
-- rien à personne en restant là. Un propriétaire parti en voyage retrouve ses
-- demandes au retour plutôt qu'un écran vide, et la cliente qui attend garde le
-- droit d'annuler elle-même. Ne pas ajouter de délai ici sans que le cahier des
-- charges en pose un.
--
-- PAS D'EDGE FUNCTION POUR L'EXPIRATION. Le §7.2 en dessine une
-- (« expire-options, cron horaire »), mais elle ne ferait qu'appeler une
-- fonction SQL qui existe déjà : un aller-retour HTTP, un secret de plus à
-- garder, et une panne possible entre deux morceaux qui vivent dans la même
-- base. pg_cron appelle expire_options() là où elle est. La ligne du §7.2 reste
-- vraie sur le fond — quelque chose passe toutes les quelques minutes — et
-- c'est la mise en œuvre la plus courte qui la rend vraie.
--
-- TOUTES LES 15 MINUTES, ET NON TOUTES LES HEURES. Le §7.2 dit « horaire ».
-- Une heure de retard sur une option échue, c'est une heure pendant laquelle
-- une date libre se lit « prise » dans venue_calendar() — et c'est justement le
-- moment où une autre famille regarde. Quinze minutes coûtent 96 réveils de
-- plus par jour sur une fonction qui ne fait rien 95 fois sur 96, et le plan
-- gratuit de Supabase les offre.
--
-- Rejouable : les fonctions sont remplacées, la contrainte reposée, les tâches
-- pg_cron réécrites sous le même nom, la publication touchée seulement si la
-- table n'y est pas déjà.
-- Dépend de : 004 (notifications, notify_user, expire_options, booking_groups),
--             006 (RLS des notifications), 012/020 (request_booking).
-- =============================================================================

-- =============================================================================
-- 1. notify_user() — LA NOTIFICATION SE SUFFIT À ELLE-MÊME
--
-- « Les textes viennent du type et du payload. » Jusqu'ici le payload portait
-- deux identifiants, et rien d'autre : l'écran aurait dû aller rechercher le
-- nom de la salle, la date et le créneau pour écrire une ligne lisible — donc
-- faire une requête par notification, ou recomposer en Dart ce que la base sait
-- déjà. On remplit le payload À L'ÉCRITURE, une fois pour toutes.
--
-- ET ON LE FIGE. Une notification est datée : elle raconte ce qui s'est passé
-- ce jour-là. Une salle renommée demain ne doit pas réécrire l'annonce d'hier —
-- c'est la différence entre une notification et une vue.
--
-- LE CONTEXTE L'EMPORTE SUR L'APPELANT (`p_payload || v_contexte`). Les clés
-- de contexte viennent de la base ; celles de l'appelant complètent — un motif,
-- un statut — mais ne peuvent pas contredire le nom de la salle ou la date.
--
-- 'role' EST LA CLÉ QUI DÉCIDE DE L'ÉCRAN D'ARRIVÉE. 'booking_confirmed' part
-- aux deux parties : sans elle, l'application devrait deviner si la personne
-- qui touche la notification est la cliente ou le propriétaire, et la deviner
-- avec le seul identifiant de session — c'est-à-dire refaire ici le travail de
-- la base. Elle est calculée là où client_id et owner_id sont sous la main.
--
-- 'booking_id' EST NORMALISÉ vers la ligne REPRÉSENTATIVE du groupe, celle du
-- premier créneau — la même que booking_groups, owner_request_detail() et
-- accepter_demande(). Une journée entière s'ouvre donc toujours par la même de
-- ses deux lignes, quelle que soit celle que l'appelant avait sous la main.
-- =============================================================================

create or replace function public.notify_user(
  p_user_id uuid,
  p_type    text,
  p_payload jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_source   uuid  := nullif(p_payload ->> 'booking_id', '')::uuid;
  v_contexte jsonb := '{}'::jsonb;
begin
  if v_source is not null then
    -- jsonb_strip_nulls : une clé absente vaut mieux qu'une clé à null. Côté
    -- application, « la salle n'a pas de commune » et « la clé n'existe pas »
    -- se traitent pareil, et le payload reste lisible à l'œil nu.
    select jsonb_strip_nulls(jsonb_build_object(
             'booking_id',     representative.id,
             'group_id',       bg.group_id,
             'venue_id',       bg.venue_id,
             'venue_name',     v.name,
             'commune',        v.commune,
             'event_date',     bg.event_date,
             'requested_slot', bg.requested_slot,
             'slots',          bg.slots,
             'guest_count',    bg.guest_count,
             'role',           case
                                 when p_user_id = bg.client_id then 'client'
                                 when p_user_id = v.owner_id   then 'owner'
                               end
           ))
      into v_contexte
      from public.bookings       source
      join public.booking_groups bg on bg.group_id = source.group_id
      join public.venues         v  on v.id        = bg.venue_id
      -- La ligne représentative : le premier créneau du groupe, c'est-à-dire
      -- bg.slots[1]. Même convention qu'en 013, 014 et 016.
      join public.bookings representative
        on  representative.group_id = bg.group_id
        and representative.slot     = bg.slots[1]
     where source.id = v_source;
  end if;

  insert into public.notifications (user_id, type, payload)
  values (p_user_id, p_type, p_payload || coalesce(v_contexte, '{}'::jsonb));
end;
$$;

comment on function public.notify_user(uuid, text, jsonb) is
  'Dépose une notification (§4.1, CORE-04) et remplit son payload : nom de la salle, date, '
  'créneau, invités, et le rôle du destinataire — pour que le texte affiché ne demande aucune '
  'seconde requête, et qu''il reste celui du jour où il a été écrit. '
  'Appelée par les fonctions de transition, et par elles seules.';

revoke execute on function public.notify_user(uuid, text, jsonb) from public, anon, authenticated;

-- =============================================================================
-- 2. 'booking_expired' — UNE OPTION ÉCHUE N'EST PAS UNE ANNULATION
--
-- expire_options() déposait jusqu'ici un 'booking_cancelled' portant
-- « reason: option_expired » dans son payload. L'application aurait dû lire le
-- type, puis le payload, pour savoir laquelle des deux phrases écrire — et une
-- phrase fausse ici est coûteuse : « votre réservation a été annulée » laisse
-- croire que quelqu'un l'a annulée, alors que personne n'a rien fait, et que
-- c'est justement le problème.
--
-- Le type du §4.1 reste la clé du texte. On lui ajoute donc une valeur plutôt
-- que de faire dire deux choses à une seule.
-- =============================================================================

alter table public.notifications drop constraint if exists notifications_type_check;

alter table public.notifications add constraint notifications_type_check
  check (type in ('booking_requested',   -- nouvelle demande, côté propriétaire
                  'booking_answered',    -- réponse du propriétaire, côté client
                  'booking_confirmed',   -- acompte reçu, les deux parties
                  'booking_cancelled',   -- une PERSONNE a annulé (§5.3)
                  'booking_expired',     -- l'option de 72 h est passée (§5.1)
                  'reminder_j7',
                  'reminder_j1',
                  'review_invitation'));

-- =============================================================================
-- 3. request_booking() — NOTIFIER APRÈS, PAS AVANT
--
-- POURQUOI ELLE EST RÉÉCRITE ICI. Sa version de 020 appelle notify_user() avant
-- d'insérer les lignes, avec un payload qui porte le groupe mais pas la demande.
-- Deux conséquences, dont la seconde était déjà un défaut :
--
--   1. Le contexte du §1 ne peut pas se remplir : au moment de l'appel, les
--      lignes de bookings n'existent pas encore. La notification du
--      propriétaire serait la seule à rester nue.
--
--   2. Sans 'booking_id', elle n'ouvre rien. owner_request_detail(),
--      accepter_demande() et refuser_demande() attendent toutes l'identifiant
--      d'une LIGNE ; le groupe ne leur sert pas d'entrée. Une notification
--      « nouvelle demande » qu'on touche et qui ne mène nulle part est pire
--      qu'absente.
--
-- Rien d'autre ne change : mêmes contrôles, mêmes codes Ferha, même ordre, et
-- toujours UNE seule instruction d'insertion — le trigger bookings_check_journee
-- (§6.1) vérifie que les deux lignes d'une journée entière y sont ensemble.
--
-- L'insertion ne passe plus par une CTE : la fonction a maintenant quelque chose
-- à faire APRÈS elle, et `return query with created as (insert …)` ne laisse pas
-- de place entre les deux. Elle insère, relit le groupe, notifie, puis rend les
-- lignes — le montant qu'elle rend est celui que le trigger bookings_set_price
-- vient d'écrire, exactement comme avant.
-- =============================================================================

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
  v_client  uuid := auth.uid();
  v_owner   uuid;
  v_group   uuid := gen_random_uuid();
  v_slots   text[];
  v_phone   text := public.telephone_normalise(p_phone);
  v_demande uuid;
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

  -- UNE SEULE INSTRUCTION pour les deux lignes d'une journée entière — c'est ce
  -- que vérifie le trigger bookings_check_journee (§6.1).
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
  from unnest(v_slots) as s;

  -- La ligne représentative du groupe : le premier créneau. C'est elle que la
  -- notification désigne, et c'est elle qu'attendent les trois fonctions de
  -- l'espace propriétaire.
  select b.id into v_demande
  from public.bookings b
  where b.group_id = v_group
  order by b.slot
  limit 1;

  perform public.notify_user(
    v_owner, 'booking_requested',
    jsonb_build_object('booking_id', v_demande)
  );

  return query
  select b.* from public.bookings b where b.group_id = v_group order by b.slot;
end;
$$;

comment on function public.request_booking(uuid, date, text, integer, text, text, text, uuid[]) is
  'Pose une demande (§3, étape 3). Insère les deux lignes d''une journée entière en une instruction (§6.1). '
  'Reçoit le numéro auquel la salle rappellera et l''écrit dans profiles.phone ; refuse sans lui (FE007). '
  'Le montant vient du trigger bookings_set_price, donc d''estimate_price() — aucune règle de prix ici. '
  'Notifie le propriétaire APRÈS l''insertion, avec l''identifiant de la ligne représentative : c''est lui '
  'qui ouvre le détail de la demande. '
  'Chaque refus porte son code Ferha dans son hint : FE001 créneau pris, FE002 bloqué, '
  'FE003 date passée, FE004 salle fermée, FE005 sa propre salle, FE006 non connecté, '
  'FE007 numéro manquant ou mal formé. '
  'Le SQLSTATE PTxxx, lui, ne sert qu''à donner son code HTTP à PostgREST.';

revoke execute on function public.request_booking(uuid, date, text, integer, text, text, text, uuid[])
  from public, anon;
grant execute on function public.request_booking(uuid, date, text, integer, text, text, text, uuid[])
  to authenticated;

-- =============================================================================
-- 4. expire_options() — UN GROUPE, UNE NOTIFICATION, DEUX DESTINATAIRES
--
-- TROIS CHOSES CHANGENT, ET LES TROIS SE VOIENT À L'USAGE.
--
--   1. UNE JOURNÉE ENTIÈRE NE PRÉVIENT QU'UNE FOIS. L'UPDATE en expirait déjà
--      les deux lignes d'un bloc — elles portent la même échéance, posée
--      ensemble par accept_booking() —, mais la boucle notifiait par LIGNE. La
--      cliente qui avait demandé le 3 juillet en entier recevait deux fois le
--      même message, pour une seule réservation. `distinct on (group_id)`
--      referme cela : une réservation, une notification.
--
--   2. LE PROPRIÉTAIRE EST PRÉVENU LUI AUSSI. C'est sa date qui vient de
--      repartir à la vente, et personne ne le lui disait. Il l'aurait appris en
--      rouvrant son agenda — c'est-à-dire trop tard pour rappeler la famille qui
--      hésitait encore.
--
--   3. LE TYPE DIT CE QUI S'EST PASSÉ : 'booking_expired', voir le §2.
--
-- ELLE TRAVAILLE EN DEUX TEMPS, et la coupure n'est pas cosmétique. L'UPDATE
-- expire et retient les groupes touchés ; la boucle prévient ensuite, en
-- relisant booking_groups. Boucler directement sur l'UPDATE ... RETURNING — ce
-- que faisait la version de 004 — oblige à redire ici quelle est la ligne
-- représentative d'un groupe, alors que booking_groups le dit déjà pour 013,
-- 014 et 016. Un second exemplaire de cette règle, c'est un second endroit où
-- une journée entière peut s'ouvrir par le mauvais de ses deux créneaux.
--
-- LE COMPTE RENDU CHANGE DE SENS : la fonction rendait un nombre de LIGNES, elle
-- rend maintenant un nombre de RÉSERVATIONS. C'est ce que lit un humain dans
-- cron.job_run_details, et « 2 » pour une seule journée entière expirée n'aurait
-- rien voulu dire.
--
-- CE QUI NE CHANGE PAS : la relancer ne notifie pas deux fois. L'UPDATE ne
-- touche que des lignes « accepted » ; une fois passées en « expired », le
-- second passage n'en trouve aucune et ne dépose rien. C'est la seule garantie
-- qui compte pour une tâche qui tourne toutes les quinze minutes.
-- =============================================================================

create or replace function public.expire_options()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_groupes uuid[];
  v_row     record;
begin
  -- 1. EXPIRER. Une journée entière porte la même échéance sur ses deux
  --    lignes — accept_booking() les pose ensemble —, et cet UPDATE les prend
  --    donc toutes les deux. C'est déjà « jamais une ligne sur deux ».
  with expirees as (
    update public.bookings b
       set status = 'expired', status_reason = 'Option de 72 h échue sans acompte.'
     where b.status = 'accepted'
       and b.option_expires_at is not null
       and b.option_expires_at < now()
    returning b.group_id
  )
  select array_agg(distinct e.group_id) into v_groupes from expirees e;

  -- Le cas de très loin le plus fréquent : 95 réveils sur 96 n'ont rien à
  -- faire, et sortent ici.
  if v_groupes is null then
    return 0;
  end if;

  -- 2. PRÉVENIR, une fois par RÉSERVATION et non par ligne. booking_groups dit
  --    laquelle des deux lignes représente le groupe ; on ne le redit pas.
  for v_row in
    select b.id as booking_id, bg.client_id, v.owner_id
      from public.booking_groups bg
      join public.bookings b
        on  b.group_id = bg.group_id
        and b.slot     = bg.slots[1]
      join public.venues v on v.id = bg.venue_id
     where bg.group_id = any (v_groupes)
  loop
    -- Les deux parties, une fois chacune. notify_user() remplit le reste du
    -- payload — nom de la salle, date, créneau — et pose le rôle qui dira à
    -- chacun sur quel écran il atterrit.
    perform public.notify_user(
      v_row.client_id, 'booking_expired',
      jsonb_build_object('booking_id', v_row.booking_id)
    );
    perform public.notify_user(
      v_row.owner_id, 'booking_expired',
      jsonb_build_object('booking_id', v_row.booking_id)
    );
  end loop;

  return array_length(v_groupes, 1);
end;
$$;

comment on function public.expire_options() is
  'Tâche pg_cron, toutes les 15 minutes (§7.2) : libère les demandes acceptées non payées après '
  '72 h (§5.1) et prévient le client ET le propriétaire, une fois chacun par réservation — une '
  'journée entière expire d''un bloc. Rend le nombre de RÉSERVATIONS expirées. '
  'Rôle de service uniquement.';

-- Le rôle de service ignore ces révocations ; les clients, non.
revoke execute on function public.expire_options() from public, anon, authenticated;

-- =============================================================================
-- 5. pg_cron — L'OPTION S'ÉTEINT TOUTE SEULE
--
-- POURQUOI PAR MIGRATION ET NON PAR LE TABLEAU DE BORD. Une tâche créée à la
-- main dans l'interface Supabase n'existe que dans CE projet : elle ne se relit
-- pas, ne se revoit pas, et un projet recréé — ce qui arrivera — repartirait
-- sans elle, avec des options qui n'expirent plus et personne pour s'en
-- apercevoir. Écrite ici, elle se réapplique avec le reste.
--
-- LES TÂCHES TOURNENT SOUS postgres, propriétaire de expire_options(). La
-- fonction est SECURITY DEFINER et révoquée à anon, authenticated et public :
-- elle n'est appelable que par le rôle de service et par son propriétaire. Le
-- cron est exactement l'un de ces deux appelants légitimes.
--
-- LA SECONDE TÂCHE EXISTE PARCE QUE LA PREMIÈRE ÉCRIT. pg_cron consigne chaque
-- exécution dans cron.job_run_details ; à 96 exécutions par jour, c'est 35 000
-- lignes par an pour une table que personne ne relit au-delà de la semaine
-- écoulée. Sept jours suffisent à comprendre ce qui s'est passé, et la table
-- reste petite.
--
-- `end_time` et non `start_time` : une exécution encore en cours n'a pas de date
-- de fin, et la comparaison l'écarte d'elle-même. On ne purge jamais ce qui
-- tourne.
-- =============================================================================

create extension if not exists pg_cron;

grant usage on schema cron to postgres;

-- REJOUABLE : pg_cron réécrit une tâche portant un nom déjà pris, mais on
-- décroche d'abord explicitement — le comportement du remplacement dépend de la
-- version de l'extension, celui de ces trois lignes non.
do $$
begin
  if exists (select 1 from cron.job where jobname = 'ferha-expire-options') then
    perform cron.unschedule('ferha-expire-options');
  end if;

  if exists (select 1 from cron.job where jobname = 'ferha-purge-cron-history') then
    perform cron.unschedule('ferha-purge-cron-history');
  end if;
end $$;

-- Toutes les 15 minutes (§5.1, §7.2).
select cron.schedule(
  'ferha-expire-options',
  '*/15 * * * *',
  $cron$select public.expire_options();$cron$
);

-- Une fois par nuit, à une heure creuse.
select cron.schedule(
  'ferha-purge-cron-history',
  '20 3 * * *',
  $cron$delete from cron.job_run_details where end_time < now() - interval '7 days';$cron$
);

-- =============================================================================
-- 6. LIRE SES NOTIFICATIONS, ET LES MARQUER LUES
--
-- CES DEUX FONCTIONS NE SONT PAS « SECURITY DEFINER », ET C'EST LE POINT. Tout
-- le reste du projet en use parce qu'il faut lire des tables fermées — profiles,
-- venues suspendues, le téléphone de l'autre partie. Ici, il n'y a rien à
-- ouvrir : la politique notifications_select_own (006) dit déjà « les vôtres et
-- rien d'autre », et une fonction qui s'exécute avec les droits de l'appelant la
-- laisse faire son travail. Écrire un second « where user_id = auth.uid() »
-- ferait deux gardiens pour une seule règle — et le jour où l'un des deux
-- changerait, c'est le plus permissif qui gagnerait.
--
-- C'est aussi ce qui rend le compteur juste sans qu'on ait à le dire : le
-- sous-select de non_lues compte les notifications de l'appelant, parce que RLS
-- ne lui en montre pas d'autres.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- mes_notifications — la liste ET le compteur, en un appel
--
-- LE COMPTEUR NE SE DÉDUIT PAS DE LA LISTE. La cloche affiche le nombre de non
-- lues ; la liste, elle, s'arrête aux p_limite plus récentes. Compter en Dart
-- les non lues de la page reçue donnerait un badge qui rétrécit quand on
-- remonte. Le sous-select ci-dessous porte sur TOUTE la table — filtrée par RLS,
-- donc sur les seules notifications de l'appelant — et il est évalué une fois
-- pour l'ensemble du résultat.
--
-- La colonne est donc la même sur chaque ligne, et l'application n'en lit
-- qu'une. Une liste vide ne renvoie aucune ligne, donc aucun compteur : c'est
-- juste, puisqu'une liste vide n'a rien à compter.
-- -----------------------------------------------------------------------------

create or replace function public.mes_notifications(p_limite integer default 50)
returns table (
  id         uuid,
  type       text,
  payload    jsonb,
  read_at    timestamptz,
  created_at timestamptz,
  non_lues   bigint
)
language sql
stable
set search_path = public
as $$
  select
    n.id,
    n.type,
    n.payload,
    n.read_at,
    n.created_at,
    (select count(*) from public.notifications u where u.read_at is null)
  from public.notifications n
  -- Les plus récentes en haut : c'est celle du dessus qu'on attendait.
  order by n.created_at desc
  -- Bornée des deux côtés : un appel sans limite ne doit pas pouvoir demander
  -- dix mille lignes, et une limite à zéro ne rendrait jamais le compteur.
  limit greatest(1, least(coalesce(p_limite, 50), 200));
$$;

comment on function public.mes_notifications(integer) is
  'Les notifications de l''appelant, les plus récentes en tête, avec le nombre total de non lues '
  'répété sur chaque ligne — c''est le badge de la cloche. Ni SECURITY DEFINER ni filtre écrit à '
  'la main : la politique notifications_select_own (006) est le seul garde-fou.';

revoke execute on function public.mes_notifications(integer) from public, anon;
grant  execute on function public.mes_notifications(integer) to authenticated;

-- -----------------------------------------------------------------------------
-- marquer_notifications_lues — une, ou toutes
--
-- UNE SEULE FONCTION POUR LES DEUX GESTES. Toucher une notification et appuyer
-- sur « Tout marquer comme lu » font exactement la même écriture ; deux
-- fonctions auraient été deux endroits où poser la même date.
--
-- `read_at is null` DANS LE WHERE, et pas seulement pour économiser : c'est ce
-- qui rend le geste idempotent. Rouvrir l'écran, retoucher la même ligne, ou
-- appuyer deux fois sur « Tout marquer » n'écrasent pas la date de première
-- lecture par une seconde — et le compte rendu, lui, dit combien de
-- notifications ont RÉELLEMENT changé d'état.
--
-- Le trigger notifications_guard_update (006) veille par-dessus : même par un
-- appel direct à PostgREST, seul read_at est modifiable.
-- -----------------------------------------------------------------------------

create or replace function public.marquer_notifications_lues(p_id uuid default null)
returns integer
language plpgsql
set search_path = public
as $$
declare
  v_count integer;
begin
  update public.notifications n
     set read_at = now()
   where n.read_at is null
     and (p_id is null or n.id = p_id);

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

comment on function public.marquer_notifications_lues(uuid) is
  'Marque lue une notification (p_id), ou toutes celles de l''appelant (p_id null). '
  'Rend le nombre de lignes réellement changées. La politique notifications_update_own (006) '
  'borne l''écriture aux siennes ; le trigger notifications_guard_update interdit le reste.';

revoke execute on function public.marquer_notifications_lues(uuid) from public, anon;
grant  execute on function public.marquer_notifications_lues(uuid) to authenticated;

-- =============================================================================
-- 7. TEMPS RÉEL — notifications DANS LA PUBLICATION
--
-- Même raisonnement qu'en 013 pour bookings, et le même garde-fou : Realtime
-- évalue notifications_select_own (006) pour chaque abonné avant de lui livrer
-- une ligne. Ouvrir la publication n'ouvre donc pas la table, et si la politique
-- de SELECT changeait un jour, elle changerait ici aussi — un seul endroit à
-- surveiller.
--
-- L'abonnement Flutter pose en plus un filtre `user_id=eq.<uid>` : il ne
-- remplace pas la politique, il évite au serveur d'évaluer des lignes qui ne
-- partiraient de toute façon pas.
--
-- C'EST CE QUI REND LA CLOCHE VIVANTE. Sans cela, le propriétaire n'apprendrait
-- une demande qu'en tirant l'écran vers le bas — et le client sa réponse qu'en
-- rouvrant l'application. Une minuterie de rafraîchissement ferait le contraire
-- de ce qu'on cherche : du réseau en permanence pour n'apprendre presque jamais
-- rien, sur une 4G algérienne (§7.3).
-- =============================================================================

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename  = 'notifications'
  ) then
    alter publication supabase_realtime add table public.notifications;
  end if;
end $$;
