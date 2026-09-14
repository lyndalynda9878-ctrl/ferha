# L'arabe — ce qui est traduit, et ce qui ne l'est pas

**Dix écrans** parlent arabe, en deux temps :

* **J22 — le parcours client, sept écrans** : accueil/recherche, résultats,
  fiche salle, calendrier, demande, l'écran de confirmation qui suit l'envoi, et
  l'acompte.
* **Après le J22 — l'authentification, trois écrans** : connexion,
  inscription, profil. Hors plan, et fait d'un bloc.

Le reste de l'application est **en français, et volontairement** : les écrans du
propriétaire, l'assistant, les avis. Une traduction à moitié faite dit plus fort
qu'une absence que le travail est inachevé — on ne s'arrête pas au milieu d'un
parcours, on s'arrête à sa fin.

```
lib/core/l10n/
  app_fr.arb              le modèle : les clés, les descriptions, les pluriels
  app_ar.arb              la version arabe — arabe standard, pas de darja
  formats_ferha.dart      dates, mois, montants, initiales du calendrier
  message_erreur.dart     réseau, délai, session, refus de la base
  locale_controller.dart  la langue active, et où elle est retenue
  generated/              écrit par `flutter gen-l10n`, jamais à la main

lib/features/auth/
  auth_messages.dart      ce qui est propre à GoTrue, et rien d'autre
```

---

## LES TROIS PIÈGES DU §10, ET OÙ CHACUN EST TRAITÉ

### 1. Les prix et les nombres restent en CHIFFRES LATINS

`intl` connaît les chiffres arabes-indiens — ٠١٢٣٤٥٦٧٨٩ — et `NumberFormat` en
locale `ar` les sort de lui-même. « ١٨٠ ٠٠٠ دج » serait typographiquement
irréprochable et pratiquement illisible : en Algérie, les prix, les dates et les
numéros de téléphone s'écrivent en chiffres latins, sur les devantures comme sur
les factures.

**Aucun nombre ne passe donc par `intl`.** `FormatsFerha` les met en forme à la
main, à partir de `toString()`, qui rend toujours des chiffres ASCII quelle que
soit la langue. Ce n'est pas un raccourci : c'est la seule façon d'être sûr que
la langue ne peut pas changer un montant.

Ce qui se traduit d'un montant, c'est sa **devise** : `DA` devient `دج`.

Vérifié par `test/formats_ferha_test.dart`, et sur les écrans eux-mêmes par
`test/six_ecrans_en_arabe_test.dart` et `test/ecrans_auth_en_arabe_test.dart`,
qui relisent **tout** le texte affiché et échouent à la première occurrence d'un
chiffre arabe-indien. Un numéro de téléphone en est un, et c'est celui du profil
qui l'a rappelé : il s'affiche tel que la base le porte, sans mise en forme.

### 2. Les icônes directionnelles se retournent, les autres non

Flutter le fait seul, à une condition : que l'icône porte
`matchTextDirection: true`. C'est le cas de `Icons.arrow_back`,
`Icons.arrow_forward` et `Icons.chevron_right` — et ce n'est pas le cas de
`Icons.search`, `Icons.close` ou `Icons.star`, qui ne montrent aucune direction.

Il n'y a donc **rien à écrire** pour ce piège-là, et c'est exactement ce qui le
rend dangereux : le jour où quelqu'un remplace la flèche de retour par une icône
dessinée à la main, personne ne s'en apercevra en français.

Le test regarde donc la matrice réellement posée à l'écran : la flèche de retour
du calendrier doit être dans un `Transform` qui inverse l'axe des x, et la loupe
de l'accueil ne doit pas l'être.

### 3. Le calendrier commence toujours par dimanche, et se lit de droite à gauche

Les deux à la fois, et ce n'est pas contradictoire : **le miroir est affaire de
direction, pas d'ordre**. Les sept initiales restent dans l'ordre dimanche →
samedi ; c'est le `Row` qui, sous une `Directionality` RTL, pose la première
colonne à droite.

Inverser la liste en arabe mettrait samedi en tête — c'est-à-dire décalerait
toutes les dates d'un cran. Un calendrier faux, dans les deux langues.

---

## UN QUATRIÈME PIÈGE, QUE LES MAQUETTES NE NOMMENT PAS : LE DÉBORDEMENT

Les mots arabes n'ont pas la longueur des mots français. Une rangée qui tenait
de justesse sur 390 px de large n'y tient plus, et Flutter le dit à sa façon —
une bande jaune et noire, et une exception.

`test/six_ecrans_en_arabe_test.dart` et `test/ecrans_auth_en_arabe_test.dart`
montent les dix écrans sur **390 × 844**, la taille du téléphone des maquettes,
et échouent sur la moindre exception de mise en page. Les autres tests d'écran
travaillent sur une fenêtre de 1000 × 2400 — c'est très bien pour vérifier une
logique, et cela ne verrait jamais un débordement.

Les écrans d'authentification sont ceux où ce piège mord le plus : un libellé de
champ, un texte d'aide et un message de validation se superposent dans la même
colonne étroite, et trois lignes arabes plus longues que leurs équivalents
français suffisent à faire déborder un formulaire qui tenait.

---

## LA RELECTURE ÉCRAN PAR ÉCRAN : TROIS ÉTATS, ET NON UN SEUL

Les deux bancs ci-dessus montent les écrans **pleins** — une salle, un devis, un
profil. C'est l'état qu'on dessine, et c'est celui qu'on regarde le moins mal.

`test/relecture_arabe_test.dart` monte les mêmes dix écrans dans les trois
autres : **le chargement**, **le vide**, **l'erreur de réseau**. Trente images,
et quatre contrôles sur chacune — ils sont dans `test/controles_arabe.dart`,
avec ce qu'ils cherchent et pourquoi. Ces trois états-là ne se dessinent pas,
ils se déduisent, et c'est pour cela qu'ils cassent : un squelette calé sur la
longueur du texte français, une phrase de vide plus longue que tout le reste de
l'écran, un message d'erreur et son bouton sur une même ligne.

`test/ecrans_non_traduits_en_arabe_test.dart` monte en arabe les écrans qui sont
restés en français — propriétaire, assistant, avis — et ne leur demande que deux
choses : ne pas tomber, ne pas déborder. Ils s'affichent de droite à gauche dès
que la langue change, et un `left` oublié ne se voit qu'en RTL. Il les monte
aussi **en français, à la même taille** : sans ce témoin, un débordement ne dit
pas s'il vient de l'arabe ou de la largeur du téléphone.

### Le piège du banc lui-même : `flutter test` n'a pas de police

`flutter test` ne charge aucune police et rend chaque signe dans un **carré** de
la taille du corps. « Assistant Ferha » en corps 20 y mesure 297 px là où
Bricolage Grotesque en donne environ 150 — et la barre de titre de l'assistant
« débordait » de 69 px sans que rien ne cloche à l'écran.

Sur une fenêtre de 1000 px, cela ne se voyait pas. Sur les 390 px des maquettes,
cela invente des défauts. Les deux bancs de la relecture chargent donc la police
de la charte (`chargeLaPoliceDeLaCharte`, dans `controles_arabe.dart`) avant de
mesurer quoi que ce soit. Le texte courant, lui, prend la police système, que le
test ne sait pas charger : sur lui, le contrôle exagère encore la largeur. Il
peut crier pour rien, il ne peut pas se taire à tort — c'est le bon sens de
l'erreur, et c'est pour cela qu'on le garde ainsi.

---

## CE QUI RESTE EN FRANÇAIS À L'ÉCRAN, ET QUI N'EST PAS UN OUBLI

Trois catégories, et le contrôle des textes français les nomme une par une
(`donneesDeLaBase` et `motsQuiRestentLatins`) :

1. **Les libellés d'options**, qui viennent de `venue_options.label_fr`.
   `label_ar` existe et personne ne l'écrit encore.
2. **Les équipements, les types d'événement et les wilayas**, qui viennent
   d'`amenities.label_fr`, d'`event_types.label_fr` et de `wilayas.name_fr` —
   les trois `select` de `search_providers.dart` le disent. Voir plus bas : ces
   73 libellés attendent une relecture humaine.
3. **Des mots latins DANS une phrase arabe**, et la phrase, elle, est bien
   traduite : « بطاقة CIB » (une marque), « الدخول بحساب Amina » (un compte de
   démonstration), « الترحيل 007_auth.sql … مشروع Supabase » (un nom de fichier
   et un nom de produit, dans une phrase qui s'adresse à celui qui installe), et
   « Français » — la bascule annonce toujours la langue vers laquelle elle mène.

La troisième n'était pas prévue : c'est le banc qui l'a trouvée.

---

## L'ESPACEMENT DES CAPITALES NE VAUT PAS POUR L'ARABE

Les intitulés de section de la charte sont des capitales espacées
(`letterSpacing: 1.2`). **En arabe, les lettres d'un mot se lient** : les écarter
ne donne pas un titre aéré, cela casse les liaisons et rend le mot
méconnaissable.

`context.espacementDesCapitales()` rend la valeur de la charte en écriture
latine et zéro en arabe. Ce n'est pas une valeur de charte — c'est une propriété
de l'écriture, au même titre que le sens de lecture.

---

## LA BASCULE DE LANGUE, ET SES DEUX ÉCRITURES

Elle est dans le **Profil**, en haut à droite, et elle annonce toujours la langue
vers laquelle elle mène — jamais celle qu'on lit. Un bouton « Français » sur une
page française ne dit pas s'il change quelque chose.

| Où | Ce que ça suit | Quand ça sert |
|---|---|---|
| `profiles.locale` | le **compte** | on se reconnecte depuis un autre téléphone ; un jour, un courriel ou une notification |
| préférence d'appareil (`shared_preferences`) | le **téléphone** | un visiteur sans compte — c'est-à-dire tout le parcours du §3 jusqu'à l'envoi |

**C'est l'appareil qui décide au démarrage**, et c'est la seule chose qui compte
ici : elle se lit avant la première image, sans réseau. Faire dépendre la langue
du profil ferait s'ouvrir l'application en français chez quelqu'un qui l'a mise
en arabe, le temps d'une requête — un clignotement, et dans le mauvais sens de
lecture.

**Écrire dans le profil ne fait jamais échouer la bascule.** La langue a déjà
changé à l'écran quand la requête part ; si le réseau est tombé, on garde le
choix sur l'appareil et on se tait. Refuser de changer de langue faute de réseau
serait absurde.

**Le changement s'applique sans redémarrer** : `MaterialApp.locale` lit
`localeProvider`, et changer son état reconstruit l'arbre entier — titres, barre
d'onglets, direction du texte. Une application qu'on doit fermer pour changer de
langue apprend à son utilisateur qu'il s'est trompé de bouton.

> `shared_preferences` est autorisé ici, et seulement pour cela : une langue est
> une **préférence d'affichage**. La règle du projet vaut toujours — aucune
> donnée métier, aucun jeton, aucun prix ne va dans ce fichier en clair.

---

## AJOUTER UN TEXTE

1. la clé et sa **description** dans `app_fr.arb` — la description dit *où* le
   texte s'affiche et *pourquoi* il est formulé ainsi, pas ce qu'il veut dire ;
2. la traduction dans `app_ar.arb` ;
3. `flutter gen-l10n` ;
4. `AppLocalizations.of(context).maCle` dans l'écran.

**Un texte écrit en dur dans l'un des écrans traduits fait échouer un test.**
`test/textes_en_dur_test.dart` relit ces fichiers comme du texte et signale
toute chaîne qui ressemble à de la prose — des lettres, et une espace ou un
accent — ou à un libellé de bouton (un seul mot capitalisé). Il interdit aussi
d'y appeler `dateEnFrancais`, `nomMois`, `montantEnDinars`,
`messageErreurAuthEnFrancais` et leurs semblables, qui n'écrivent qu'en
français.

### Trois registres pour un créneau, et pourquoi

Le français écrit « Soir » sur une puce, « Soirée » en tête de phrase et
« soirée » au milieu d'une phrase. L'arabe écrit السهرة dans les trois cas.
Appeler `toLowerCase()` sur un libellé traduit marcherait **par accident** en
arabe — la casse n'y existe pas — et cacherait que c'est une question de langue.
D'où `CreneauTraduit.surUnePuce`, `.dansUnePhrase`, `.auMilieuDUnePhrase`.

### Les pluriels arabes ont six formes

`zero`, `one`, `two`, `few`, `many`, `other` — et ce n'est pas de la
coquetterie : « قاعتان » (deux salles) n'est pas « 2 قاعات ». C'est la raison
d'être des pluriels ICU dans `resultatsSalles`, `ficheAvisVerifies` et
`demandeCouvertsAuDela`, là où le français se contenterait d'un « s ».

### Les erreurs de GoTrue se lisent par leur CODE

`auth_messages.dart` ne traite que ce qui est propre à l'authentification — mot
de passe faible, adresse déjà prise, compte suspendu — et passe **tout le reste**
à `message_erreur.dart`. Les cas que les deux partagent portent les mêmes clés :
`erreurReseau`, `erreurDelaiDepasse`, `erreurSessionExpiree`, `erreurBaseRefuse`,
`erreurInattendue`. Une session expirée se dit pareil qu'on la découvre en se
connectant ou en envoyant une demande.

**Un repli sur le message anglais vivait là**, pour les versions de GoTrue qui ne
renvoyaient pas de code sur certaines réponses. Il est parti avec la traduction
de ces écrans-là, pour une raison qui n'existait pas tant qu'ils étaient
français : reconnaître une
phrase anglaise pour en choisir une française marchait ; le faire pour en choisir
une arabe revient à traduire une traduction. Le code est un contrat, le message
est une formulation.

Quand le code est inconnu, `authRefusNonTraduit` le **nomme** et montre le
message d'origine. Il est en anglais, et c'est mieux qu'un « une erreur est
survenue » qui ferait perdre le temps qu'il prétend faire gagner.

`messageErreurAuthEnFrancais` reste pour les écrans **non traduits** — le
propriétaire, les avis — qui s'en servent comme repli au bout de leurs propres
traducteurs. Elle lit le modèle français, la même source que la version
traduite : leurs phrases ne vivent donc pas ailleurs que dans les ARB. Elle
disparaîtra le jour où ces écrans passeront à l'arabe.

### Les mois sont ceux de l'Algérie

جانفي, فيفري, أفريل, جوان, جويلية, أوت — et non يناير, فبراير, أغسطس. La
seconde série est de l'arabe correct écrit pour quelqu'un d'autre ; la première
est celle qu'on lit sur un calendrier algérien, dans un journal algérien et sur
un acte d'état civil algérien.

---

## LES LIBELLÉS DE LA BASE ATTENDENT UNE RELECTURE

Les équipements, les types d'événement et les 58 wilayas portent un libellé
arabe en base, marqué `-- À RELIRE` dans les migrations 003, 009 et 010 : ils ont
été écrits sans relecture par un locuteur natif.

`supabase/outils/libelles_arabes.ps1` en tire la liste complète — code, français,
arabe actuel, et une colonne vide pour la correction — dans
`docs/libelles-arabes-a-relire.md`. La mention ne sera retirée que sur ce qui
aura été relu.

**Ces libellés ne sont pas dans les fichiers ARB, et ils n'y seront jamais** :
ce sont des données, pas des textes d'interface. Un équipement ajouté en base
apparaît dans l'application sans qu'on recompile quoi que ce soit.

## LES TRADUCTIONS DE L'AUTHENTIFICATION ONT ÉTÉ RELUES

Les 52 clés ajoutées après le J22 pour la connexion, l'inscription et le profil
ont été **relues et validées** par un locuteur natif, sans aucune correction.
`docs/traductions-auth-a-relire.md` en garde la trace, groupée par écran.

Ce document est une **vue** : la traduction ne vit que dans `app_ar.arb`. Une
relecture sans correction ne change donc pas une ligne — rien n'a été touché.

**Aucun test ne peut dire si une traduction est juste.** Les bancs vérifient
qu'un écran tient, qu'il se lit dans le bon sens et qu'il ne montre pas de
chiffres arabes-indiens ; que « أنشئ حسابي » soit la bonne façon de dire « Créer
mon compte » ne se vérifie qu'en le lisant. C'est pour cela que ces 52 lignes
sont passées sous des yeux, et c'est la seule vérification qui vaille pour
elles.

Les libellés arabes de la **base**, eux, attendent toujours — voir la section
précédente.

---

## CE QUI MANQUE ENCORE

* **Les écrans du propriétaire** (§4.3) — tableau de bord, agenda, détail d'une
  demande, publication d'une salle, photos. C'est le plus gros morceau restant,
  et il a sa propre logique : un propriétaire lit des états de réservation, des
  indicateurs et des créneaux, un vocabulaire que le parcours client ne
  rencontre pas. `nomMois` est descendu dans `agenda_screen.dart` en attendant.
* **L'assistant** (écran 8). Cas particulier : sa réponse suit la langue de la
  QUESTION, pas celle de l'application — c'est ce que fait déjà
  `direction_du_texte.dart`. Ce qui reste à traduire est l'écran autour : le
  champ, les exemples, les états.
* **Les avis** (§5.4), et la synthèse qui les résume — même particularité : la
  synthèse est rédigée dans la langue des avis.
* **Les textes que la base envoie** : les messages des notifications (§7.2) et
  les courriels. Ils ne passent pas par l'application, et `profiles.locale`
  existe précisément pour eux.
* **Le nom de l'application dans une phrase arabe.** L'assistant écrit parfois
  « تطبيق فرحة », parfois « فِرحة » : `appTitle` dit فرحة, et c'est cette
  forme-là qui fera foi le jour où on la lui imposera.
