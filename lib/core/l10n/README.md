# L'arabe — ce qui est traduit, et ce qui ne l'est pas

**Six écrans** parlent arabe depuis le J22 : accueil/recherche, résultats, fiche
salle, calendrier, demande, acompte — plus l'écran de confirmation qui suit
l'envoi d'une demande, qui appartient au même geste.

Le reste de l'application est **en français, et volontairement** : les écrans du
propriétaire, l'assistant, les avis, la connexion. Une traduction à moitié faite
dit plus fort qu'une absence que le travail est inachevé — on ne s'arrête pas au
milieu d'un parcours, on s'arrête à sa fin.

```
lib/core/l10n/
  app_fr.arb              le modèle : les clés, les descriptions, les pluriels
  app_ar.arb              la version arabe — arabe standard, pas de darja
  formats_ferha.dart      dates, mois, montants, initiales du calendrier
  message_erreur.dart     les erreurs que ces six écrans peuvent montrer
  locale_controller.dart  la langue active, et où elle est retenue
  generated/              écrit par `flutter gen-l10n`, jamais à la main
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
`test/six_ecrans_en_arabe_test.dart`, qui relit **tout** le texte affiché et
échoue à la première occurrence d'un chiffre arabe-indien.

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

`test/six_ecrans_en_arabe_test.dart` monte les sept écrans sur **390 × 844**, la
taille du téléphone des maquettes, et échoue sur la moindre exception de mise en
page. Les autres tests d'écran travaillent sur une fenêtre de 1000 × 2400 —
c'est très bien pour vérifier une logique, et cela ne verrait jamais un
débordement.

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

**Un texte écrit en dur dans l'un des six écrans fait échouer un test.**
`test/textes_en_dur_test.dart` relit ces fichiers comme du texte et signale
toute chaîne qui ressemble à de la prose — des lettres, et une espace ou un
accent — ou à un libellé de bouton (un seul mot capitalisé). Il interdit aussi
d'y appeler `dateEnFrancais`, `nomMois`, `montantEnDinars` et leurs semblables,
qui n'écrivent qu'en français.

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
* **La connexion et l'inscription**, et avec elles `auth_messages.dart`. Le jour
  où ils seront traduits, c'est ce fichier-là qui rejoindra `message_erreur.dart`,
  pas l'inverse : les phrases sont déjà identiques des deux côtés pour les cas
  qu'ils partagent.
* **Les textes que la base envoie** : les messages des notifications (§7.2) et
  les courriels. Ils ne passent pas par l'application, et `profiles.locale`
  existe précisément pour eux.
* **Le nom de l'application dans une phrase arabe.** L'assistant écrit parfois
  « تطبيق فرحة », parfois « فِرحة » : `appTitle` dit فرحة, et c'est cette
  forme-là qui fera foi le jour où on la lui imposera.
