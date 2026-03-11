import Foundation
import SwiftUI
import Combine
import AppKit
import UniformTypeIdentifiers

@MainActor
final class RenamePresetStore: ObservableObject {

    @Published var items: [RenamePreset] = []
    @Published var presetToApply: RenamePreset?
    @Published var lastErrorMessage: String?
    @Published var lastInfoMessage: String?

    private let appDir: URL
    private let presetsDir: URL
    private let listURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.appDir = base.appendingPathComponent("MuniRename", isDirectory: true)
        self.presetsDir = appDir.appendingPathComponent("Presets", isDirectory: true)
        self.listURL = appDir.appendingPathComponent("presets.json")

        do {
            try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: presetsDir, withIntermediateDirectories: true)
        } catch {
            lastErrorMessage = "Impossible de créer les dossiers presets: \(error.localizedDescription)"
        }

        load()
        if items.isEmpty {
            items = Self.defaults()
            save()
        }
    }

    // MARK: - Persistance
    func load() {
        do {
            guard FileManager.default.fileExists(atPath: listURL.path) else {
                items = []
                return
            }

            let data = try Data(contentsOf: listURL)
            let decoded = try PresetCodec.decodePresetList(from: data)
            items = normalizePresetCollection(decoded)
        } catch {
            items = []
            lastErrorMessage = "Lecture presets impossible: \(error.localizedDescription)"
        }
    }

    func save() {
        do {
            items = normalizePresetCollection(items)
            let data = try PresetCodec.encodePresetList(items)
            try data.write(to: listURL, options: .atomic)
        } catch {
            lastErrorMessage = "Sauvegarde presets impossible: \(error.localizedDescription)"
        }
    }

    // MARK: - CRUD
    func add(category: String) {
        let cleanCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalCategory = cleanCategory.isEmpty ? "Divers" : cleanCategory
        let name = uniqueName(base: "Nouveau preset", category: finalCategory)
        items.append(RenamePreset(name: name, category: finalCategory))
        save()
    }

    func delete(_ preset: RenamePreset) {
        items.removeAll { $0.id == preset.id }
        save()
    }

    func duplicate(_ preset: RenamePreset) {
        var copy = sanitize(preset)
        copy.id = UUID()
        copy.name = uniqueName(base: preset.name + " (copie)", category: preset.category)
        items.append(copy)
        save()
    }

    func resetToDefaults() {
        items = Self.defaults()
        save()
        lastInfoMessage = "Les presets par défaut ont été réinitialisés."
    }

    func validationIssues(for preset: RenamePreset) -> [PresetValidationIssue] {
        PresetValidator.validate(sanitize(preset))
    }

    // MARK: - Import / Export
    func exportSingle(_ preset: RenamePreset) {
        let panel = NSSavePanel()
        if #available(macOS 12.0, *) {
            panel.allowedContentTypes = [.json]
        } else {
            panel.allowedFileTypes = ["json"]
        }
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = sanitizeFileName(preset.name) + ".json"
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first

        let write: (URL) -> Void = { url in
            do {
                let data = try PresetCodec.encodePreset(self.sanitize(preset))
                try data.write(to: url, options: .atomic)
                self.lastInfoMessage = "Preset exporté: \(url.lastPathComponent)"
            } catch {
                self.lastErrorMessage = "Export impossible: \(error.localizedDescription)"
                NSAlert(error: error).runModal()
            }
        }

        if let win = frontmostWindow() {
            panel.beginSheetModal(for: win) { resp in
                guard resp == .OK, let url = panel.url else { return }
                write(url)
            }
        } else if panel.runModal() == .OK, let url = panel.url {
            write(url)
        }
    }

    func importSingle() {
        let panel = NSOpenPanel()
        if #available(macOS 12.0, *) {
            panel.allowedContentTypes = [.json]
        } else {
            panel.allowedFileTypes = ["json"]
        }
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first

        let read: (URL) -> Void = { url in
            do {
                let data = try Data(contentsOf: url)
                var imported = try PresetCodec.decodePreset(from: data)

                let issues = PresetValidator.validate(imported)
                imported = self.sanitize(imported)
                imported.id = UUID()
                imported.name = self.uniqueName(base: imported.name, category: imported.category)

                self.items.append(imported)
                self.save()

                if issues.isEmpty {
                    self.lastInfoMessage = "Preset importé: \(imported.name)"
                } else {
                    self.lastInfoMessage = "Preset importé avec normalisation (\(issues.count) correction(s))."
                }
            } catch {
                self.lastErrorMessage = "Import impossible: \(error.localizedDescription)"
                NSAlert(error: error).runModal()
            }
        }

        if let win = frontmostWindow() {
            panel.beginSheetModal(for: win) { resp in
                guard resp == .OK, let url = panel.url else { return }
                read(url)
            }
        } else if panel.runModal() == .OK, let url = panel.url {
            read(url)
        }
    }

    // MARK: - Groupes
    var categories: [String] {
        let all = items.map { $0.category.trimmingCharacters(in: .whitespacesAndNewlines) }
        let clean = all.map { $0.isEmpty ? "Divers" : $0 }
        return Array(Set(clean)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func presets(in category: String) -> [RenamePreset] {
        items
            .filter { normalizeCategory($0.category) == normalizeCategory(category) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Presets par défaut (outil manuel générique)
    static func defaults() -> [RenamePreset] {
        var photos = RenamePreset(name: "Photos - Date + compteur", category: "Médias")
        photos.date = .init(enabled: true, format: "yyyy-MM-dd", usePrefix: true, useSuffix: false, useAtPosition: false, atIndex: 1)
        photos.num = .init(enabled: true, asPrefix: false, start: 1, step: 1, pad: 3, sep: "_", onlySelection: false, pattern: "")

        var docs = RenamePreset(name: "Documents - Nettoyage espaces", category: "Documents")
        docs.replace = .init(enabled: true, find: "\\s+", replace: " ", regex: true, caseSensitive: false)
        docs.remove = .init(enabled: true, from: nil, to: nil, collapseSpaces: true, trimWhitespace: true)

        var pdf = RenamePreset(name: "PDF - Extension normalisée", category: "Documents")
        pdf.ext = .init(enabled: true, newExt: "pdf", caseChange: .lower)

        return [photos, docs, pdf]
    }

    // MARK: - Utilitaires
    private func sanitize(_ preset: RenamePreset) -> RenamePreset {
        var p = preset

        p.formatVersion = max(1, p.formatVersion)
        p.name = p.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if p.name.isEmpty { p.name = "Sans titre" }

        p.category = normalizeCategory(p.category)

        if p.num.step <= 0 { p.num.step = 1 }
        p.num.pad = max(1, min(p.num.pad, 12))

        if p.add.insertIndex < 1 { p.add.insertIndex = 1 }
        if p.date.atIndex < 1 { p.date.atIndex = 1 }

        if p.ext.enabled {
            p.ext.newExt = p.ext.newExt.replacingOccurrences(of: ".", with: "")
        }

        if p.destination.enabled, p.destination.url == nil {
            p.destination.enabled = false
        }

        return p
    }

    private func normalizePresetCollection(_ source: [RenamePreset]) -> [RenamePreset] {
        var result: [RenamePreset] = []
        var seenIDs = Set<UUID>()
        var usedNamesByCategory: [String: Set<String>] = [:]

        for raw in source {
            var p = sanitize(raw)

            if seenIDs.contains(p.id) {
                p.id = UUID()
            }
            seenIDs.insert(p.id)

            let categoryKey = normalizeCategory(p.category)
            let currentNames = usedNamesByCategory[categoryKey, default: []]
            p.name = makeUniqueName(base: p.name, existing: currentNames)
            usedNamesByCategory[categoryKey, default: []].insert(p.name.lowercased())

            result.append(p)
        }

        return result
    }

    private func uniqueName(base: String, category: String) -> String {
        let existing = Set(
            items
                .filter { normalizeCategory($0.category) == normalizeCategory(category) }
                .map { $0.name.lowercased() }
        )
        return makeUniqueName(base: base, existing: existing)
    }

    private func makeUniqueName(base: String, existing: Set<String>) -> String {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let root = trimmed.isEmpty ? "Sans titre" : trimmed

        if !existing.contains(root.lowercased()) {
            return root
        }

        var i = 2
        while true {
            let candidate = "\(root) (\(i))"
            if !existing.contains(candidate.lowercased()) {
                return candidate
            }
            i += 1
        }
    }

    private func normalizeCategory(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Divers" : trimmed
    }

    private func frontmostWindow() -> NSWindow? {
        NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible })
    }

    private func sanitizeFileName(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return s.components(separatedBy: bad).joined().replacingOccurrences(of: " ", with: "_")
    }
}
