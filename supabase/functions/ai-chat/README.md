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
| Appelée par | l'écran 8 (`lib/features/assistant/`), sans compte |

```powershell
$env:FERHA_SUPABASE_ANON_KEY = "..."          # SUPABASE_ANON_KEY de env.json
.\..\..\tests\agent_30_questions.ps1          # les 30 questions de référence
.\..\..\tests\agent_30_questions.ps1 -detail  # avec les réponses rédigées
```

---

## LES EN-TÊTES CORS, ET POURQUOI ILS N'ÉTAIENT PAS LÀ AVANT

Jusqu'au J20, cette fonction n'était appelée que par le banc des 30 questions —
un script PowerShell, qui n'est pas un navigateur et ne demande donc aucune
permission. L'écran 8 change cela : la page Flutter web est servie depuis
`localhost`, la fonction depuis `*.supabase.co`, et le navigateur envoie
d'abord un `OPTIONS` de pré-vol.

**Sans réponse à ce pré-vol, l'appel n'a pas lieu** — et il n'échoue même pas
d'une façon qu'on puisse afficher : il ne part jamais. Ce sont les mêmes
en-têtes que « create-checkout », posés pour la même raison.

---

## LA PHOTO PART VERS L'APPLICATION, PAS VERS LE MODÈLE

L'écran 8 ne montre pas une liste de noms : il montre des **cartes** — photo,
nom, commune, prix —, et chacune ouvre la vraie fiche. La migration 031 fait
donc remonter `cover_photo` depuis `search_venues()`, où elle était déjà.

La fonction compose désormais **deux objets** là où il y en avait un :

| | Contenu |
|---|---|
| `contexte` — ce que le MODÈLE lit | nom, commune, wilaya, capacité, parking, équipements, prix, note |
| `salles` — ce que l'APPLICATION reçoit | le même, **plus la photo** |

Un chemin de Storage n'aide pas à rédiger trois phrases ; il occupe du contexte,
et le §8.5 tient parce que ce contexte est PAUVRE. Chaque champ ajouté est de la
matière à reformuler — et à déborder. Une photo s'affiche, elle ne se raconte
pas.

---

## LES SUGGESTIONS QUE CETTE FONCTION NE RENVOIE PAS

La maquette de l'écran 8 dessine trois puces sous la réponse — « Avec espace
femmes », « Moins de 200 000 », « Avec jardin ». **Cette fonction n'en renvoie
aucune** : elle rédige une réponse, elle ne propose pas de suite.

L'écran lit pourtant le champ `suggestions` et n'affiche la rangée que s'il est
rempli. Le jour où la fonction en produira, les puces apparaîtront sans qu'on
touche à Flutter — et d'ici là il n'y a aucun bouton décoratif qui relancerait
une recherche que personne n'a choisie.

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

* il choisissait le **1er août** pour « un samedi soir en août » — un dimanche —
  et donnait donc le prix d'un dimanche, la majoration du week-end n'étant pas
  la même ;
* il **perdait l'option de 72 heures** en reformulant le parcours de
  réservation : le délai au bout duquel la date se relâche.

Les quatre vivent maintenant dans `avancerJusquAVenir()`,
`prochaineDateAuJour()`, `phraseAnneeSupposee()` et `procedureComplete()`, où
rien ne peut les déformer.

### Une réponse de procédure se vérifie

Le parcours de réservation est une attestation, pas une rédaction. Les quatre
repères — **48 h** de réponse, **25 %** d'acompte, **72 h** d'option, les moyens
de paiement — sont cherchés dans la réponse rendue, chiffres arabes-indiens
compris. S'il en manque un, on rejoue ; s'il en manque encore un, c'est
`PROCEDURE` (ou `PROCEDURE_AR`) qui part **mot pour mot**, dans la langue de la
question. Moins fluide, et juste.

---

## Les critères que le modèle extrait

Le §8.1 dit que la similarité ne sait pas compter. Chaque fois qu'un nombre est
parti dans `soft_query`, le vecteur l'a perdu :

| Demande | Champ | Effet |
|---|---|---|
| « un samedi soir en août » | `jour_semaine` | la date devient le premier samedi à venir **de ce mois-là** |
| « un parking d'au moins 100 places » | `parking_min` | un **filtre** : en dessous, la salle ne convient pas |
| « beaucoup de parking », « bzaf » | `parking_flou` | un **tri** : `p_ordre = 'parking'`, du plus grand au plus petit |
| « la moins chère », « رخيصة » | `prix_bas` | `p_ordre = 'prix'`, et la liste tombe à **trois** salles |

`parking_spaces` est une colonne, pas un équipement : elle a donc un filtre et un
tri, comme toute colonne chiffrée. Le prix, lui, vient toujours d'`estimate_price()`
et de nulle part ailleurs — on n'ajoute qu'un ordre, jamais une seconde formule.

**Le vecteur reste le classement par défaut.** Quand `p_ordre` est donné, il ne
disparaît pas : il passe en second et départage les ex æquo. Une demande chiffrée
se tranche par le chiffre ; ce que le chiffre ne sépare pas, le sens le sépare
encore.

---

## LE GARDE-FOU DU §8.5, ET SA LIMITE

Le banc vérifie SIX choses sur chaque réponse : aucun identifiant hors
contexte, aucune salle non publiée, aucun prix absent de la base, aucun nom
propre coupé entre deux écritures, la réponse écrite dans l'écriture de la
question, et aucun appel à contacter qui que ce soit.

Les quatre premiers vivent aussi DANS la fonction, sous `validerLaReponse()` :
une réponse qui en manque un fait rejouer, et au deuxième échec c'est la liste
brute qui part. Le banc est le second regard, celui qui ne croit pas la
fonction sur parole.

### Contrôle principal : les identifiants

Le modèle rend, à côté de sa réponse, la **liste des `venue_id` qu'il cite**, en
sortie structurée. Chacun doit être dans le contexte ; sinon la génération
rejoue, et au deuxième échec on rend la liste brute.

C'est le seul contrôle qui **ne dépende ni de la langue ni de l'écriture**.

### Filet secondaire : les noms — EN ÉCRITURE LATINE SEULEMENT

Un second passage cherche dans la prose les noms du catalogue entier, brouillons
compris. Il attrape ce que la déclaration ne dit pas : une salle nommée sans que
son identifiant soit déclaré.

**Il ne voyait rien d'une réponse en arabe**, tant que l'agent y translittérait
les noms — `قاعة ابن خلدون` pour Salle Ibn Khaldoun — car aucune comparaison de
chaînes latines ne les y retrouve. Environ un tiers des questions de référence
sont en arabe.

Écrire un détecteur de noms translittérés était exclu : cela demanderait de
deviner comment un modèle rend « Chréa » en arabe, une seconde source de vérité
plus fragile que celle qu'elle prétend garder.

**On a donc pris le problème par l'autre bout : le nom ne se translittère plus.**
La règle 9 du prompt de rédaction impose d'écrire le nom propre
exactement comme le contexte le porte, en écriture latine, même au milieu d'une
phrase en arabe — `قاعة Salle Ibn Khaldoun`. Elle a d'abord une raison d'usage :
c'est le nom que la personne lira sur l'application, et une translittération
l'empêche de l'y retrouver. Elle a pour effet second de rendre ce filet
opérant dans les deux écritures.

**Elle vaut pour TOUT nom propre — salles, communes, wilayas.** Le J21 avait
vu passer Blida écrit avec son article en arabe et sa fin en latin, dans un
seul mot. Illisible dans les deux alphabets, introuvable pour qui le cherche.
Un nom propre s'écrit donc soit en latin comme la base le porte, soit
**entièrement** dans l'écriture de la réponse — et pour cela il faut que la
forme arabe existe quelque part.

| | Forme latine | Forme arabe |
|---|---|---|
| Salle | `venues.name` | aucune → latin obligatoire |
| Commune | `venues.commune` | aucune → latin obligatoire |
| Wilaya | `wilayas.name_fr` | `wilayas.name_ar`, dans le contexte sous `wilaya_ar` |

Interdire la coupure sans fournir la forme arabe serait demander au modèle de
la retrouver de mémoire — c'est précisément ce qu'il a raté. La migration 030
fait donc remonter `wilaya_name_ar` : le nom arabe devient une DONNÉE, comme le
prix et la capacité, et la règle 10 le couvre du même coup.

**Et cette fois le banc le vérifie.** Son quatrième contrôle relit chaque mot
de la réponse : un mot qui mélange les deux alphabets est signalé.

Il tolère le cas qui n'est PAS une coupure, et c'est toute sa difficulté :
l'arabe colle ses monolittères (« et », « pour », « par ») et son article au
mot suivant. Une conjonction arabe écrite devant un nom latin INTACT n'est pas
une faute, et la signaler reviendrait à accuser une réponse correcte. Le banc
retire donc au plus deux monolittères puis l'article, et ce qui reste doit
tenir dans un seul alphabet. L'article ne peut pas manger le début d'un nom
arabe : sur le Blida coupé il ne prend que l'article, le reste est encore à
cheval, et la coupure se voit.

**Ce que cela ne garantit pas.** Une règle de prompt se néglige. Quand le modèle
désobéit et translittère quand même, le filet ne voit rien — comme avant, et
sans le dire. Il échoue ouvert. La garantie, sur une réponse en arabe comme
ailleurs, reste la déclaration d'identifiants : c'est elle qui est vérifiée, et
c'est pour cela que le prompt en fait le champ le plus important.

La question 16 avait produit `قاعة ابن خaldoun` — un nom coupé au milieu entre
les deux écritures, illisible dans l'une comme dans l'autre. C'est ce cas-là,
autant que le filet, que la règle 9 ferme.

### Deux noms qui échappent au filet

Un nom trop court (moins de cinq caractères) ou fait uniquement de mots communs
— le catalogue contient une salle appelée littéralement **« salle »** — n'est
pas cherché dans la prose : il se confondrait avec le vocabulaire courant. Pour
ces salles-là aussi, seul le contrôle par identifiant s'applique.

### La langue de la réponse ne se demande plus : elle se compte

C'était une consigne — la règle 5 du prompt — et elle échouait comme échouent
les consignes : **par intermittence**. La question 15, en darja, a reçu une
réponse française au J20. « بغيت صالة في وهران عندها 300 كرسي » en a reçu une au
J21, alors que la même question, posée au coup d'avant, rendait de l'arabe
impeccable.

**La faute n'était pas dans la rédaction.** Elle était une étape plus haut : le
modèle d'extraction avait classé cette question arabe en `langue: "mixte"` — et
« mixte » veut dire « réponds en français simple ». La rédaction a obéi à une
consigne juste, sur une langue fausse.

Une écriture n'est pas un jugement : c'est un comptage de lettres, du même
ordre que la comparaison de deux dates. `ecritureArabe()` la tranche donc dans
la fonction, et **l'emporte sur ce que le modèle déclare**. Ne lui reste que le
seul vrai jugement, celui qu'aucune plage Unicode ne rend : séparer `fr` de
`mixte`, le français du franco-arabe translittéré — « kayen salle f wahran »
s'écrit dans le même alphabet que « bonjour ».

`langueCorrespond()` relit ensuite la réponse et compte de même. **Les noms
propres sont retirés avant le comptage** : la règle 9 impose de les écrire en
latin au milieu d'une phrase arabe, et sans ce retrait une réponse arabe citant
trois salles porterait des dizaines de lettres latines parfaitement légitimes —
le contrôle accuserait une réponse juste.

**Le banc, lui, lit l'attendu dans la QUESTION, pas dans `criteres.langue`.**
C'est tout son cinquième contrôle : juger la réponse sur l'étiquette que la
fonction s'est donnée, c'est lui demander si elle est d'accord avec elle-même —
et c'est exactement ce qui serait passé inaperçu au J21, l'étiquette étant
fausse et la réponse fidèle à l'étiquette.

### Aucun appel au contact direct (§9)

L'agent a écrit « **Contactez les propriétaires pour vérifier la
disponibilité** ». Deux fautes en une phrase : c'est une invitation à contourner
la plateforme, et il n'y a de toute façon **personne à joindre** — le téléphone
ne se donne qu'une fois la demande acceptée.

La cause était dans le prompt. L'ancienne règle 4 disait « le propriétaire seul
confirme », et le modèle en tirait obligeamment la conclusion qu'il fallait
aller le voir. Elle dit maintenant **où** cela se passe : dans l'application, en
ouvrant la fiche et en envoyant une demande — et nulle part ailleurs. Le plus
souvent, la bonne fin de réponse est de n'en pas avoir.

`appelAuContact()` la vérifie des deux côtés de l'alphabet, aux frontières de
mot : `appeler` et `appelez`, jamais `appelée` — « une salle appelée El Bahia »
est une phrase correcte, et un motif trop large la condamnerait. Côté arabe,
`رقم` seul est écarté : il veut dire « numéro » au sens large, et parlerait d'un
nombre de chaises.

La liste brute du deuxième échec passe ces deux contrôles **par construction** :
son en-tête est dans la langue de la question, et il n'y a pas de prose où
glisser un appel au contact.

---

## Ce qui reste une consigne, et non un garde-fou

Deux règles vivent encore dans le prompt sans que **rien ne les vérifie
mécaniquement** :

1. **Ne renvoyer vers rien** quand la liste est vide — ni « les communes
   voisines », ni « revenez plus tard ».
2. ~~**Répondre dans la langue de la question**~~ — ce n'est plus une consigne
   non plus : l'écriture de la question se compte au lieu de se demander, et le
   banc vérifie celle de la réponse. C'est son cinquième contrôle. Voir plus
   haut.
3. **N'affirmer d'une salle que ce que le contexte contient** (règle 10). La
   question 18 présentait Salle El Bahia comme « proche de la mer » : la base ne
   le dit nulle part, et le contexte envoyé au modèle ne contient aucune
   description. Un fait inventé sur une salle vraie est aussi coûteux qu'une
   salle inventée — la personne se déplace pour rien dans les deux cas — mais
   **aucun contrôle mécanique ne peut le détecter** : vérifier une prose libre
   contre un contexte demanderait un second modèle, qui se tromperait aussi.
4. ~~**Écrire les noms sans les couper entre deux écritures**~~ (règle 9) —
   ce n'est plus une simple consigne : le banc la vérifie, c'est son
   quatrième contrôle. Voir plus haut.
5. **Au plus cinq salles.** Garantie autrement : le contexte lui-même est coupé
   à cinq — trois quand la question porte sur le prix — et un contexte absent ne
   se cite pas.

Ce sont des tendances, pas des certitudes. La 3 est celle qui compte le plus et
c'est aussi celle qu'on sait le moins vérifier : elle repose entièrement sur le
fait que le contexte est **pauvre**. Le jour où l'on y ajoutera la description
libre d'une salle, le modèle aura de la matière à reformuler — et à déborder.

---

## Ce qui manque encore

* **`kb_documents` et le vrai §8.2.** Le parcours de réservation est aujourd'hui
  six lignes en dur dans `PROCEDURE`. Elles ont un avantage sur un RAG — elles
  ne peuvent pas se tromper — et un défaut : toute autre question de support
  reste sans réponse.
* **`ai_cache`, les 30 réponses pré-générées du §8.5**, pour que la démonstration
  survive à un quota épuisé.
* **L'agent n'a AUCUNE MÉMOIRE.** Il reçoit une question et rien d'autre : chaque
  question est traitée seule. Ce que l'écran 8 affiche est un compte rendu de ce
  qui s'est dit, pas un fil que l'agent relit — « et avec un jardin ? » posé
  après coup ne marche pas. L'écran le dit à sa façon, en proposant des exemples
  de questions ENTIÈRES.
* **La limite de débit par utilisateur** (20 messages/jour). Elle demande
  d'identifier l'utilisateur, ce que le journal s'interdit — il faudra décider
  où cette identité vit.
* **Le mode dégradé en recherche plein texte (§8.4).** Si le service d'empreintes
  ne répond pas, l'agent continue **sans vecteur** : le tri exact suffit, le
  classement fin est perdu. Le repli `tsvector` + `pg_trgm` reste à écrire.
* **La description d'une salle n'est pas dans le contexte.** Le modèle reçoit le
  nom, la commune, la capacité, les équipements, le prix et la note — rien qui
  décrive le lieu. C'est ce qui rend la règle 10 tenable aujourd'hui, et ce qui
  empêche l'agent de répondre finement à « une salle près de la mer » autrement
  que par le classement vectoriel. Ajouter la description est un arbitrage à
  faire, pas un oubli.
