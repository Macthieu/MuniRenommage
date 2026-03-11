import Foundation

struct PresetValidationIssue: Equatable {
    let field: String
    let message: String
}

enum PresetValidator {
    static func validate(_ preset: RenamePreset) -> [PresetValidationIssue] {
        var issues: [PresetValidationIssue] = []

        if preset.formatVersion < 1 {
            issues.append(.init(field: "formatVersion", message: "La version de format doit être >= 1."))
        }

        if preset.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init(field: "name", message: "Le nom du preset est obligatoire."))
        }

        if preset.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init(field: "category", message: "La catégorie du preset est obligatoire."))
        }

        if preset.num.step <= 0 {
            issues.append(.init(field: "num.step", message: "Le pas de numérotation doit être > 0."))
        }

        if preset.num.pad < 1 || preset.num.pad > 12 {
            issues.append(.init(field: "num.pad", message: "Le padding doit être entre 1 et 12."))
        }

        if preset.add.insertIndex < 1 {
            issues.append(.init(field: "add.insertIndex", message: "La position d'insertion doit être >= 1."))
        }

        if preset.date.atIndex < 1 {
            issues.append(.init(field: "date.atIndex", message: "La position de date doit être >= 1."))
        }

        if preset.date.enabled {
            let formatter = DateFormatter()
            formatter.dateFormat = preset.date.format
            let sample = formatter.string(from: Date())
            if sample.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(.init(field: "date.format", message: "Le format de date est invalide."))
            }
        }

        if preset.ext.enabled {
            let cleaned = preset.ext.newExt.replacingOccurrences(of: ".", with: "")
            if cleaned.contains("/") || cleaned.contains(":") {
                issues.append(.init(field: "ext.newExt", message: "L'extension ne doit pas contenir / ou :."))
            }
        }

        if preset.destination.enabled, preset.destination.url == nil {
            issues.append(.init(field: "destination.url", message: "Une destination activée doit avoir un dossier cible."))
        }

        return issues
    }
}

struct PresetFileV1: Codable {
    var schemaVersion: Int = 1
    var preset: RenamePreset
}

struct PresetListFileV1: Codable {
    var schemaVersion: Int = 1
    var presets: [RenamePreset]
}

enum PresetCodec {
    static func decodePreset(from data: Data) throws -> RenamePreset {
        let decoder = JSONDecoder()

        if let wrapped = try? decoder.decode(PresetFileV1.self, from: data) {
            return wrapped.preset
        }

        return try decoder.decode(RenamePreset.self, from: data)
    }

    static func encodePreset(_ preset: RenamePreset) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(PresetFileV1(schemaVersion: 1, preset: preset))
    }

    static func decodePresetList(from data: Data) throws -> [RenamePreset] {
        let decoder = JSONDecoder()

        if let wrapped = try? decoder.decode(PresetListFileV1.self, from: data) {
            return wrapped.presets
        }

        return try decoder.decode([RenamePreset].self, from: data)
    }

    static func encodePresetList(_ presets: [RenamePreset]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(PresetListFileV1(schemaVersion: 1, presets: presets))
    }
}
