import Foundation
import SwiftUI
import Combine
import AppKit
import UniformTypeIdentifiers

@MainActor
final class RenamePresetStore: ObservableObject {

    // Liste en mémoire + preset « à appliquer » à la fenêtre principale
    @Published var items: [RenamePreset] = []
    @Published var presetToApply: RenamePreset?

    // Dossiers: ~/Library/Application Support/MuniRename/Presets
    private let appDir: URL
    private let presetsDir: URL
    private let listURL: URL // stockage “ancien” tout-en-un, on le garde pour compat

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.appDir     = base.appendingPathComponent("MuniRename", isDirectory: true)
        self.presetsDir = appDir.appendingPathComponent("Presets", isDirectory: true)
        self.listURL    = appDir.appendingPathComponent("presets.json")

        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: presetsDir, withIntermediateDirectories: true)

        load()
        if items.isEmpty {
            items = Self.defaults()
            save()
        }
    }

    // MARK: - Persistance (liste principale en JSON lisible par l’humain/IA)
    func load() {
        guard let data = try? Data(contentsOf: listURL) else { return }
        if let decoded = try? JSONDecoder().decode([RenamePreset].self, from: data) {
            items = decoded
        }
    }

    func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if let data = try? enc.encode(items) {
            try? data.write(to: listURL, options: .atomic)
        }
    }

    // MARK: - CRUD
    func add(category: String) {
        items.append(RenamePreset(name: "Nouveau preset", category: category))
        save()
    }

    func delete(_ preset: RenamePreset) {
        items.removeAll { $0.id == preset.id }
        save()
    }

    func duplicate(_ preset: RenamePreset) {
        var copy = preset
        copy.id = UUID()
        copy.name += " (copie)"
        items.append(copy)
        save()
    }

    // MARK: - Import / Export (panels AppKit robustes)
    func exportSingle(_ preset: RenamePreset) {
        // Tout se passe sur le MainActor (on y est déjà grâce à @MainActor, mais on reste explicite)
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

        // Ecriture JSON (lisible pour IA/humain)
        let write: (URL) -> Void = { url in
            do {
                let enc = JSONEncoder()
                enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                let data = try enc.encode(preset)
                try data.write(to: url, options: .atomic)
            } catch {
                NSAlert(error: error).runModal()
            }
        }

        if let win = frontmostWindow() {
            panel.beginSheetModal(for: win) { resp in
                guard resp == .OK, let url = panel.url else { return }
                write(url)
            }
        } else {
            if panel.runModal() == .OK, let url = panel.url {
                write(url)
            }
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
                let preset = try JSONDecoder().decode(RenamePreset.self, from: data)
                self.items.append(preset)
                self.save()
            } catch {
                NSAlert(error: error).runModal()
            }
        }

        if let win = frontmostWindow() {
            panel.beginSheetModal(for: win) { resp in
                guard resp == .OK, let url = panel.url else { return }
                read(url)
            }
        } else {
            if panel.runModal() == .OK, let url = panel.url {
                read(url)
            }
        }
    }

    // MARK: - Groupes par catégories
    var categories: [String] {
        Array(Set(items.map(\.category))).sorted()
    }

    func presets(in category: String) -> [RenamePreset] {
        items
            .filter { $0.category == category }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Exemples par défaut
    static func defaults() -> [RenamePreset] {
        var caucus = RenamePreset(name: "Caucus – Renommage standard", category: "Caucus")
        caucus.date = .init(enabled: true, format: "yyyy-MM-dd", usePrefix: true, useSuffix: false, useAtPosition: false, atIndex: 1)
        caucus.num  = .init(enabled: true, asPrefix: true, start: 1, step: 1, pad: 2, sep: " – ", onlySelection: false)
        caucus.special = .init(enabled: true, normalizeUnicode: true, stripDiacritics: true, dashToEnDash: true, spacesToUnderscore: false)

        var seance = RenamePreset(name: "Séance – Ordre du jour", category: "Conseil")
        seance.replace = .init(enabled: true, find: "\\s+", replace: " ", regex: true, caseSensitive: false)
        seance.num = .init(enabled: true, asPrefix: true, start: 1, step: 1, pad: 1, sep: ". ", onlySelection: true)

        var travaux = RenamePreset(name: "Travaux publics – PDF en MAJUSCULES", category: "Services")
        travaux.casing = .init(enabled: true, style: .upper)
        travaux.ext = .init(enabled: true, newExt: "pdf", caseChange: .lower)

        return [caucus, seance, travaux]
    }

    // MARK: - Util
    private func frontmostWindow() -> NSWindow? {
        NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible })
    }

    private func sanitizeFileName(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return s.components(separatedBy: bad).joined().replacingOccurrences(of: " ", with: "_")
    }
}
