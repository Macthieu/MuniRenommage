# BRANDING ET ICONE - MuniRename

Date: 2026-03-11

## Etat actuel

- Source icone: `assets/branding/MuniRename_icon_source.png`
- Format source: PNG
- Taille source: 768x1024 (non carrée)
- Integration app: `MuniRename/Assets.xcassets/AppIcon.appiconset`
- Target app icon: `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` (deja configure dans le projet)

## Flux retenu

1. Conserver un fichier source unique dans `assets/branding/`.
2. Generer les tailles macOS standard dans `AppIcon.appiconset`.
3. Mettre a jour `Contents.json` avec les `filename` associes.

## Script officiel

Script: `scripts/generate_appicon.sh`

Ce script:
- prend `assets/branding/MuniRename_icon_source.png`,
- le normalise en 1024x1024 sans distortion (padding),
- genere toutes les tailles AppIcon macOS,
- regenere `Contents.json` avec les correspondances de fichiers.

## Commande d'utilisation

```bash
./scripts/generate_appicon.sh
```

## Remplacement futur de l'icone

1. Remplacer le fichier source:
- `assets/branding/MuniRename_icon_source.png`

2. Regenerer les assets:
- `./scripts/generate_appicon.sh`

3. Verifier dans Xcode:
- `AppIcon` bien selectionne dans le target
- icone visible dans le bundle/app

## Notes qualite

- Une source non carree est acceptee, mais un master carre 1024x1024 est recommande pour un rendu optimal.
- Ne plus deposer d'icone brute a la racine du repo.
