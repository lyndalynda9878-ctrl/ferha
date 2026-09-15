-- =============================================================================
-- Ferha — 034_gardien_des_empreintes.sql
-- Le service d'empreintes ne s'endort plus (J25).
--
-- CE QUE CE FICHIER APPORTE
--
--   gardien_empreintes        le journal des réveils, avec les VRAIES réponses
--   reveiller_empreintes()    relève la réponse précédente, puis frappe à /health
--   etat_du_gardien           une ligne qui dit si le gardien tient encore
--   ferha-reveil-empreintes   la tâche pg_cron, toutes les 5 minutes
--
-- POURQUOI UN GARDIEN. Render endort l'offre gratuite. Mesuré au J25 : le
-- premier appel après deux heures de silence coûte **62 s**, et l'instance met
-- ensuite plusieurs minutes à atteindre son régime sur 0,1 vCPU. À chaud, le
-- même appel coûte 85 à 573 ms. Une démonstration ouverte à froid fait donc
-- attendre son premier visiteur une minute — sauf si quelqu'un a frappé avant
-- lui.
--
-- LA MIGRATION 033 A DÉJÀ BORNÉ LE PIRE CAS côté application : `ai-chat`
-- abandonne le service au bout de 2 s et répond sans vecteur. Ce fichier-ci ne
-- répare donc pas une panne, il rend sa qualité au service : le classement
-- sémantique est là parce que le service est chaud, et non parce que le
-- visiteur a eu de la chance. Les deux se complètent et aucun ne remplace
-- l'autre.
--
-- POURQUOI TOUTES LES 5 MINUTES. Render annonce un endormissement à 15 minutes.
-- Mes mesures ne l'ont pas vérifié — elles montrent seulement qu'à 2 minutes de
-- silence le service répond encore en 348 ms, et qu'à 2 heures il est froid. 5
-- minutes laissent donc trois fois la marge sur la valeur annoncée. Et comme
-- pg_cron ne coûte rien à l'appel, la fréquence n'est pas un arbitrage
-- budgétaire : 288 appels par jour ne se paient nulle part.
--
-- POURQUOI PAS GITHUB ACTIONS. Un dépôt privé est plafonné à 2 000 minutes par
-- mois. Une exécution toutes les 5 minutes en consommerait plus de 8 000. Ici,
-- pg_cron et pg_net sont déjà installés et éprouvés : 461 exécutions du job
-- `ferha-expire-options` depuis le 11 septembre, 100 % réussies, aucune
-- manquée. Ce gardien n'ajoute donc AUCUNE dépendance.
--
-- ET POURQUOI PAS UN pg_cron POUR RÉVEILLER SUPABASE LUI-MÊME : un pg_cron ne
-- tourne pas dans un projet en pause. Tenir Supabase éveillé est un autre
-- problème, et il se traite de dehors.
--
-- ON RELÈVE À LA PASSE SUIVANTE, et c'est la seule subtilité du fichier.
-- `net.http_get()` ne fait que DÉPOSER la requête : un travailleur l'émet
-- ensuite, hors de notre transaction, et la réponse n'existe donc pas encore
-- quand la fonction rend la main. Chaque passage relève la réponse du passage
-- précédent, puis dépose la sienne. Une réponse est donc journalisée avec
-- 5 minutes de retard — sans importance pour ce qu'on en fait.
--
-- L'URL N'EST PAS UN SECRET, et elle est déjà dans le dépôt
-- (`supabase/functions/embed-venue/index.ts`). On la lit quand même dans le
-- Vault en premier, pour qu'une autre instance Render se règle sans toucher au
-- SQL ; à défaut on retombe sur celle du dépôt, pour qu'un projet recréé
-- reparte avec son gardien sans qu'on ait à poser quoi que ce soit. `/health`
-- ne demande aucun jeton — c'est écrit dans services/embeddings/README.md, et
-- c'est ce qui rend ce fichier possible sans clé.
--
-- Rejouable : la table est `if not exists`, la fonction est remplacée, la
-- tâche est décrochée avant d'être reposée.
-- Dépend de : pg_cron et pg_net (déjà installés), vault (facultatif).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Le journal des réveils
--
-- IL EXISTE PARCE QUE cron.job_run_details NE SUFFIT PAS. Celui-ci dit que la
-- tâche s'est exécutée, pas que le service a répondu : une tâche qui dépose une
-- requête vers une adresse morte est enregistrée « succeeded ». C'est
-- exactement le piège qu'on veut éviter — un voyant vert au-dessus d'un service
-- éteint.
--
-- On garde donc le CODE HTTP et le CORPS rendus par le service. `net`
-- _http_response, lui, est purgé par pg_net à son propre rythme : on n'y laisse
-- pas nos preuves.
-- -----------------------------------------------------------------------------

create table if not exists public.gardien_empreintes (
  id          bigserial primary key,
  demande_id  bigint      not null,
  emise_a     timestamptz not null default now(),
  relevee_a   timestamptz,
  status_code integer,
  timed_out   boolean,
  erreur      text,
  contenu     text
);

comment on table public.gardien_empreintes is
  'Journal des réveils du service d''empreintes (J25). Garde la VRAIE réponse — '
  'code HTTP et corps — parce que cron.job_run_details ne dit que si la tâche a '
  'tourné, jamais si le service a répondu. Relevée à la passe suivante : pg_net '
  'est asynchrone.';

create index if not exists gardien_empreintes_emise_a_idx
  on public.gardien_empreintes (emise_a desc);

-- CETTE TABLE NE REGARDE PERSONNE D'AUTRE QUE L'EXPLOITATION. RLS active sans
-- aucune politique : personne ne lit, pas même un compte connecté. Le rôle de
-- service passe outre, et c'est le seul qui en a besoin.
alter table public.gardien_empreintes enable row level security;

revoke all on public.gardien_empreintes from anon, authenticated;

-- -----------------------------------------------------------------------------
-- reveiller_empreintes — relever, puis frapper
-- -----------------------------------------------------------------------------

create or replace function public.reveiller_empreintes()
returns bigint
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_url     text;
  v_requete bigint;
begin
  -- 1. RELEVER CE QUI ATTEND. On rapatrie la réponse de la passe précédente
  --    avant d'en déposer une neuve.
  update public.gardien_empreintes g
     set relevee_a   = now(),
         status_code = r.status_code,
         timed_out   = r.timed_out,
         erreur      = r.error_msg,
         contenu     = left(r.content, 500)
    from net._http_response r
   where r.id = g.demande_id
     and g.relevee_a is null;

  -- UNE RÉPONSE QUI NE VIENDRA PLUS est close explicitement. Sans cela une
  -- ligne muette resterait « en attente » pour toujours, et l'on ne saurait pas
  -- distinguer « pas encore revenue » de « perdue ». pg_net purge ses réponses
  -- à son rythme ; au-delà d'un quart d'heure, il n'y a plus rien à espérer.
  update public.gardien_empreintes
     set relevee_a = now(),
         erreur    = 'réponse absente de pg_net au moment du relevé'
   where relevee_a is null
     and emise_a < now() - interval '15 minutes';

  -- 2. L'ADRESSE. Le Vault d'abord, le dépôt ensuite — voir l'en-tête.
  select decrypted_secret into v_url
    from vault.decrypted_secrets
   where name = 'ferha_embeddings_url';

  v_url := coalesce(nullif(trim(v_url), ''), 'https://ferha-embeddings.onrender.com');

  -- 3. FRAPPER. Le délai est celui de pg_net, pas celui du service : on ne fait
  --    que déposer. 120 s laissent la place à un démarrage à froid (62 s
  --    mesurées), sans quoi le gardien abandonnerait précisément le jour où il
  --    sert à quelque chose.
  select net.http_get(
           url                  => rtrim(v_url, '/') || '/health',
           timeout_milliseconds => 120000)
    into v_requete;

  insert into public.gardien_empreintes (demande_id) values (v_requete);

  -- 4. NE PAS GARDER L'HISTOIRE ENTIÈRE. Sept jours suffisent à voir une panne
  --    et à la dater ; au-delà, c'est 2 000 lignes par semaine pour rien.
  delete from public.gardien_empreintes
   where emise_a < now() - interval '7 days';

  return v_requete;
end;
$$;

comment on function public.reveiller_empreintes() is
  'Tâche pg_cron (J25) : tient le service d''empreintes éveillé en frappant /health. '
  'Relève d''abord la réponse de la passe précédente — pg_net est asynchrone — puis '
  'dépose la sienne et purge au-delà de sept jours. Rend l''identifiant de requête '
  'pg_net. Rôle de service uniquement.';

revoke execute on function public.reveiller_empreintes()
  from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- etat_du_gardien — la seule requête à lire pour savoir s'il tient
--
-- UNE VUE, ET NON UNE REQUÊTE À RETENIR. Le jour où le service tombe, on ne se
-- souviendra pas de la jointure : on se souviendra d'un nom.
--
-- ELLE N'EST PAS PUBLIQUE. Contrairement à `venue_availability`, elle ne montre
-- rien qu'un inconnu ait à voir : on révoque explicitement.
-- -----------------------------------------------------------------------------

create or replace view public.etat_du_gardien as
select
  (select max(emise_a) from public.gardien_empreintes)                    as derniere_frappe,
  (select max(emise_a) from public.gardien_empreintes
    where status_code = 200)                                             as derniere_reussite,
  (select now() - max(emise_a) from public.gardien_empreintes
    where status_code = 200)                                             as depuis_la_derniere_reussite,
  (select count(*) from public.gardien_empreintes
    where emise_a > now() - interval '24 hours')                         as frappes_24h,
  (select count(*) from public.gardien_empreintes
    where emise_a > now() - interval '24 hours' and status_code = 200)    as reussites_24h,
  (select count(*) from public.gardien_empreintes
    where emise_a > now() - interval '24 hours'
      and relevee_a is not null and status_code is distinct from 200)     as echecs_24h,
  (select contenu from public.gardien_empreintes
    where relevee_a is not null order by emise_a desc limit 1)            as dernier_corps,
  (select erreur from public.gardien_empreintes
    where relevee_a is not null order by emise_a desc limit 1)            as derniere_erreur;

comment on view public.etat_du_gardien is
  'L''état du réveil des empreintes, en une ligne. `derniere_reussite` et '
  '`dernier_corps` sont ce qui compte : ils viennent du SERVICE, pas de pg_cron. '
  'Un job vert au-dessus d''un service mort se voit ici, et nulle part ailleurs.';

revoke all on public.etat_du_gardien from anon, authenticated;

-- -----------------------------------------------------------------------------
-- La tâche
--
-- REJOUABLE : on décroche explicitement avant de reposer, comme
-- `ferha-synthese-avis` (032). Le comportement du remplacement dépend de la
-- version de pg_cron, celui de ces lignes non.
-- -----------------------------------------------------------------------------

grant usage on schema cron to postgres;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'ferha-reveil-empreintes') then
    perform cron.unschedule('ferha-reveil-empreintes');
  end if;
end $$;

select cron.schedule(
  'ferha-reveil-empreintes',
  '*/5 * * * *',
  $cron$select public.reveiller_empreintes();$cron$
);
