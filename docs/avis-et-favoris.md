# Les avis et les favoris

Retour au [README](../README.md).

## Les avis

Un avis exige une réservation **honorée**, et la règle est portée par le schéma
plutôt que par un écran : `reviews.booking_id` est `unique not null` vers
`bookings`. Pas de réservation, pas d'avis ; et jamais deux avis sur la même.

La fenêtre est étroite et elle n'est écrite qu'une fois, dans `fenetre_avis()` :
**J+1 à J+30** après l'événement. Avant, la soirée n'a pas eu lieu. Après, on ne
se souvient plus de la salle, on se souvient de son humeur. La politique RLS,
`client_bookings()`, `avis_a_deposer()` et `deposer_avis()` lisent toutes ces
deux bornes du même endroit.

Une journée entière occupe deux lignes de `bookings`, donc deux `booking_id`,
donc deux avis possibles si l'on s'arrêtait là. `reviews.booking_group_id`,
unique lui aussi, ferme la brèche : **un événement, un avis**. Il est renseigné
par un déclencheur, jamais par l'appelant.

Le propriétaire a un droit de réponse, une seule fois. Une fois qu'il a
répondu, l'avis est figé : laisser l'auteur réécrire sa note après coup rendrait
la réponse incompréhensible.

**Une salle sans avis n'a pas d'étoiles — et surtout pas zéro.** La note est
`null`, le champ `estNotee` est faux, et l'écran affiche un tiret. Zéro virgule
zéro serait un mensonge : ce n'est pas une mauvaise note, c'est une absence de
note. Quand il y a des avis, la note affichée est une **moyenne bayésienne**
(m = 5, C = 4,0) et non une moyenne simple : une salle avec un seul 5/5 ne doit
pas dépasser une salle qui tient 4,6 sur quarante avis.

## Les favoris

Un cœur sur la carte d'une salle, et cette salle se retrouve dans l'onglet
Favoris. C'est tout, et c'est voulu : **pas de dossiers, pas de notes, pas de
partage, pas de tableau de comparaison.**

**Le cœur vit sur la carte, pas sur les écrans qui l'utilisent.** La même
`VenueCard` dessine une salle sur l'accueil et dans les résultats : poser le
cœur dessus le fait apparaître aux deux endroits sans dupliquer une ligne. La
fiche salle porte le même widget et le même fournisseur derrière — retirer un
favori depuis la fiche l'éteint aussi dans les résultats, sans que l'un ait à
prévenir l'autre.

**Il s'allume au doigt, et il se rééteint si la base refuse.** L'état passe à
l'écran d'abord, part vers la base ensuite, et **revient en arrière** si elle dit
non — avec un message qui explique pourquoi. Un cœur resté allumé sur un favori
qui n'existe pas serait le même mensonge qu'un prix qui changerait entre la liste
et la fiche.

**Le geste interrompu se termine.** Un visiteur sans compte qui touche le cœur ne
perd pas son geste : l'écran de connexion s'ouvre par-dessus, et quand il se
referme sur une session valide, **le cœur s'allume tout seul**. La personne n'a
pas à retrouver la salle et à retoucher le cœur — elle a déjà dit ce qu'elle
voulait. C'est la règle de navigation habituelle (voir [Architecture](architecture.md#la-règle-de-navigation)) : on demande la
connexion au moment d'agir, jamais à l'entrée.

**L'onglet n'éjecte personne.** Sans compte, il explique pourquoi un favori se
range sur un compte plutôt que sur l'appareil, et propose de se connecter. Il ne
redirige pas : le routeur n'a aucune redirection globale, et cet onglet n'en
gagne pas une. Vide, il ne dit pas « aucun favori » — il nomme le geste qui
manque, « touchez le cœur sur une salle pour la retrouver ici », et donne un
bouton qui ramène à la recherche.

**Aucun compteur « 12 personnes aiment cette salle ».** La RLS ne rend que mes
lignes, donc ce chiffre n'existe pas — et sur un catalogue de démonstration il
serait une preuve sociale fabriquée. C'est le même refus que pour les numéros de
téléphone des comptes partagés.

Enfin, **les favoris d'Amina font partie du décor** : trois salles, remises en
place à chaque heure ronde comme les réservations et les dates bloquées. Un
visiteur qui pose cinq cœurs en voit cinq pendant sa visite ; à l'heure suivante
il n'en reste que les trois du décor. Sans cela, « Entrer comme Amina » ouvrirait
dans une semaine les favoris de trente inconnus.

### Ce qui manque encore

- **LE PRIX ET LA DISPONIBILITÉ POUR UNE DATE, À CÔTÉ DE CHAQUE FAVORI.** C'est
  la suite logique, et c'est le vrai besoin : une famille visite six salles et
  veut savoir laquelle a encore le samedi. Ce n'est pas construit, et la raison
  est que **l'onglet Favoris ne porte aucune date**. Le prix affiché sur une
  carte vient d'`estimate_price()` pour aujourd'hui, le soir, une personne —
  les valeurs d'attente de l'accueil, là où aucune date n'est encore choisie.
  Afficher « libre le 14 juin, 210 000 DA » demanderait de porter une date dans
  l'onglet, de la faire choisir, de la retenir, puis d'interroger
  `tient_la_date()` **et** `estimate_price()` pour chaque salle de la liste :
  le coût de la page double, et l'écran cesse d'être une liste pour devenir une
  seconde recherche. Le jour où on le fera, ce sera avec une date unique posée
  en haut de l'onglet, pas une par carte.

