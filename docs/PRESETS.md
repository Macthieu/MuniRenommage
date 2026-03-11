# PRESETS - MuniRename

Date: 2026-03-11
Option retenue: **B - refactorer modérément**

## 1) Ce qu'est un preset dans MuniRename

Un preset est un **profil métier de renommage manuel** réutilisable.

Ce n'est pas un raccourci UI éphémère: il encapsule une configuration complète de règles de renommage, de filtres et de destination, afin d'appliquer rapidement un comportement cohérent sur un lot de fichiers.

## 2) Ce que contient un preset

Type principal: `RenamePreset`

Champs structurants:
- `id`: identifiant stable
- `formatVersion`: version de format du preset
- `name`: nom lisible
- `category`: regroupement fonctionnel
- règles:
- `replace`
- `remove`
- `add`
- `date`
- `num`
- `casing`
- `ext`
- `folder`
- `special`
- `filters`
- `destination`

## 3) Comment les presets sont stockés

Stockage local app:
- dossier: `~/Library/Application Support/MuniRename/`
- fichier principal: `presets.json`

Formats supportés:
- liste versionnée: `PresetListFileV1` (`schemaVersion`, `presets`)
- compatibilité ancienne liste brute: `[RenamePreset]`

Import/export unitaire:
- enveloppe versionnée: `PresetFileV1` (`schemaVersion`, `preset`)
- compatibilité format brut: `RenamePreset`

## 4) Validation et fiabilité

Validation centralisée (`PresetValidator`):
- nom obligatoire
- catégorie obligatoire
- version de format >= 1
- pas de numérotation > 0
- padding borné
- positions (date/insertion) >= 1
- extension sans caractères interdits
- destination cohérente (URL requise si activée)

Sanitization avant persistance:
- normalisation des champs vides
- correction des bornes invalides
- normalisation extension
- désactivation destination invalide
- dédoublonnage de noms par catégorie
- dédoublonnage des IDs

## 5) Capacités utilisateur couvertes

La couche actuelle couvre:
- créer
- dupliquer
- renommer (édition de `name`)
- changer catégorie
- supprimer
- réinitialiser tous les presets par défaut
- exporter/importer JSON
- appliquer un preset à la fenêtre principale

## 6) Pourquoi l'option B (refactor modéré)

- L'existant était récupérable (modèle de règles déjà riche).
- Le principal problème était la robustesse (validation/format/UX), pas la nécessité d'une refonte totale immédiate.
- Le refactor modéré permet d'améliorer fortement la fiabilité sans casser brutalement la compatibilité des presets déjà créés.

## 7) Limites actuelles

- Pas de migration multi-versions avancée au-delà de `v1` (base posée, migration future à formaliser).
- L'éditeur de preset reste dense: l'ergonomie peut encore être simplifiée par groupes métier.
- Pas encore de tests UI sur l'éditeur de presets (mais règles/format validés côté core package).

## 8) Evolution prévue

- Ajouter une stratégie de migration explicite (`v1 -> v2`) avec tests de non-régression.
- Ajouter des presets d'exemple orientés usages réels "manuel en lot".
- Ajouter un résumé lisible d'un preset (vue compacte) avant application.
