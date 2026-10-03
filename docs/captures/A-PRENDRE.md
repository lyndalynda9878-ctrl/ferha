# Les six captures du README

Le README les appelle par leur nom : un fichier renommé, ou une extension
doublée (`.png.png`), et l'image est cassée sans erreur nulle part. Prises le
3 octobre 2026 ; ce fichier dit comment les reprendre à l'identique.

Toutes se prennent sur <https://ferha.pages.dev>, pas en local : c'est le site
que le lecteur ouvrira, et une capture d'un `localhost` se reconnaît à sa barre
d'adresse.

## Ce qui ne doit figurer sur aucune des six

Ces quatre règles valent pour toutes les captures, sans exception.

- **Aucune adresse de projet Supabase.** Ni `xxxx.supabase.co` dans la barre
  d'adresse, ni dans un panneau d'outils de développement laissé ouvert.
- **Aucun jeton, aucune clé.** Donc : outils de développement fermés, onglet
  réseau fermé, console fermée.
- **Aucun numéro de téléphone.** Les comptes de démonstration n'en portent pas,
  mais un numéro saisi à la main pendant un essai resterait à l'écran.
- **Aucune adresse électronique personnelle.** Les adresses en
  `@demo.ferha.dz` sont faites pour être vues ; une vraie, non.

**LE FORMAT EST CELUI D'UN TÉLÉPHONE : 390 px de large.** Ferha est une
application mobile, et c'est la largeur pour laquelle les maquettes sont
dessinées (CLAUDE.md, « Maquettes et charte ») : une capture en fenêtre de
bureau montrerait une mise en page que personne n'utilisera. Les six images
font donc **780 × 1688 px** — 390 × 844 à la densité 2, celle du mode appareil
de Chrome.

En pratique : le mode appareil des outils de développement, réglé à 390 × 844,
et la commande « Capture screenshot » de ce mode. Elle ne prend que l'écran
simulé — ni panneau d'outils, ni barre d'adresse, ni bureau — et respecte donc
d'elle-même la deuxième règle ci-dessus, à condition de ne rien capturer
d'autre. Il n'y a pas de barre d'adresse sur les images, et c'est voulu : sur
un téléphone il n'y en a pas non plus.

**Les six au même format, sans exception** : la 01 et la 04 se comparent côte à
côte, et une seule image d'une autre taille casserait la rangée dans le README.

---

## 01-accueil-fr-clair.png

**Écran** : l'accueil, qui est l'écran de recherche.
**Langue** : français. **Thème** : clair.

Ce qui doit être dans le cadre :

- le formulaire entier, rien de sélectionné : le champ « Wilaya, commune ou nom
  de salle », les puces de wilayas (Sétif, Oran, Constantine, Blida, Alger), les
  champs « Date » et « Invités », le choix du créneau — Midi, Soir, Journée —,
  les types d'événement et le bouton « Rechercher » : la promesse du produit en
  un coup d'œil ;
- le début de « Les mieux notées », avec au moins une carte entière — photo,
  nom, commune, couverts, prix par soirée, note en étoiles ;
- la barre d'onglets du bas.

Les puces de wilayas ne portent pas de nombre de salles : l'écran n'en affiche
pas.

Ce qui ne doit pas y être : un menu ouvert par-dessus, un clavier virtuel.

## 02-resultats-filtres.png

**Écran** : les résultats, après une recherche qui rend plusieurs salles.
**Langue** : français. **Thème** : clair.

Prendre la capture **avec au moins deux filtres actifs** — par exemple la
wilaya d'Oran et une capacité — pour que la rangée de filtres retirables soit
visible en tête de liste. C'est elle qui se voit mal quand on la raconte.

Ce qui doit être dans le cadre :

- la rangée des filtres actifs, chacun avec sa croix ;
- au moins deux cartes de salle entières : photo, nom, commune, capacité, prix
  et, sur au moins une, **la note en étoiles** ;
- idéalement une carte **sans note** juste à côté d'une carte notée — c'est la
  démonstration silencieuse du choix « pas d'avis, pas d'étoiles, et surtout
  pas 0,0 ».

## 03-fiche-salle-calendrier.png

**Écran** : « Disponibilité », le calendrier plein écran qu'on ouvre depuis la
fiche d'une salle.
**Langue** : français. **Thème** : clair.

Prendre **Salle El Bahia** (Oran) : c'est la salle la mieux garnie du décor —
six photos, cinq options, une grille tarifaire complète.

Ce qui doit être dans le cadre :

- le choix du créneau en tête — Midi, Soir, Journée entière —, sur **Soir** ;
- **juillet et août 2027 en entier**, l'un sous l'autre : ce sont les mois qui
  portent les dates bloquées du décor, et l'on y voit côte à côte des dates
  **libres** (vert) et **indisponibles** (sable) ;
- la légende en bas — Libre, Réservé, Indisponible.

Les trois états de l'application sont ceux de la légende : libre, réservé,
indisponible. Sur ces deux mois et ce créneau, aucune date n'est réservée : la
capture en montre deux sur trois, et la légende nomme le troisième. Le bloc du
prix n'y est pas — il est sur la fiche, pas sur cet écran.

Le calendrier est la pièce la plus travaillée de l'application. Une capture qui
coupe un mois en deux ne sert à rien.

## 04-accueil-ar-sombre.png

**Écran** : le même accueil que la capture 01.
**Langue** : arabe. **Thème** : sombre.

C'est la capture qui prouve le plus en une image, à condition qu'on puisse la
**comparer à la 01** : même écran, même largeur. Le lecteur doit voir d'un coup
que toute la mise en page s'est retournée.

Elle n'est pas prise dans le même état que la 01, et c'est ce qui la rend
parlante : **Oran est sélectionné et « 300 » saisi dans les invités**. La
section du bas devient alors « الأعلى تقييماً في ORAN » — les mieux notées à
Oran. Le formulaire est légèrement défilé : le champ de recherche est sorti par
le haut, les puces de wilayas sont la première ligne visible.

Ce qui doit être dans le cadre :

- le sens de lecture inversé : titre et cloche échangés, puces et champs
  alignés à droite, carte retournée (cœur à gauche, note à gauche), barre
  d'onglets dans l'ordre Profil → Accueil ;
- la puce Oran cochée et le champ des invités rempli, dans la couleur d'accent
  du thème sombre ;
- **les chiffres, qui restent latins** — 300, 286 000, 450, 4,3. C'est une
  décision, pas un oubli, et elle ne se voit que là.

Ce qui reste en français dans la page arabe, et que la capture montre tel quel :
les noms de wilayas, les types d'événement et les quatre libellés de la barre
d'onglets. Le README le dit dans « Ce que ça ne fait pas, et pourquoi ».

Pour basculer : l'écran de profil, ou le sélecteur de langue de l'accueil.

## 05-espace-proprietaire.png

**Écran** : le tableau de bord du propriétaire (écran 9).
**Langue** : français. **Thème** : clair.
**Compte** : entrer comme Karim.

Ce qui doit être dans le cadre :

- le sélecteur de salle en titre — **Salle El Bahia** et sa flèche —, qui
  montre que Karim en tient plusieurs ;
- les deux raccourcis : « Agenda » et « Publier une autre salle » ;
- **la file des demandes en attente de cette salle** — trois sur la capture —,
  chacune avec son prénom et l'initiale du nom, sa date, son créneau, ses
  invités, son type d'événement, son estimation, et son âge (« il y a 17
  jours ») ;
- le début de « Ce mois-ci » : taux d'occupation, prévisionnel du mois, note
  moyenne, demandes acceptées, avec leur variation par rapport au mois
  précédent.

La file ne compte que les demandes de la salle choisie : Karim en a quatre en
tout, trois sur El Bahia. Les chiffres du mois sont ceux du jour de la capture —
le 3 octobre 2026, un mois sans réservation : 0 %, 0 DA, et des flèches qui
descendent. Ils sont vrais ; ils changeront avec la date.

À vérifier **avant** de déclencher la capture : la file n'est pas vide. Si elle
l'est, le ménage horaire ne l'a pas encore remise — attendre le passage à la
minute 10, ou relancer `seed/004_demo_bookings.sql`.

## 06-assistant.png

**Écran** : l'assistant, après deux ou trois échanges.
**Langue** : français. **Thème** : au choix, mais le sombre rend mieux les
bulles de conversation.

La capture doit montrer **ce qui distingue cet assistant**, donc une
conversation choisie, pas la première venue. La meilleure combinaison :

1. une question à laquelle il répond bien, avec des salles à l'appui — par
   exemple « une salle pour 300 personnes à Oran » ;
2. **une question hors sujet, et son refus** — par exemple « quel temps
   fait-il ? ». C'est cette bulle-là qui vaut la capture : elle montre un
   assistant qui dit « je ne sais pas » au lieu d'inventer.

Si les deux ne tiennent pas dans un écran, prendre celle qui contient le refus.
