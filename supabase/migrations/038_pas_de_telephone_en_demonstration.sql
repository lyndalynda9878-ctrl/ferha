-- =============================================================================
-- Ferha — 038_pas_de_telephone_en_demonstration.sql
-- Un compte de démonstration ne PEUT PAS porter de numéro de téléphone (J26).
--
-- L'INCIDENT, EN UNE PHRASE. Le 17 septembre 2026 à 15 h 36, un vrai numéro de
-- mobile algérien s'est affiché sur ferha.pages.dev, dans le bloc « Le contact »
-- de l'espace propriétaire. Il avait été tapé trois minutes plus tôt sur
-- l'écran 5 par quelqu'un qui suivait le parcours du README, connecté avec le
-- bouton « Entrer comme Amina ». `request_booking()` l'avait rangé dans
-- `profiles.phone` du compte partagé ; `booking_contact()` l'avait ensuite
-- révélé, très correctement, parce que la réservation était confirmée.
--
-- RIEN N'ÉTAIT CASSÉ. Le §9 a fonctionné. Les seeds posent bien `phone = null`
-- (seed/003_demo_accounts.sql, ligne 235). L'empreinte du décor portait NULL
-- pour les huit personnes. Le ménage aurait effacé le numéro de lui-même au
-- passage de 18 h 10. Tout était juste, et un numéro appartenant peut-être à un
-- inconnu est quand même resté lisible en ligne pendant un temps.
--
-- LE DÉFAUT N'EST DONC PAS UN BOGUE, C'EST UNE COMBINAISON : un compte partagé,
-- plus un champ de coordonnées obligatoire. Le second remplit le premier. Aucun
-- des deux n'est fautif seul.
--
-- -----------------------------------------------------------------------------
-- POURQUOI UN DÉCLENCHEUR, ET PAS UN GARDE DANS request_booking()
--
-- Parce qu'il y a plusieurs portes, et qu'on en aurait bouché une :
--
--   * request_booking()             (020, ligne 557) — l'écran 5 ;
--   * envoyer_salle_en_validation() (021, ligne 666) — la publication d'une
--     salle, qui exige elle aussi « un propriétaire joignable » ;
--   * handle_new_user()             (007, ligne 75)  — le numéro des métadonnées
--     d'inscription ;
--   * la politique `profiles_update_self`, qui laisse tout compte connecté
--     écrire sa propre ligne directement par PostgREST, sans passer par aucune
--     de ces fonctions.
--
-- Trois fonctions et une porte ouverte sur la table elle-même. Un garde par
-- porte, c'est trois endroits à ne pas oublier aujourd'hui et un quatrième à
-- oublier demain. Le déclencheur est en dessous de toutes : il n'y a plus de
-- chemin qui contourne.
--
-- IL FORCE, IL NE REFUSE PAS. Une contrainte CHECK dirait non, et
-- `request_booking()` lèverait une exception : le parcours du testeur
-- s'arrêterait net sur l'écran 5. Or la demande doit aboutir — c'est le numéro,
-- et lui seul, qui ne doit pas se déposer. Le déclencheur met donc `phone` à
-- NULL et laisse l'écriture passer.
--
-- LES DEUX CHAMPS VOYAGENT ENSEMBLE. `profiles_phone_verified_requires_phone`
-- interdit `phone_verified = true` sans numéro :
--
--     CHECK ((NOT phone_verified) OR (phone IS NOT NULL))
--
-- Mettre `phone` à NULL sans toucher à `phone_verified` ferait donc échouer
-- l'écriture sur une ligne qui portait un numéro vérifié — exactement le refus
-- qu'on cherche à éviter. Les deux sont remis ensemble, dans le même geste.
--
-- LE CRITÈRE N'EST PAS INVENTÉ ICI. `id::text like 'd0000000-%'` est la
-- convention posée par seed/003_demo_accounts.sql et reprise telle quelle par
-- le ménage du décor — 035 lignes 684 et 770, 036 lignes 199, 472 et 618. Elle
-- est recopiée et non encapsulée dans une fonction, pour que ce fichier et le
-- ménage disent LE MÊME texte : deux définitions divergeraient un jour.
--
-- IL EXISTE UN TROISIÈME EXEMPLAIRE, ET IL EST EN DART :
--
--     lib/features/auth/demo_accounts.dart
--       const String prefixeCompteDemonstration = 'd0000000-';
--       bool estCompteDeDemonstration(String? idUtilisateur)
--
-- Il ne protège rien — la protection, c'est le déclencheur ci-dessous. Il sert
-- à DIRE à la personne que son numéro ne sera pas gardé, sur l'écran de demande
-- (écran 5) et sur le récapitulatif de publication d'une salle. Si le préfixe
-- change ici sans changer là-bas, l'application promettra une chose et la base
-- en fera une autre : c'est exactement le mensonge que ce fichier répare.
-- Le commentaire symétrique se trouve dans demo_accounts.dart.
--
-- L'ORDRE DES DÉCLENCHEURS. PostgreSQL les appelle par ordre alphabétique, à
-- timing égal. Sur `profiles`, cela donne :
--
--     profiles_guard_privileges                    (018)
--     profiles_normalise_telephone                 (020)
--     profiles_pas_de_telephone_en_demonstration   (celui-ci)
--     profiles_set_updated_at                      (001)
--
-- Celui-ci passe APRÈS la normalisation, donc en dernier sur `phone` : rien ne
-- peut plus y remettre une valeur derrière lui. Le nom a été choisi pour cela.
-- Les deux ordres seraient corrects aujourd'hui ; celui-ci le restera si un
-- quatrième déclencheur arrive.
--
-- CE QU'IL NE FAIT PAS. Il ne touche ni `full_name`, ni `email`, ni `locale` :
-- l'empreinte du décor les porte et le ménage les remet (036). Il ne touche à
-- aucun compte réel — un vrai client garde son numéro, c'est chez lui qu'il
-- sert.
--
-- Dépend de : 001 (profiles), 018 (profiles_guard_privileges), 020
--             (profiles_normalise_telephone, telephone_valide).
-- =============================================================================

create or replace function public.profiles_pas_de_telephone_en_demonstration()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  -- La convention du décor, mot pour mot comme en 035 et 036.
  if new.id::text like 'd0000000-%' then
    -- Les deux ensemble, jamais l'un sans l'autre : voir l'en-tête et
    -- profiles_phone_verified_requires_phone.
    new.phone          := null;
    new.phone_verified := false;
  end if;

  return new;
end;
$$;

comment on function public.profiles_pas_de_telephone_en_demonstration() is
  'Force phone à NULL et phone_verified à false sur les comptes de démonstration (d0000000-…). '
  'Force, ne refuse pas : la demande de l''écran 5 doit aboutir, c''est le numéro qui ne doit pas '
  'se déposer. Un numéro algérien bien formé appartient à quelqu''un, et la démonstration est en ligne.';

drop trigger if exists profiles_pas_de_telephone_en_demonstration on public.profiles;

create trigger profiles_pas_de_telephone_en_demonstration
  before insert or update on public.profiles
  for each row
  execute function public.profiles_pas_de_telephone_en_demonstration();

-- -----------------------------------------------------------------------------
-- Le rattrapage — ce qui est déjà en base
--
-- Le déclencheur ne regarde que les écritures à venir. La ligne posée le
-- 17 septembre a été remise à NULL à la main à 15 h 50 ; ce bloc rend le fichier
-- complet pour une base qui n'aurait pas reçu ce geste, et ne fait rien ici.
-- -----------------------------------------------------------------------------

update public.profiles
   set phone = null, phone_verified = false
 where id::text like 'd0000000-%'
   and (phone is not null or phone_verified);

-- -----------------------------------------------------------------------------
-- Le bloc de preuve
-- -----------------------------------------------------------------------------

do $$
declare
  v_comptes  integer;
  v_avec_tel integer;
  v_declench integer;
begin
  select count(*) into v_comptes
  from public.profiles where id::text like 'd0000000-%';

  select count(*) into v_avec_tel
  from public.profiles
  where id::text like 'd0000000-%' and (phone is not null or phone_verified);

  select count(*) into v_declench
  from pg_trigger t join pg_class c on c.oid = t.tgrelid
  where c.relname = 'profiles'
    and t.tgname = 'profiles_pas_de_telephone_en_demonstration';

  raise notice 'Comptes de démonstration : %. Avec un numéro : %. Déclencheur en place : %.',
    v_comptes, v_avec_tel, v_declench;

  if v_avec_tel <> 0 then
    raise exception 'ÉCHEC — % compte(s) de démonstration portent encore un numéro.', v_avec_tel;
  end if;

  if v_declench <> 1 then
    raise exception 'ÉCHEC — le déclencheur n''est pas en place.';
  end if;
end $$;

select
  (select count(*) from public.profiles where id::text like 'd0000000-%')   as comptes_de_demonstration,
  (select count(*) from public.profiles
    where id::text like 'd0000000-%' and phone is not null)                 as avec_un_numero,
  (select count(*) from pg_trigger t join pg_class c on c.oid = t.tgrelid
    where c.relname = 'profiles'
      and t.tgname = 'profiles_pas_de_telephone_en_demonstration')          as declencheur;
