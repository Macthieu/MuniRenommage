# AUDIT COMPLET - MuniRename

Date: 2026-03-11
Portee: audit mainteneur principal (code, architecture, assets, release readiness)

## 1) Arborescence observee

```text
.
├── MuniRename/
│   ├── ContentView.swift
│   ├── MuniRenameApp.swift
│   ├── RenamePresetStore.swift
│   └── Assets.xcassets/
│       └── AppIcon.appiconset/Contents.json
├── MuniRename.xcodeproj/
├── README.md
├── LICENSE
├── .gitignore
├── MuniRename_icon.png
└── docs/
    └── STATUS-INITIAL.md
```

## 2) Stack et structure technique

- App macOS SwiftUI avec usage AppKit ponctuel (`NSOpenPanel`, `NSSavePanel`, `NSAlert`, `NSWorkspace`, `NSSound`).
- Projet Xcode classique (`.xcodeproj`), pas de Swift Package dédié.
- Une seule target app (`MuniRename`), pas de target de tests.
- Ressources: `Assets.xcassets` (icone app declaree via `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`).
- Versioning projet: `MARKETING_VERSION = 1.0`, `CURRENT_PROJECT_VERSION = 1`.
- Bundle ID actuel: `Mars.MuniRename`.

## 3) Build actuel

- Build non executable ici: `xcodebuild` indisponible (Xcode complet non selectionne).
- En l'etat, validation compile/runtime non prouvable dans cet environnement.

## 4) Etat qualite/release

- `LICENSE` present (GPLv3).
- `README.md` present mais encore incomplet pour une release robuste (pas de limitations connues, pas de roadmap claire, pas de guide contribution/release).
- `CHANGELOG.md` absent.
- CI GitHub Actions absente.
- Tags/release: aucun.

## 5) Cohérence produit

- Nom produit/target/scheme/README: globalement coherent (`MuniRename`).
- Bundle identifier (`Mars.MuniRename`) peu neutre pour un projet OSS public.
- Ressources branding incoherentes:
  - `MuniRename_icon.png` a la racine, non versionne dans le flux app icon.
  - `AppIcon.appiconset` ne reference aucun fichier image (seulement les slots), donc risque d'icone par defaut.

## 6) Revue critique (classement)

## Bloquant

1. Couche Presets partiellement non operationnelle dans l'UI:
- `PresetEditorView` est un placeholder (`VStack { /* ... */ }`), donc edition fine de preset absente.
- Risque fonctionnel majeur pour une fonctionnalite centrale annoncee.

2. Architecture monolithique et couplee:
- `ContentView.swift` (~1163 lignes) melange modeles, logique metier, persistance implicite, VM et UI.
- Frein direct a la maintenabilite, aux tests et a la stabilisation produit.

3. Chaine d'icones incomplete:
- Icône source non integree proprement, AppIcon potentiellement vide.
- Incompatible avec une release macOS credibile.

## Important

1. Robustesse metier renommage insuffisante:
- Pas de validation centralisee des noms cibles (caracteres interdits, nom vide, longueur, contraintes FS).
- Detection de collisions limitee (verifie seulement existence immediate du chemin cible, pas tous les cas de collisions intra-lot ni swaps complexes).
- Fort couplage preview/execution dans la VM UI.

2. Presets: persistance fragile pour evolution:
- Pas de version de schema explicite dans le format JSON.
- Validation metier incomplete avant sauvegarde/import.
- Import ajoute directement un preset decode sans garde-fous (nom dupliqué, champs incoherents, extension invalide, etc.).

3. Gestion d'erreurs partiellement silencieuse:
- Plusieurs `try?` sans remontée utilisateur/contextuelle pour load/save.
- Debogue et support utilisateur difficiles.

4. Qualite projet OSS incomplète:
- Pas de tests unitaires.
- Pas de CI.
- Pas de changelog/versioning release explicite.

## Souhaitable

1. Clarifier l'UX des operations lourdes:
- Mode simulation explicite, resume pre-application, rapport post-operation.

2. Mieux structurer le code:
- Separation explicite `App/`, `Features/`, `Domain/`, `Infrastructure/`, `Shared/`.

3. Documentation mainteneur:
- Ajouter guide architecture + conventions + process release.

## 7) Conclusion d'audit

Le projet est recuperable et deja fonctionnel sur plusieurs points (base SwiftUI/AppKit, logique de preview, import/export de presets existant), mais il n'est pas encore au niveau d'une release publique serieuse.

Priorites de remise a niveau:
1. Stabiliser l'architecture et extraire la logique metier testable.
2. Refondre/moderer la couche Presets avec validation + schema versionne.
3. Corriger la chaine d'icones/app assets.
4. Ajouter tests, changelog, CI minimale et process release.
