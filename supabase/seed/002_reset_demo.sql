-- =============================================================================
-- Ferha — seed/002_reset_demo.sql
-- Efface les données de démonstration de 001_demo_venues.sql, et rien d'autre.
--
-- CE QU'IL EFFACE : les cinq comptes de démonstration — les quatre
-- propriétaires de 001 et la cliente Amina de 003 — leurs identités GoTrue,
-- leurs quinze salles, et tout ce qui pend à ces salles : photos, équipements,
-- tarifs, options, dates bloquées.
--
-- CE QU'IL N'EFFACE PAS : le référentiel amenities (c'est du schéma, pas de la
-- démonstration), high_season_periods, et absolument rien qui appartienne à un
-- vrai utilisateur.
--
-- COMMENT IL RECONNAÎT SES DONNÉES : par le préfixe des identifiants, posé
-- exprès dans 001 —
--     propriétaires  d0000000-0000-4000-a000-0000000000NN
--     salles         5a11e000-0000-4000-a000-0000000000NN
-- Pas par le nom, pas par la wilaya, pas par l'adresse e-mail : un vrai
-- propriétaire peut s'appeler Karim et tenir une salle à Oran. L'identifiant,
-- lui, ne se produit pas par hasard.
--
-- SI CE FICHIER ÉCHOUE sur une violation de clé étrangère : c'est que des
-- réservations ont été prises sur une salle de démonstration.
-- bookings.venue_id est en RESTRICT, et c'est voulu — une réservation est une
-- trace comptable, elle ne s'efface pas dans le dos de son client. Le dernier
-- bloc de ce fichier vous dira lesquelles. À vous de décider ; ce script ne le
-- décidera pas pour vous.
--
-- REJOUABLE : le lancer deux fois de suite ne produit ni erreur ni effet.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- Avant d'effacer : y a-t-il des réservations sur ces salles ?
--
-- On regarde d'abord et on s'arrête net, avec un message lisible, plutôt que
-- de laisser sortir une erreur de clé étrangère que personne n'aura envie de
-- déchiffrer.
-- -----------------------------------------------------------------------------

do $$
declare
  v_bookings integer;
begin
  select count(*) into v_bookings
  from public.bookings b
  where b.venue_id::text like '5a11e000-%'
     or b.client_id::text like 'd0000000-%';

  if v_bookings > 0 then
    raise exception
      'ARRÊT — % réservation(s) portent sur des salles ou des comptes de '
      'démonstration. Rien n''a été effacé. Une réservation est une trace '
      'comptable : décidez vous-même de son sort avant de relancer ce fichier.',
      v_bookings
      using hint = 'select * from public.bookings where venue_id::text like ''5a11e000-%'';';
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
-- -----------------------------------------------------------------------------

delete from public.venue_photos    where venue_id::text like '5a11e000-%';
delete from public.venue_amenities where venue_id::text like '5a11e000-%';
delete from public.venue_pricing   where venue_id::text like '5a11e000-%';
delete from public.venue_blackouts where venue_id::text like '5a11e000-%';
delete from public.venue_options   where venue_id::text like '5a11e000-%';

-- -----------------------------------------------------------------------------
-- Les salles, puis les comptes
--
-- Dans cet ordre : venues.owner_id référence profiles, et profiles.id
-- référence auth.users. Supprimer auth.users cascaderait jusqu'en bas, mais
-- l'ordre explicite rend le fichier lisible et n'importe quel blocage
-- reconnaissable à la ligne près.
--
-- Les notifications des comptes de démonstration partent avec eux : la clé
-- étrangère de notifications.user_id est en CASCADE.
-- -----------------------------------------------------------------------------

delete from public.venues   where id::text like '5a11e000-%';
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
-- Preuve qu'il ne reste rien. Doit renvoyer 0 partout.
-- -----------------------------------------------------------------------------

select
  (select count(*) from public.venues          where id::text       like '5a11e000-%') as salles,
  (select count(*) from public.venue_photos    where venue_id::text like '5a11e000-%') as photos,
  (select count(*) from public.venue_amenities where venue_id::text like '5a11e000-%') as equipements,
  (select count(*) from public.venue_pricing   where venue_id::text like '5a11e000-%') as tarifs,
  (select count(*) from public.venue_blackouts where venue_id::text like '5a11e000-%') as dates_bloquees,
  (select count(*) from public.profiles        where id::text       like 'd0000000-%') as profils,
  (select count(*) from auth.users             where id::text       like 'd0000000-%') as comptes;
