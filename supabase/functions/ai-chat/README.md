# ai-chat — l'agent de recherche

Quatre temps (§8.1) : le modèle **extrait** les critères, le SQL **trie** de
façon exacte, le vecteur **classe** ce qui reste, le modèle **rédige** à partir
des salles trouvées et de rien d'autre.

Modèle : **`gemini-3.5-flash-lite`**, palier gratuit. Surchargeable par le
secret `GEMINI_MODEL` sans redéploiement.

| | |
|---|---|
| Secret à créer | `GEMINI_API_KEY` |
| Facultatif | `GEMINI_MODEL` |
| Déjà posés au J19 | `EMBEDDINGS_URL`, `EMBED_TOKEN` |
| `verify_jwt` | `true` — c'est l'application qui appelle |

```powershell
$env:FERHA_SUPABASE_ANON_KEY = "..."          # SUPABASE_ANON_KEY de env.json
.\..\..\tests\agent_30_questions.ps1          # les 30 questions de référence
.\..\..\tests\agent_30_questions.ps1 -detail  # avec les réponses rédigées
```

---

## Ce que le modèle ne fait jamais

Aucune **affirmation factuelle vérifiable**. La comparaison de dates, le report
d'année, l'annonce de l'hypothèse, le prix : tout se calcule dans la fonction ou
en SQL. Il rédige, il n'atteste pas.

C'est la même règle que le §8.1 énonce pour la recherche — « la similarité ne
sait pas compter » — appliquée à la génération. Chaque fois qu'on a laissé le
modèle produire un fait, il s'est trompé au moins une fois :

* il rendait l'**année en cours** pour « le 14 août », déjà passée, et l'agent
  répondait « cette date est passée » à qui demandait un prix ;
* il **recopiait la date de l'exemple** du prompt dans la phrase d'hypothèse —
  « je pars sur le 14 août » en chiffrant le 1er.

Les deux vivent maintenant dans `avancerJusquAVenir()` et
`phraseAnneeSupposee()`, où rien ne peut les déformer.

---

## LE GARDE-FOU DU §8.5, ET SA LIMITE

### Contrôle principal : les identifiants

Le modèle rend, à côté de sa réponse, la **liste des `venue_id` qu'il cite**, en
sortie structurée. Chacun doit être dans le contexte ; sinon la génération
rejoue, et au deuxième échec on rend la liste brute.

C'est le seul contrôle qui **ne dépende ni de la langue ni de l'écriture**.

### Filet secondaire : les noms — EN ÉCRITURE LATINE SEULEMENT

Un second passage cherche dans la prose les noms du catalogue entier, brouillons
compris. Il attrape ce que la déclaration ne dit pas : une salle nommée sans que
son identifiant soit déclaré.

**Il ne voit rien d'une réponse en arabe.** L'agent y translittère les noms —
`قاعة ابن خلدون` pour Salle Ibn Khaldoun, `مجمع الشريعة` pour Complexe Chréa —
et aucune comparaison de chaînes latines ne les y retrouvera. Environ un tiers
des questions de référence sont concernées.

Ce n'est pas un oubli. Écrire un détecteur de noms translittérés demanderait de
deviner comment un modèle rend « Chréa » en arabe : ce serait une seconde source
de vérité, plus fragile que celle qu'elle prétend garder, et fausse le jour où
le modèle change de translittération. On préfère une limite connue à une
protection qui ment.

**Conséquence pratique** : sur une réponse en arabe, la garantie repose
entièrement sur la déclaration d'identifiants. Elle tient tant que le modèle
déclare fidèlement ce qu'il cite — ce que le prompt lui présente comme le champ
le plus important.

### Deux noms qui échappent au filet

Un nom trop court (moins de cinq caractères) ou fait uniquement de mots communs
— le catalogue contient une salle appelée littéralement **« salle »** — n'est
pas cherché dans la prose : il se confondrait avec le vocabulaire courant. Pour
ces salles-là aussi, seul le contrôle par identifiant s'applique.

---

## Ce qui reste une consigne, et non un garde-fou

Trois règles vivent dans le prompt et **rien ne les vérifie mécaniquement** :

1. **Ne renvoyer vers rien** quand la liste est vide — ni « les communes
   voisines », ni « revenez plus tard ». Mesurée sur les 30 questions, elle
   tient deux fois sur trois : la question 29 invite encore à « vérifier les
   wilayas ou communes voisines ».
2. **Répondre dans la langue de la question.** Tenue partout sauf sur la
   question 20, répondue en français à une question en darja.
3. **Au plus cinq salles.** Garantie autrement : le contexte lui-même est coupé
   à cinq, et un contexte absent ne se cite pas.

Les deux premières demanderaient un contrôle automatique pour devenir des
garanties. En l'état, ce sont des tendances — bonnes, pas certaines.

---

## Ce qui manque encore

* **`kb_documents` et le vrai §8.2.** Le parcours de réservation est aujourd'hui
  six lignes en dur dans `PROCEDURE`. Elles ont un avantage sur un RAG — elles
  ne peuvent pas se tromper — et un défaut : toute autre question de support
  reste sans réponse.
* **`ai_cache`, les 30 réponses pré-générées du §8.5**, pour que la démonstration
  survive à un quota épuisé.
* **La limite de débit par utilisateur** (20 messages/jour). Elle demande
  d'identifier l'utilisateur, ce que le journal s'interdit — il faudra décider
  où cette identité vit.
* **Le mode dégradé en recherche plein texte (§8.4).** Si le service d'empreintes
  ne répond pas, l'agent continue **sans vecteur** : le tri exact suffit, le
  classement fin est perdu. Le repli `tsvector` + `pg_trgm` reste à écrire.
* **Le classement ne sait pas lire un nombre dans un document.** La question 14
  — « une salle avec beaucoup de places de parking » — ne se filtre pas, et le
  vecteur ne compare pas 150 à 35. Il faudrait en faire un critère exact.
