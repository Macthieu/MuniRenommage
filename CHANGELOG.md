# Changelog

Toutes les évolutions notables de ce projet sont documentées ici.

Le format suit [Keep a Changelog](https://keepachangelog.com/fr/1.0.0/) et ce projet suit [SemVer](https://semver.org/lang/fr/).

## [Unreleased]

## [0.2.0] - 2026-03-11

### Added
- Swift Package `MuniRenameCore` pour exécuter et valider la logique métier sans Xcode.
- CLI `munirename-cli` (preview/apply/validate-preset) pour usage manuel.
- Binaire `munirename-smoketests` pour vérifications automatisables sans XCTest.
- Validation et versionnement des presets (`formatVersion`, codec versionné, validation dédiée).
- Script `scripts/generate_appicon.sh` pour générer l’AppIcon complet.
- Documentation technique: `docs/STATUS-INITIAL.md`, `docs/AUDIT.md`, `docs/DECISIONS.md`, `docs/PRESETS.md`, `docs/BRANDING.md`.
- CI GitHub Actions minimale (`swift build`, smoke-tests, validation CLI).

### Changed
- Renforcement du moteur de renommage (collisions, validations, exécution move en 2 phases).
- Refonte de la gestion Presets (store plus robuste, import/export fiabilisés, édition complète).
- UX d’exécution: simulation, confirmation avant application, rapport post-opération, bannière de résultat.
- Intégration réelle de l’icône app (AppIcon.appiconset complet, source déplacée hors racine).

### Fixed
- Correction de la chaîne d’icône incomplète (slots AppIcon sans fichiers).
- Correction de points de compatibilité Swift/macos (`ContentUnavailableView` fallback).

## [0.1.0] - 2026-03-11

### Added
- Première publication du projet MuniRename.
