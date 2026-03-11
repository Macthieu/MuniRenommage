# MuniRename v0.2.0

Cette release marque une remise à niveau majeure de MuniRename vers un niveau publiable plus sérieux.

## Points clés

- Refonte de la robustesse du renommage en lot.
- Couche Presets renforcée (validation, versionnage, import/export robuste).
- Ajout d'un cœur métier exécutable/testable sans Xcode.
- Ajout d'un CLI manuel (`munirename-cli`) pour preview/apply/validation de preset.
- Ajout de smoke-tests exécutables (`munirename-smoketests`).
- Ajout de simulation, confirmation et rapport d'opération dans l'UI.
- Correction complète de l'intégration AppIcon (assets générés + flux documenté).
- Documentation projet fortement améliorée (`README`, docs techniques, changelog).

## Détails techniques

- Nouveau package Swift: `MuniRenameCore`
- Nouveau script d'assets: `scripts/generate_appicon.sh`
- Nouvelle CI GitHub minimale: build + smoke-tests + check CLI

## Breaking / migration

- Aucun breaking API public garanti.
- Les presets existants restent lisibles via compatibilité du codec.

## Limites connues

- La CI n'exécute pas encore de build Xcode complet de l'app GUI.
- L'ergonomie de l'éditeur de presets peut encore être simplifiée.
