# Les six captures du README

Le README les appelle déjà par leur nom. Tant que les fichiers ne sont pas là,
les six images sont cassées — sans conséquence, le dépôt est privé.

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

Deux conseils qui font la différence entre une capture utile et une capture
molle : prendre en fenêtre large (autour de 1440 px) pour que la mise en page
respire, et **recadrer sur le contenu** — ni bureau, ni barre des tâches, ni
favoris. La barre d'adresse peut rester si elle montre `ferha.pages.dev` : elle
prouve que le site est en ligne.

---

## 01-accueil-fr-clair.png

**Écran** : l'accueil, qui est l'écran de recherche.
**Langue** : français. **Thème** : clair.

Ce qui doit être dans le cadre :

- le champ « où », le champ « quand », le champ « combien » et le bouton qui
  lance la recherche — c'est-à-dire la promesse du produit en un coup d'œil ;
- les puces de wilayas sous le formulaire, avec leur nombre de salles : elles
  montrent que les données sont réelles et non un décor dessiné ;
- la barre d'onglets du bas.

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

**Écran** : la fiche d'une salle, déroulée jusqu'au calendrier.
**Langue** : français. **Thème** : clair.

Prendre **Salle El Bahia** (Oran) : c'est la salle la mieux garnie du décor —
six photos, cinq options, une grille tarifaire complète.

Ce qui doit être dans le cadre, en priorité **le calendrier** :

- un mois où l'on voit les **trois états** côte à côte : libre, pris, et passé.
  Juillet ou août 2027 conviennent, ils portent des dates bloquées ;
- la légende des trois états si l'écran l'affiche ;
- si la hauteur le permet, le bloc du prix au-dessus.

Le calendrier est la pièce la plus travaillée de l'application. Une capture qui
le coupe en deux ne sert à rien.

## 04-accueil-ar-sombre.png

**Écran** : le même accueil que la capture 01.
**Langue** : arabe. **Thème** : sombre.

C'est la capture qui prouve le plus en une image, à condition qu'on puisse la
**comparer à la 01**. Donc : même écran, même position de défilement, même
largeur de fenêtre. Le lecteur doit voir d'un coup que toute la mise en page
s'est retournée.

Ce qui doit être dans le cadre :

- le sens de lecture inversé, visible sur l'alignement des champs et sur la
  barre d'onglets ;
- **les chiffres, qui restent latins** — capacité, prix, nombres de salles sur
  les puces. C'est une décision, pas un oubli, et elle ne se voit que là ;
- la flèche de retour retournée, si l'écran en porte une.

Pour basculer : l'écran de profil, ou le sélecteur de langue de l'accueil.

## 05-espace-proprietaire.png

**Écran** : le tableau de bord du propriétaire (écran 9).
**Langue** : français. **Thème** : clair.
**Compte** : entrer comme Karim.

Ce qui doit être dans le cadre :

- **la file des demandes en attente**, avec au moins deux demandes et leur âge
  (« il y a 2 heures », « il y a 3 jours ») ;
- les chiffres du haut : taux d'occupation, part des demandes acceptées, note
  moyenne — et leur variation par rapport au mois précédent ;
- le sélecteur de salle, qui montre que Karim en tient plusieurs.

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
