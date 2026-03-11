# MuniRename

MuniRename est un logiciel de renommage en lot **manuel** pour macOS, inspiré par la puissance d'outils comme Bulk Rename Utility, avec une interface plus lisible et orientée usage quotidien.

Le projet est sous licence GNU GPL v3.0.

## Objectif produit

- Renommer des lots de fichiers de façon contrôlée.
- Prévisualiser les résultats avant d'écrire quoi que ce soit sur disque.
- Rester explicite et manuel: pas d'orchestration automatisée cachée.

## Fonctionnalités

- Prévisualisation en direct des nouveaux noms.
- Règles combinables:
- remplacement (texte/regex)
- suppression par plage
- ajout préfixe/suffixe/insertion
- date automatique
- numérotation (padding, pas, pattern)
- casse
- extension
- ajout dossier parent
- transformations spéciales
- Filtres (regex, récursif, fichiers cachés).
- Destination configurable (sur place, autre dossier, copie).
- Gestion des collisions et validations de noms.
- Exécution de déplacement en 2 phases pour fiabiliser les swaps.
- Undo de la dernière opération.
- Presets versionnés (création, duplication, édition, import/export JSON, reset défauts).
- Rapport de simulation et rapport post-exécution.

## Structure du dépôt

- `MuniRename/App/` point d'entrée app.
- `MuniRename/Features/Renaming/` UI et VM de renommage.
- `MuniRename/Features/Presets/` store presets.
- `MuniRename/Domain/` logique métier app.
- `Sources/MuniRenameCore/` cœur métier testable sans Xcode.
- `Sources/munirename-cli/` CLI manuel (`preview`, `apply`, `validate-preset`).
- `Sources/munirename-smoketests/` smoke-tests exécutables.
- `docs/` audit, décisions, presets, branding, status initial.
- `scripts/xcode_build.sh` build app macOS avec Xcode.
- `scripts/generate_appicon.sh` génération des assets AppIcon.

## Installation / Build

## Option A — Application macOS (Xcode)

1. Ouvrir le projet:

```bash
open MuniRename.xcodeproj
```

2. Sélectionner le schéma `MuniRename`.
3. Lancer l'application (`Run`).

Build CLI Xcode reproductible (utile si `xcode-select` pointe sur CommandLineTools):

```bash
./scripts/xcode_build.sh
```

## Option B — Sans Xcode complet (CLI + core)

Prérequis: Swift installé (`swift --version`).

```bash
swift build
swift run munirename-smoketests
swift run munirename-cli --help
```

## Usage (app)

1. Choisir un dossier source.
2. Activer les règles nécessaires.
3. Vérifier la simulation / preview.
4. Confirmer l'application.
5. Consulter le rapport et utiliser `Annuler` si nécessaire.

## Usage (CLI)

```bash
swift run munirename-cli preview --preset ./preset.json --directory ./dossier
swift run munirename-cli apply --preset ./preset.json --directory ./dossier --dry-run
swift run munirename-cli validate-preset --preset ./preset.json
```

## Presets

- Un preset est un profil de renommage réutilisable.
- Format versionné (`formatVersion`) avec compatibilité de lecture des formats précédents.
- Stockage principal local:
- `~/Library/Application Support/MuniRename/presets.json`
- Détails: voir `docs/PRESETS.md`.

## Branding / icône

- Source icône: `assets/branding/MuniRename_icon_source.png`
- Génération AppIcon:

```bash
./scripts/generate_appicon.sh
```

- Détails: voir `docs/BRANDING.md`.

## Limitations connues

- L'éditeur de presets est fonctionnel mais peut encore être simplifié visuellement.
- Une migration de presets multi-versions plus avancée sera ajoutée avec les futures versions.

## Roadmap

- Améliorer encore l'ergonomie de l'éditeur de presets.
- Ajouter export de rapport d'opération.
- Stabiliser vers une version `v1.0.0` quand UX + robustesse + packaging seront finalisés.

## Développement

- CI GitHub: `.github/workflows/ci.yml`
- Changelog: `CHANGELOG.md`
- Décisions d'architecture: `docs/DECISIONS.md`

## Licence

Ce projet est distribué sous licence GNU GPL v3.0.
Voir `LICENSE`.
