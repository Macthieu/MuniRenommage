import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

// MARK: - Modèles
struct FileEntry: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    var originalName: String { url.lastPathComponent }
    var ext: String { url.pathExtension }
    var baseName: String { url.deletingPathExtension().lastPathComponent }
}

enum CaseStyle: String, CaseIterable, Identifiable, Codable {
    case unchanged = "Aucune", lower = "minuscules", upper = "MAJUSCULES", title = "Casse Titre"
    var id: String { rawValue }
}
enum ExtCase: String, CaseIterable, Identifiable, Codable {
    case none = "(inchangé)", lower = "minuscules", upper = "MAJUSCULES"
    var id: String { rawValue }
}

// MARK: - Règles (Codable pour presets)
struct ReplaceSec:    Codable { var enabled = false; var find = ""; var replace = ""; var regex = true; var caseSensitive = false }
struct RemoveSec:     Codable { var enabled = false; var from: Int? = nil; var to: Int? = nil; var collapseSpaces = false; var trimWhitespace = false }
struct AddSec:        Codable { var enabled = false; var usePrefix = false; var prefix = ""; var useSuffix = false; var suffix = ""; var insertText = ""; var insertIndex: Int = 1 }
struct DateSec:       Codable { var enabled = false; var format = "yyyy-MM-dd"; var usePrefix = false; var useSuffix = false; var useAtPosition = true; var atIndex: Int = 1 }
struct NumberingSec: Codable {
    var enabled       = false
    var asPrefix      = true
    var start         = 1
    var step          = 1
    var pad           = 3              // largeur utilisée si pattern vide
    var sep           = " - "
    var onlySelection = false
    var pattern       = ""            // ex. "04.##" ou "4.01.##"
}
struct CaseSec:       Codable { var enabled = false; var style: CaseStyle = .unchanged }
struct ExtSec:        Codable { var enabled = false; var newExt = ""; var caseChange: ExtCase = .none }
struct FolderNameSec: Codable { var enabled = false; var addParentAsPrefix = true; var sep = " – " }
struct SpecialSec:    Codable { var enabled = false; var normalizeUnicode = true; var stripDiacritics = false; var dashToEnDash = false; var spacesToUnderscore = false }
struct FiltersSec:    Codable { var recursive = false; var includeHidden = false; var includeRegex = ""; var excludeRegex = "" }
struct DestinationSec:Codable { var enabled = false; var url: URL? = nil; var copyInsteadOfMove = false }

// MARK: - Preset (renommé pour éviter toute collision)
struct RenamePreset: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String = "Sans titre"
    var category: String = "Divers"
    var replace: ReplaceSec = .init()
    var remove: RemoveSec = .init()
    var add: AddSec = .init()
    var date: DateSec = .init()
    var num: NumberingSec = .init()
    var casing: CaseSec = .init()
    var ext: ExtSec = .init()
    var folder: FolderNameSec = .init()
    var special: SpecialSec = .init()
    var filters: FiltersSec = .init()
    var destination: DestinationSec = .init()

    static func == (lhs: RenamePreset, rhs: RenamePreset) -> Bool { lhs.id == rhs.id }
}

// MARK: - ViewModel du renommeur
final class RenameVM: ObservableObject {
    enum UndoEntry { case move(from: URL, to: URL), delete(url: URL) }

    @Published var directoryURL: URL?
    @Published var entries: [FileEntry] = []
    @Published var selection: Set<UUID> = []

    /// Quand c'est activé, l'aperçu (colonne « Nouveau nom »)
    /// n'applique les règles qu'aux fichiers sélectionnés.
    @Published var previewOnlySelection = false
    
    @Published var replace = ReplaceSec()
    @Published var remove  = RemoveSec()
    @Published var add     = AddSec()
    @Published var date    = DateSec()
    @Published var num     = NumberingSec()
    @Published var casing  = CaseSec()
    @Published var ext     = ExtSec()
    @Published var folder  = FolderNameSec()
    @Published var special = SpecialSec()
    @Published var filters = FiltersSec()
    @Published var destination = DestinationSec()

    @Published var preview: [UUID: String] = [:]
    @Published var statuses: [UUID: String] = [:]
    @Published var isLoading = false

    private var undoJournal: [UndoEntry] = []
    private let worker = DispatchQueue(label: "RenameVM.worker", qos: .userInitiated)
    private var previewJob = 0

    // Dossiers
    func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Choisir un dossier"
        if panel.runModal() == .OK { directoryURL = panel.url; loadEntries() }
    }
    func pickDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Choisir le dossier de destination"
        if panel.runModal() == .OK { destination.url = panel.url }
    }

    // Chargement
    func loadEntries() {
        guard let dir = directoryURL else { return }
        isLoading = true
        let includeHidden = filters.includeHidden
        let recursive = filters.recursive
        let includeRx = filters.includeRegex
        let excludeRx = filters.excludeRegex

        worker.async { [weak self] in
            guard let self else { return }
            var urls: [URL] = []
            do {
                if recursive {
                    let en = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey], options: includeHidden ? [] : [.skipsHiddenFiles])
                    while let u = en?.nextObject() as? URL {
                        if (try? u.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { urls.append(u) }
                    }
                } else {
                    urls = try FileManager.default
                        .contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isRegularFileKey], options: includeHidden ? [] : [.skipsHiddenFiles])
                        .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
                }

                var list = urls.map { FileEntry(url: $0) }

                if !includeRx.isEmpty, let inc = try? NSRegularExpression(pattern: includeRx) {
                    list = list.filter {
                        inc.firstMatch(in: $0.originalName, range: NSRange($0.originalName.startIndex..<$0.originalName.endIndex, in: $0.originalName)) != nil
                    }
                }
                if !excludeRx.isEmpty, let exc = try? NSRegularExpression(pattern: excludeRx) {
                    list = list.filter {
                        exc.firstMatch(in: $0.originalName, range: NSRange($0.originalName.startIndex..<$0.originalName.endIndex, in: $0.originalName)) == nil
                    }
                }

                let sorted = list.sorted { $0.originalName.localizedStandardCompare($1.originalName) == .orderedAscending }

                DispatchQueue.main.async {
                    self.entries = sorted
                    self.selection.removeAll()
                    self.isLoading = false
                    self.recomputePreviewAsync()
                }
            } catch {
                DispatchQueue.main.async {
                    self.entries = []; self.selection.removeAll()
                    self.isLoading = false; self.preview = [:]; self.statuses = [:]
                }
            }
        }
    }

    // Aperçu
    func recomputePreviewAsync() {
        let jobId = previewJob &+ 1
        previewJob = jobId

        let entries   = self.entries
        let replace   = self.replace
        let remove    = self.remove
        let add       = self.add
        let date      = self.date
        let num       = self.num
        let casing    = self.casing
        let ext       = self.ext
        let folder    = self.folder
        let special   = self.special
        let dirURL    = self.directoryURL
        let selection = self.selection
        let previewOnlySelection = self.previewOnlySelection

        // Liste concrète des fichiers sélectionnés
        let selectionList: [FileEntry] =
            selection.isEmpty ? [] : entries.filter { selection.contains($0.id) }

        // Scope global de l’aperçu : tous les fichiers ou seulement la sélection
        let previewScope: [FileEntry]
        if previewOnlySelection, !selectionList.isEmpty {
            previewScope = selectionList
        } else {
            previewScope = entries
        }

        // Scope de numérotation :
        // - si "Numérotation → seulement pour la sélection" est cochée → on utilise la sélection
        // - sinon → on suit le scope de l’aperçu
        let numberingTargets: [FileEntry]
        if num.onlySelection, !selectionList.isEmpty {
            numberingTargets = selectionList
        } else {
            numberingTargets = previewScope
        }

        let orderIndex: [UUID: Int] = Dictionary(
            uniqueKeysWithValues: numberingTargets.enumerated().map { ($0.element.id, $0.offset) }
        )

        // Ensemble des fichiers pour lesquels on applique réellement les règles
        let previewTargetIDs = Set(previewScope.map(\.id))

        worker.async { [weak self] in
            guard let self else { return }
            var newPreview: [UUID: String] = [:]
            var newStatuses: [UUID: String] = [:]

            for e in entries {
                // Hors du scope d’aperçu → on garde le nom original et on ne touche pas
                guard previewTargetIDs.contains(e.id) else {
                    newPreview[e.id] = e.originalName
                    continue
                }

                var base = e.baseName

                // 1) Remplacer
                if replace.enabled, !replace.find.isEmpty {
                    if replace.regex,
                       let rx = try? NSRegularExpression(
                            pattern: replace.find,
                            options: replace.caseSensitive ? [] : [.caseInsensitive]
                       ) {
                        base = rx.stringByReplacingMatches(
                            in: base,
                            range: NSRange(base.startIndex..<base.endIndex, in: base),
                            withTemplate: replace.replace
                        )
                    } else if !replace.regex {
                        base = base.replacingOccurrences(
                            of: replace.find,
                            with: replace.replace,
                            options: replace.caseSensitive ? [] : [.caseInsensitive]
                        )
                    }
                }

                // 2) Retirer
                if remove.enabled {
                    if let from = remove.from,
                       let to = remove.to,
                       from > 0,
                       to >= from,
                       from <= base.count {
                        let f = base.index(base.startIndex, offsetBy: from - 1)
                        let t = base.index(base.startIndex, offsetBy: min(to, base.count) - 1)
                        base.removeSubrange(f...t)
                    }
                    if remove.trimWhitespace {
                        base = base.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    if remove.collapseSpaces {
                        base = base.replacingOccurrences(
                            of: "\\s+",
                            with: " ",
                            options: .regularExpression
                        )
                    }
                }

                // 3) Ajouter
                if add.enabled {
                    if add.usePrefix { base = add.prefix + base }
                    if add.useSuffix { base += add.suffix }
                    if !add.insertText.isEmpty {
                        let idx0 = max(0, min(add.insertIndex - 1, base.count))
                        base.insert(
                            contentsOf: add.insertText,
                            at: base.index(base.startIndex, offsetBy: idx0)
                        )
                    }
                }

                // 4) Date auto
                if date.enabled {
                    let df = DateFormatter()
                    df.locale = .current
                    df.dateFormat = date.format
                    let stamp = df.string(from: Date())
                    if date.usePrefix { base = stamp + " " + base }
                    if date.useAtPosition {
                        let idx0 = max(0, min(date.atIndex - 1, base.count))
                        base.insert(
                            contentsOf: stamp,
                            at: base.index(base.startIndex, offsetBy: idx0)
                        )
                    }
                    if date.useSuffix { base = base + " " + stamp }
                }

                // 5) Numérotation
                if num.enabled, let idx = orderIndex[e.id] {
                    let n = num.start + idx * num.step
                    let token = self.formatNumber(n, using: num)
                    base = num.asPrefix ? token + num.sep + base : base + num.sep + token
                }

                // 6) Casse
                if casing.enabled {
                    switch casing.style {
                    case .unchanged: break
                    case .lower: base = base.lowercased()
                    case .upper: base = base.uppercased()
                    case .title: base = base.localizedCapitalized
                    }
                }

                // 7) Dossier parent
                if folder.enabled, let parent = dirURL?.lastPathComponent {
                    let addStr = parent + folder.sep
                    base = folder.addParentAsPrefix ? addStr + base : base + folder.sep + parent
                }

                // 8) Spécial
                if special.enabled {
                    if special.normalizeUnicode {
                        base = base.precomposedStringWithCanonicalMapping
                    }
                    if special.stripDiacritics {
                        base = base.folding(options: .diacriticInsensitive, locale: .current)
                    }
                    if special.dashToEnDash {
                        base = base.replacingOccurrences(of: " - ", with: " – ")
                    }
                    if special.spacesToUnderscore {
                        base = base.replacingOccurrences(of: " ", with: "_")
                    }
                }

                // 9) Extension
                var extPartFinal = e.ext
                if ext.enabled {
                    if !ext.newExt.isEmpty {
                        extPartFinal = ext.newExt.replacingOccurrences(of: ".", with: "")
                    }
                    switch ext.caseChange {
                    case .none: break
                    case .lower: extPartFinal = extPartFinal.lowercased()
                    case .upper: extPartFinal = extPartFinal.uppercased()
                    }
                }

                let finalName = extPartFinal.isEmpty
                    ? base
                    : base + "." + extPartFinal

                newPreview[e.id] = finalName
                newStatuses[e.id] = ""
            }

            DispatchQueue.main.async {
                guard self.previewJob == jobId else { return }
                self.preview = newPreview
                self.statuses = newStatuses
            }
        }
    }

    // Appliquer / Undo
    func apply() {
        guard directoryURL != nil else { return }
        undoJournal.removeAll()
        var hadError = false

        let targets: [FileEntry] = selection.isEmpty ? entries : entries.filter { selection.contains($0.id) }

        for e in targets {
            guard let nn = preview[e.id], !nn.isEmpty else { continue }
            if statuses[e.id]?.isEmpty == false { hadError = true; continue }

            let baseDir = destination.enabled ? (destination.url ?? e.url.deletingLastPathComponent()) : e.url.deletingLastPathComponent()
            let dest = baseDir.appendingPathComponent(nn)

            if FileManager.default.fileExists(atPath: dest.path) { statuses[e.id] = "Existant"; hadError = true; continue }

            do {
                if destination.enabled && destination.copyInsteadOfMove {
                    try FileManager.default.copyItem(at: e.url, to: dest)
                    undoJournal.append(.delete(url: dest))
                } else {
                    try FileManager.default.moveItem(at: e.url, to: dest)
                    undoJournal.append(.move(from: dest, to: e.url))
                }
            } catch {
                statuses[e.id] = "Erreur: \(error.localizedDescription)"; hadError = true
            }
        }
        loadEntries(); if hadError { NSSound.beep() }
    }

    func undoLast() {
        guard !undoJournal.isEmpty else { return }
        var failures = 0
        for op in undoJournal {
            do {
                switch op {
                case let .move(from, to): try FileManager.default.moveItem(at: from, to: to)
                case let .delete(url):    try FileManager.default.removeItem(at: url)
                }
            } catch { failures += 1 }
        }
        undoJournal.removeAll()
        loadEntries(); if failures > 0 { NSSound.beep() }
    }

    // Combine triggers
    var previewTrigger: AnyPublisher<Void, Never> {
        let pubs: [AnyPublisher<Void, Never>] = [
            $replace.map { _ in () }.eraseToAnyPublisher(),
            $remove.map  { _ in () }.eraseToAnyPublisher(),
            $add.map     { _ in () }.eraseToAnyPublisher(),
            $date.map    { _ in () }.eraseToAnyPublisher(),
            $num.map     { _ in () }.eraseToAnyPublisher(),
            $casing.map  { _ in () }.eraseToAnyPublisher(),
            $ext.map     { _ in () }.eraseToAnyPublisher(),
            $folder.map  { _ in () }.eraseToAnyPublisher(),
            $special.map { _ in () }.eraseToAnyPublisher(),
            $previewOnlySelection.map { _ in () }.eraseToAnyPublisher(),
            $selection.map { _ in () }.eraseToAnyPublisher()
        ]
        return Publishers.MergeMany(pubs).eraseToAnyPublisher()
    }

    // Formattage de la numérotation selon le masque (ex. 04.##, 4.01.##)
    private func formatNumber(_ n: Int, using num: NumberingSec) -> String {
        let rawPattern = num.pattern.trimmingCharacters(in: .whitespacesAndNewlines)

        // Aucun masque → comportement classique (001, 002, 003…)
        guard !rawPattern.isEmpty else {
            return String(format: "%0*d", num.pad, n)
        }

        // On cherche une séquence de # (ex. "##", "###")
        if let range = rawPattern.range(of: #"#{1,}"#, options: .regularExpression) {
            let hashesCount = rawPattern[range].count
            let formatted = String(format: "%0*d", hashesCount, n)

            var result = rawPattern
            result.replaceSubrange(range, with: formatted)
            return result
        } else {
            // Pas de # dans le masque → on colle le nombre à la fin
            let numPart = String(format: "%0*d", num.pad, n)
            return rawPattern + numPart
        }
    }

    // VM <-> Preset
    var currentPreset: RenamePreset {
        var p = RenamePreset()
        p.replace = replace; p.remove = remove; p.add = add; p.date = date; p.num = num
        p.casing  = casing;  p.ext    = ext;    p.folder = folder; p.special = special
        p.filters = filters; p.destination = destination
        return p
    }

    func apply(preset p: RenamePreset) {
        replace = p.replace; remove = p.remove; add = p.add; date = p.date; num = p.num
        casing  = p.casing;  ext    = p.ext;    folder = p.folder; special = p.special
        filters = p.filters; destination = p.destination

        if directoryURL != nil {
            loadEntries()
        } else {
            recomputePreviewAsync()
        }
    }

    // Finder
    func revealInFinder(ids: Set<UUID>) {
        let urls = entries.filter { ids.contains($0.id) }.map(\.url)
        if !urls.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }
    }
}

// MARK: - Carte de section
struct SectionCard<Content: View>: View {
    let title: String
    let active: Bool
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Label(active ? "Actif" : "Inactif",
                      systemImage: active ? "checkmark.circle.fill" : "circle")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(active ? Color.accentColor.opacity(0.18)
                                              : Color.secondary.opacity(0.12))
                    )
                    .overlay(
                        Capsule().stroke(active ? Color.accentColor
                                                : Color.secondary.opacity(0.35), lineWidth: 0.9)
                    )
            }
            Divider()
            content
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(active ? Color.accentColor.opacity(0.06)
                             : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(active ? Color.accentColor.opacity(0.75)
                               : Color.secondary.opacity(0.35),
                        lineWidth: active ? 1.2 : 1)
        )
        .shadow(color: .black.opacity(active ? 0.12 : 0.06),
                radius: active ? 6 : 3, x: 0, y: active ? 3 : 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }
}

// MARK: - Vue principale
struct ContentView: View {
    @EnvironmentObject var presetStore: RenamePresetStore
    @StateObject var vm = RenameVM()
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            mainLayout
        }
        .frame(minWidth: 900, minHeight: 560)
        // Appliquer un preset choisi dans la fenêtre “Presets”
        .onReceive(presetStore.$presetToApply.compactMap { $0 }) { p in
            vm.apply(preset: p)
            presetStore.presetToApply = nil
        }
    }

    // SplitView
    private var mainLayout: some View {
        HSplitView {
            rulesPane
                .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)

            fileTable
                .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(0)
        }
        .overlay(alignment: .center) {
            if vm.isLoading {
                ProgressView("Chargement…")
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
            }
        }
    }

    // Panneau règles (2 colonnes si place suffisante)
    private var rulesPane: some View {
        GeometryReader { geo in
            ScrollView {
                let w = geo.size.width - 24
                let leftMin:  CGFloat = 420
                let rightMin: CGFloat = 560
                let gap: CGFloat = 12
                let twoCols = w >= (leftMin + rightMin + gap)

                if twoCols {
                    HStack(alignment: .top, spacing: gap) {
                        leftRulesColumn
                            .frame(minWidth: leftMin,  maxWidth: .infinity, alignment: .topLeading)
                            .padding(.trailing, 4)
                        rightRulesColumn
                            .frame(minWidth: rightMin, maxWidth: .infinity, alignment: .topLeading)
                            .padding(.leading, 4)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                } else {
                    VStack(alignment: .leading, spacing: gap) {
                        leftRulesColumn
                        rightRulesColumn
                    }
                    .padding(10)
                }
            }
            .clipped()
            .modifier(PreviewRecomputeModifier(vm: vm))
        }
    }

    private var leftRulesColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionCard(title: "(1) Remplacer",   active: vm.replace.enabled) { replaceView }
            SectionCard(title: "(2) Retirer",      active: vm.remove.enabled)  { removeView }
            SectionCard(title: "(3) Ajouter",      active: vm.add.enabled)     { addView }
            SectionCard(title: "(4) Date auto",    active: vm.date.enabled)    { dateView }
            SectionCard(title: "(5) Numérotation", active: vm.num.enabled)     { numberingView }
        }
    }

    private var rightRulesColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionCard(title: "(6) Casse",          active: vm.casing.enabled)     { caseView }
            SectionCard(title: "(7) Extension",      active: vm.ext.enabled)        { extView }
            SectionCard(title: "(8) Dossier parent", active: vm.folder.enabled)     { folderView }
            SectionCard(title: "(9) Spécial",        active: vm.special.enabled)    { specialView }
            SectionCard(title: "Destination",        active: vm.destination.enabled){ destinationView }
            SectionCard(
                title: "Filtres",
                active: !vm.filters.includeRegex.isEmpty
                     || !vm.filters.excludeRegex.isEmpty
                     || vm.filters.recursive
                     || vm.filters.includeHidden
            ) { filtersView }
        }
    }

    // Toolbar
    var toolbar: some View {
        HStack(spacing: 12) {
            Button { vm.pickFolder() } label: { Label("Choisir un dossier", systemImage: "folder") }
            if let d = vm.directoryURL {
                Text(d.path)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if !vm.entries.isEmpty {
                Text("Sélection : \(vm.selection.count) / \(vm.entries.count)")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Button("Tout sélectionner") {
                    vm.selection = Set(vm.entries.map { $0.id })
                }
                Button("Effacer la sélection") {
                    vm.selection.removeAll()
                }

                Toggle("Prévisualiser uniquement la sélection",
                       isOn: $vm.previewOnlySelection)
                    .toggleStyle(.checkbox)

                Divider().frame(height: 18)
            }
            Button { vm.loadEntries() } label: { Label("Rafraîchir", systemImage: "arrow.clockwise") }
                .keyboardShortcut("r")

            // Boutons presets
            Button("Gestion des presets…") { openWindow(id: "presets") }
            Button("Charger preset…") { presetStore.importSingle() }
            Button("Enregistrer preset de la configuration courante…") {
                var p = vm.currentPreset
                p.name = "Preset depuis la fenêtre"
                presetStore.items.append(p)
                presetStore.save()
            }

            Divider().frame(height: 18)
            Button { vm.apply() } label: { Label("Appliquer", systemImage: "hammer") }
                .keyboardShortcut(.return)
            Button { vm.undoLast() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                .keyboardShortcut("z", modifiers: [.command, .shift])
        }
        .padding(8)
    }

    private func tf(_ binding: Binding<String>, placeholder: String = "") -> some View {
        TextField(placeholder, text: binding)
            .textFieldStyle(.roundedBorder)
    }

    // --- Vues de sections ---
    // (tout le reste de tes vues replaceView, removeView, addView, dateView,
    //  numberingView, caseView, extView, folderView, specialView, destinationView,
    //  filtersView, fileTable) RESTENT COMME TU LES AS.
}

// MARK: - Fenêtre : Gestionnaire de Presets
struct PresetsManagerView: View {
    @EnvironmentObject var store: RenamePresetStore
    @State private var selection: RenamePreset.ID?

    private func bindingForSelection() -> Binding<RenamePreset>? {
        guard let id = selection,
              let idx = store.items.firstIndex(where: { $0.id == id }) else { return nil }
        return $store.items[idx]
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(store.categories, id: \.self) { cat in
                    Section(cat) {
                        ForEach(store.presets(in: cat)) { item in
                            Text(item.name).tag(item.id)
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItemGroup {
                    Menu {
                        ForEach(store.categories, id: \.self) { cat in
                            Button("Nouveau dans « \(cat) »") { store.add(category: cat) }
                        }
                        Divider()
                        Button("Nouveau dossier de catégorie…") {
                            let alert = NSAlert()
                            alert.messageText = "Nouvelle catégorie"
                            alert.informativeText = "Saisissez un nom de catégorie"
                            let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
                            alert.accessoryView = tf
                            alert.addButton(withTitle: "OK")
                            alert.addButton(withTitle: "Annuler")
                            if alert.runModal() == .alertFirstButtonReturn {
                                store.items.append(RenamePreset(name: "Nouveau preset", category: tf.stringValue))
                                store.save()
                            }
                        }
                    } label: {
                        Label("Nouveau", systemImage: "plus")
                    }

                    Button {
                        if let sel = selection,
                           let item = store.items.first(where: { $0.id == sel }) {
                            store.duplicate(item)
                        }
                    } label: { Label("Dupliquer", systemImage: "square.on.square") }
                        .disabled(selection == nil)

                    Button {
                        if let sel = selection,
                           let item = store.items.first(where: { $0.id == sel }) {
                            store.delete(item)
                        }
                    } label: { Label("Supprimer", systemImage: "trash") }
                        .disabled(selection == nil)

                    Divider()

                    Button { store.importSingle() } label: {
                        Label("Importer…", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        if let sel = selection,
                           let item = store.items.first(where: { $0.id == sel }) {
                            store.exportSingle(item)
                        }
                    } label: {
                        Label("Exporter…", systemImage: "square.and.arrow.up")
                    }
                        .disabled(selection == nil)
                }
            }
        } detail: {
            if let binding = bindingForSelection() {
                PresetEditorView(preset: binding) {
                    store.presetToApply = binding.wrappedValue
                }
                .padding(12)
                .navigationTitle(binding.wrappedValue.name)
            } else {
                ContentUnavailableView(
                    "Aucun preset sélectionné",
                    systemImage: "text.badge.plus",
                    description: Text("Choisissez ou créez un preset dans la liste.")
                )
            }
        }
        .onDisappear { store.save() }
    }
}

// MARK: - Éditeur de preset
struct PresetEditorView: View {
    @Binding var preset: RenamePreset
    var applyAction: () -> Void

    var body: some View {
        // <<< garde ici exactement le code que tu avais, inchangé >>>
        // (il est long, donc je ne le recopie pas pour éviter une erreur)
        VStack { /* ... ton contenu existant ... */ }
    }
}

// MARK: - Debounce preview
struct PreviewRecomputeModifier: ViewModifier {
    @ObservedObject var vm: RenameVM

    func body(content: Content) -> some View {
        content
            .onReceive(
                vm.previewTrigger
                    .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            ) { _ in
                vm.recomputePreviewAsync()
            }
    }
}

// MARK: - Sous-vues des règles et du tableau
extension ContentView {

    // Helper pour les champs Int? de type "from / to"
    private func optionalIntField(
        _ title: String,
        value: Binding<Int?>,
        width: CGFloat = 60
    ) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .frame(width: 80, alignment: .trailing)
            TextField(
                "",
                text: Binding(
                    get: { value.wrappedValue.map(String.init) ?? "" },
                    set: { newValue in
                        let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                        value.wrappedValue = trimmed.isEmpty ? nil : Int(trimmed)
                    }
                )
            )
            .frame(width: width)
        }
    }

    // MARK: (1) Remplacer
    private var replaceView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Activer cette étape", isOn: $vm.replace.enabled)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Rechercher")
                    .frame(width: 90, alignment: .trailing)
                tf($vm.replace.find, placeholder: "Texte ou expression régulière")
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Remplacer par")
                    .frame(width: 90, alignment: .trailing)
                tf($vm.replace.replace, placeholder: "Texte de remplacement")
            }

            HStack {
                Toggle("Regex", isOn: $vm.replace.regex)
                Toggle("Sensible à la casse", isOn: $vm.replace.caseSensitive)
            }
            .toggleStyle(.checkbox)
        }
    }

    // MARK: (2) Retirer
    private var removeView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Activer cette étape", isOn: $vm.remove.enabled)

            HStack(spacing: 12) {
                optionalIntField("De", value: Binding(
                    get: { vm.remove.from },
                    set: { vm.remove.from = $0 }
                ))
                optionalIntField("À", value: Binding(
                    get: { vm.remove.to },
                    set: { vm.remove.to = $0 }
                ))
                Text("(index 1 = 1er caractère)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Toggle("Réduire les espaces multiples",
                       isOn: $vm.remove.collapseSpaces)
                Toggle("Supprimer espaces début/fin",
                       isOn: $vm.remove.trimWhitespace)
            }
            .toggleStyle(.checkbox)
        }
    }

    // MARK: (3) Ajouter
    private var addView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Activer cette étape", isOn: $vm.add.enabled)

            HStack {
                Toggle("Préfixe", isOn: $vm.add.usePrefix)
                tf($vm.add.prefix, placeholder: "Texte du préfixe")
            }

            HStack {
                Toggle("Suffixe", isOn: $vm.add.useSuffix)
                tf($vm.add.suffix, placeholder: "Texte du suffixe")
            }

            HStack(spacing: 8) {
                Text("Insérer")
                    .frame(width: 80, alignment: .trailing)
                tf($vm.add.insertText, placeholder: "Texte à insérer")
                Spacer()
                Stepper(value: $vm.add.insertIndex, in: 1...9999) {
                    Text("Position \(vm.add.insertIndex)")
                }
                .frame(width: 170, alignment: .trailing)
            }
        }
    }

    // MARK: (4) Date auto
    private var dateView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Activer cette étape", isOn: $vm.date.enabled)

            HStack {
                Text("Format")
                    .frame(width: 80, alignment: .trailing)
                tf($vm.date.format, placeholder: "yyyy-MM-dd")
            }

            HStack {
                Toggle("Préfixe", isOn: $vm.date.usePrefix)
                Toggle("À la position", isOn: $vm.date.useAtPosition)
                Stepper(value: $vm.date.atIndex, in: 1...9999) {
                    Text("\(vm.date.atIndex)")
                }
                Toggle("Suffixe", isOn: $vm.date.useSuffix)
            }
            .toggleStyle(.checkbox)

            Text("Utilise les formats DateFormatter (ex : yyyy-MM-dd, yyyyMMdd_HHmm).")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: (5) Numérotation
    private var numberingView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Activer la numérotation", isOn: $vm.num.enabled)

            HStack {
                Toggle("Numéro en préfixe", isOn: $vm.num.asPrefix)
                Toggle("Seulement pour la sélection", isOn: $vm.num.onlySelection)
            }
            .toggleStyle(.checkbox)

            HStack(spacing: 14) {
                Stepper(value: $vm.num.start, in: -9999...9999) {
                    Text("Départ : \(vm.num.start)")
                }
                Stepper(value: $vm.num.step, in: 1...999) {
                    Text("Pas : \(vm.num.step)")
                }
                Stepper(value: $vm.num.pad, in: 1...6) {
                    Text("Chiffres : \(vm.num.pad)")
                }
            }

            HStack {
                Text("Séparateur")
                    .frame(width: 80, alignment: .trailing)
                tf($vm.num.sep, placeholder: "Ex. \" - \"")
            }

            HStack {
                Text("Patron")
                    .frame(width: 80, alignment: .trailing)
                tf($vm.num.pattern, placeholder: "Ex. 04.## (facultatif)")
            }

            Text("Patron vide → simple remplissage (001, 002…).")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: (6) Casse
    private var caseView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Activer le changement de casse", isOn: $vm.casing.enabled)

            Picker("Style", selection: $vm.casing.style) {
                ForEach(CaseStyle.allCases) { style in
                    Text(style.rawValue).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)
        }
    }

    // MARK: (7) Extension
    private var extView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Activer le changement d’extension", isOn: $vm.ext.enabled)

            HStack {
                Text("Nouvelle extension")
                    .frame(width: 130, alignment: .trailing)
                tf($vm.ext.newExt, placeholder: "laisser vide pour conserver")
                    .frame(maxWidth: 200)
            }

            Picker("Casse de l’extension", selection: $vm.ext.caseChange) {
                ForEach(ExtCase.allCases) { style in
                    Text(style.rawValue).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)
        }
    }

    // MARK: (8) Dossier parent
    private var folderView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Activer", isOn: $vm.folder.enabled)

            Toggle("Ajouter le nom du dossier parent en préfixe",
                   isOn: $vm.folder.addParentAsPrefix)
                .toggleStyle(.checkbox)

            HStack {
                Text("Séparateur")
                    .frame(width: 90, alignment: .trailing)
                tf($vm.folder.sep)
                    .frame(maxWidth: 160)
            }

            if let dir = vm.directoryURL {
                Text("Dossier courant : \(dir.lastPathComponent)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: (9) Spécial
    private var specialView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Activer", isOn: $vm.special.enabled)

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Normaliser Unicode", isOn: $vm.special.normalizeUnicode)
                Toggle("Supprimer les accents", isOn: $vm.special.stripDiacritics)
                Toggle("Remplacer \" - \" par « – »", isOn: $vm.special.dashToEnDash)
                Toggle("Remplacer les espaces par des _",
                       isOn: $vm.special.spacesToUnderscore)
            }
            .toggleStyle(.checkbox)
        }
    }

    // MARK: Destination
    private var destinationView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Activer destination différente", isOn: $vm.destination.enabled)

            HStack {
                if let url = vm.destination.url {
                    Text(url.path)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("Utiliser le même dossier que la source.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Choisir…") {
                    vm.pickDestination()
                }
            }
            .disabled(!vm.destination.enabled)

            Toggle("Copier au lieu de déplacer",
                   isOn: $vm.destination.copyInsteadOfMove)
                .toggleStyle(.checkbox)
                .disabled(!vm.destination.enabled)
        }
    }

    // MARK: Filtres
    private var filtersView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("Inclure sous-dossiers (récursif)",
                       isOn: $vm.filters.recursive)
                Toggle("Inclure fichiers cachés",
                       isOn: $vm.filters.includeHidden)
            }
            .toggleStyle(.checkbox)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Inclure (regex)")
                    .frame(width: 110, alignment: .trailing)
                tf($vm.filters.includeRegex, placeholder: "laisser vide pour tout")
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Exclure (regex)")
                    .frame(width: 110, alignment: .trailing)
                tf($vm.filters.excludeRegex, placeholder: "laisser vide pour rien")
            }

            Text("Les filtres s’appliquent aux noms d’origine avant renommage.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Tableau des fichiers
    private var fileTable: some View {
        Table(vm.entries, selection: $vm.selection) {
            TableColumn("Nom original", value: \.originalName)
            TableColumn("Nouveau nom") { entry in
                Text(vm.preview[entry.id] ?? "—")
            }
            TableColumn("Statut") { entry in
                let status = vm.statuses[entry.id] ?? ""
                Text(status)
                    .foregroundStyle(status.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
            }
        }
        .contextMenu(forSelectionType: FileEntry.ID.self) { ids in
            if !ids.isEmpty {
                Button("Afficher dans le Finder") {
                    vm.revealInFinder(ids: ids)
                }
            }
        }
    }
}

