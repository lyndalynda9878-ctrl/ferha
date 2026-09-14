# Ferha — la mise en ligne du web

Une adresse publique qui ouvre l'application, **alors que le dépôt reste privé**.

Hébergeur : **Cloudflare Pages**, en mode *Direct Upload*. GitHub Actions
construit, Cloudflare sert.

| | |
|---|---|
| `build/web` sur le disque | **31,85 Mo** en 34 fichiers |
| Le plus gros fichier | `canvaskit/canvaskit.wasm`, **6,73 Mo** |
| Ce qu'une PREMIÈRE visite télécharge | **~4 Mo** compressés |
| Limites de Pages | 25 Mio par fichier, 20 000 fichiers — on en est loin |

> **Les 31,85 Mo ne sont pas ce que le visiteur télécharge.** Le dossier
> `canvaskit/` pèse à lui seul **25,75 Mo** : quatre variantes du moteur de
> rendu (20,13 Mo de `.wasm`), dont le navigateur n'en prend **qu'une**, et
> quatre tables de symboles (5,34 Mo) qui ne servent qu'à relire une pile
> d'appels et ne sont jamais demandées par une page.
>
> Le vrai coût d'une première visite, compressé par Cloudflare : `main.dart.js`
> 1,10 Mo, `canvaskit.wasm` 2,04 à 2,70 Mo selon le navigateur, la police
> 0,24 Mo — et quelques kilo-octets pour le reste.

---

## Pourquoi pas GitHub Pages, et pourquoi pas d'APK

**GitHub Pages exige un dépôt public.** Le code de Ferha reste fermé : cette
seule ligne écarte l'hébergeur le plus évident. Cloudflare Pages lit les dépôts
privés, ne demande pas de carte bancaire et n'endort pas le site — contrairement
à Render, qui héberge le service des empreintes et met une minute à se réveiller.

**L'APK est reporté.** Sur un dépôt privé, le fichier attaché à une *Release*
n'est pas téléchargeable sans compte autorisé : le lien serait mort pour qui le
reçoit. Et quelqu'un qui découvre un travail ouvre une adresse, il n'installe pas
un paquet Android.

---

## Ce qui ne change pas dans le code

Deux choses ont été vérifiées avant d'écrire quoi que ce soit, et aucune ne
demande de modification.

### `<base href="/">` est déjà la bonne valeur

`web/index.html` porte `<base href="$FLUTTER_BASE_HREF">`, et
`flutter build web` y écrit `/` par défaut. C'est exactement ce qu'il faut pour
un site servi **à la racine** d'un sous-domaine, ce qui est le cas de
`<NOM-DU-PROJET>.pages.dev`.

> `--base-href` ne servirait que si l'application vivait dans un
> SOUS-DOSSIER — `exemple.com/ferha/`. Ce n'est pas le cas ici, et le mettre à
> `/ferha/` casserait tout : le navigateur chercherait `main.dart.js` dans un
> dossier qui n'existe pas.

### Le routage par dièse rend toute réécriture inutile

C'est exact, et voici pourquoi. Aucun `usePathUrlStrategy()` n'est appelé dans
`lib/` : Flutter web garde donc sa stratégie par défaut, le **fragment**. Les
adresses de l'application s'écrivent `https://…/#/salle/<id>`, et **tout ce qui
suit le `#` ne quitte jamais le navigateur** — le serveur ne voit que `/`, qui
sert `index.html`. Il n'y a rien à réécrire parce qu'il n'y a rien à router.

Pas de `_redirects`, donc, et pas de règle de *SPA fallback*.

> **Ce qui rendrait la règle obligatoire :** le jour où quelqu'un appellera
> `usePathUrlStrategy()` pour avoir des adresses sans dièse. Ce jour-là,
> `https://…/salle/<id>` arriverait vraiment jusqu'à Cloudflare, qui répondrait
> 404, et il faudrait un fichier `web/_redirects` contenant `/* /index.html 200`.
> Tant que le dièse est là, ce fichier serait un mystère pour le prochain
> lecteur.

Un détail qui n'est pas un défaut : une adresse tapée à la main **sans** dièse
(`https://…/accueil`) rend un 404 de Cloudflare. L'application ne fabrique
jamais de telles adresses, donc personne ne l'obtient en naviguant.

---

## 1. Cloudflare, écran par écran

Rien de tout cela n'a été fait : il n'y a pas encore de compte.

1. **dash.cloudflare.com** → créer un compte, confirmer l'adresse e-mail. Aucune
   carte bancaire n'est demandée. **Ne pas** ajouter de domaine : Pages donne son
   propre sous-domaine.

2. Menu de gauche → **Workers & Pages** → bouton **Create application** →
   onglet **Pages** → **Upload assets**.

3. **Le nom du projet.** Il décide de l'adresse : `<NOM-DU-PROJET>.pages.dev`.

   > ⚠️ **Si le nom est déjà pris, Cloudflare y ajoute quelques caractères au
   > hasard** et le dit à ce moment-là. L'adresse finale n'est donc pas
   > forcément celle qu'on croyait. **Note-la** : trois choses en dépendent — le
   > secret `CLOUDFLARE_PROJECT_NAME`, le `Site URL` de Supabase et la variable
   > `APP_ORIGIN`.

4. **Le premier envoi, à la main.** Glisser le contenu du dossier `build/web`
   (construit en local par `flutter build web --release
   --dart-define-from-file=env.json`) et **Deploy site**.

   > Ce premier envoi manuel n'est pas une corvée pour rien : il **crée** le
   > projet, que le workflow ne sait pas créer tout seul, et il donne un site
   > vivant à regarder avant d'automatiser quoi que ce soit. Si quelque chose
   > cloche à cette étape, ce n'est pas GitHub Actions qu'il faut déboguer.

5. **La branche de production.** Dans les réglages du projet, celle qui est
   déclarée comme branche de production doit être **`master`** — le dépôt n'est
   pas sur `main`.

   > ⚠️ **C'est le piège de Pages.** `wrangler pages deploy --branch=…` publie
   > en PRODUCTION si la branche correspond, et en APERÇU sinon. Un aperçu
   > s'ouvre à une adresse qui change à chaque envoi, et l'adresse publique
   > `<NOM-DU-PROJET>.pages.dev` reste alors sur le premier envoi manuel, pour
   > toujours, sans qu'aucune erreur ne soit levée. Symptôme : le site en ligne
   > ne bouge plus alors que le workflow est vert.

6. **Le jeton d'API.** Coin haut droit → **My Profile** → **API Tokens** →
   **Create Token** → **Create Custom Token**.

   Sous **Permissions**, une seule ligne : **Account** · **Cloudflare Pages** ·
   **Edit**. Rien d'autre — un jeton qui ne peut que déployer des pages ne peut
   pas faire autre chose s'il fuit.

   Le jeton ne s'affiche **qu'une fois**. Il va directement dans les secrets
   GitHub de l'étape 2, sans passer par un fichier ni par une conversation.

7. **L'identifiant du compte.** Page **Workers & Pages**, colonne de droite :
   **Account ID**. Il est aussi dans l'adresse du tableau de bord, entre
   `dash.cloudflare.com/` et le reste.

---

## 2. GitHub, les cinq secrets

Dépôt → **Settings** → **Secrets and variables** → **Actions** → onglet
**Secrets** → **New repository secret**, cinq fois.

| Nom du secret | Où le prendre |
|---|---|
| `SUPABASE_URL` | `env.json`, à la racine du dépôt |
| `SUPABASE_ANON_KEY` | `env.json` également |
| `CLOUDFLARE_API_TOKEN` | étape 1.6 ci-dessus |
| `CLOUDFLARE_ACCOUNT_ID` | étape 1.7 ci-dessus |
| `CLOUDFLARE_PROJECT_NAME` | le nom retenu à l'étape 1.3 |

> **`GITHUB_TOKEN` n'est pas dans cette liste et ne doit pas y être.** GitHub le
> fabrique à chaque exécution. Le workflow s'en sert uniquement pour faire
> apparaître le déploiement dans l'onglet *Deployments* du dépôt.

> **`SUPABASE_ANON_KEY` n'est pas un secret**, au sens propre : elle part dans
> le JavaScript servi au navigateur, et n'importe qui peut la lire depuis le
> site. Elle est ici parce que la règle du projet est qu'**aucune clé ne dort
> dans le dépôt** — pas même publique, pas même en exemple. Ce qui la borne
> n'est pas son secret, ce sont les politiques RLS.

> **`CLOUDFLARE_PROJECT_NAME` n'est pas sensible non plus.** Il pourrait vivre
> dans l'onglet *Variables*, à côté. Il est dans les secrets pour qu'il n'y ait
> qu'UN écran à remplir et qu'UN écran à relire le jour où quelque chose ne
> marche pas.

Le workflow **refuse de construire** si l'un des cinq manque ou est vide, et il
nomme lesquels — jamais leur valeur. Sans ce garde-fou, un `SUPABASE_URL` absent
ne casserait rien : `flutter build web` réussirait, et le site se mettrait en
ligne sur l'écran de configuration. On chercherait la panne dans Cloudflare
pendant une heure.

---

## 3. Supabase, ce qu'il faut ajouter

Trois choses, et la troisième est celle qu'on oublie.

### Les adresses de retour de l'authentification

Tableau de bord Supabase → **Authentication** → **URL Configuration**.

| Champ | Ce qu'on y met |
|---|---|
| **Site URL** | `https://<NOM-DU-PROJET>.pages.dev` |
| **Redirect URLs** | ajouter `https://<NOM-DU-PROJET>.pages.dev/**` — **sans retirer** les adresses `http://localhost:*` du développement |

`auth_service.dart` appelle `signUp` **sans** `emailRedirectTo` : le lien de
confirmation envoyé par courriel retombe donc sur le **Site URL**, et sur rien
d'autre. Tant qu'il vaut `localhost`, un compte créé depuis le site public reçoit
un lien qui ne mène nulle part — sur la machine du destinataire, `localhost`,
c'est chez lui.

Le `**` traverse les barres obliques : il couvre `…/` comme `…/#/accueil`.

### `APP_ORIGIN`, pour le paiement

Tableau de bord Supabase → **Edge Functions** → **Secrets** :

| Nom | Valeur |
|---|---|
| `APP_ORIGIN` | `https://<NOM-DU-PROJET>.pages.dev` |

> ⚠️ **Une ORIGINE, pas une adresse.** Ni barre oblique finale, ni chemin, ni
> dièse. `create-checkout` compare `new URL(success_url).origin` à cette
> chaîne, au caractère près, et `origin` ne porte jamais de barre finale.
> `https://<NOM-DU-PROJET>.pages.dev/` — avec la barre — refuserait donc TOUS
> les paiements : la fonction rendrait `FE057`, que l'application traduit par
> « le paiement n'a pas pu être lancé », sans dire lequel des deux côtés a
> tort.

Ce que cela change : `urlDeRetour()` n'acceptera plus que les adresses de retour
de ce domaine — et celles de `localhost`, laissées ouvertes pour le
développement. La variable est **facultative** ; jusqu'ici elle n'était pas
posée, et n'importe quelle adresse http(s) était acceptée. Le commentaire en tête
de `create-checkout/index.ts` le dit depuis le J15 : « le jour où l'application
aura un domaine, cette variable ferme la porte sans qu'une ligne de code
change ». C'est ce jour-là.

> Revenir sur `success_url` ne confirme **aucun** paiement — c'est
> `chargily-webhook` qui confirme. `APP_ORIGIN` ne protège donc pas l'argent,
> elle empêche seulement qu'on renvoie un client ailleurs après sa propre
> transaction.

### La CORS : rien à faire, et c'est vérifié

L'application n'appelle que deux fonctions — `ai-chat` (l'assistant) et
`create-checkout` (le paiement) —, et les deux répondent déjà
`Access-Control-Allow-Origin: *`. L'API PostgREST de Supabase est ouverte à
toutes les origines par construction ; ce qui borne ce qu'on en tire, ce sont les
politiques RLS, pas l'origine de l'appel.

Aucun réglage de CORS à changer, donc, ni côté Supabase, ni côté Cloudflare.

---

## 4. Le premier déploiement automatique

Une fois les cinq secrets posés :

1. Pousser sur `master` — ou, sans rien à pousser, dépôt → **Actions** →
   **Mise en ligne** → **Run workflow**.
2. Suivre l'exécution dans l'onglet **Actions**. Elle fait, dans l'ordre : les
   cinq secrets, Flutter, `flutter pub get`, `flutter test`, la construction, et
   l'envoi.
3. La dernière étape écrit l'adresse déployée dans son journal. Elle doit être
   `https://<NOM-DU-PROJET>.pages.dev` — **si c'est une adresse à rallonge avec
   un identifiant devant, c'est un aperçu** : revoir l'étape 1.5.

> **Les tests tournent aussi ici, et c'est voulu.** `ci.yml` s'exécute sur le
> même push, mais en parallèle : rien ne garantit qu'il ait fini, ni qu'il soit
> vert, au moment où celui-ci publie. Une demi-minute de tests coûte moins cher
> qu'une application cassée en ligne.

### Vérifier que le site est vivant

Sur un téléphone, ou une fenêtre de 390 px de large :

- [ ] La page s'ouvre sur l'accueil — **pas** sur l'écran de configuration
      (s'il apparaît : `SUPABASE_URL` ou `SUPABASE_ANON_KEY` n'est pas arrivée
      jusqu'à la construction).
- [ ] La recherche rend des salles : la base répond, donc la clé est bonne.
- [ ] Basculer en arabe depuis le profil : la page se retourne sans recharger.
- [ ] Ouvrir une fiche, **copier l'adresse, la recharger** : elle doit revenir
      sur la même salle. C'est ce que vérifient `galerie_rechargement_test.dart`
      et `demande_envoyee_rechargement_test.dart` ; la production est le seul
      endroit où l'historique du navigateur est le vrai.
- [ ] Créer un compte et cliquer le lien du courriel : il doit revenir sur le
      site, pas sur `localhost`.

---

## Ce qu'il faut savoir ensuite

- **Le cache du navigateur.** `main.dart.js` garde le même nom d'une version à
  l'autre : rien dans l'adresse ne dit qu'il a changé. C'est le
  `flutter_service_worker.js` qui s'en occupe, en comparant `version.json`. Si
  un jour une mise à jour semble ne pas arriver, c'est là qu'il faut regarder —
  et un rechargement forcé (Ctrl+Maj+R) tranche la question en deux secondes.

- **Le dépôt reste privé.** Cloudflare ne lit pas le code : GitHub Actions lui
  envoie un dossier de fichiers déjà construits. Rien de ce qui est publié ne
  contient de source Dart — sauf `assets/NOTICES`, qui ne porte que les licences
  des dépendances.

- **Le jour où le dépôt deviendra public**, rien de ceci ne devient inutile :
  GitHub Pages resterait plus lent à servir depuis l'Algérie, et le workflow
  d'ici marche déjà.

- **L'APK reste à faire** (J24b ou plus tard). Il demande une signature, un
  `keystore` hors du dépôt, et un endroit où poser le fichier qui ne soit pas
  une *Release* de dépôt privé.

- **Rien n'a été déployé en écrivant ce document.** Aucun compte n'a été créé,
  aucun secret n'a été posé, et `build/web` n'a pas quitté cette machine.
