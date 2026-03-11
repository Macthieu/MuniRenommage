# STATUS CURRENT - MuniRename

Date: 2026-03-11

## Point Xcode (ancien blocage) - résolution

Le blocage initial venait de `xcode-select` pointant vers `CommandLineTools`.

Etat actuel:
- Xcode complet détecté: `/Applications/Xcode.app`
- Build app validé avec:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project MuniRename.xcodeproj -scheme MuniRename -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

Résultat: `BUILD SUCCEEDED`.

## Commande recommandée

Pour éviter toute ambiguïté d'environnement, utiliser:

```bash
./scripts/xcode_build.sh
```

Le script force automatiquement `DEVELOPER_DIR` vers Xcode complet si disponible.

## Qualité actuelle

- Build app Xcode: OK
- Build Swift Package: OK
- Smoke-tests (`munirename-smoketests`): OK
- CLI (`munirename-cli --help`): OK
