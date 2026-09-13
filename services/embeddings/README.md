# Ferha — le service des empreintes

Transforme du texte en vecteurs de 384 nombres, pour la recherche par le sens
(§7.1, §8.4). Il ne connaît aucune salle et ne parle pas à Supabase :
l'indexation et la recherche sont le J19.

Modèle : **`intfloat/multilingual-e5-small`**, export ONNX officiel quantifié en
int8 (`onnx/model_qint8_avx512_vnni.onnx`, 118 Mo). Ni `torch`, ni
`sentence-transformers` — ils ne tiendraient pas dans les 512 Mo de Render.

| | |
|---|---|
| Mémoire mesurée | **259 Mo** au repos, **262 Mo** sous charge |
| Chargement du modèle | 0,7 s |
| Une question courte | 8 ms |
| Les 15 salles du J19, en un lot | 2,1 s |
| Sur le disque | 123 Mo (modèle + vocabulaire) |

Mesures faites sur un poste Windows, un seul fil d'exécution. L'offre gratuite
de Render donne 0,1 vCPU : compter **plus lent** sur les temps, pas sur la
mémoire.

---

## Les deux routes

### `GET /health` — sans jeton

C'est le réveil. Render endort l'offre gratuite après quinze minutes ; le
réveilleur n'a pas à connaître le jeton.

```json
{"etat":"ok","modele":"intfloat/multilingual-e5-small","dimensions":384,"charge":true}
```

### `POST /embed` — jeton obligatoire

```
Authorization: Bearer <EMBED_TOKEN>
```

```json
{ "textes": ["salle des fêtes à Oran"], "nature": "question" }
```

`nature` vaut `question` (ce que tape quelqu'un qui cherche, préfixe `query: `)
ou `salle` (ce qui est indexé, préfixe `passage: `). **Elle n'a pas de valeur
par défaut, et c'est voulu** : les deux préfixes font partie du modèle E5, et se
tromper ne lève aucune erreur — ça dégrade la recherche en silence.

```json
{
  "modele": "intfloat/multilingual-e5-small",
  "dimensions": 384,
  "prefixe": "query: ",
  "vecteurs": [[0.031, -0.047, ...]]
}
```

Les vecteurs sont **normalisés** : leur produit scalaire est leur cosinus. Au
plus 64 textes par appel.

Refus : `401` sans jeton ou avec un mauvais, `400` sur un texte vide, `422` sur
plus de 64 textes ou une `nature` inconnue.

---

## Déployer sur Render, écran par écran

Le dépôt GitHub doit être poussé d'abord — Render lit le code depuis GitHub, pas
depuis le poste.

1. **dashboard.render.com** → bouton **New +** en haut à droite → **Web
   Service**.

2. **Connect a repository** : autoriser Render sur GitHub si ce n'est pas déjà
   fait, puis choisir le dépôt **ferha** → **Connect**.

3. Remplir la page de configuration :

   | Champ | Valeur |
   |---|---|
   | **Name** | `ferha-embeddings` (il donne l'adresse `ferha-embeddings.onrender.com`) |
   | **Language** | `Python 3` |
   | **Branch** | `master` |
   | **Region** | `Frankfurt (EU Central)` — le plus proche de l'Algérie |
   | **Root Directory** | `services/embeddings` |
   | **Build Command** | `pip install -r requirements.txt && python telecharger_modele.py` |
   | **Start Command** | `uvicorn app:app --host 0.0.0.0 --port $PORT` |

   > **Root Directory est le champ qui compte le plus.** Sans lui, Render
   > cherche `requirements.txt` à la racine du dépôt, n'y trouve qu'un projet
   > Flutter, et la construction échoue.

   > **Le modèle se télécharge dans la commande de BUILD**, pas au démarrage.
   > Ce que le build écrit reste sur l'instance : sans cela, les 123 Mo seraient
   > retirés de Hugging Face à chaque réveil, plusieurs fois par jour, et le
   > premier appel expirerait.

4. **Instance Type** : choisir **Free**. ⚠️ Render présélectionne une offre
   payante — il faut descendre dans la liste et cocher **Free** explicitement.
   C'est le seul endroit de cette page où l'on peut se retrouver à payer.

5. **Environment Variables** → **Add Environment Variable** :

   | Key | Value |
   |---|---|
   | `EMBED_TOKEN` | une longue chaîne aléatoire, gardée hors du dépôt |

   Pour en fabriquer une :
   ```powershell
   [Convert]::ToBase64String((1..32 | ForEach-Object { Get-Random -Max 256 }))
   ```

   > Le service **refuse de démarrer** sans `EMBED_TOKEN`. C'est délibéré : un
   > service qui démarrerait en refusant toutes les requêtes ressemble à une
   > panne, et on chercherait la panne ailleurs.

6. **Advanced** → **Health Check Path** : `/health`.

7. **Create Web Service**. La première construction prend cinq à dix minutes,
   surtout à cause des 123 Mo du modèle.

### Ce qu'il faut savoir ensuite

- **Le service s'endort après quinze minutes** sans requête. Le réveil prend 30
  à 60 secondes : la première requête après une pause peut sembler bloquée.
  C'est pour cela que la commande de vérification ci-dessous appelle `/health`
  en premier, avec un long délai d'attente.
- La version de Python est fixée par `.python-version` (3.12.4). Si Render
  l'ignore, ajouter une variable d'environnement `PYTHON_VERSION` = `3.12.4`.

---

## Prouver qu'il comprend les langues

`preuve-multilingue.ps1`, à la racine de ce dossier. Il demande l'empreinte
d'une question **en français**, puis celles de six textes — trois façons de dire
la même chose (arabe, français, franco-arabe) et trois sans rapport — et compare.

```powershell
.\preuve-multilingue.ps1 -url "https://ferha-embeddings.onrender.com" -jeton "VOTRE_JETON"
```

Sortie obtenue **en local** — un `uvicorn app:app` sur ce poste, joint par le
réseau en HTTP, avec la commande de démarrage que Render emploiera. Elle n'a
pas encore tourné contre une instance Render : au J18, rien n'y est déployé.
Ce qu'elle prouve est donc le modèle et le service, pas l'hébergement.

```
  0,8767   AR   arabe standard   قاعة أفراح في وهران
  0,9268   FR   meme sens        salle de mariage a Oran
  0,8572   MIX  franco-arabe     kayen salle f wahran l3ors
  0,8266   HORS mecanique fr     reparation de moteur diesel a Tamanrasset
  0,7918   HORS mecanique ar     إصلاح محرك السيارة
  0,7968   HORS meteo darja      واش راه الطقس

  pire pertinent 0,8572   meilleur hors-sujet 0,8266   marge 0,0306
```

**CE QUI COMPTE EST L'ORDRE, PAS L'ÉCART.** E5 tasse ses cosinus dans une bande
étroite : tout se joue entre 0,75 et 0,95, y compris pour des textes qui n'ont
rien à voir. Une marge de 0,03 n'est donc pas un signe de faiblesse — mais elle
dit au J19 de classer les salles par proximité (les *n* premières) et de **ne
pas** filtrer sur un seuil absolu du genre « garder au-dessus de 0,85 ». Un tel
seuil serait réglé sur trois exemples et se tromperait sur le quatrième.

---

## Vérifier en local, avant de pousser

```powershell
python -m venv .venv
.\.venv\Scripts\pip install -r requirements-dev.txt
.\.venv\Scripts\python telecharger_modele.py
$env:EMBED_TOKEN = "jeton-de-test-local"
.\.venv\Scripts\python verifier.py
```

`verifier.py` contrôle la surface HTTP (dont les 401), la forme et la
normalisation des vecteurs, le déterminisme, le fait que les deux préfixes
donnent bien deux vecteurs différents, le multilingue, et la mémoire pas à pas.

Pour lancer le service en local :

```powershell
$env:EMBED_TOKEN = "jeton-de-test-local"
.\.venv\Scripts\python -m uvicorn app:app --port 8099
.\preuve-multilingue.ps1   # ses valeurs par defaut visent ce service-la
```

---

## Pourquoi `sentencepiece` et pas `tokenizers`

`tokenizers` lit `tokenizer.json` et fait tout toute seule. Elle coûte **266 Mo
de mémoire résidente** — la moitié du budget de Render, pour découper des
phrases. `sentencepiece` lit le même vocabulaire depuis un fichier de 5 Mo et en
coûte **49**. C'est cet écart, et lui seul, qui fait tenir le service.

Le prix à payer est qu'il faut poser à la main le décalage d'XLM-RoBERTa et les
jetons spéciaux — `app.py` l'explique en tête. **Les deux chemins ont été
comparés sur 517 textes** : les trente questions de référence du J20, des fiches
de salle, de l'arabe vocalisé, des ligatures, du tatweel, des emoji, et trois
cents chaînes tirées au hasard dans trois alphabets. Zéro écart.
