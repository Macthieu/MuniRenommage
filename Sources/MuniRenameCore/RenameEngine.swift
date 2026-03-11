import Foundation

public struct RenamePreviewEntry: Sendable {
    public var outputName: String
    public var status: String

    public init(outputName: String, status: String) {
        self.outputName = outputName
        self.status = status
    }
}

public struct RenamePreview: Sendable {
    public var byID: [UUID: RenamePreviewEntry]

    public init(byID: [UUID: RenamePreviewEntry]) {
        self.byID = byID
    }
}

public struct PlannedRename: Sendable {
    public var id: UUID
    public var sourceURL: URL
    public var destinationURL: URL
    public var outputName: String

    public init(id: UUID, sourceURL: URL, destinationURL: URL, outputName: String) {
        self.id = id
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        self.outputName = outputName
    }
}

public struct RenamePlan: Sendable {
    public var operations: [PlannedRename]
    public var statuses: [UUID: String]

    public init(operations: [PlannedRename], statuses: [UUID: String]) {
        self.operations = operations
        self.statuses = statuses
    }
}

public enum RenameUndoAction: Sendable {
    case move(from: URL, to: URL)
    case delete(url: URL)
}

public struct RenameExecutionReport: Sendable {
    public var statuses: [UUID: String]
    public var undoActions: [RenameUndoAction]
    public var errorCount: Int
    public var renamedCount: Int

    public init(statuses: [UUID: String], undoActions: [RenameUndoAction], errorCount: Int, renamedCount: Int) {
        self.statuses = statuses
        self.undoActions = undoActions
        self.errorCount = errorCount
        self.renamedCount = renamedCount
    }
}

public enum RenameEngine {
    public static func computePreview(
        items: [RenameItem],
        directoryURL: URL?,
        selection: Set<UUID>,
        previewOnlySelection: Bool,
        rules: RenameRules,
        now: Date = Date()
    ) -> RenamePreview {
        let selectionList: [RenameItem] = selection.isEmpty ? [] : items.filter { selection.contains($0.id) }

        let previewScope: [RenameItem]
        if previewOnlySelection, !selectionList.isEmpty {
            previewScope = selectionList
        } else {
            previewScope = items
        }

        let numberingTargets: [RenameItem]
        if rules.numbering.onlySelection, !selectionList.isEmpty {
            numberingTargets = selectionList
        } else {
            numberingTargets = previewScope
        }

        let orderIndex: [UUID: Int] = Dictionary(
            uniqueKeysWithValues: numberingTargets.enumerated().map { ($0.element.id, $0.offset) }
        )

        let targetIDs = Set(previewScope.map(\.id))
        var outputNames: [UUID: String] = [:]
        var statuses: [UUID: String] = [:]

        for item in items {
            guard targetIDs.contains(item.id) else {
                outputNames[item.id] = item.originalName
                statuses[item.id] = ""
                continue
            }

            let output = buildOutputName(
                for: item,
                numberingIndex: orderIndex[item.id],
                directoryURL: directoryURL,
                rules: rules,
                now: now
            )

            outputNames[item.id] = output
            statuses[item.id] = ""
        }

        let plan = buildPlan(items: items, selection: selection, outputNames: outputNames, rules: rules)
        for (id, status) in plan.statuses {
            statuses[id] = status
        }

        let result = Dictionary(uniqueKeysWithValues: items.map { item in
            let entry = RenamePreviewEntry(
                outputName: outputNames[item.id] ?? item.originalName,
                status: statuses[item.id] ?? ""
            )
            return (item.id, entry)
        })

        return RenamePreview(byID: result)
    }

    public static func buildPlan(
        items: [RenameItem],
        selection: Set<UUID>,
        outputNames: [UUID: String],
        rules: RenameRules
    ) -> RenamePlan {
        let targets: [RenameItem] = selection.isEmpty ? items : items.filter { selection.contains($0.id) }
        let sourceURLs = Set(targets.map { $0.url.standardizedFileURL })

        var statuses: [UUID: String] = [:]
        var operations: [PlannedRename] = []
        var collisions: [URL: [UUID]] = [:]

        for item in targets {
            let outputName = outputNames[item.id] ?? item.originalName

            if let validation = validateFilename(outputName) {
                statuses[item.id] = validation
                continue
            }

            let destinationDir: URL =
                rules.destination.enabled
                    ? (rules.destination.url ?? item.url.deletingLastPathComponent())
                    : item.url.deletingLastPathComponent()
            let destinationURL = destinationDir.appendingPathComponent(outputName).standardizedFileURL
            let sourceURL = item.url.standardizedFileURL

            if !rules.destination.copyInsteadOfMove && sourceURL == destinationURL {
                statuses[item.id] = ""
                continue
            }

            collisions[destinationURL, default: []].append(item.id)
            operations.append(
                PlannedRename(
                    id: item.id,
                    sourceURL: sourceURL,
                    destinationURL: destinationURL,
                    outputName: outputName
                )
            )
        }

        for (destination, ids) in collisions where ids.count > 1 {
            for id in ids {
                statuses[id] = "Collision interne: \(destination.lastPathComponent)"
            }
        }

        for op in operations {
            if !(statuses[op.id] ?? "").isEmpty { continue }

            guard FileManager.default.fileExists(atPath: op.destinationURL.path) else { continue }

            if rules.destination.copyInsteadOfMove {
                statuses[op.id] = "Existant: \(op.destinationURL.lastPathComponent)"
                continue
            }

            if !sourceURLs.contains(op.destinationURL.standardizedFileURL) {
                statuses[op.id] = "Existant: \(op.destinationURL.lastPathComponent)"
            }
        }

        return RenamePlan(operations: operations, statuses: statuses)
    }

    public static func apply(plan: RenamePlan, rules: RenameRules) -> RenameExecutionReport {
        var statuses = plan.statuses
        var undoActions: [RenameUndoAction] = []
        var errorCount = statuses.values.filter { !$0.isEmpty }.count
        var renamedCount = 0

        var operations = plan.operations
        operations.sort {
            $0.sourceURL.path.localizedStandardCompare($1.sourceURL.path) == .orderedAscending
        }

        if rules.destination.enabled && rules.destination.copyInsteadOfMove {
            for op in operations {
                if !(statuses[op.id] ?? "").isEmpty { continue }

                do {
                    try FileManager.default.copyItem(at: op.sourceURL, to: op.destinationURL)
                    undoActions.append(.delete(url: op.destinationURL))
                    renamedCount += 1
                } catch {
                    statuses[op.id] = "Erreur copie: \(error.localizedDescription)"
                    errorCount += 1
                }
            }

            return RenameExecutionReport(
                statuses: statuses,
                undoActions: undoActions,
                errorCount: errorCount,
                renamedCount: renamedCount
            )
        }

        struct TempMove {
            let op: PlannedRename
            let tempURL: URL
        }

        var prepared: [TempMove] = []

        for op in operations {
            if !(statuses[op.id] ?? "").isEmpty { continue }

            let tempName = ".munirename-tmp-\(UUID().uuidString)-\(op.sourceURL.lastPathComponent)"
            let tempURL = op.sourceURL.deletingLastPathComponent().appendingPathComponent(tempName)

            do {
                try FileManager.default.moveItem(at: op.sourceURL, to: tempURL)
                prepared.append(TempMove(op: op, tempURL: tempURL))
            } catch {
                statuses[op.id] = "Erreur preparation: \(error.localizedDescription)"
                errorCount += 1
            }
        }

        for item in prepared {
            let op = item.op
            if !(statuses[op.id] ?? "").isEmpty {
                rollbackTempIfNeeded(tempURL: item.tempURL, sourceURL: op.sourceURL)
                continue
            }

            do {
                try FileManager.default.moveItem(at: item.tempURL, to: op.destinationURL)
                undoActions.append(.move(from: op.destinationURL, to: op.sourceURL))
                renamedCount += 1
            } catch {
                statuses[op.id] = "Erreur deplacement: \(error.localizedDescription)"
                errorCount += 1
                rollbackTempIfNeeded(tempURL: item.tempURL, sourceURL: op.sourceURL)
            }
        }

        return RenameExecutionReport(
            statuses: statuses,
            undoActions: undoActions,
            errorCount: errorCount,
            renamedCount: renamedCount
        )
    }

    private static func rollbackTempIfNeeded(tempURL: URL, sourceURL: URL) {
        guard FileManager.default.fileExists(atPath: tempURL.path) else { return }
        _ = try? FileManager.default.moveItem(at: tempURL, to: sourceURL)
    }

    private static func buildOutputName(
        for item: RenameItem,
        numberingIndex: Int?,
        directoryURL: URL?,
        rules: RenameRules,
        now: Date
    ) -> String {
        var base = item.baseName

        if rules.replace.enabled, !rules.replace.find.isEmpty {
            if rules.replace.regex,
               let regex = try? NSRegularExpression(
                    pattern: rules.replace.find,
                    options: rules.replace.caseSensitive ? [] : [.caseInsensitive]
               ) {
                base = regex.stringByReplacingMatches(
                    in: base,
                    range: NSRange(base.startIndex..<base.endIndex, in: base),
                    withTemplate: rules.replace.replace
                )
            } else if !rules.replace.regex {
                base = base.replacingOccurrences(
                    of: rules.replace.find,
                    with: rules.replace.replace,
                    options: rules.replace.caseSensitive ? [] : [.caseInsensitive]
                )
            }
        }

        if rules.remove.enabled {
            if let from = rules.remove.from,
               let to = rules.remove.to,
               from > 0,
               to >= from,
               from <= base.count {
                let start = base.index(base.startIndex, offsetBy: from - 1)
                let end = base.index(base.startIndex, offsetBy: min(to, base.count) - 1)
                base.removeSubrange(start...end)
            }

            if rules.remove.trimWhitespace {
                base = base.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            if rules.remove.collapseSpaces {
                base = base.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            }
        }

        if rules.add.enabled {
            if rules.add.usePrefix { base = rules.add.prefix + base }
            if rules.add.useSuffix { base += rules.add.suffix }
            if !rules.add.insertText.isEmpty {
                let idx0 = max(0, min(rules.add.insertIndex - 1, base.count))
                base.insert(contentsOf: rules.add.insertText, at: base.index(base.startIndex, offsetBy: idx0))
            }
        }

        if rules.date.enabled {
            let formatter = DateFormatter()
            formatter.locale = .current
            formatter.dateFormat = rules.date.format
            let stamp = formatter.string(from: now)

            if rules.date.usePrefix { base = stamp + " " + base }
            if rules.date.useAtPosition {
                let idx0 = max(0, min(rules.date.atIndex - 1, base.count))
                base.insert(contentsOf: stamp, at: base.index(base.startIndex, offsetBy: idx0))
            }
            if rules.date.useSuffix { base = base + " " + stamp }
        }

        if rules.numbering.enabled, let numberingIndex {
            let n = rules.numbering.start + numberingIndex * rules.numbering.step
            let numberToken = formatNumber(n, using: rules.numbering)
            base = rules.numbering.asPrefix
                ? numberToken + rules.numbering.separator + base
                : base + rules.numbering.separator + numberToken
        }

        if rules.casing.enabled {
            switch rules.casing.style {
            case .unchanged:
                break
            case .lower:
                base = base.lowercased()
            case .upper:
                base = base.uppercased()
            case .title:
                base = base.localizedCapitalized
            }
        }

        if rules.folder.enabled, let parent = directoryURL?.lastPathComponent {
            let prefix = parent + rules.folder.separator
            base = rules.folder.addParentAsPrefix ? prefix + base : base + rules.folder.separator + parent
        }

        if rules.special.enabled {
            if rules.special.normalizeUnicode {
                base = base.precomposedStringWithCanonicalMapping
            }
            if rules.special.stripDiacritics {
                base = base.folding(options: .diacriticInsensitive, locale: .current)
            }
            if rules.special.dashToEnDash {
                base = base.replacingOccurrences(of: " - ", with: " – ")
            }
            if rules.special.spacesToUnderscore {
                base = base.replacingOccurrences(of: " ", with: "_")
            }
        }

        var ext = item.ext
        if rules.ext.enabled {
            if !rules.ext.newExtension.isEmpty {
                ext = rules.ext.newExtension.replacingOccurrences(of: ".", with: "")
            }

            switch rules.ext.caseStyle {
            case .unchanged:
                break
            case .lower:
                ext = ext.lowercased()
            case .upper:
                ext = ext.uppercased()
            }
        }

        return ext.isEmpty ? base : "\(base).\(ext)"
    }

    private static func formatNumber(_ value: Int, using rules: NumberingRule) -> String {
        let pattern = rules.pattern.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !pattern.isEmpty else {
            return String(format: "%0*d", rules.pad, value)
        }

        if let range = pattern.range(of: #"#{1,}"#, options: .regularExpression) {
            let count = pattern[range].count
            let formatted = String(format: "%0*d", count, value)
            var output = pattern
            output.replaceSubrange(range, with: formatted)
            return output
        }

        let formatted = String(format: "%0*d", rules.pad, value)
        return pattern + formatted
    }

    private static func validateFilename(_ name: String) -> String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Nom vide"
        }

        if name == "." || name == ".." {
            return "Nom invalide: \(name)"
        }

        if name.contains("/") || name.contains(":") {
            return "Caractere interdit (/ ou :)"
        }

        if name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            return "Caractere de controle interdit"
        }

        if name.utf8.count > 255 {
            return "Nom trop long (>255 octets)"
        }

        return nil
    }
}
