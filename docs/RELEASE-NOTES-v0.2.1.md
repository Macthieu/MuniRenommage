# MuniRename v0.2.1

Release patch orientée stabilisation Xcode et maintenabilité du projet.

## Améliorations clés

- Validation réelle du build app macOS avec Xcode complet (`BUILD SUCCEEDED`).
- Ajout d'un script de build Xcode reproductible: `scripts/xcode_build.sh`.
- Ajout d'un job CI GitHub pour builder l'app Xcode en plus du core package.
- Nettoyage de l'arborescence app:
  - `MuniRename/App/`
  - `MuniRename/Features/`
  - `MuniRename/Domain/`
- Documentation mise à jour pour la procédure Xcode actuelle (`docs/STATUS-CURRENT.md`, README, changelog).

## Pourquoi cette release

Cette version ferme explicitement le point de risque initial sur l'environnement Xcode et rend le build GUI reproductible sans dépendre d'un `xcode-select` global bien configuré.

## Notes

- Le warning `Metadata extraction skipped. No AppIntents.framework dependency found.` est attendu ici et non bloquant.
- Le warning sur destination multiple macOS (`arm64`, `x86_64`) est informatif et non bloquant.
