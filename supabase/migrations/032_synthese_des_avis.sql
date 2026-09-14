-- =============================================================================
-- Ferha — 032_synthese_des_avis.sql
-- La synthèse des avis : le bloc « ✦ Synthèse des 34 avis » de l'écran 7
-- (§8.2, deuxième usage ; §7.2 summarize-reviews).
--
-- CE QUE CE FICHIER POSE : la table qui garde une synthèse par salle, la
-- fonction qui dit LESQUELLES sont à refaire, la porte d'écriture, le bloc
-- ajouté à `avis_de_la_salle()`, et la tâche pg_cron qui réveille l'Edge
-- Function chaque nuit.
--
-- CE QU'IL NE POSE PAS : la synthèse elle-même. Aucun texte n'est rédigé ici. La
-- base RANGE et COMPARE ; c'est « summarize-reviews » qui écrit, à partir du
-- texte des avis et de rien d'autre.
--
-- =============================================================================
-- LE §8.2 DIT « PAS DE RAG », ET C'EST LA CLÉ DE TOUT LE FICHIER
--
-- Les quatre usages de l'agent n'ont pas la même technique. La recherche de
-- salle fouille un catalogue entier, donc vecteur ; la synthèse d'avis lit LES
-- AVIS D'UNE SEULE SALLE, et ils tiennent tous dans le contexte. Il n'y a rien à
-- chercher, rien à classer, rien à rapprocher. Le §8.2 l'écrit en toutes
-- lettres : « Pas de RAG : tous les avis tiennent dans le contexte. Résumé
-- pré-calculé la nuit et stocké. »
--
-- D'où l'absence totale de `venue_embeddings` dans ce fichier. La synthèse ne
-- doit rien à l'index sémantique — elle partage seulement sa DISCIPLINE, celle
-- du hachage, et c'est la section suivante.
--
-- =============================================================================
-- « SEULEMENT LES SALLES DONT LES AVIS ONT CHANGÉ » — UN HACHAGE, COMME EN 027
--
-- Le quota gratuit est limité. Repasser chaque nuit sur quinze salles dont
-- aucune n'a bougé, c'est quinze appels pour quinze textes identiques — et le
-- jour où le catalogue en compte trois cents, c'est le quota d'une semaine
-- dépensé en une nuit.
--
-- ON POUVAIT COMPTER LES AVIS, ET C'AURAIT ÉTÉ FAUX. Un compteur ne voit ni un
-- avis CORRIGÉ — le §5.4 laisse trente jours pour se relire — ni un avis
-- supprimé et remplacé le même jour. La synthèse resterait celle d'un texte que
-- plus personne ne lit.
--
-- ON HACHE DONC CE QU'ON RÉSUME, exactement comme `document_salle()` hache ce
-- qu'elle vectorise : identifiant, note et texte de chaque avis, dans un ordre
-- STABLE. Un mot corrigé change le hachage ; une réécriture de table, non.
--
-- LE MODÈLE ENTRE DANS LA COMPARAISON, comme en 027 et pour la même raison :
-- changer de modèle, c'est changer ce qui serait écrit, donc tout refaire.
--
-- =============================================================================
-- PAS DE SYNTHÈSE SOUS TROIS AVIS
--
-- « On ne résume pas deux phrases. » Un résumé de deux avis n'est pas un résumé :
-- c'est une paraphrase, plus longue que l'original et moins fidèle. Pire, il
-- donne au lecteur l'impression d'une tendance là où il n'y a que deux soirées.
--
-- LE SEUIL EST ÉCRIT UNE FOIS, dans `synthese_avis_minimum()`. Deux gardiens le
-- lisent — celle qui propose le travail et celle qui accepte le résultat — et
-- aucun des deux ne porte le chiffre. Le déplacer demande de toucher une ligne.
--
-- ON COMPTE LES AVIS QUI PORTENT DU TEXTE, et non les avis. Une note sans
-- commentaire ne donne rien à résumer : trois étoiles muettes et deux phrases
-- feraient « trois avis » au compteur et deux phrases au modèle. C'est le texte
-- qui est la matière, donc c'est le texte qu'on compte.
--
-- =============================================================================
-- CE QUI NE SORT PAS D'ICI : LE NOM DES CLIENTS
--
-- `avis_pour_synthese()` rend la note, la date et le corps de chaque avis. Pas
-- l'auteur, pas même abrégé. Ce n'est pas une consigne donnée au modèle, c'est
-- une absence : il ne peut pas écrire « Sarah B. a trouvé la salle froide »
-- parce qu'il n'a jamais lu « Sarah B. ».
--
-- C'est la même discipline que le §8.5 applique aux salles — un garde-fou vaut
-- mieux qu'une consigne, et une donnée absente vaut mieux qu'un garde-fou.
--
-- =============================================================================
-- LA TABLE EST FERMÉE, COMME venue_embeddings
--
-- RLS active, AUCUNE POLITIQUE : la table est vide pour tout le monde sauf pour
-- `service_role` et pour les fonctions SECURITY DEFINER. Elle ne sort que par
-- `avis_de_la_salle()`, qui borne déjà ce qui se lit par `can_read_venue()`.
--
-- POURQUOI FERMER CE QUI EST PUBLIC ? Parce que la table contiendra AUSSI la
-- synthèse d'une salle suspendue ou dépubliée le jour où l'une le sera, et que
-- l'ouvrir en lecture directe créerait une seconde porte à tenir d'accord avec
-- la première. Une table technique se ferme par défaut.
--
-- LA SUPPRESSION EST EN CASCADE, comme les empreintes et pour la même raison :
-- une synthèse est un CALCUL, pas une trace comptable. Elle se refait. C'est
-- `bookings` qui est en RESTRICT, parce qu'une réservation, elle, ne se refait
-- pas.
--
-- Dépend de : 001 (venues), 002 (can_read_venue), 004 (reviews, venue_ratings),
--             022 (pg_cron), 026 (avis_de_la_salle, qu'on redéfinit).
--
-- Rejouable : extensions et table conditionnelles, fonctions remplacées, tâche
-- pg_cron décrochée avant d'être reposée.
-- =============================================================================

-- Le hachage vient de pgcrypto, déjà posée dans `extensions` (001).
create extension if not exists pgcrypto with schema extensions;

-- L'appel HTTP de la tâche nocturne. Voir la section 6.
--
-- ELLE RESTE DANS `public`, ET CE N'EST PAS UN OUBLI. Le linter de Supabase la
-- signale — « extension in public » — et on ne peut pas la déplacer : pg_net est
-- déclarée NON RELOCALISABLE (`extrelocatable = false`), et `alter extension …
-- set schema` la refuse.
--
-- Ce qui est signalé est la seule NAMESPACE D'ENREGISTREMENT de l'extension.
-- Aucun de ses quinze objets n'atterrit dans `public` : ils vivent tous dans le
-- schéma `net`, que l'extension crée elle-même. C'est pourquoi tous les appels
-- ci-dessous s'écrivent `net.http_post`, et non `public.http_post`.
create extension if not exists pg_net;

-- =============================================================================
-- 1. venue_review_summaries — une synthèse par salle
-- =============================================================================

create table if not exists public.venue_review_summaries (
  venue_id     uuid primary key
                 references public.venues(id) on delete cascade,

  -- Le texte affiché sous les notes, dans l'écran 7.
  summary      text not null,

  -- Combien d'avis PORTANT DU TEXTE ont nourri cette synthèse. Affiché avec
  -- elle — « Synthèse des 34 avis » — et jamais recalculé côté application :
  -- le nombre d'avis d'aujourd'hui n'est pas celui d'où vient ce texte.
  review_count integer not null check (review_count >= 0),

  -- SHA-256 des avis résumés. C'est lui qui évite de rappeler le modèle pour
  -- rien, et lui qui détecte un avis corrigé. Voir l'en-tête.
  source_hash  text not null,

  -- Le modèle qui a rédigé. Un changement de modèle refait tout.
  model        text not null,

  updated_at   timestamptz not null default now()
);

comment on table public.venue_review_summaries is
  'La synthèse d''avis d''une salle (§8.2), rédigée la nuit par l''Edge Function '
  '« summarize-reviews » et par elle seule. RLS active et aucune politique : '
  'la table ne sort que par avis_de_la_salle(). Jamais moins de '
  'synthese_avis_minimum() avis porteurs de texte.';

comment on column public.venue_review_summaries.source_hash is
  'SHA-256 des avis résumés — identifiant, note et corps, dans un ordre stable. '
  'Un avis ajouté, corrigé ou supprimé le change ; une réécriture de table, non. '
  'C''est la seule chose qui distingue une salle à retraiter d''une salle déjà à '
  'jour, et le quota gratuit en dépend.';

comment on column public.venue_review_summaries.review_count is
  'Le nombre d''avis PORTEURS DE TEXTE d''où vient cette synthèse — pas le '
  'nombre d''avis d''aujourd''hui. C''est ce nombre que l''écran affiche, pour '
  'qu''il corresponde toujours au texte qu''il annonce.';

alter table public.venue_review_summaries enable row level security;

-- =============================================================================
-- 2. synthese_avis_minimum — LE SEUIL, ÉCRIT UNE SEULE FOIS
--
-- Trois. Une fonction plutôt qu'une constante répétée : les deux gardiens la
-- lisent, le test la lit, et déplacer le seuil ne demande de changer qu'ici.
-- =============================================================================

-- `search_path` FIXÉ MÊME ICI, alors que la fonction ne lit rien. C'est la
-- convention du projet, et le linter de Supabase la vérifie : une fonction sans
-- search_path est une fonction dont la résolution dépend de l'appelant. Celle-ci
-- ne risquait rien — elle rend une constante — mais une exception non écrite
-- finit par en appeler d'autres.
create or replace function public.synthese_avis_minimum()
returns integer
language sql
immutable
set search_path = ''
as $$ select 3 $$;

comment on function public.synthese_avis_minimum() is
  'Le nombre minimal d''avis PORTEURS DE TEXTE sous lequel on ne résume pas '
  '(§8.2) : on ne résume pas deux phrases. Lu par avis_pour_synthese() et par '
  'enregistrer_synthese_avis() ; écrit ici et nulle part ailleurs.';

grant execute on function public.synthese_avis_minimum() to anon, authenticated;

-- =============================================================================
-- 3. avis_pour_synthese — CE QUE L'EDGE FUNCTION DEMANDE EN UN SEUL APPEL
--
-- Elle rend, pour chaque salle PUBLIÉE qui atteint le seuil : le texte de ses
-- avis, leur hachage, et si le travail est à refaire. L'Edge Function n'a donc
-- aucune règle à connaître — ni « publiée », ni « trois avis », ni « a changé ».
-- C'est la même division du travail qu'en 027 avec `salles_a_indexer()`, et elle
-- a la même raison : une règle écrite dans le TypeScript serait un second
-- gardien, et celui-là s'oublierait le jour où quelqu'un écrirait un second
-- résumeur.
--
-- `a_refaire` COUVRE TROIS CAS : aucune synthèse, un texte d'avis différent, un
-- modèle différent.
--
-- ELLE REND AUSSI LES SALLES DÉJÀ À JOUR, avec `a_refaire` à faux. L'Edge
-- Function les compte dans son journal sans les traiter : savoir qu'on a
-- regardé quinze salles et rédigé une seule est exactement ce qu'on veut lire au
-- matin.
--
-- `notes_basses` EST UN FAIT, PAS UN JUGEMENT. Combien d'avis à 3 étoiles ou
-- moins. Le modèle ne le calcule pas — il le reçoit —, et l'Edge Function s'en
-- sert pour EXIGER une réserve dans la synthèse quand il y en a. « Un résumé
-- exclusivement flatteur n'est pas cru » (maquettes, écran 7).
-- =============================================================================

create or replace function public.avis_pour_synthese(p_model text)
returns table (
  venue_id     uuid,
  name         text,
  review_count integer,
  notes_basses integer,
  source_hash  text,
  a_refaire    boolean,
  avis         jsonb
)
language sql
stable
security definer
set search_path = public, extensions
as $$
  with textes as (
    -- LES AVIS PORTEURS DE TEXTE, ET EUX SEULS. Une note muette ne donne rien à
    -- résumer ; la compter ferait promettre « trois avis » pour deux phrases.
    select r.venue_id,
           r.id,
           r.rating,
           btrim(r.body) as corps,
           r.created_at
      from public.reviews r
     where nullif(btrim(coalesce(r.body, '')), '') is not null
  ),
  par_salle as (
    select t.venue_id,
           count(*)::integer as nb,
           count(*) filter (where t.rating <= 3)::integer as basses,
           -- L'ORDRE EST STABLE — par identifiant. Sans `order by`, PostgreSQL
           -- rend les lignes comme il l'arrange, et le hachage changerait au gré
           -- des réécritures de table : tout se résumerait à nouveau, plusieurs
           -- fois par semaine, pour des textes que personne n'aurait modifiés.
           encode(
             extensions.digest(
               string_agg(t.id::text || '|' || t.rating::text || '|' || t.corps,
                          E'\n' order by t.id),
               'sha256'),
             'hex') as hachage,
           jsonb_agg(
             jsonb_build_object(
               -- NI AUTEUR, NI IDENTIFIANT DE CLIENT. Voir l'en-tête : le modèle
               -- ne peut nommer personne parce qu'il ne lit aucun nom.
               'note',  t.rating,
               'date',  t.created_at::date,
               'texte', t.corps)
             order by t.created_at desc) as liste
      from textes t
     group by t.venue_id
  )
  select v.id,
         v.name,
         p.nb,
         p.basses,
         p.hachage,
         s.venue_id is null
           or s.source_hash is distinct from p.hachage
           or s.model       is distinct from p_model,
         p.liste
    from public.venues v
    join par_salle p on p.venue_id = v.id
    left join public.venue_review_summaries s on s.venue_id = v.id
   where v.status = 'published'
     and p.nb >= public.synthese_avis_minimum()
   order by v.name;
$$;

comment on function public.avis_pour_synthese(text) is
  'Les salles PUBLIÉES qui ont au moins synthese_avis_minimum() avis porteurs '
  'de texte : leurs avis (note, date, corps — jamais l''auteur), le hachage de '
  'ce texte, et si la synthèse est à refaire — avis modifiés, ou modèle '
  'différent. Les trois règles vivent ici et nulle part ailleurs : l''Edge '
  'Function ne les connaît pas.';

revoke execute on function public.avis_pour_synthese(text)
  from public, anon, authenticated;

-- =============================================================================
-- 4. enregistrer_synthese_avis — LA SEULE PORTE D'ÉCRITURE
--
-- ELLE REVÉRIFIE LES DEUX RÈGLES, comme `enregistrer_empreinte()` revérifie la
-- publication. Entre le moment où l'Edge Function a demandé la liste et celui où
-- elle rapporte les textes, une minute passe — le temps qu'un propriétaire
-- dépublie sa salle, ou qu'un client retire son avis et fasse retomber le compte
-- sous le seuil. Sans ce contrôle, on écrirait une synthèse de deux phrases sur
-- une salle qui n'est plus en vente.
--
-- ELLE NE REVÉRIFIE PAS LE HACHAGE, et c'est délibéré. Si un avis est arrivé
-- entre-temps, la synthèse rendue est celle du texte d'AVANT — ce qui est vrai,
-- et c'est ce que `source_hash` consigne. La nuit suivante, le hachage courant
-- différera du hachage stocké et la salle repassera d'elle-même. Le système se
-- rattrape ; refuser l'écriture ferait perdre un appel déjà payé.
--
-- Elle rend le nombre de lignes écrites — 0 quand une des deux règles a cessé de
-- tenir, et l'Edge Function le journalise.
-- =============================================================================

create or replace function public.enregistrer_synthese_avis(
  p_venue_id    uuid,
  p_summary     text,
  p_source_hash text,
  p_review_count integer,
  p_model       text
)
returns integer
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_avec_texte integer;
  v_ecrites    integer;
begin
  if nullif(btrim(coalesce(p_summary, '')), '') is null then
    raise exception 'Une synthèse vide ne s''enregistre pas.'
      using errcode = 'invalid_parameter_value';
  end if;

  if not exists (select 1 from public.venues v
                  where v.id = p_venue_id and v.status = 'published') then
    return 0;
  end if;

  select count(*)::integer into v_avec_texte
    from public.reviews r
   where r.venue_id = p_venue_id
     and nullif(btrim(coalesce(r.body, '')), '') is not null;

  if v_avec_texte < public.synthese_avis_minimum() then
    return 0;
  end if;

  insert into public.venue_review_summaries
    (venue_id, summary, review_count, source_hash, model, updated_at)
  values
    (p_venue_id, btrim(p_summary), p_review_count, p_source_hash, p_model, now())
  on conflict (venue_id) do update
    set summary      = excluded.summary,
        review_count = excluded.review_count,
        source_hash  = excluded.source_hash,
        model        = excluded.model,
        updated_at   = now();

  get diagnostics v_ecrites = row_count;
  return v_ecrites;
end;
$$;

comment on function public.enregistrer_synthese_avis(uuid, text, text, integer, text) is
  'La seule porte d''écriture de venue_review_summaries. Revérifie que la salle '
  'est publiée et qu''elle atteint encore synthese_avis_minimum() avis porteurs '
  'de texte — une minute passe entre la lecture et l''écriture. Rend le nombre '
  'de lignes écrites : 0 quand une des deux règles a cessé de tenir.';

revoke execute on function public.enregistrer_synthese_avis(uuid, text, text, integer, text)
  from public, anon, authenticated;

-- =============================================================================
-- 5. avis_de_la_salle — LE BLOC DE LA MAQUETTE ARRIVE
--
-- La 026 se terminait par « AUCUNE SYNTHÈSE IA […] Un cadre vide en attendant
-- dirait au visiteur que l'application est inachevée ». Elle existe maintenant,
-- et la phrase reste vraie pour l'autre moitié du cas : `synthese` est NULL tant
-- qu'aucune n'a été rédigée, et l'écran ne dessine alors rien du tout.
--
-- TROIS CHAMPS, ET PAS UN. Le texte ne se suffit pas : la maquette annonce
-- « Synthèse des 34 avis » et la consigne demande la date de dernière mise à
-- jour. Le nombre vient de la table et NON d'un `count(*)` d'aujourd'hui — un
-- texte de la semaine dernière annoncé « des 40 avis » promettrait six avis
-- qu'il n'a jamais lus.
--
-- RIEN D'AUTRE NE CHANGE. Les notes, les sous-notes, la liste et `nom_abrege()`
-- sont ceux de la 026, mot pour mot.
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

    -- LA SYNTHÈSE, ET SES DEUX COMPAGNONS OBLIGATOIRES. Les trois sont NULL
    -- ensemble tant que « summarize-reviews » n'est pas passée : l'écran ne
    -- dessine alors aucun cadre.
    'summary',            s.summary,
    'summary_count',      s.review_count,
    'summary_updated_at', s.updated_at,

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
  left join public.venue_review_summaries s on s.venue_id = v.id
  where v.id = p_venue_id
    and public.can_read_venue(v.id);

  if v_resultat is null then
    raise exception 'Salle introuvable.' using errcode = 'no_data_found';
  end if;

  return v_resultat;
end;
$fn$;

comment on function public.avis_de_la_salle(uuid) is
  'Écran 7 — les avis d''une salle en un seul appel : la note bayésienne de '
  'venue_ratings (§5.4), les quatre sous-notes, la synthèse pré-calculée (§8.2) '
  'avec sa date et le nombre d''avis dont elle vient, et la liste, le plus '
  'récent en tête. Le nom du client passe par nom_abrege() et par lui seul : '
  '« Sarah B. », jamais le nom entier, jamais l''e-mail, jamais le téléphone (§9). '
  'summary est NULL tant qu''aucune synthèse n''existe — l''écran ne dessine '
  'alors pas de cadre vide.';

grant execute on function public.avis_de_la_salle(uuid) to anon, authenticated;

-- =============================================================================
-- 6. LA TÂCHE NOCTURNE — pg_cron RÉVEILLE L'EDGE FUNCTION
--
-- POURQUOI UNE EDGE FUNCTION ICI, ALORS QUE LA 022 S'EN ÉTAIT PASSÉE. Le cron
-- d'expiration appelle `expire_options()`, qui vit dans la base : il n'y avait
-- rien à sortir. Ici, il faut parler à un modèle de langage — donc une clé
-- d'API, qui n'a rien à faire dans PostgreSQL (§7.1, « Ne jamais faire »). Le
-- travail se fait hors de la base, et le cron ne fait que frapper à la porte.
--
-- LA CLÉ DE SERVICE VIT DANS LE VAULT, PAS DANS CE FICHIER. Aucun secret ne
-- s'écrit dans le dépôt. Deux secrets sont lus par leur NOM :
--
--   ferha_functions_url       « https://<projet>.supabase.co/functions/v1 »
--   ferha_service_role_key    la clé service_role du projet
--
-- Ils se posent une fois, depuis l'éditeur SQL de Supabase :
--
--   select vault.create_secret('https://…/functions/v1', 'ferha_functions_url');
--   select vault.create_secret('eyJ…',                   'ferha_service_role_key');
--
-- TANT QU'ILS N'EXISTENT PAS, LA TÂCHE NE FAIT RIEN ET LE DIT. Elle rend NULL
-- après un `raise warning` visible dans les journaux, plutôt que d'échouer :
-- une tâche cron en erreur toutes les nuits est un bruit qu'on finit par ne plus
-- lire.
--
-- pg_net EST ASYNCHRONE : `net.http_post` dépose la requête et rend son
-- identifiant. La tâche dure quelques millisecondes ; la synthèse, elle, prend
-- le temps qu'il faut de l'autre côté. C'est exactement ce qu'on veut d'un cron
-- — il déclenche, il n'attend pas.
--
-- 3 h 50, ENTRE LES DEUX TÂCHES DE LA 022 (3 h 20 pour la purge) et à une heure
-- où personne ne lit d'avis. La nuit est la fenêtre du §8.2 : « Fraîcheur J+1 ».
-- =============================================================================

create or replace function public.declencher_synthese_avis()
returns bigint
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_url     text;
  v_cle     text;
  v_requete bigint;
begin
  select decrypted_secret into v_url
    from vault.decrypted_secrets where name = 'ferha_functions_url';

  select decrypted_secret into v_cle
    from vault.decrypted_secrets where name = 'ferha_service_role_key';

  if v_url is null or v_cle is null then
    raise warning 'Synthèse des avis : secrets absents du Vault '
      '(ferha_functions_url : %, ferha_service_role_key : %). '
      'Rien n''a été déclenché.',
      v_url is not null, v_cle is not null;
    return null;
  end if;

  select net.http_post(
           url     => rtrim(v_url, '/') || '/summarize-reviews',
           headers => jsonb_build_object(
                        'Content-Type',  'application/json',
                        'Authorization', 'Bearer ' || v_cle),
           body    => '{}'::jsonb,
           -- Le délai d'attente de pg_net, pas celui du travail : on ne fait que
           -- déposer la requête. La fonction, elle, continue de l'autre côté.
           timeout_milliseconds => 10000)
    into v_requete;

  return v_requete;
end;
$$;

comment on function public.declencher_synthese_avis() is
  'Tâche pg_cron nocturne (§7.2) : réveille l''Edge Function « summarize-reviews » '
  'par pg_net. Lit l''URL et la clé de service dans le Vault, par leur nom — '
  'aucun secret n''est écrit dans le dépôt. Rend l''identifiant de requête pg_net, '
  'ou NULL avec un avertissement quand un secret manque. Rôle de service '
  'uniquement.';

revoke execute on function public.declencher_synthese_avis()
  from public, anon, authenticated;

grant usage on schema cron to postgres;

-- REJOUABLE : on décroche explicitement avant de reposer. Le comportement du
-- remplacement dépend de la version de pg_cron, celui de ces lignes non.
do $$
begin
  if exists (select 1 from cron.job where jobname = 'ferha-synthese-avis') then
    perform cron.unschedule('ferha-synthese-avis');
  end if;
end $$;

select cron.schedule(
  'ferha-synthese-avis',
  '50 3 * * *',
  $cron$select public.declencher_synthese_avis();$cron$
);
