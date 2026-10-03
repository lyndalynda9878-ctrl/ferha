# La recherche et l'assistant

Retour au [README](../README.md).

## La recherche

L'accueil **est** la recherche : où, quand, combien, et le
bouton part. Les résultats gardent les filtres actifs en tête, chacun
retirable d'un tap.

**Rien n'est filtré ni calculé en Dart.** Une seule fonction SQL,
`search_venues()`, prend les critères et renvoie des lignes déjà triées, déjà
tarifées. Le prix d'une carte est celui de la **date choisie**, majorations
comprises — pas un « à partir de », et pas un montant qui changerait entre
la liste et la fiche.

Le nombre d'invités sert deux fois : il écarte les salles trop petites, et il
entre dans le calcul du prix comme nombre de couverts. « 300 invités » affiche
donc le prix pour 300 couverts, supplément compris.

Les critères voyagent dans l'URL (`/resultats?wilaya=31&date=…`) et non dans
l'état : sur le web, une recherche se copie, se partage et survit à un
rechargement.

Le filtre **type d'événement** retire vraiment des salles : `venue_event_types`
dit ce que chaque salle accepte. Trois salles de démonstration refusent quelque
chose, pour que le filtre se voie à l'usage — le grand palais de Zéralda ne
fait que mariages et fiançailles, la petite salle d'Ouled Yaïch ne fait pas de
mariage. Une salle qui n'a **rien déclaré accepte tout** : le silence d'un
propriétaire ne vaut pas refus.

### Ce qui ne s'affiche pas

Une salle **sans avis n'a pas d'étoiles**. Pas « 0,0 (0) » : une salle neuve
n'est pas une salle mal notée. La base renvoie `NULL` plutôt que zéro, et
l'écran d'accueil intitule sa liste « Salles à découvrir » tant qu'aucune note
n'existe, « Les mieux notées » ensuite.

### Les trois états

| État | Ce qu'on voit |
|---|---|
| Chargement | des cartes squelettes, à la forme de ce qui arrive |
| Vide | ce qui bloque, **nommé**, et un bouton par critère à retirer |
| Erreur | le message traduit, un bouton Réessayer, et le détail technique repliable |

L'état vide ne dit jamais « aucun résultat » tout court : il nomme le critère le
plus probablement responsable — une date déjà prise, un budget sous le prix réel
d'un vendredi d'été — et chaque piste proposée est un bouton qui retire
vraiment ce critère.

### Sans compte

Chercher et consulter ne demandent **aucune connexion**. Voir la règle de
navigation dans [Architecture](architecture.md#la-règle-de-navigation).

## La recherche sémantique

Les filtres SQL répondent à « Oran, 300 personnes, avec parking ». Ils ne
répondent pas à « une salle lumineuse pas trop loin de la mer pour un mariage
d'été » : aucune colonne ne porte « lumineuse ». La recherche sémantique
travaille sur le sens plutôt que sur les colonnes, et vient **par-dessus** le
filtre — elle ne le remplace pas, elle reclasse ce qu'il a laissé passer.

Chaque salle est résumée en un document bilingue — nom, commune, wilaya en
français **et en arabe**, types d'événement, équipements — puis transformée en
vecteur. Le modèle est **`intfloat/multilingual-e5-small`**, en **384
dimensions**, servi par un petit service Python sur Render. Bilingue à dessein :
la moitié des questions arrivent en arabe, et il faut qu'elles tombent sur les
mêmes salles.

**Quand le service dort, la recherche continue sans lui.** L'instance gratuite
s'endort, et le premier appel coûtait 62 secondes. L'assistant abandonne
désormais au bout de 2 secondes et répond avec les filtres seuls : le classement
est moins fin, la réponse arrive. Abandonner ne coûte pas le réveil — Render
démarre l'instance dès que la requête atteint son routeur et poursuit même si le
client s'en va — donc le premier visiteur paie 2 secondes au lieu de 62, et le
suivant trouve un service chaud.

## L'assistant

Il répond sur le catalogue et sur le parcours de réservation. **Il refuse le
reste, et c'est le travail, pas une limite subie.** Entre une réponse inventée
et « je ne sais pas », le second garde la confiance ; le premier la perd une
fois pour toutes. « Quel temps fait-il ? » n'obtient pas de réponse. « Comment
réserver ? » en obtient une.

Les procédures qu'il récite — le parcours en six étapes, l'acompte de 25 %,
l'option de 72 h — sont des **textes écrits à la main**, en français et en
arabe, constants dans `supabase/functions/ai-chat/index.ts`. Le modèle ne les
compose pas : il les rend. C'est moins souple qu'une base de connaissances, et
cela a un avantage qu'aucune base de connaissances n'a — ces textes ne peuvent
pas se tromper. La version arabe existe séparément non pour traduire, mais pour
garantir : quelqu'un qui écrit en arabe mérite le repli dans sa langue.

Ce qu'il sait faire, ce qui l'a fait échouer pendant la mise au point, et le
banc des trente questions qui le tient sont écrits dans
[`supabase/functions/ai-chat/README.md`](../supabase/functions/ai-chat/README.md).

