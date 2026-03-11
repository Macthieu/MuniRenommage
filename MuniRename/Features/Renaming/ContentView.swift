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
    static let currentFormatVersion = 1

    var id = UUID()
    var formatVersion: Int = RenamePreset.currentFormatVersion
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

    private enum CodingKeys: String, CodingKey {
        case id
        case formatVersion
        case name
        case category
        case replace
        case remove
        case add
        case date
        case num
        case casing
        case ext
        case folder
        case special
        case filters
        case destination
    }

    init(
        id: UUID = UUID(),
        formatVersion: Int = RenamePreset.currentFormatVersion,
        name: String = "Sans titre",
        category: String = "Divers",
        replace: ReplaceSec = .init(),
        remove: RemoveSec = .init(),
        add: AddSec = .init(),
        date: DateSec = .init(),
        num: NumberingSec = .init(),
        casing: CaseSec = .init(),
        ext: ExtSec = .init(),
        folder: FolderNameSec = .init(),
        special: SpecialSec = .init(),
        filters: FiltersSec = .init(),
        destination: DestinationSec = .init()
    ) {
        self.id = id
        self.formatVersion = formatVersion
        self.name = name
        self.category = category
        self.replace = replace
        self.remove = remove
        self.add = add
        self.date = date
        self.num = num
        self.casing = casing
        self.ext = ext
        self.folder = folder
        self.special = special
        self.filters = filters
        self.destination = destination
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        formatVersion = try container.decodeIfPresent(Int.self, forKey: .formatVersion) ?? RenamePreset.currentFormatVersion
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Sans titre"
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? "Divers"
        replace = try container.decodeIfPresent(ReplaceSec.self, forKey: .replace) ?? .init()
        remove = try container.decodeIfPresent(RemoveSec.self, forKey: .remove) ?? .init()
        add = try container.decodeIfPresent(AddSec.self, forKey: .add) ?? .init()
        date = try container.decodeIfPresent(DateSec.self, forKey: .date) ?? .init()
        num = try container.decodeIfPresent(NumberingSec.self, forKey: .num) ?? .init()
        casing = try container.decodeIfPresent(CaseSec.self, forKey: .casing) ?? .init()
        ext = try container.decodeIfPresent(ExtSec.self, forKey: .ext) ?? .init()
        folder = try container.decodeIfPresent(FolderNameSec.self, forKey: .folder) ?? .init()
        special = try container.decodeIfPresent(SpecialSec.self, forKey: .special) ?? .init()
        filters = try container.decodeIfPresent(FiltersSec.self, forKey: .filters) ?? .init()
        destination = try container.decodeIfPresent(DestinationSec.self, forKey: .destination) ?? .init()
    }
}

// MARK: - ViewModel du renommeur
final class RenameVM: ObservableObject {
    struct RunSummary {
        let targetCount: Int
        let blockedCount: Int
        let unchangedCount: Int
        let plannedCount: Int
    }

    struct RunReport {
        let date: Date
        let targetCount: Int
        let blockedCount: Int
        let unchangedCount: Int
        let plannedCount: Int
        let renamedCount: Int
        let errorCount: Int
        let issues: [String]
    }

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
    @Published var lastRunReport: RunReport?

    private var undoJournal: [RenameUndoAction] = []
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

        let entries = self.entries
        let rules = self.currentRules
        let dirURL = self.directoryURL
        let selection = self.selection
        let previewOnlySelection = self.previewOnlySelection

        worker.async { [weak self] in
            guard let self else { return }
            let result = RenameEngine.computePreview(
                entries: entries,
                directoryURL: dirURL,
                selection: selection,
                previewOnlySelection: previewOnlySelection,
                rules: rules
            )

            DispatchQueue.main.async {
                guard self.previewJob == jobId else { return }
                self.preview = result.names
                self.statuses = result.statuses
            }
        }
    }

    // Appliquer / Undo
    func apply() {
        guard directoryURL != nil else { return }
        let targets = targetEntries()
        let summary = runSummary(for: targets)

        let result = RenameEngine.apply(
            entries: entries,
            selection: selection,
            outputNames: preview,
            rules: currentRules
        )

        let issues: [String] = targets.compactMap { entry in
            let status = result.statuses[entry.id] ?? ""
            guard !status.isEmpty else { return nil }
            let output = preview[entry.id] ?? entry.originalName
            return "\(entry.originalName) -> \(output): \(status)"
        }

        statuses = result.statuses
        undoJournal = result.undoActions
        lastRunReport = RunReport(
            date: Date(),
            targetCount: summary.targetCount,
            blockedCount: summary.blockedCount,
            unchangedCount: summary.unchangedCount,
            plannedCount: summary.plannedCount,
            renamedCount: result.renamedCount,
            errorCount: result.errorCount,
            issues: issues
        )
        loadEntries()

        if result.errorCount > 0 {
            NSSound.beep()
        }
    }

    func undoLast() {
        guard !undoJournal.isEmpty else { return }
        var failures = 0
        for op in undoJournal {
            do {
                switch op {
                case let .move(from, to):
                    try FileManager.default.moveItem(at: from, to: to)
                case let .delete(url):
                    try FileManager.default.removeItem(at: url)
                }
            } catch { failures += 1 }
        }
        undoJournal.removeAll()
        loadEntries()
        if failures > 0 { NSSound.beep() }
    }

    func runSummary(for entriesScope: [FileEntry]? = nil) -> RunSummary {
        let targets = entriesScope ?? targetEntries()

        var blocked = 0
        var unchanged = 0

        for entry in targets {
            let status = statuses[entry.id] ?? ""
            if !status.isEmpty {
                blocked += 1
                continue
            }

            let output = preview[entry.id] ?? entry.originalName
            if output == entry.originalName {
                unchanged += 1
            }
        }

        let planned = max(0, targets.count - blocked - unchanged)
        return RunSummary(
            targetCount: targets.count,
            blockedCount: blocked,
            unchangedCount: unchanged,
            plannedCount: planned
        )
    }

    var applySummaryText: String {
        let s = runSummary()
        return """
        Cibles: \(s.targetCount)
        Planifiées: \(s.plannedCount)
        Bloquées (erreurs): \(s.blockedCount)
        Inchangées: \(s.unchangedCount)
        """
    }

    var simulationReportText: String {
        let targets = targetEntries()
        let s = runSummary(for: targets)

        var lines: [String] = []
        lines.append("Simulation MuniRename")
        lines.append("Cibles: \(s.targetCount)")
        lines.append("Planifiées: \(s.plannedCount)")
        lines.append("Bloquées: \(s.blockedCount)")
        lines.append("Inchangées: \(s.unchangedCount)")
        lines.append("")
        lines.append("Détail:")

        for entry in targets {
            let output = preview[entry.id] ?? entry.originalName
            let status = statuses[entry.id] ?? ""
            let suffix = status.isEmpty ? "" : " [\(status)]"
            lines.append("- \(entry.originalName) -> \(output)\(suffix)")
        }

        return lines.joined(separator: "\n")
    }

    private func targetEntries() -> [FileEntry] {
        selection.isEmpty ? entries : entries.filter { selection.contains($0.id) }
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
            $destination.map { _ in () }.eraseToAnyPublisher(),
            $previewOnlySelection.map { _ in () }.eraseToAnyPublisher(),
            $selection.map { _ in () }.eraseToAnyPublisher()
        ]
        return Publishers.MergeMany(pubs).eraseToAnyPublisher()
    }

    var currentRules: RenameRules {
        RenameRules(
            replace: replace,
            remove: remove,
            add: add,
            date: date,
            num: num,
            casing: casing,
            ext: ext,
            folder: folder,
            special: special,
            destination: destination
        )
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
    @State private var showApplyConfirmation = false
    @State private var showSimulation = false
    @State private var showRunReport = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            mainLayout
            if let report = vm.lastRunReport {
                Divider()
                reportBanner(report)
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        // Appliquer un preset choisi dans la fenêtre “Presets”
        .onReceive(presetStore.$presetToApply.compactMap { $0 }) { p in
            vm.apply(preset: p)
            presetStore.presetToApply = nil
        }
        .alert("Confirmer l'application", isPresented: $showApplyConfirmation) {
            Button("Annuler", role: .cancel) {}
            Button("Appliquer", role: .destructive) {
                vm.apply()
                showRunReport = vm.lastRunReport != nil
            }
        } message: {
            Text(vm.applySummaryText)
        }
        .sheet(isPresented: $showSimulation) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Simulation")
                    .font(.headline)
                ScrollView {
                    Text(vm.simulationReportText)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Spacer()
                    Button("Fermer") { showSimulation = false }
                }
            }
            .padding(16)
            .frame(minWidth: 720, minHeight: 480)
        }
        .sheet(isPresented: $showRunReport) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Rapport d'exécution")
                    .font(.headline)
                ScrollView {
                    Text(runReportText)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Spacer()
                    Button("Fermer") { showRunReport = false }
                }
            }
            .padding(16)
            .frame(minWidth: 720, minHeight: 480)
        }
    }

    @ViewBuilder
    private func reportBanner(_ report: RenameVM.RunReport) -> some View {
        let hasErrors = report.errorCount > 0
        HStack(spacing: 12) {
            Image(systemName: hasErrors ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(hasErrors ? .orange : .green)
            Text(hasErrors
                ? "Dernière opération: \(report.renamedCount) succès, \(report.errorCount) erreur(s)."
                : "Dernière opération réussie: \(report.renamedCount) fichier(s) traité(s)."
            )
            .font(.callout)
            Spacer()
            Button("Voir le rapport") { showRunReport = true }
                .buttonStyle(.link)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(hasErrors ? Color.orange.opacity(0.12) : Color.green.opacity(0.12))
    }

    private var runReportText: String {
        guard let report = vm.lastRunReport else {
            return "Aucun rapport disponible."
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium

        var lines: [String] = []
        lines.append("Date: \(formatter.string(from: report.date))")
        lines.append("Cibles: \(report.targetCount)")
        lines.append("Planifiées: \(report.plannedCount)")
        lines.append("Bloquées avant exécution: \(report.blockedCount)")
        lines.append("Inchangées: \(report.unchangedCount)")
        lines.append("Traitées avec succès: \(report.renamedCount)")
        lines.append("Erreurs: \(report.errorCount)")
        lines.append("")
        lines.append("Détail erreurs/blocages:")

        if report.issues.isEmpty {
            lines.append("- Aucun")
        } else {
            for issue in report.issues {
                lines.append("- \(issue)")
            }
        }

        return lines.joined(separator: "\n")
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
            Button("Importer preset…") { presetStore.importSingle() }
            Button("Sauver preset courant…") {
                var p = vm.currentPreset
                p.formatVersion = RenamePreset.currentFormatVersion
                p.name = "Preset depuis la fenêtre"
                presetStore.items.append(p)
                presetStore.save()
            }

            Divider().frame(height: 18)
            Button { showSimulation = true } label: { Label("Simulation", systemImage: "doc.text.magnifyingglass") }
            Button { showRunReport = vm.lastRunReport != nil } label: { Label("Dernier rapport", systemImage: "list.bullet.clipboard") }
                .disabled(vm.lastRunReport == nil)
            Button { showApplyConfirmation = true } label: { Label("Appliquer", systemImage: "hammer") }
                .keyboardShortcut(.return)
            Button { vm.undoLast() } label: { Label("Annuler", systemImage: "arrow.uturn.backward") }
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
    @State private var showResetConfirmation = false

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
                                store.add(category: tf.stringValue)
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

                    Divider()

                    Button {
                        showResetConfirmation = true
                    } label: {
                        Label("Réinitialiser défauts", systemImage: "arrow.counterclockwise")
                    }
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
                if #available(macOS 14.0, *) {
                    ContentUnavailableView(
                        "Aucun preset sélectionné",
                        systemImage: "text.badge.plus",
                        description: Text("Choisissez ou créez un preset dans la liste.")
                    )
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "text.badge.plus")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                        Text("Aucun preset sélectionné")
                            .font(.headline)
                        Text("Choisissez ou créez un preset dans la liste.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .alert("Réinitialiser les presets ?", isPresented: $showResetConfirmation) {
            Button("Annuler", role: .cancel) {}
            Button("Réinitialiser", role: .destructive) {
                store.resetToDefaults()
                selection = store.items.first?.id
            }
        } message: {
            Text("Cette action remplace tous les presets actuels par les presets par défaut.")
        }
        .alert("Erreur presets", isPresented: Binding(
            get: { store.lastErrorMessage != nil },
            set: { if !$0 { store.lastErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.lastErrorMessage ?? "")
        }
        .alert("Information", isPresented: Binding(
            get: { store.lastInfoMessage != nil },
            set: { if !$0 { store.lastInfoMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.lastInfoMessage ?? "")
        }
        .onDisappear { store.save() }
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
        .overlay {
            if vm.directoryURL == nil {
                VStack(spacing: 8) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("Aucun dossier sélectionné")
                        .font(.headline)
                    Text("Commencez par cliquer sur « Choisir un dossier ».")
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else if vm.entries.isEmpty && !vm.isLoading {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("Aucun fichier trouvé")
                        .font(.headline)
                    Text("Vérifiez les filtres ou choisissez un autre dossier.")
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
        }
    }
}
