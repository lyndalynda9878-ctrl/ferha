-- =============================================================================
-- Ferha — 027_index_semantique.sql
-- L'index sémantique : une empreinte par salle, et la recherche par le sens
-- (§8.3, §8.4 ; §7.2 embed-venue).
--
-- CE QUE CE FICHIER POSE, ET CE QU'IL NE POSE PAS. Il pose la table des
-- empreintes, le document que l'on transforme en vecteur, et la fonction qui
-- classe les salles par proximité. Il ne fabrique AUCUN vecteur : c'est le
-- service d'empreintes qui le fait, appelé par l'Edge Function « embed-venue ».
-- La base stocke et compare ; elle ne calcule pas d'empreinte.
--
-- =============================================================================
-- HNSW ET PAS IVFFLAT (§8.4)
--
-- IVFFlat partitionne l'espace en `lists` cellules, et le nombre de cellules
-- doit être choisi D'APRÈS la quantité de données — la règle usuelle est
-- « nombre de lignes / 1000 ». Avec quinze salles, ce nombre n'a pas de sens :
-- l'index se construirait sur un échantillon qui n'existe pas, et il faudrait
-- le RECONSTRUIRE à chaque fois que le catalogue double. Un index qui doit être
-- refait pour rester juste est un index qu'on oubliera de refaire.
--
-- HNSW se construit ligne à ligne. Il est correct dès la première salle, il le
-- reste à la millième, et il n'a rien à réapprendre entre les deux. Il coûte
-- plus cher à la construction et en mémoire — sur quinze lignes, cela ne se
-- mesure pas.
--
-- vector_cosine_ops, ET PAS vector_l2_ops. Les empreintes sortent normalisées
-- du service (J18) : sur des vecteurs de longueur 1, cosinus et distance
-- euclidienne classent dans le même ordre. Mais l'opérateur doit correspondre à
-- CE QUE LA REQUÊTE DEMANDE, sans quoi l'index n'est tout simplement pas
-- utilisé — silencieusement, avec un balayage complet à la place. La recherche
-- ci-dessous utilise `<=>`, donc l'index est en cosinus.
--
-- =============================================================================
-- LE NOM DU MODÈLE EST STOCKÉ, ET CE N'EST PAS DE LA DOCUMENTATION
--
-- Deux modèles de 384 dimensions cohabiteraient sans la moindre erreur : les
-- vecteurs ont la même forme, l'index les accepte, la requête tourne. Elle
-- rendrait simplement n'importe quoi, parce que comparer l'empreinte d'un
-- modèle à celle d'un autre revient à comparer deux systèmes de coordonnées
-- différents. Rien ne le signalerait — ni erreur, ni résultat vide : juste des
-- salles mal classées.
--
-- `model` est donc une colonne, et `salles_a_indexer()` traite un changement de
-- modèle exactement comme un changement de contenu : il faut tout refaire.
--
-- =============================================================================
-- AUCUNE LECTURE CLIENTE SUR CETTE TABLE
--
-- RLS activée, et AUCUNE POLITIQUE. Ce n'est pas un oubli : une table dont la
-- RLS est active et qui n'a pas de politique est vide pour tout le monde, sauf
-- pour `service_role` et pour les fonctions SECURITY DEFINER. C'est exactement
-- ce qu'on veut — la table ne sort que par `recherche_semantique()`.
--
-- POURQUOI LA FERMER, puisqu'un document de salle ne contient que du public ?
-- Parce qu'elle contient AUSSI les empreintes des salles non publiées le jour
-- où l'on en indexera, et parce que 384 nombres par salle sont un coût de
-- bande passante que personne n'a de raison de payer sur une 4G algérienne
-- (§7.3). Une table technique se ferme par défaut ; on l'ouvre si un besoin
-- apparaît, jamais l'inverse.
--
-- =============================================================================
-- LA SUPPRESSION EST EN CASCADE, ET C'EST LE CONTRAIRE DE bookings
--
-- `bookings.venue_id` est en RESTRICT parce qu'une réservation est une trace
-- comptable : elle doit survivre, et une suppression franche doit échouer.
-- Une empreinte n'est pas une trace : c'est un CALCUL, refaisable en une
-- seconde à partir de la salle. La garder après la salle ne protégerait rien
-- et laisserait un vecteur orphelin dans l'index de recherche.
--
-- Dépend de : 001 (venues, wilayas, event_types, amenities),
--             003 (venue_amenities), 004 (venue_ratings),
--             010 (venue_event_types), 011 (venue_detail).
--
-- Rejouable : extension et table conditionnelles, fonctions remplacées.
-- =============================================================================

-- L'extension va dans `extensions`, la convention Supabase — c'est là que
-- vivent déjà pgcrypto et uuid-ossp. Les types sont donc QUALIFIÉS partout
-- ci-dessous : les fonctions du projet posent `set search_path = public`, et
-- un `vector(384)` non qualifié y serait introuvable.
create extension if not exists vector with schema extensions;

-- -----------------------------------------------------------------------------
-- venue_embeddings — une ligne par salle indexée
-- -----------------------------------------------------------------------------

create table if not exists public.venue_embeddings (
  venue_id     uuid primary key
                 references public.venues(id) on delete cascade,

  -- Le document tel qu'il a été vectorisé. On le garde POUR POUVOIR EXPLIQUER :
  -- quand une salle sort d'une recherche sans qu'on comprenne pourquoi, c'est
  -- ce texte-là qu'il faut lire, et non celui que `document_salle()` rendrait
  -- aujourd'hui.
  content      text not null,

  embedding    extensions.vector(384) not null,

  -- Le modèle qui a produit le vecteur. Voir l'en-tête.
  model        text not null,

  -- SHA-256 du document, en hexadécimal. Calculé en SQL par `document_salle()`
  -- et par elle seule : deux implémentations du même hachage finiraient par
  -- diverger sur un accent ou une fin de ligne, et tout se réindexerait à
  -- chaque passage sans que rien n'ait changé.
  content_hash text not null,

  updated_at   timestamptz not null default now()
);

comment on table public.venue_embeddings is
  'Une empreinte de 384 nombres par salle publiée (§8.3, §8.4). Remplie par '
  'l''Edge Function « embed-venue », jamais par le client. RLS active et aucune '
  'politique : la table ne sort que par recherche_semantique().';

comment on column public.venue_embeddings.model is
  'Le modèle qui a produit le vecteur. Deux modèles de même dimension '
  'cohabiteraient sans erreur et rendraient n''importe quoi : un changement de '
  'modèle force le réindexage au même titre qu''un changement de texte.';

-- L'INDEX. `m` et `ef_construction` restent aux valeurs par défaut (16 et 64) :
-- elles sont faites pour des jeux bien plus gros, et les régler à la baisse
-- pour quinze lignes n'accélérerait rien de mesurable.
create index if not exists venue_embeddings_hnsw_cosinus
  on public.venue_embeddings
  using hnsw (embedding extensions.vector_cosine_ops);

alter table public.venue_embeddings enable row level security;

-- Aucune politique, et on retire jusqu'au droit de regarder la table : un
-- `select` d'un client reçoit « permission denied » plutôt qu'un résultat vide,
-- ce qui est plus facile à diagnostiquer si quelqu'un essaie un jour.
revoke all on public.venue_embeddings from anon, authenticated;

-- =============================================================================
-- document_salle — LE TEXTE QUE L'ON TRANSFORME EN VECTEUR (§8.3)
--
-- ÉCRITE UNE SEULE FOIS, elle sert à l'indexation ET au réindexage : si le
-- document se composait à deux endroits, le hachage dirait « inchangé » pour un
-- texte qui a changé, et la salle garderait pour toujours une empreinte fausse.
--
-- ELLE EST BILINGUE, et c'est un choix. Les tables portent `name_ar` et
-- `label_ar` parce que l'application est bilingue ; la moitié des questions de
-- référence du J20 arrivent en arabe ou en franco-arabe. Le modèle est
-- multilingue et rapproche déjà « قاعة أفراح وهران » d'un document français —
-- mais lui donner les deux graphies du nom d'une wilaya coûte quelques mots et
-- lui évite de devoir traduire « Sétif » en « سطيف » de tête.
--
-- CE QU'ELLE N'INCLUT PAS, ET POURQUOI :
--
--   * LE PRIX. Il se CALCULE, par estimate_price(), et il dépend de la date, du
--     créneau et du nombre d'invités. Un prix figé dans un document vieillirait
--     en silence, et le §5 interdit une seconde source de prix. La question 9 du
--     J20 (« combien coûte El Bahia un samedi d'août ») se répond par la
--     fonction de prix, pas par la recherche sémantique.
--   * L'ADRESSE EXACTE ET LE TÉLÉPHONE. Ils ne servent pas à choisir une salle,
--     et le §9 les réserve à qui a une réservation acceptée.
--   * LE STATUT. Une salle non publiée n'est jamais indexée : le statut n'a donc
--     pas à figurer dans le texte.
--
-- LA NOTE EST ARRONDIE AU DIXIÈME, comme elle s'affiche. La moyenne bayésienne
-- bouge à chaque avis déposé ; sans arrondi, le hachage changerait à chaque fois
-- et l'on rappellerait le service d'empreintes pour un texte que personne n'aurait
-- lu différemment.
--
-- L'ORDRE EST STABLE PARTOUT — équipements par `position` puis par code, types
-- d'événement de même. Sans `order by`, PostgreSQL rend les lignes dans l'ordre
-- qui l'arrange, et le hachage changerait au gré des réécritures de table : tout
-- se réindexerait sans raison, plusieurs fois par jour.
-- =============================================================================

create or replace function public.document_salle(p_venue_id uuid)
returns table (content text, content_hash text)
language sql
stable
security definer
set search_path = public, extensions
as $$
  with salle as (
    select v.*, w.name_fr as wilaya_fr, w.name_ar as wilaya_ar
      from public.venues v
      left join public.wilayas w on w.code = v.wilaya_code
     where v.id = p_venue_id
  ),
  types as (
    select string_agg(t.label_fr || ' (' || t.label_ar || ')', ', '
                      order by t.position, t.code) as liste
      from public.venue_event_types vt
      join public.event_types t on t.code = vt.event_type
     where vt.venue_id = p_venue_id
  ),
  equipements as (
    select string_agg(a.label_fr || ' (' || a.label_ar || ')', ', '
                      order by a.position, a.code) as liste
      from public.venue_amenities va
      join public.amenities a on a.code = va.amenity_code
     where va.venue_id = p_venue_id
  ),
  assemble as (
    select concat_ws(E'\n',
      'Salle des fêtes : ' || s.name,
      'Commune : ' || s.commune,
      'Wilaya : ' || coalesce(s.wilaya_fr, '?')
        || coalesce(' (' || s.wilaya_ar || ')', '')
        || ' — code ' || s.wilaya_code,
      'Capacité : ' || s.capacity_seated || ' invités assis',
      case when s.area_sqm is not null
           then 'Superficie : ' || s.area_sqm || ' m²' end,
      -- ZÉRO PLACE N'EST PAS « NON RENSEIGNÉ », et la différence compte : la
      -- question 14 du J20 cherche un grand parking, la 6 un parking fermé.
      case when s.parking_spaces is null then 'Parking : non renseigné'
           when s.parking_spaces = 0     then 'Parking : aucun'
           else 'Parking : ' || s.parking_spaces || ' places' end,
      case when t.liste is not null then 'Types d''événement : ' || t.liste end,
      case when e.liste is not null then 'Équipements et services : ' || e.liste end,
      case when r.review_count > 0
           then 'Note : ' || to_char(round(r.bayesian_rating, 1), 'FM9.0')
                || ' sur 5, sur ' || r.review_count || ' avis'
           else 'Note : aucun avis pour l''instant' end,
      case when nullif(btrim(coalesce(s.description, '')), '') is not null
           then 'Description : ' || btrim(s.description) end
    ) as texte
    from salle s
    cross join types t
    cross join equipements e
    left join public.venue_ratings r on r.venue_id = s.id
  )
  select a.texte,
         encode(extensions.digest(a.texte, 'sha256'), 'hex')
    from assemble a;
$$;

comment on function public.document_salle(uuid) is
  'Le document de synthèse d''une salle (§8.3) et son SHA-256 : nom, commune, '
  'wilaya en français et en arabe, capacité, superficie, parking, types '
  'd''événement, équipements, note et nombre d''avis, description. '
  'Ni prix (il se calcule), ni adresse, ni téléphone (§9). L''ordre y est stable, '
  'sans quoi le hachage bougerait à chaque réécriture de table.';

revoke execute on function public.document_salle(uuid) from public, anon, authenticated;

-- =============================================================================
-- salles_a_indexer — CE QUE L'EDGE FUNCTION DEMANDE EN UN SEUL APPEL
--
-- Elle rend TOUTES les salles publiées, leur document, son hachage, et si le
-- travail est à refaire. L'Edge Function n'a donc aucune règle à connaître :
-- elle ne décide ni de ce qui est publié, ni de ce qui a changé.
--
-- C'EST LA BASE QUI DIT « PUBLIÉE », PAS LE TYPESCRIPT. Un filtre écrit dans
-- l'Edge Function serait un second gardien pour une règle qui vit ici — et
-- celui-là s'oublierait le jour où quelqu'un écrirait un second indexeur.
--
-- `a_refaire` COUVRE LE CHANGEMENT DE MODÈLE autant que le changement de texte.
-- =============================================================================

create or replace function public.salles_a_indexer(p_model text)
returns table (
  venue_id     uuid,
  name         text,
  content      text,
  content_hash text,
  a_refaire    boolean
)
language sql
stable
security definer
set search_path = public, extensions
as $$
  select v.id,
         v.name,
         d.content,
         d.content_hash,
         e.venue_id is null
           or e.content_hash is distinct from d.content_hash
           or e.model        is distinct from p_model
    from public.venues v
    cross join lateral public.document_salle(v.id) d
    left join public.venue_embeddings e on e.venue_id = v.id
   where v.status = 'published'
   order by v.name;
$$;

comment on function public.salles_a_indexer(text) is
  'Les salles PUBLIÉES, leur document, son hachage, et si l''empreinte est à '
  'refaire — texte modifié, ou modèle différent. La règle « seulement les '
  'salles publiées » vit ici et nulle part ailleurs : l''Edge Function ne la '
  'connaît pas.';

revoke execute on function public.salles_a_indexer(text) from public, anon, authenticated;

-- =============================================================================
-- enregistrer_empreinte — LA SEULE PORTE D'ÉCRITURE
--
-- ELLE REVÉRIFIE LA PUBLICATION. C'est la ceinture sous `salles_a_indexer()` :
-- entre le moment où l'Edge Function a demandé la liste et celui où elle
-- rapporte les vecteurs, quelques dizaines de secondes passent — le temps qu'un
-- propriétaire dépublie sa salle. Sans ce contrôle, la salle repartirait dans
-- l'index de recherche, et la question 29 du J20 (« kayen salle f Birtouta ? »)
-- citerait une salle qui n'est pas publiée.
--
-- Elle rend le nombre de lignes écrites — 0 quand la salle n'est plus publiée.
-- =============================================================================

create or replace function public.enregistrer_empreinte(
  p_venue_id     uuid,
  p_content      text,
  p_content_hash text,
  p_embedding    extensions.vector(384),
  p_model        text
)
returns integer
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_ecrites integer;
begin
  if not exists (select 1 from public.venues v
                  where v.id = p_venue_id and v.status = 'published') then
    return 0;
  end if;

  insert into public.venue_embeddings
    (venue_id, content, embedding, model, content_hash, updated_at)
  values
    (p_venue_id, p_content, p_embedding, p_model, p_content_hash, now())
  on conflict (venue_id) do update
    set content      = excluded.content,
        embedding    = excluded.embedding,
        model        = excluded.model,
        content_hash = excluded.content_hash,
        updated_at   = now();

  get diagnostics v_ecrites = row_count;
  return v_ecrites;
end;
$$;

comment on function public.enregistrer_empreinte(uuid, text, text, extensions.vector, text) is
  'Écrit ou remplace l''empreinte d''une salle. Revérifie que la salle est '
  'toujours publiée — elle a pu être dépubliée pendant que le service calculait '
  '— et rend 0 sans rien écrire dans ce cas. Seule porte d''écriture de '
  'venue_embeddings.';

revoke execute on function
  public.enregistrer_empreinte(uuid, text, text, extensions.vector, text)
  from public, anon, authenticated;

-- =============================================================================
-- recherche_semantique — LES SALLES, CLASSÉES PAR PROXIMITÉ (§8.4)
--
-- AUCUN SEUIL ABSOLU, ET C'EST LA DÉCISION LA PLUS IMPORTANTE DE CE FICHIER.
-- Le modèle tasse ses cosinus dans une bande étroite : au J18, la marge mesurée
-- entre « la même demande dite en arabe » et « un texte sans aucun rapport »
-- était d'environ trois centièmes. Un « garder au-dessus de 0,85 » serait réglé
-- sur trois exemples et se tromperait sur le quatrième — tantôt en vidant la
-- réponse, tantôt en laissant tout passer. On CLASSE, et on coupe au nombre.
--
-- C'est à l'agent du J20 de dire « aucune salle ne convient » (question 8), et
-- il le dira sur des critères VÉRIFIABLES — wilaya, capacité, date — pas sur un
-- cosinus. La recherche sémantique propose des candidats ; elle ne tranche pas.
--
-- LE STATUT EST REVÉRIFIÉ ICI AUSSI. L'index ne contient que des salles
-- publiées, mais une salle dépubliée hier y est encore : rien ne l'en retire,
-- et le §4.4 veut qu'elle disparaisse tout de suite. Le `join` sur
-- `status = 'published'` est donc ce qui garantit la règle, pas le contenu de
-- l'index.
--
-- LE MODÈLE EST EXIGÉ. Comparer un vecteur à ceux d'un autre modèle rend des
-- résultats plausibles et faux ; on ne compare qu'à ce qui a été fabriqué par
-- le même. Les lignes d'un autre modèle sont simplement ignorées — elles
-- seront refaites au prochain passage de l'indexeur.
--
-- `proximite` = 1 − distance cosinus, pour que le nombre affiché monte quand la
-- salle est plus proche. C'est le sens que tout le monde attend d'une
-- « proximité », et l'inverse de ce que rend `<=>`.
-- =============================================================================

create or replace function public.recherche_semantique(
  p_embedding extensions.vector(384),
  p_model     text,
  p_limit     integer default 5
)
returns table (
  venue_id        uuid,
  name            text,
  commune         text,
  wilaya_name     text,
  capacity_seated integer,
  rating          numeric,
  review_count    bigint,
  proximite       double precision
)
language sql
stable
security definer
set search_path = public, extensions
as $$
  select v.id,
         v.name,
         v.commune,
         w.name_fr,
         v.capacity_seated,
         round(r.bayesian_rating, 1),
         coalesce(r.review_count, 0),
         1 - (e.embedding <=> p_embedding)
    from public.venue_embeddings e
    join public.venues v
      on v.id = e.venue_id
     and v.status = 'published'
    left join public.wilayas      w on w.code = v.wilaya_code
    left join public.venue_ratings r on r.venue_id = v.id
   where e.model = p_model
   order by e.embedding <=> p_embedding
   limit greatest(1, least(coalesce(p_limit, 5), 50));
$$;

comment on function public.recherche_semantique(extensions.vector, text, integer) is
  'Les salles publiées, CLASSÉES par proximité à un vecteur de question (§8.4). '
  'Aucun seuil absolu : la marge mesurée au J18 est de l''ordre de trois '
  'centièmes, et un seuil réglé sur trois exemples se tromperait sur le '
  'quatrième. C''est l''agent (J20) qui dit « rien ne convient », sur des '
  'critères vérifiables. Le statut est revérifié ici : une salle dépubliée est '
  'encore dans l''index, et ne doit plus sortir.';

-- OUVERTE AUX VISITEURS, comme la recherche ordinaire : chercher une salle est
-- l'étape 2 du parcours du §3, et elle se fait sans compte.
grant execute on function public.recherche_semantique(extensions.vector, text, integer)
  to anon, authenticated;
