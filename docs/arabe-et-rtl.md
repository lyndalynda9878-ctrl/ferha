# L'arabe et le sens de lecture

Retour au [README](../README.md).

L'arabe n'est pas une traduction posée sur une interface française : c'est un
second sens de lecture, et il retourne la mise en page entière. Le projet s'y
tient par **217 tests** — 152 dans les quatre fichiers nommés pour l'arabe, 46
qui interdisent qu'un texte français soit écrit en dur hors des fichiers ARB,
13 sur les formats, et 6 qui balayent les deux ARB caractère par caractère.

Quatre décisions ne se devinent pas, et ce sont elles que les tests protègent :

- **les chiffres restent latins.** Prix, capacités, dates : les chiffres
  indo-arabes orientaux ne sont pas ceux qu'on lit en Algérie ;
- **les icônes directionnelles se retournent, les autres non.** La flèche de
  retour change de côté, la loupe reste une loupe ;
- **le calendrier commence toujours par dimanche**, dans les deux langues ;
- **les mois portent leurs noms algériens** et non les noms du Machrek.

Le détail — quelle clé pour quel écran, ce qui se traduit et ce qui ne se
traduit pas, comment ajouter une chaîne — vit dans
[`lib/core/l10n/README.md`](../lib/core/l10n/README.md).

### Ce qui manque encore

- **LA RELECTURE ARABE SUIT UNE LISTE D'ÉCRANS ÉCRITE À LA MAIN, ET UNE LISTE
  ÉCRITE À LA MAIN ARRIVE TOUJOURS UN CRAN DERRIÈRE LE DERNIER ÉCRAN.**
  `relecture_arabe_test.dart` monte onze écrans qu'il nomme un par un. Les
  quatre contrôles sont bons — débordement, français resté à l'écran, chiffres
  arabes-indiens, icônes retournées — mais ils ne regardent que ce qu'on a
  pensé à leur donner. Or c'est sur le dernier écran écrit que les défauts se
  trouvent, et le dernier écran écrit est justement celui qui n'est pas encore
  dans la liste. L'onglet Favoris l'a montré : ses dix chaînes arabes sont
  restées illisibles cinquante heures dans l'arbre de travail alors que le
  contrôle qui les aurait attrapées existait déjà et tournait soixante fois.

  La sortie n'est pas d'ajouter chaque écran à la main en se promettant de ne
  pas oublier — c'est ce qu'on fait aujourd'hui, et c'est ce qui échoue. Il
  faudrait que le banc TROUVE les écrans au lieu de les recevoir : parcourir
  `lib/features/**/**_screen.dart`, et faire échouer le test sur tout écran qui
  n'est ni monté ni explicitement écarté avec sa raison. Le coût réel n'est pas
  le parcours, c'est que chaque écran demande ses propres fournisseurs — l'état
  vide, l'état d'erreur — et qu'aucun ne se monte tout seul. C'est un vrai
  chantier, pas une ligne.

  En attendant, `test/encodage_des_arb_test.dart` montre la forme que doit
  prendre un gardien : **il ne suit aucune liste**. Il lit les deux ARB en
  entier et n'a rien à apprendre quand un écran s'ajoute. Il n'attrape qu'une
  famille de défauts sur quatre, mais celle-là, il l'attrapera toujours.

