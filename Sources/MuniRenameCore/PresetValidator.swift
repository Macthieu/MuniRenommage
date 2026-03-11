import Foundation

public struct PresetValidationIssue: Equatable, Sendable {
    public var field: String
    public var message: String

    public init(field: String, message: String) {
        self.field = field
        self.message = message
    }
}

public enum PresetValidator {
    public static func validate(_ preset: RenamePreset) -> [PresetValidationIssue] {
        var issues: [PresetValidationIssue] = []

        if preset.formatVersion < 1 {
            issues.append(.init(field: "formatVersion", message: "La version de format doit etre >= 1."))
        }

        if preset.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init(field: "name", message: "Le nom du preset est obligatoire."))
        }

        if preset.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init(field: "category", message: "La categorie du preset est obligatoire."))
        }

        if preset.rules.numbering.step <= 0 {
            issues.append(.init(field: "rules.numbering.step", message: "Le pas de numerotation doit etre > 0."))
        }

        if preset.rules.numbering.pad < 1 || preset.rules.numbering.pad > 12 {
            issues.append(.init(field: "rules.numbering.pad", message: "Le padding de numerotation doit etre entre 1 et 12."))
        }

        if preset.rules.add.insertIndex < 1 {
            issues.append(.init(field: "rules.add.insertIndex", message: "La position d'insertion doit etre >= 1."))
        }

        if preset.rules.date.atIndex < 1 {
            issues.append(.init(field: "rules.date.atIndex", message: "La position de date doit etre >= 1."))
        }

        if preset.rules.date.enabled {
            let formatter = DateFormatter()
            formatter.dateFormat = preset.rules.date.format
            let sample = formatter.string(from: Date())
            if sample.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(.init(field: "rules.date.format", message: "Le format de date est invalide."))
            }
        }

        if preset.rules.ext.enabled {
            let cleaned = preset.rules.ext.newExtension.replacingOccurrences(of: ".", with: "")
            if cleaned.contains("/") || cleaned.contains(":") {
                issues.append(.init(field: "rules.ext.newExtension", message: "L'extension ne doit pas contenir / ou :."))
            }
        }

        if preset.rules.destination.enabled, preset.rules.destination.url == nil {
            issues.append(.init(field: "rules.destination.url", message: "La destination activee doit avoir un dossier cible."))
        }

        return issues
    }
}

public enum PresetCodec {
    public static func decodePreset(from data: Data) throws -> RenamePreset {
        let decoder = JSONDecoder()

        if let wrapped = try? decoder.decode(PresetDocument.self, from: data) {
            return wrapped.preset
        }

        return try decoder.decode(RenamePreset.self, from: data)
    }

    public static func encodePresetDocument(_ preset: RenamePreset) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(PresetDocument(schemaVersion: 1, preset: preset))
    }
}
