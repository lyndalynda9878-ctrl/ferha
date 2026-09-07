---
name: verification
description: À utiliser systématiquement avant de rendre la main, après toute modification du code Ferha — lance le format, l'analyse et les tests, relit les règles du projet, et prépare un commit propre.
---

# Vérification avant de rendre la main

À exécuter dans cet ordre, sans en sauter.

## 1. Format
`dart format .`

## 2. Analyse
`flutter analyze --fatal-infos --fatal-warnings`
Aucune sortie attendue. Un avertissement se corrige, il ne se justifie pas.

## 3. Tests
`flutter test`
Si un test échoue, corrige le code — pas le test, sauf si le test était faux.

## 4. Relecture à froid des règles
Relis CLAUDE.md et vérifie point par point :
- aucune valeur hexadécimale hors de lib/core/theme/ferha_colors.dart
- aucun left/right : uniquement start/end et EdgeInsetsDirectional
- thème clair ET sombre traités
- aucune donnée de salle en dur, aucune clé ni secret
- aucune dépendance ajoutée sans mon accord

## 5. Commit
Commits atomiques, messages conventionnels (feat:, fix:, chore:, ci:).
Vérifie avec git status qu'aucun fichier généré n'est ajouté.

## 6. Compte rendu
Dis-moi :
- les fichiers créés ou modifiés
- la commande pour lancer
- les décisions prises à ma place, et pourquoi
- ce qui reste en suspens, s'il y a lieu
