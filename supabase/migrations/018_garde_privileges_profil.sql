-- =============================================================================
-- Ferha — 018_garde_privileges_profil.sql
-- Un compte ne se donne pas de droits à lui-même (§9).
--
-- CE QUE CE FICHIER CORRIGE, ET C'ÉTAIT OUVERT
--
-- `profiles_update_self` (002) autorise un compte à modifier SA ligne :
--
--   using (id = auth.uid()) with check (id = auth.uid())
--
-- Cette politique dit QUELLE LIGNE on peut écrire. Elle ne dit rien de ce qu'on
-- peut y écrire — et `profiles` porte deux colonnes qui ne sont pas des
-- données, mais des DROITS : `is_admin` et `is_owner`. N'importe quel compte
-- connecté pouvait donc faire, avec la seule clé anon et son jeton :
--
--   update public.profiles set is_admin = true where id = auth.uid();
--
-- Ce qu'il obtenait n'était pas cosmétique. `is_admin()` (002) devient vrai, et
-- avec elle :
--
--   * `profiles_select_self` s'élargit — « using (id = auth.uid() or
--     is_admin()) » — et le compte lit TOUS les profils : nom entier, e-mail,
--     téléphone de chaque utilisateur de la plateforme. Mesuré avant ce
--     correctif : neuf profils sur neuf.
--   * `venues_guard_status` (001) laisse passer les administrateurs, donc le
--     compte publie n'importe quelle salle — celle des autres comprise — en
--     court-circuitant le contrôle humain d'ADM-01.
--
-- LA POLITIQUE N'ÉTAIT PAS LE BON ENDROIT POUR LE DIRE, et c'est pourquoi le
-- correctif est un trigger. Un `WITH CHECK` ne voit que la ligne d'ARRIVÉE : il
-- ne peut pas distinguer « ce compte était déjà administrateur » de « ce compte
-- vient de se déclarer administrateur ». C'est exactement le raisonnement déjà
-- écrit en 001 pour `venues_guard_status`, et le même remède.
--
-- QUI PASSE ENCORE
--
--   * Le rôle de service — `auth.uid()` est null. Les migrations, le
--     déclencheur d'inscription de 007 et le futur back-office en ont besoin,
--     et c'est par lui que le PREMIER administrateur est créé. Il n'y a pas
--     d'autre chemin, et c'est le point.
--   * Un administrateur déjà en place. Promouvoir ou révoquer quelqu'un est un
--     geste d'administration ; ce qu'on ferme ici, c'est de le devenir soi-même.
--
-- ET `is_owner` NE SE DÉCLARE PLUS, IL SE CONSTATE. Le drapeau ne peut se lever
-- que sur un compte qui possède RÉELLEMENT une salle. `creer_salle()` (017)
-- continue donc de fonctionner sans une ligne de changement : elle insère la
-- salle avant de lever le drapeau, si bien que la condition est déjà vraie
-- quand le trigger la vérifie. Un compte qui ne possède rien, lui, ne peut plus
-- se dire propriétaire.
--
-- `is_owner` n'ouvrait aucun droit — `owner_venues()` ne connaît que
-- `venues.owner_id`, et toutes les fonctions de l'espace propriétaire passent
-- par `owns_venue()`. Le verrouiller ne bouche donc pas une faille : cela
-- empêche la base de porter une affirmation fausse, ce qui est une raison
-- suffisante.
--
-- CE FICHIER NE CHANGE RIEN CÔTÉ FLUTTER. L'application ne fait que LIRE ces
-- deux colonnes (`auth_providers.dart`, `profil_screen.dart`) ; aucun écran
-- n'en écrit une.
--
-- Rejouable : la fonction et le trigger sont remplacés.
-- Dépend de : 001 (profiles), 002 (is_admin), 017 (creer_salle, qui lève
--             is_owner et dont ce trigger ne doit pas casser le chemin).
-- =============================================================================

create or replace function public.profiles_guard_privileges()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Le rôle de service passe : migrations, déclencheur d'inscription (007),
  -- back-office à venir. C'est aussi par lui, et par lui seul, que le premier
  -- administrateur existe.
  if auth.uid() is null then
    return new;
  end if;

  -- Un administrateur en place promeut et révoque : c'est son métier. On ferme
  -- l'entrée, pas la fonction.
  if public.is_admin() then
    return new;
  end if;

  -- ---------------------------------------------------------------------------
  -- À l'insertion : les deux drapeaux naissent faux, quoi qu'on écrive.
  --
  -- Le cas ne devrait pas se présenter — `handle_new_user()` (007) crée déjà la
  -- ligne, en rôle de service, et il n'y a pas de politique DELETE sur
  -- `profiles`. Mais `profiles_insert_self` existe, et une porte qu'on laisse
  -- ouverte parce qu'on croit que personne ne l'emprunte finit par servir.
  --
  -- On CORRIGE plutôt qu'on ne refuse : si un jour l'inscription doit se
  -- rattraper côté client, elle ne doit pas échouer sur un drapeau qu'elle
  -- n'avait pas l'intention de poser.
  -- ---------------------------------------------------------------------------
  if tg_op = 'INSERT' then
    new.is_admin := false;
    new.is_owner := false;
    return new;
  end if;

  -- ---------------------------------------------------------------------------
  -- À la mise à jour : `is_admin` ne bouge pas. Jamais, dans aucun sens.
  -- ---------------------------------------------------------------------------
  if new.is_admin is distinct from old.is_admin then
    raise exception
      'Un compte ne peut pas modifier ses droits d''administration.'
      using errcode = 'check_violation';
  end if;

  -- ---------------------------------------------------------------------------
  -- `is_owner` se constate, il ne se déclare pas.
  -- ---------------------------------------------------------------------------
  if new.is_owner and not old.is_owner then
    -- La condition est déjà vraie quand `creer_salle()` (017) arrive ici :
    -- elle insère la salle, puis lève le drapeau, dans la même transaction.
    if not exists (
      select 1 from public.venues v where v.owner_id = new.id
    ) then
      raise exception
        'Un compte ne devient propriétaire qu''en inscrivant une salle.'
        using errcode = 'check_violation';
    end if;
  end if;

  if old.is_owner and not new.is_owner then
    -- Retirer le drapeau ne se fait pas depuis l'application : la salle
    -- resterait, et son propriétaire n'aurait plus de chemin vers elle.
    raise exception
      'Le statut de propriétaire ne se retire pas depuis l''application.'
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

comment on function public.profiles_guard_privileges() is
  'Interdit à un compte de se donner is_admin, et de se déclarer is_owner sans posséder de salle (§9). '
  'Un WITH CHECK ne voyant que la ligne d''arrivée, la règle vit dans un trigger — même raison qu''en 001.';

drop trigger if exists profiles_guard_privileges on public.profiles;
create trigger profiles_guard_privileges
  before insert or update on public.profiles
  for each row execute function public.profiles_guard_privileges();
