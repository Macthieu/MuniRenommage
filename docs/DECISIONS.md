# DECISIONS D'ARCHITECTURE - MuniRename

Date: 2026-03-11

## D1 - Garder l'app macOS, extraire un coeur metier testable sans Xcode

Decision:
- Ajout d'un Swift Package a la racine (`Package.swift`) avec:
  - `MuniRenameCore` (bibliotheque metier)
  - `munirename-cli` (outil manuel en ligne de commande)
  - `munirename-smoketests` (validation executable sans XCTest/Testing)

Pourquoi:
- Permet de valider la logique de renommage sans dependre de Xcode.
- Repond au besoin "fonctionner sans Xcode".
- Permet une evolution plus robuste de la logique metier.

Trade-off:
- Double couche temporaire (app SwiftUI + core package) tant que l'app n'importe pas directement le package.

## D2 - Renommage securise avec planification explicite

Decision:
- Introduire une etape de plan (`buildPlan`) avant execution.
- Execution move en 2 phases (`source -> temp -> destination`) pour gerer swaps et collisions de sequence.

Pourquoi:
- Evite les erreurs classiques de renommage en lot (A->B et B->A, chaines de noms).
- Rend le comportement plus deterministe.

Trade-off:
- Complexite supplementaire dans le moteur.

## D3 - Validation metier centralisee des noms cibles

Decision:
- Validation explicite des noms:
  - nom vide,
  - `.` / `..`,
  - caracteres interdits (`/`, `:`),
  - caracteres de controle,
  - longueur > 255 octets,
  - collisions internes,
  - cible deja existante.

Pourquoi:
- Fiabilite avant ecriture disque.
- Messages d'erreur plus lisibles.

## D4 - Presets versionnes et validates

Decision:
- Nouveau modele preset dans le core avec `formatVersion`.
- Encodage/decodage via `PresetCodec` avec support:
  - format enveloppe (`PresetDocument` + `schemaVersion`),
  - compat format brut (`RenamePreset`).
- Validation via `PresetValidator`.

Pourquoi:
- Base evolutive pour migration future.
- Renforce import/export JSON.

## D5 - Positionnement produit explicite

Decision:
- MuniRename est maintenu comme outil de renommage en lot **manuel**.
- Le CLI reste un mode d'execution manuel, pas une automatisation orchestreur.

Pourquoi:
- Respect du positionnement souhaite (type Bulk Rename Utility sur macOS, UX plus propre).
