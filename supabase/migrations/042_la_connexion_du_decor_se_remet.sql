-- =============================================================================
-- Ferha — 042_la_connexion_du_decor_se_remet.sql
-- Toutes les heures, le mot de passe et l'adresse de connexion d'Amina et de
-- Karim reviennent à ceux des boutons « Entrer comme… ».
--
-- LA CEINTURE, PAS LES BRETELLES. Les bretelles, c'est 041 : le déclencheur
-- empêche GoTrue de changer ces colonnes. Ce fichier ne sert que le jour où
-- elles lâcheraient — 041 supprimé pour un diagnostic et oublié, une version de
-- GoTrue qui écrirait sous un autre rôle, une restauration de sauvegarde. Ce
-- jour-là, les boutons resteraient cassés au plus une heure, pas pour toujours.
--
-- POURQUOI UNE FONCTION À PART, ET NON UNE SEPTIÈME ÉTAPE DE menage_du_decor().
-- Le ménage (035, 036, 039) fait treize kilo-octets, et ses colonnes de sortie
-- sont lues par etat_du_decor : y ajouter une étape oblige à le réécrire en
-- entier et à changer son type de retour. Et surtout, une ceinture qui dépend
-- des bretelles n'en est pas une : si le ménage s'arrête sur une empreinte
-- périmée (ses deux `return` du début), les boutons doivent quand même revenir.
-- D'où une fonction courte, et sa propre tâche cron.
--
-- LES DEUX COMPTES SONT NOMMÉS, et ce n'est pas une donnée de salle : ce sont
-- exactement ceux de lib/features/auth/demo_accounts.dart et de seed/003. Les
-- six autres personnes du décor n'ont pas de mot de passe et ne doivent pas en
-- recevoir un : le critère `d0000000-%` seul leur en donnerait un.
--
-- `demo1234` N'EST PAS UN SECRET. Il est écrit en clair dans l'application,
-- exprès (voir demo_accounts.dart) : ce sont des comptes publics.
--
-- ON N'ÉCRIT QUE CE QUI A BOUGÉ. Un hachage bcrypt neuf à chaque passe
-- changerait la ligne toutes les heures pour rien. On compare d'abord ; le
-- `case` protège crypt() d'un hachage vide, qui lèverait « invalid salt ».
--
-- L'ADRESSE VIENT DE decor_profiles (036), pas d'un littéral : c'est là que le
-- décor dit qui est Amina, et le ménage remet `profiles.email` à la même valeur.
--
-- LE DÉCLENCHEUR DE 041 LAISSE PASSER : la tâche tourne en `postgres`.
--
-- Dépend de : seed/003 (les comptes), 036 (decor_profiles), 041.
-- =============================================================================

create or replace function public.remettre_la_connexion_du_decor()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_remis integer;
begin
  update auth.users u
     set encrypted_password = case
           when u.encrypted_password like '$2%'
            and u.encrypted_password = extensions.crypt('demo1234', u.encrypted_password)
           then u.encrypted_password
           else extensions.crypt('demo1234', extensions.gen_salt('bf'))
         end,
         email      = e.email,
         updated_at = now()
    from public.decor_profiles e
   where e.id = u.id
     and u.id in ('d0000000-0000-4000-a000-000000000010',   -- Amina
                  'd0000000-0000-4000-a000-000000000001')   -- Karim
     and (u.email is distinct from e.email
          or case
               when u.encrypted_password like '$2%'
               then u.encrypted_password <> extensions.crypt('demo1234', u.encrypted_password)
               else true
             end);
  get diagnostics v_remis = row_count;

  return v_remis;
end;
$$;

comment on function public.remettre_la_connexion_du_decor() is
  'Remet demo1234 et l''adresse du décor sur Amina et Karim s''ils ont bougé. Ceinture de '
  '041, sous sa propre tâche cron. Renvoie le nombre de comptes remis.';

revoke execute on function public.remettre_la_connexion_du_decor() from public, anon, authenticated;

-- À la minute 12 : après le ménage (minute 10), pour ne pas se marcher dessus
-- dans les journaux. L'ordre n'a pas d'effet sur le résultat.
do $$
begin
  if exists (select 1 from cron.job where jobname = 'ferha-connexion-du-decor') then
    perform cron.unschedule('ferha-connexion-du-decor');
  end if;
end $$;

select cron.schedule(
  'ferha-connexion-du-decor',
  '12 * * * *',
  $cron$select public.remettre_la_connexion_du_decor();$cron$
);

-- -----------------------------------------------------------------------------
-- Le bloc de preuve
-- -----------------------------------------------------------------------------

do $$
declare
  v_remis   integer;
  v_bons    integer;
  v_tache   integer;
begin
  v_remis := public.remettre_la_connexion_du_decor();

  select count(*) into v_bons
  from auth.users u
  join public.decor_profiles e on e.id = u.id
  where u.id in ('d0000000-0000-4000-a000-000000000010',
                 'd0000000-0000-4000-a000-000000000001')
    and u.email = e.email
    and u.encrypted_password like '$2%'
    and u.encrypted_password = extensions.crypt('demo1234', u.encrypted_password);

  select count(*) into v_tache from cron.job where jobname = 'ferha-connexion-du-decor';

  raise notice 'Comptes remis à l''instant : %. Comptes conformes : %/2. Tâche cron : %.',
    v_remis, v_bons, v_tache;

  if v_bons <> 2 then
    raise exception 'ÉCHEC — % compte(s) de démonstration sur 2 se connectent avec demo1234.', v_bons;
  end if;

  if v_tache <> 1 then
    raise exception 'ÉCHEC — la tâche cron n''est pas planifiée.';
  end if;
end $$;
