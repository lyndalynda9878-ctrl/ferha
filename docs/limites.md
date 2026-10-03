# Limites

La version longue de « Ce que ça ne fait pas, et pourquoi ». Retour au [README](../README.md).

Un projet qui ne dit pas ses trous demande qu'on les cherche. Voici les miens.

**Les tests SQL ne tournent pas tout seuls, et c'est le plus gros trou de ce
dépôt.** Vingt-deux fichiers dans `supabase/tests/` vérifient ce que le Dart ne peut
pas vérifier : le prix qui ne vient que d'`estimate_price()`, la RLS qui isole
deux clients, le double créneau que la base refuse. La CI GitHub lance
`flutter analyze` et les 683 tests Dart à chaque push — **elle ne lance aucun
des vingt-deux**. Ils se collent à la main dans l'éditeur SQL de Supabase, ou
s'enchaînent par la boucle `psql` documentée dans
[`supabase/README.md`](../supabase/README.md#les-lancer-tous-en-une-seule-commande).

**Ce que ça a déjà coûté, deux fois.** Trois de ces tests ont pourri dix jours
sans que personne le voie : ils étaient écrits, ils étaient justes, et ils ne
tournaient pas. Et le 19 septembre 2026, le décor de démonstration en ligne
portait deux favoris au lieu de trois et un profil détourné — `etat_du_decor` le
disait depuis des heures, le test 17 de `tests/018` l'aurait crié, et personne
n'avait rien lancé. Un test qu'on n'exécute pas n'est pas un test : c'est une
intention, et elle passe au vert toute seule.

**Le chemin pour le combler, nommé.** Un Supabase LOCAL dans le robot GitHub —
`supabase start` pose Postgres dans un conteneur, `supabase db reset` y applique
les 42 migrations et les seeds, puis la même boucle `psql` enchaîne les
vingt et un fichiers autonomes contre `localhost`. Aucun secret n'est nécessaire :
la base est jetable et naît vide à chaque exécution. Ce qui coûte, c'est de
faire tenir la pile Supabase dans le robot — l'image met des minutes à démarrer,
les seeds supposent des comptes GoTrue que `db reset` ne crée pas seul, et
`013` restera dehors de toute façon. C'est une journée, pas une ligne, et c'est
pour cela qu'elle n'est pas faite : elle est notée pour plus tard, pas oubliée.

**Le paiement est en mode test.** Chargily tourne avec ses clés de bac à sable :
aucune somme n'est débitée, et l'écran de l'acompte le dit au client au lieu de
le laisser croire qu'il paie. Passer en production demande un compte marchand
vérifié, pas une ligne de code.

**La validation d'une salle n'existe pas encore, et c'est plus sévère que ça en
a l'air.** Le cahier des charges veut qu'aucune salle ne soit visible
avant contrôle humain. La moitié protectrice est en place : une salle inscrite
depuis l'application naît en `draft`, passe en `pending` quand son propriétaire
l'envoie, et **rien ne la passe jamais en `published`** — ni fonction, ni écran,
ni déclencheur. Toutes les recherches filtrent sur `published`. Une salle
inscrite dans la démonstration n'apparaît donc nulle part, jamais. Le filet
existe ; c'est la console qui manque. En attendant, une surveillance horaire
compte ces salles — `salles_publiees_par_un_visiteur` dans la vue
`etat_du_decor` — et je les retire à la main.

**Le propriétaire ne peut pas saisir sa grille tarifaire**. Les quatre
éléments demandés existent en base et servent au calcul : prix de base par
créneau, majoration week-end, majoration de haute saison — juin à septembre — et
prix par couvert au-delà d'un seuil. Mais l'écran qui les saisit n'est pas
écrit. Or `search_venues()` joint `venue_pricing` par une jointure interne : une
salle sans tarif ne sort d'aucune recherche. L'application le dit en toutes
lettres à la fin du parcours d'inscription, plutôt que de laisser un
propriétaire attendre des demandes qui ne viendraient jamais.

**Les libellés venus de la base restent en français dans une page arabe.** La
nuance est ailleurs que là où on l'attend : les référentiels **sont** bilingues.
`wilayas` porte `name_fr` et `name_ar`, `event_types`, `amenities` et
`venue_options` portent `label_fr` et `label_ar` — toutes ces colonnes sont
`not null` et renseignées pour les 58 wilayas et tous les codes. C'est le client
Flutter qui ne les demande jamais : `search_providers.dart` écrit `name_fr` et
`label_fr` en dur, quelle que soit la langue active. Le réparer, c'est choisir
la colonne selon la langue — un après-midi. La barre d'onglets du bas — Accueil,
Assistant, Favoris, Profil — reste elle aussi en français dans la page arabe,
pour une raison plus simple encore : `lib/core/router/home_shell.dart` écrit ses
quatre libellés en dur au lieu de les lire dans l'ARB. Ce qui n'a, lui, aucune
traduction, c'est le contenu saisi par les propriétaires : `venues.name`,
`venues.commune`, `venues.description`, les motifs de dates bloquées et le texte
des avis. Celui-là demanderait un vrai circuit de traduction, pas une colonne.

**Les comptes de démonstration ne PEUVENT PAS porter de numéro de téléphone :
la base le refuse.** Un numéro algérien bien formé appartient à quelqu'un, et le
site est en ligne — c'est une décision, pas un état de fait. Un déclencheur
(`profiles_pas_de_telephone_en_demonstration`, migration 038) remet `phone` à
NULL sur tout compte `d0000000-…`, quelle que soit la porte empruntée : l'écran
de demande, la publication d'une salle, l'inscription, ou une écriture directe
par l'API. Il force au lieu de refuser, pour que le parcours de démonstration aboutisse
normalement ; l'écran de demande le dit à qui tape un numéro.

Le mécanisme de confidentialité du cahier des charges — le contact de l'autre partie révélé seulement après
acceptation, par `booking_contact()` — est bien là, et couvert par
`supabase/tests/007_adresse_et_telephone.sql` et
`supabase/tests/019_pas_de_telephone_en_demonstration.sql`. Il n'a simplement
rien à révéler sur un compte partagé : l'espace propriétaire affiche « ce client
n'a pas renseigné de numéro » au lieu d'un faux numéro. Chez un vrai client, le
numéro est conservé — c'est par lui que la salle rappelle.

**Cette règle-là a été écrite après coup, et c'est pour ça qu'elle est sûre.**
Le 17 septembre 2026, un visiteur connecté comme Amina a tapé son vrai numéro
sur l'écran de demande, et il s'est affiché en clair chez Karim : un compte
partagé plus un champ de coordonnées obligatoire, c'est le second qui remplit le
premier. Les seeds posaient bien `phone = null` et ce mécanisme fonctionnait — rien
n'était cassé, et c'est justement pourquoi le correctif est descendu dans la
base plutôt que dans l'écran qui se trouvait être la porte du jour.

**Le nom, l'adresse et la connexion des comptes de démonstration sont figés
depuis le 3 octobre 2026.** Le 17 septembre, `full_name` et `email` étaient
restés ouverts : aucun écran ne les écrit, et le ménage les remettait au bout de
deux heures. La condition qui retournerait ce choix était écrite d'avance — le
jour où l'adresse du site serait diffusée. Ce jour est arrivé, et l'essai fait
pour de vrai ce jour-là a trouvé plus grave qu'un nom barbouillé : connecté comme
Amina, un visiteur pouvait **changer le mot de passe** par l'API
d'authentification, et les deux boutons de démonstration cessaient de marcher
pour tout le monde. Il pouvait aussi inscrire un facteur MFA que personne
d'autre ne pouvait retirer.

Quatre protections ferment ces portes :

- la migration 040 fige le nom et l'adresse dans `profiles` ;
- la migration 041 fige, dans `auth.users`, le mot de passe, l'adresse, le
  téléphone et les métadonnées, quand c'est le service d'authentification qui
  écrit ;
- la migration 042 remet `demo1234` chaque heure s'il a bougé — une ceinture,
  au cas où 041 lâcherait ;
- TOTP est désactivé dans le tableau de bord Supabase. Ce réglage-là n'est dans
  aucun fichier du dépôt : un projet recréé repartirait avec TOTP activé.

Le détail, et la commande qui prouve les trois portes, sont dans
[`supabase/README.md`](../supabase/README.md#ce-quun-visiteur-ne-peut-pas-leur-faire).

**Pas de SMS : la connexion se fait par adresse électronique et mot de passe.**
Et la messagerie intégrée de Supabase, en offre gratuite, n'envoie que quelques
messages par heure : une inscription normale peut donc ne jamais recevoir sa
confirmation. C'est la raison d'être des deux boutons de démonstration — ils ne
sont pas un raccourci de confort, ils sont le seul chemin fiable pour un
visiteur.

**Pas de notification sur téléphone** (FCM), et **pas de rappels J-7 ni J-1**.
Les deux types existent dans la contrainte de `notifications.type`, et rien ne
les écrit : la place est réservée, le déclencheur n'est pas posé. Les
notifications dans l'application, elles, fonctionnent et arrivent en temps réel.

**Le service d'empreintes dort.** Il tourne sur une offre gratuite qui endort
l'instance ; le premier appel après deux heures de silence coûtait 62 secondes.
Un gardien le réveille toutes les cinq minutes, et l'assistant abandonne le
service au bout de 2 secondes pour répondre sans vecteur plutôt que de faire
attendre. Voir [Les gardiens](gardiens.md).

**Pas d'APK.** Il demande une signature, un `keystore` gardé hors du dépôt et un
circuit de publication. Le site web, lui, s'ouvre en un lien — c'est ce que
quelqu'un qui découvre le projet fera. Voir [La mise en ligne](deploiement.md).

