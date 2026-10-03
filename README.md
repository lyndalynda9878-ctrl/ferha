# Ferha

Application de réservation de salles des fêtes en Algérie. Les familles
cherchent une salle, voient le prix exact pour leur date et envoient une demande ;
les propriétaires l'acceptent, encaissent l'acompte et tiennent leur agenda — en
français ou en arabe, sur le web et sur téléphone.

**Voir l'application en ligne : <https://ferha.pages.dev>**

## Essayer en trois minutes

Deux boutons sur l'écran de connexion évitent toute inscription. Le parcours
ci-dessous fait le tour complet, des deux côtés.

1. Ouvrir <https://ferha.pages.dev> et toucher **« Entrer comme Amina
   (cliente) »**.
2. Sur l'accueil, chercher **Oran**, puis ouvrir **Salle El Bahia** — 450
   places, la salle la mieux garnie du catalogue.
3. Dans le calendrier, choisir le **samedi 18 septembre 2027**, créneau
   **soir**. La date est libre, et elle est en haute saison : le devis affiche
   la majoration.
4. Envoyer la demande. Elle part chez Karim, qui est le propriétaire de cette
   salle-là — c'est pour cela qu'on la choisit.
5. Se déconnecter, puis **« Entrer comme Karim (propriétaire) »**. La demande
   est en tête de sa file. L'ouvrir, **accepter**. Une option de 72 h se pose
   sur la date.
6. Revenir comme Amina. La réservation attend son acompte : choisir
   **l'acompte en espèces**, pas la carte.
7. Repasser chez Karim, ouvrir la demande, **confirmer l'encaissement**. La
   réservation passe en confirmée, des deux côtés.

**Prenez la carte seulement si vous voulez voir la page Chargily.** Le paiement
est en mode test et aucune somme n'est débitée — l'écran le dit —, mais la page
de Chargily n'est pas joignable depuis toutes les connexions. Le parcours
espèces, lui, ne quitte jamais l'application et marche partout.

**L'astuce qui vaut le détour : ouvrez deux fenêtres côte à côte.** Amina dans
la fenêtre normale, Karim dans une fenêtre de navigation privée — les deux
sessions ne se marchent pas dessus. Envoyez la demande chez Amina sans quitter
la fenêtre de Karim des yeux : **sa cloche s'allume pendant que vous regardez**,
sans rechargement. C'est la meilleure démonstration du projet, et personne ne la
trouve seul.

**Vous ne pouvez rien casser.** Tout ce qu'un visiteur fait sur les salles de
démonstration s'efface tout seul au bout de deux heures, et le décor — les
demandes en attente, les avis, les dates bloquées, jusqu'au rôle et à la langue
des deux comptes — se remet en place à chaque heure. Le nom, l'adresse et le mot
de passe des deux comptes, eux, ne se modifient pas du tout. Essayez tout, y
compris refuser, annuler et bloquer des dates. Voir [Les gardiens et le
décor](docs/gardiens.md).

## Captures

| | | |
|:-:|:-:|:-:|
| <img src="docs/captures/01-accueil-fr-clair.png" width="250" alt="L'accueil, qui est l'écran de recherche — français, thème clair"> | <img src="docs/captures/02-resultats-filtres.png" width="250" alt="Les résultats, avec les filtres actifs retirables"> | <img src="docs/captures/03-fiche-salle-calendrier.png" width="250" alt="Le calendrier de disponibilité d'une salle"> |
| L'accueil, qui est la recherche | Les résultats et leurs filtres retirables | Le calendrier d'une salle |
| <img src="docs/captures/04-accueil-ar-sombre.png" width="250" alt="Le même accueil en arabe, thème sombre : toute la mise en page se retourne"> | <img src="docs/captures/05-espace-proprietaire.png" width="250" alt="L'espace propriétaire : la file des demandes et les chiffres du mois"> | <img src="docs/captures/06-assistant.png" width="250" alt="L'assistant, qui répond sur le catalogue et refuse le reste"> |
| Le même accueil en arabe, en sombre | L'espace propriétaire | L'assistant, qui refuse ce qu'il ne sait pas |

## Ce que ce dépôt montre

| | Ce qui est fait | En chiffres |
|---|---|---|
| **Application** | Flutter, web et téléphone, thème clair et sombre livrés ensemble ([architecture](docs/architecture.md)) | 683 tests Dart |
| **Deux langues** | Français et arabe, la mise en page entière se retourne de droite à gauche ([détail](docs/arabe-et-rtl.md)) | 217 tests dédiés |
| **Base de données** | PostgreSQL (Supabase) : RLS sur chaque table, prix calculés en base et jamais en Dart, changements d'état par fonctions sécurisées ([supabase/README.md](supabase/README.md)) | 42 migrations, 22 bancs d'essai SQL |
| **Recherche** | Filtres SQL, puis une recherche sémantique par vecteurs qui reclasse les résultats ([détail](docs/recherche-et-assistant.md)) | modèle multilingue, 384 dimensions |
| **Assistant** | Répond sur le catalogue, refuse le reste au lieu d'inventer ([détail](docs/recherche-et-assistant.md#lassistant)) | banc de 37 questions |
| **Paiement** | Acompte par carte algérienne (Chargily, mode test) ou en espèces, confirmé par un webhook signé ([détail](docs/paiement.md)) | 1 seul arrondi, lu aux 3 endroits qui l'affichent |
| **Serveur** | Cinq Edge Functions (Deno) : paiement, webhook, empreintes, synthèse des avis, assistant | 5 fonctions |
| **Mise en ligne** | GitHub Actions compile et publie sur Cloudflare Pages à chaque poussée ([détail](docs/deploiement.md)) | automatique |
| **Fiabilité** | Trois gardiens tiennent éveillés ce qui s'endort, et un décor de démonstration se répare seul ([détail](docs/gardiens.md)) | pire attente : 62 s → 2 s |

## Ce que ça ne fait pas, et pourquoi

- **Les tests SQL ne tournent pas dans la CI.** Les 22 bancs d'essai se lancent
  à la main ; la CI ne lance que l'analyse et les tests Dart. C'est le plus gros
  trou du dépôt, et le chemin pour le combler est écrit.
- **Le paiement est en mode test.** Passer en production demande un compte
  marchand vérifié, pas une ligne de code.
- **Aucune console d'administration.** Une salle inscrite depuis l'application
  reste invisible, faute d'écran pour la valider — le filet est en place, la
  console manque. Le propriétaire ne peut pas non plus saisir sa grille
  tarifaire depuis l'application.
- **Des libellés restent en français dans la page arabe** : les wilayas et les
  types d'événement, que l'application lit en français alors que la base les a
  dans les deux langues, et la barre d'onglets — Accueil, Assistant, Favoris,
  Profil —, dont les libellés sont écrits en dur.
- **Ni SMS, ni notification sur téléphone, ni rappels avant l'événement.** Les
  notifications dans l'application, elles, arrivent en temps réel.
- **Pas d'APK** : le site web s'ouvre en un lien.

La version longue, avec le coût et la raison de chaque trou :
[docs/limites.md](docs/limites.md).

## Installation

```bash
cp env.example.json env.json   # puis SUPABASE_URL et SUPABASE_ANON_KEY
flutter pub get
flutter run -d chrome --dart-define-from-file=env.json
flutter analyze && flutter test
```

Les deux valeurs se prennent dans le tableau de bord Supabase, *Project
Settings › API*. `env.json` n'est jamais versionné, et la clé `service_role`
n'apparaît nulle part dans l'application. `--dart-define-from-file` est
obligatoire : sans lui, l'application s'arrête sur un écran qui dit quelle clé
manque. Le détail est dans [docs/architecture.md](docs/architecture.md).

## Documentation

| Document | Sujet |
|---|---|
| [docs/architecture.md](docs/architecture.md) | structure du code, configuration, comptes et navigation, identité visuelle |
| [supabase/README.md](supabase/README.md) | la base : migrations, RLS, prix, tâches planifiées, tests SQL |
| [docs/recherche-et-assistant.md](docs/recherche-et-assistant.md) | la recherche, la recherche sémantique, l'assistant |
| [docs/paiement.md](docs/paiement.md) | l'acompte, par carte et en espèces |
| [docs/alertes.md](docs/alertes.md) | l'option de 72 h, la cloche et le temps réel |
| [docs/avis-et-favoris.md](docs/avis-et-favoris.md) | les avis et les favoris |
| [docs/arabe-et-rtl.md](docs/arabe-et-rtl.md) | l'arabe et le sens de lecture — et [lib/core/l10n/README.md](lib/core/l10n/README.md) |
| [docs/gardiens.md](docs/gardiens.md) | les gardiens, et le décor de démonstration qui se répare |
| [docs/deploiement.md](docs/deploiement.md) | la mise en ligne sur Cloudflare Pages |
| [docs/limites.md](docs/limites.md) | ce que l'application ne fait pas, en long |
| [supabase/functions/ai-chat/README.md](supabase/functions/ai-chat/README.md) | l'assistant et son banc d'essai |
| [docs/captures/A-PRENDRE.md](docs/captures/A-PRENDRE.md) | ce que chacune des six captures montre, et comment la reprendre |
| `docs/cahier-des-charges_1.html`, `docs/maquettes.html` | le cahier des charges et les maquettes des écrans |

## Comment ce projet a été développé

J'ai développé Ferha avec Claude Code. Je définissais les objectifs de chaque
étape, je faisais les vérifications — dans l'application, en base et en ligne —
et je validais chaque étape avant la suivante. Les règles que le projet impose
au code, de la palette aux règles métier, sont écrites dans
[CLAUDE.md](CLAUDE.md).

## Licence

Le code est sous licence MIT — voir [LICENSE](LICENSE).

Bricolage Grotesque est sous SIL Open Font License 1.1 — voir
[assets/fonts/OFL.txt](assets/fonts/OFL.txt).
