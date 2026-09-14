# summarize-reviews — la synthèse des avis

Le deuxième des quatre usages du §8.2, et le seul qui ne soit **pas du RAG** :
« tous les avis tiennent dans le contexte. Résumé pré-calculé la nuit et
stocké. » Il n'y a rien à chercher, rien à classer — on lit les avis d'UNE
salle, et on les résume.

Modèle : **`gemini-3.5-flash-lite`**, le même que l'agent, surchargeable par le
secret `GEMINI_MODEL`.

| | |
|---|---|
| Déclencheur | pg_cron, `ferha-synthese-avis`, tous les jours à 3 h 50 |
| Secrets Edge Function | `GEMINI_API_KEY` (déjà posé au J20), `GEMINI_MODEL` (facultatif) |
| Secrets Vault de la base | `ferha_functions_url`, `ferha_service_role_key` |
| `verify_jwt` | `true`, **et un second contrôle dans la fonction** — voir plus bas |
| Migration | `032_synthese_des_avis.sql` |
| Test SQL | `supabase/tests/017_synthese_des_avis.sql` |

```sql
-- Ce que fait le cron, à la main :
select public.declencher_synthese_avis();   -- rend un id de requête pg_net, ou NULL

-- Ce que la nuit a écrit :
select v.name, s.review_count, s.updated_at, left(s.summary, 120)
  from public.venue_review_summaries s
  join public.venues v on v.id = s.venue_id
 order by s.updated_at desc;

-- Ce qui reste à faire, et pourquoi :
select name, review_count, notes_basses, a_refaire
  from public.avis_pour_synthese('gemini-3.5-flash-lite');
```

---

## LA RÈGLE MÉTIER VIT EN SQL, PAS ICI

Cette fonction ne connaît ni « publiée », ni « trois avis », ni « a changé ».
Elle transporte. C'est la division du travail qu'« embed-venue » a avec
`salles_a_indexer()`, et elle a la même raison : une règle écrite dans le
TypeScript serait un second gardien, qui finirait par diverger de celui qui
compte.

| Qui décide | Quoi |
|---|---|
| `avis_pour_synthese()` | quelles salles sont éligibles, et lesquelles sont à refaire |
| `synthese_avis_minimum()` | le seuil de trois avis — écrit **une seule fois** |
| `enregistrer_synthese_avis()` | accepte ou refuse l'écriture, en revérifiant |
| la fonction | appelle le modèle, et relit sa sortie |

---

## « SEULEMENT LES SALLES DONT LES AVIS ONT CHANGÉ »

Le quota gratuit est limité. Sans ce tri, chaque nuit rappellerait le modèle sur
des textes identiques — et le jour où le catalogue comptera trois cents salles,
c'est le quota d'une semaine qui partirait en une nuit.

**On pouvait compter les avis, et ç'aurait été faux.** Un compteur ne voit ni un
avis *corrigé* — le §5.4 laisse trente jours pour se relire — ni un avis
supprimé et remplacé le même jour. La synthèse resterait celle d'un texte que
plus personne ne lit.

On **hache** donc ce qu'on résume : identifiant, note et corps de chaque avis,
dans un ordre stable. Exactement comme `document_salle()` hache ce qu'elle
vectorise (027). Le modèle entre dans la comparaison pour la même raison qu'en
027 : en changer, c'est changer ce qui serait écrit.

Le test 4 de `017_synthese_des_avis.sql` couvre les cinq cas : jamais résumée,
fraîchement résumée, texte corrigé, retour en arrière, modèle différent.

---

## PAS DE SYNTHÈSE SOUS TROIS AVIS

« On ne résume pas deux phrases. » Un résumé de deux avis n'est pas un résumé :
c'est une paraphrase, plus longue que l'original, et il donne au lecteur
l'impression d'une tendance là où il n'y a que deux soirées.

**On compte les avis qui PORTENT DU TEXTE**, et non les avis. Une note sans
commentaire ne donne rien à résumer : trois étoiles muettes et deux phrases
feraient « trois avis » au compteur et deux phrases au modèle. C'est le piège
naturel, et c'est le test 2b.

Le seuil est écrit une fois, dans `synthese_avis_minimum()`. Deux gardiens le
lisent — celle qui propose le travail et celle qui accepte le résultat — et
aucun des deux ne porte le chiffre.

---

## CE QUE LE MODÈLE NE PEUT PAS FAIRE, PARCE QU'IL NE LE VOIT PAS

**Il ne voit aucun nom de client.** `avis_pour_synthese()` rend la note, la date
et le corps — jamais l'auteur, pas même abrégé par `nom_abrege()`. Il ne peut
pas écrire « Sarah B. a trouvé la salle froide » parce qu'il n'a jamais lu
« Sarah B. ». Ce n'est pas une consigne, c'est une absence — et le §8.5 préfère
une donnée absente à un garde-fou, un garde-fou à une consigne. Le test 1c le
vérifie.

**Il ne voit aucune note moyenne, aucun compte, aucun prix.** La note bayésienne
s'affiche juste au-dessus du bloc, calculée par `venue_ratings` ; une seconde
note écrite en toutes lettres dans la prose serait une seconde source de vérité.

---

## LES DEUX GARDE-FOUS MÉCANIQUES

### 1. Aucun chiffre qui ne soit dans les avis

Chaque suite de chiffres de la synthèse est cherchée dans le texte des avis
réunis, séparateurs retirés et chiffres arabes-indiens normalisés. « 4,6 sur
5 », « 34 avis », « jugé lent par 4 clients » : aucun de ces nombres n'est écrit
par un client, **tous seraient des calculs** — et « aucune note recalculée » est
la règle du §8.2.

C'est le seul contrôle qui ne dépende ni de la langue ni de l'écriture, comme la
déclaration d'identifiants de l'agent.

> La maquette écrit « jugé lent par 4 clients sur les mariages de plus de 350
> invités ». C'est un dessin, pas une promesse : ce 4-là est un comptage que le
> modèle ferait de tête, et qu'il ferait faux une fois sur cinq.

### 2. Une réserve quand la base en connaît une

« Un résumé exclusivement flatteur n'est pas cru » (maquettes, écran 7). Le SQL
compte les avis à trois étoiles ou moins — `notes_basses`, un **fait**, pas un
jugement — et quand il y en a, la synthèse doit déclarer au moins une réserve.

Sinon on rejoue ; au second échec **on n'écrit rien**. Contrairement à l'agent,
il n'y a pas de repli acceptable : une liste brute de salles reste utile, une
synthèse muette sur ce que les clients ont reproché ne l'est pas. L'ancienne
reste en place, et la salle repasse la nuit suivante — son hachage est toujours
différent.

**Quand tous les avis sont bons, le champ peut rester vide**, et c'est voulu :
forcer une réserve qui n'existe pas serait une invention, c'est-à-dire pire.

---

## CE QUI RESTE UNE CONSIGNE, ET NON UN GARDE-FOU

Comme l'agent avec sa règle 10, il faut le dire plutôt que de le laisser croire.
Rien ne vérifie mécaniquement :

1. **Que la réserve déclarée soit bien celle des avis.** Le modèle remplit
   `reserves` lui-même ; on compte les entrées, on ne les relit pas.
2. **Qu'aucun fait ne soit inventé.** Vérifier une prose libre contre son
   contexte demanderait un second modèle, qui se tromperait aussi.
3. **Que la langue soit bien celle des avis.**

Ce qui tient ces règles, c'est que **le contexte est pauvre** : quelques phrases
de clients, et rien d'autre. Le jour où l'on y ajouterait la description de la
salle ou sa note, le modèle aurait de la matière à déborder.

---

## LA LANGUE DE LA SYNTHÈSE EST CELLE DES AVIS

Une seule synthèse est stockée — le quota interdit d'en écrire deux. Elle est
donc rédigée dans la langue majoritaire des avis qu'elle résume, et ces avis-là
sont juste en dessous, dans la même langue.

L'application n'a rien à savoir de cette langue : `directionDuTexte()`
(`lib/core/l10n/direction_du_texte.dart`) déduit le sens d'écriture du texte
lui-même, comme pour la réponse de l'agent.

---

## QUI A LE DROIT D'APPELER

`verify_jwt = true` ne suffit pas : la clé **publique** du projet ouvre la
passerelle, et elle part dans le bundle web. Sans contrôle de plus, n'importe
qui pourrait réveiller cette fonction en boucle et vider le quota d'une nuit.

La fonction compare donc le jeton présenté à la clé de service qu'elle a dans
son environnement. **Ce contrôle marche avec les deux systèmes de clés de
Supabase** — l'ancien, où la clé de service est un JWT portant
`role: service_role`, et le nouveau, où c'est une chaîne opaque `sb_secret_…`
qui ne se décode pas. Ce projet est du second genre : sa clé publique est un
`sb_publishable_…`, et un contrôle qui n'aurait su lire qu'une revendication
`role` aurait fermé la porte au cron lui-même.

**Conséquence** : `ferha_service_role_key` dans le Vault doit porter exactement
la même valeur que le secret `SUPABASE_SERVICE_ROLE_KEY` de la fonction. C'est
la même clé, lue des deux côtés.

```sql
-- À poser UNE FOIS, depuis l'éditeur SQL de Supabase. Jamais dans le dépôt,
-- jamais dans une conversation.
select vault.create_secret('<la clé de service>', 'ferha_service_role_key');
```

Tant qu'elle manque, `declencher_synthese_avis()` rend `NULL` après un
avertissement dans les journaux, et ne déclenche rien. Elle n'échoue pas : une
tâche cron en erreur toutes les nuits est un bruit qu'on finit par ne plus lire.

---

## LES DEUX PLAFONDS

| | Valeur | Pourquoi |
|---|---|---|
| `SALLES_PAR_PASSAGE` | 8 | le quota gratuit, le jour où beaucoup de salles changent d'un coup |
| `BUDGET_TEMPS_MS` | 100 s | une Edge Function est **tuée** à 150 s ; on s'arrête avant, entre deux salles |

On ne commence jamais une salle qu'on ne pourrait pas finir : un passage
interrompu au milieu d'un appel dépenserait le quota et perdrait la synthèse.
Les salles non traitées sont toujours « à refaire » — elles repassent la nuit
suivante, rien ne les efface de la liste.

---

## Ce qui manque encore

* **Une synthèse par langue.** Une seule est stockée, dans la langue des avis.
  Un lecteur arabophone devant des avis français lit une synthèse française —
  cohérent avec ce qui est juste en dessous, mais ce n'est pas de la traduction.
  En écrire deux doublerait le quota.
* **La réponse du propriétaire n'entre pas dans la synthèse.** Elle est pourtant
  la moitié de la conversation, et parfois celle qui répond à la réserve
  (« nous avons ajouté deux climatiseurs en septembre »). L'ajouter demanderait
  de décider ce qu'on fait d'un propriétaire qui se défend — et c'est un
  arbitrage produit, pas un oubli.
* **Aucune reprise en cas de quota épuisé en cours de passage.** On s'arrête, et
  les salles restantes attendent la nuit suivante. C'est acceptable tant que le
  catalogue est petit.
