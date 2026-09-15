-- =============================================================================
-- Ferha — seed/002_reset_demo.sql
-- Efface ce qui APPARTIENT AUX COMPTES DE DÉMONSTRATION, et rien d'autre.
--
-- -----------------------------------------------------------------------------
-- CECI EST UN CHANGEMENT DE DÉFINITION, PAS UN AJOUT (J26)
--
-- Ce fichier disait, et faisait, « efface les données de 001_demo_venues.sql ».
-- Il dit maintenant « efface ce qui appartient aux comptes de démonstration ».
-- Ce n'est pas la même phrase, et la différence est une catégorie entière de
-- données : LES SALLES QU'UN VISITEUR PUBLIE EN ÉTANT ENTRÉ COMME KARIM.
--
-- Elles portent un identifiant tiré au sort, donc pas le préfixe 5a11e000-, donc
-- l'ancienne définition ne les voyait pas. Elles n'en disparaissaient pas pour
-- autant : venues.owner_id référence profiles en CASCADE, si bien que le
-- `delete from profiles` de la fin les emportait — SANS LES NOMMER, sans les
-- compter, et sans que le bloc de preuve final en dise un mot, puisqu'il ne
-- comptait que les salles en 5a11e000-.
--
-- Une cascade muette est pire qu'un échec bruyant. C'est exactement ce que la
-- règle RESTRICT du projet cherche à empêcher : « une suppression franche doit
-- échouer plutôt que d'emporter l'historique en silence ». Ce fichier les efface
-- donc maintenant EN LES NOMMANT, et son bloc de preuve les compte.
--
-- Trois d'entre elles existaient sur la base au 16 septembre 2026 — « salle »,
-- « salle reve » et « lyb », publiées les 10 et 11 septembre pendant le
-- développement du J12, quatre jours avant que l'application soit mise en ligne.
-- -----------------------------------------------------------------------------
--
-- CE QU'IL EFFACE : les cinq comptes de démonstration — les quatre
-- propriétaires de 001 et la cliente Amina de 003 — leurs identités GoTrue,
-- leurs quinze salles, LES SALLES QU'ILS ONT PUBLIÉES DEPUIS L'APPLICATION, et
-- tout ce qui pend à ces salles : photos, équipements, tarifs, options, dates
-- bloquées, types d'événement acceptés.
--
-- CE QU'IL N'EFFACE PAS : les référentiels — amenities, event_types, wilayas —
-- qui relèvent du schéma et non de la démonstration, high_season_periods, et
-- absolument rien qui appartienne à un vrai utilisateur.
--
-- CE QU'IL NE SAIT TOUJOURS PAS FAIRE : effacer les FICHIERS du bucket
-- `venue-photos`. Rien ne relie storage.objects à venues, et aucun trigger ne
-- les suit. Supprimer une salle qui portait des photos laisse donc ses fichiers
-- orphelins. Le bloc de preuve les compte désormais, pour qu'on le sache au lieu
-- de le découvrir ; les retirer se fait par l'API Storage, pas en SQL.
--
-- COMMENT IL RECONNAÎT SES DONNÉES : par le préfixe des identifiants, posé
-- exprès dans 001 —
--     propriétaires  d0000000-0000-4000-a000-0000000000NN
--     salles         5a11e000-0000-4000-a000-0000000000NN
-- Pas par le nom, pas par la wilaya, pas par l'adresse e-mail : un vrai
-- propriétaire peut s'appeler Karim et tenir une salle à Oran. L'identifiant,
-- lui, ne se produit pas par hasard.
--
-- ET, DEPUIS LE J26, PAR LE PROPRIÉTAIRE : une salle dont owner_id porte le
-- préfixe d0000000- appartient à la démonstration, quel que soit son propre
-- identifiant. C'est le critère qui rattrape les salles publiées depuis
-- l'application, et c'est le même que celui de la vue etat_du_decor (035).
--
-- L'EMPREINTE DU DÉCOR (migration 035) part aussi, et en premier : sans décor,
-- elle n'a plus d'objet, et le ménage horaire tenterait de restaurer des
-- réservations vers des salles supprimées.
--
-- LES RÉSERVATIONS DE DÉMONSTRATION de 004_demo_bookings.sql partent aussi :
-- elles portent le préfixe b0000000-, elles se recréent en relançant le
-- fichier, et leurs avis avec elles.
--
-- SI CE FICHIER ÉCHOUE sur une violation de clé étrangère : c'est que d'AUTRES
-- réservations ont été prises sur une salle de démonstration — depuis
-- l'application, par exemple, ce qui leur donne un identifiant tiré au sort.
-- bookings.venue_id est en RESTRICT, et c'est voulu — une réservation est une
-- trace comptable, elle ne s'efface pas dans le dos de son client. Le dernier
-- bloc de ce fichier vous dira lesquelles. À vous de décider ; ce script ne le
-- décidera pas pour vous.
--
-- REJOUABLE : le lancer deux fois de suite ne produit ni erreur ni effet.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- La liste des salles à effacer, arrêtée AVANT de toucher à quoi que ce soit
--
-- DEUX BRANCHES : le préfixe de la salle, pour les quinze de 001, et le préfixe
-- de son PROPRIÉTAIRE, pour celles qu'un visiteur a publiées depuis
-- l'application — elles portent un identifiant tiré au sort. Voir l'en-tête :
-- c'est là qu'est le changement de définition du J26.
--
-- UNE TABLE TEMPORAIRE ET NON UNE VUE : une vue se réévaluerait à chaque
-- instruction et se viderait au fur et à mesure que les salles disparaissent.
-- On veut que les huit suppressions qui suivent portent sur EXACTEMENT le même
-- ensemble, arrêté une fois. `on commit drop` : elle ne survit pas au fichier,
-- et aucune migration n'a à connaître son nom.
-- -----------------------------------------------------------------------------

create temp table salles_de_demonstration on commit drop as
select v.id
  from public.venues v
 where v.id::text       like '5a11e000-%'
    or v.owner_id::text like 'd0000000-%';

-- -----------------------------------------------------------------------------
-- L'empreinte du décor, ensuite
--
-- La migration 035 garde une empreinte du décor pour le remettre en place après
-- le passage d'un visiteur. Après ce fichier, il n'y a plus de décor : une
-- empreinte qui lui survit ferait tenter au ménage horaire d'insérer des
-- réservations vers des salles supprimées — une violation de clé étrangère
-- toutes les heures, dans les journaux, pour rien.
--
-- Elle n'a pas de clé étrangère vers venues, donc rien ne l'emporterait toute
-- seule. C'est exactement pour cela qu'il faut la nommer ici.
-- -----------------------------------------------------------------------------

do $$
begin
  if to_regprocedure('public.vider_le_decor()') is not null then
    perform public.vider_le_decor();
  end if;
end $$;

-- -----------------------------------------------------------------------------
-- D'abord les réservations de démonstration, et leurs avis
--
-- Elles viennent de 004_demo_bookings.sql, elles portent son préfixe, et elles
-- se recréent en une commande. Les avis passent devant : reviews.booking_id est
-- en RESTRICT, un avis publié ne s'efface pas en supprimant sa réservation.
-- -----------------------------------------------------------------------------

delete from public.reviews  where booking_id::text like 'b0000000-%';
delete from public.bookings where id::text         like 'b0000000-%';

-- -----------------------------------------------------------------------------
-- Ensuite seulement : reste-t-il des réservations sur ces salles ?
--
-- Celles-là ne viennent pas d'un fichier de seed. On regarde et on s'arrête
-- net, avec un message lisible, plutôt que de laisser sortir une erreur de clé
-- étrangère que personne n'aura envie de déchiffrer.
-- -----------------------------------------------------------------------------

do $$
declare
  v_bookings integer;
begin
  -- Le troisième cas est celui du J26 : une réservation prise sur une salle
  -- qu'un visiteur a publiée en étant entré comme Karim. Sans lui, elle ne
  -- serait comptée nulle part, et la suppression du profil l'emporterait en
  -- cascade — muettement.
  select count(*) into v_bookings
  from public.bookings b
  where b.venue_id::text like '5a11e000-%'
     or b.client_id::text like 'd0000000-%'
     or b.venue_id in (select v.id from public.venues v
                        where v.owner_id::text like 'd0000000-%');

  if v_bookings > 0 then
    raise exception
      'ARRÊT — % réservation(s) portent sur des salles ou des comptes de '
      'démonstration. Rien n''a été effacé. Une réservation est une trace '
      'comptable : décidez vous-même de son sort avant de relancer ce fichier.',
      v_bookings
      using hint = 'select * from public.bookings b join public.venues v on v.id = b.venue_id '
                   'where v.owner_id::text like ''d0000000-%'' or b.client_id::text like ''d0000000-%'';';
  end if;
end;
$$;

-- -----------------------------------------------------------------------------
-- Les tables filles
--
-- Les clés étrangères de 001 sont en CASCADE depuis venues : supprimer les
-- salles suffirait. On les nomme quand même, une par une, pour deux raisons :
-- le fichier dit alors exactement ce qu'il touche, et un jour où une cascade
-- changerait, l'effacement resterait complet.
--
-- LE CRITÈRE A DEUX BRANCHES DEPUIS LE J26 : le préfixe de la salle, pour
-- celles de 001, ET le préfixe de son propriétaire, pour celles qu'un visiteur
-- a publiées depuis l'application. Voir l'en-tête : c'est là que se joue le
-- changement de définition.
-- -----------------------------------------------------------------------------

delete from public.venue_photos      where venue_id in (select id from salles_de_demonstration);
delete from public.venue_amenities   where venue_id in (select id from salles_de_demonstration);
delete from public.venue_pricing     where venue_id in (select id from salles_de_demonstration);
delete from public.venue_blackouts   where venue_id in (select id from salles_de_demonstration);
delete from public.venue_options     where venue_id in (select id from salles_de_demonstration);
delete from public.venue_event_types where venue_id in (select id from salles_de_demonstration);

-- -----------------------------------------------------------------------------
-- Les salles, puis les comptes
--
-- Dans cet ordre : venues.owner_id référence profiles, et profiles.id
-- référence auth.users. Supprimer auth.users cascaderait jusqu'en bas, mais
-- l'ordre explicite rend le fichier lisible et n'importe quel blocage
-- reconnaissable à la ligne près.
--
-- LES SALLES PUBLIÉES DEPUIS L'APPLICATION PARTENT ICI, nommées. Elles
-- partaient déjà avant — en cascade depuis profiles, sans être comptées. La
-- différence n'est pas dans le résultat, elle est dans le fait qu'on le dise.
--
-- Les notifications des comptes de démonstration partent avec eux : la clé
-- étrangère de notifications.user_id est en CASCADE.
-- -----------------------------------------------------------------------------

delete from public.venues   where id in (select id from salles_de_demonstration);
delete from public.profiles where id::text like 'd0000000-%';

-- Les identités du fournisseur « email », posées par 003_demo_accounts.sql.
-- La clé étrangère de GoTrue les emporterait avec le compte ; on les nomme
-- pour que ce fichier reste la liste complète de ce qu'il touche.
delete from auth.identities
 where user_id::text like 'd0000000-%';

-- Emporte les quatre propriétaires de 001 et la cliente Amina de 003 : tous
-- portent le même préfixe.
delete from auth.users      where id::text like 'd0000000-%';

commit;

-- -----------------------------------------------------------------------------
-- Preuve qu'il ne reste rien. Doit renvoyer 0 partout — SAUF `fichiers_orphelins`.
--
-- `salles_publiees` EST LA COLONNE AJOUTÉE AU J26, et elle est la raison d'être
-- de ce bloc réécrit. Elle comptait 3 sans que rien ne l'affiche : les salles
-- publiées depuis l'application partaient en cascade depuis profiles, muettes.
-- Elle doit rendre 0 comme les autres ; si elle rendait autre chose, c'est que
-- le critère par propriétaire ne les a pas vues.
--
-- `fichiers_orphelins` NE PEUT PAS ÊTRE RAMENÉ À ZÉRO PAR CE FICHIER, et c'est
-- pour cela qu'il est compté à part. Rien ne relie storage.objects à venues :
-- le SQL efface la ligne d'index de la photo, jamais le fichier. S'il rend
-- autre chose que 0, les fichiers sont à retirer par l'API Storage — depuis
-- l'application, ou par un script authentifié comme le propriétaire, tant que
-- la salle existe encore, car la politique venue_photos_storage_delete (021)
-- exige owns_venue(). Après la suppression de la salle, plus personne n'y a
-- droit et il ne reste que la console.
--
-- LA LEÇON EST DANS L'ORDRE : les fichiers d'abord, la salle ensuite.
-- -----------------------------------------------------------------------------

select
  (select count(*) from public.venues
    where id::text like '5a11e000-%')                                        as salles,
  (select count(*) from public.venues
    where owner_id::text like 'd0000000-%')                                  as salles_publiees,
  (select count(*) from public.venue_photos    vp
    where not exists (select 1 from public.venues v where v.id = vp.venue_id)) as photos,
  (select count(*) from public.venue_amenities where venue_id::text like '5a11e000-%') as equipements,
  (select count(*) from public.venue_pricing   where venue_id::text like '5a11e000-%') as tarifs,
  (select count(*) from public.venue_blackouts where venue_id::text like '5a11e000-%') as dates_bloquees,
  (select count(*) from public.venue_event_types where venue_id::text like '5a11e000-%') as types_evenement,
  (select count(*) from public.profiles        where id::text       like 'd0000000-%') as profils,
  (select count(*) from auth.users             where id::text       like 'd0000000-%') as comptes,
  (select count(*) from public.bookings        where id::text       like 'b0000000-%') as reservations,
  (select count(*) from public.reviews         where booking_id::text like 'b0000000-%') as avis,
  -- Le seul compteur qui a le droit de ne pas être nul. Voir ci-dessus.
  (select count(*) from storage.objects o
    where o.bucket_id = 'venue-photos'
      and not exists (select 1 from public.venues v
                       where o.name like v.id::text || '/%'))                as fichiers_orphelins;
