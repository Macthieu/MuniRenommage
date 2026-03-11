import Foundation

struct RenameRules {
    var replace: ReplaceSec
    var remove: RemoveSec
    var add: AddSec
    var date: DateSec
    var num: NumberingSec
    var casing: CaseSec
    var ext: ExtSec
    var folder: FolderNameSec
    var special: SpecialSec
    var destination: DestinationSec
}

struct RenamePreviewResult {
    var names: [UUID: String]
    var statuses: [UUID: String]
}

struct RenameExecutionResult {
    var statuses: [UUID: String]
    var undoActions: [RenameUndoAction]
    var errorCount: Int
    var renamedCount: Int
}

enum RenameUndoAction {
    case move(from: URL, to: URL)
    case delete(url: URL)
}

private struct PlannedRename {
    let id: UUID
    let sourceURL: URL
    let destinationURL: URL
    let outputName: String
}

private struct RenamePlan {
    var operations: [PlannedRename]
    var statuses: [UUID: String]
}

enum RenameEngine {
    static func computePreview(
        entries: [FileEntry],
        directoryURL: URL?,
        selection: Set<UUID>,
        previewOnlySelection: Bool,
        rules: RenameRules
    ) -> RenamePreviewResult {
        let selectionList: [FileEntry] =
            selection.isEmpty ? [] : entries.filter { selection.contains($0.id) }

        let previewScope: [FileEntry]
        if previewOnlySelection, !selectionList.isEmpty {
            previewScope = selectionList
        } else {
            previewScope = entries
        }

        let numberingTargets: [FileEntry]
        if rules.num.onlySelection, !selectionList.isEmpty {
            numberingTargets = selectionList
        } else {
            numberingTargets = previewScope
        }

        let orderIndex: [UUID: Int] = Dictionary(
            uniqueKeysWithValues: numberingTargets.enumerated().map { ($0.element.id, $0.offset) }
        )

        let previewTargetIDs = Set(previewScope.map(\.id))
        var names: [UUID: String] = [:]
        var statuses: [UUID: String] = [:]

        for entry in entries {
            guard previewTargetIDs.contains(entry.id) else {
                names[entry.id] = entry.originalName
                statuses[entry.id] = ""
                continue
            }

            let builtName = buildOutputName(
                for: entry,
                numberingIndex: orderIndex[entry.id],
                directoryURL: directoryURL,
                rules: rules
            )

            names[entry.id] = builtName
            statuses[entry.id] = ""
        }

        let plan = buildPlan(
            entries: entries,
            selection: selection,
            outputNames: names,
            rules: rules
        )

        for (id, status) in plan.statuses {
            statuses[id] = status
        }

        return RenamePreviewResult(names: names, statuses: statuses)
    }

    static func apply(
        entries: [FileEntry],
        selection: Set<UUID>,
        outputNames: [UUID: String],
        rules: RenameRules
    ) -> RenameExecutionResult {
        var plan = buildPlan(entries: entries, selection: selection, outputNames: outputNames, rules: rules)
        var statuses = plan.statuses
        var undoActions: [RenameUndoAction] = []
        var errorCount = statuses.values.filter { !$0.isEmpty }.count
        var renamedCount = 0

        if plan.operations.isEmpty {
            return RenameExecutionResult(
                statuses: statuses,
                undoActions: [],
                errorCount: errorCount,
                renamedCount: 0
            )
        }

        plan.operations.sort { lhs, rhs in
            lhs.sourceURL.path.localizedStandardCompare(rhs.sourceURL.path) == .orderedAscending
        }

        if rules.destination.enabled && rules.destination.copyInsteadOfMove {
            for op in plan.operations {
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

            return RenameExecutionResult(
                statuses: statuses,
                undoActions: undoActions,
                errorCount: errorCount,
                renamedCount: renamedCount
            )
        }

        struct TempMove {
            let operation: PlannedRename
            let tempURL: URL
        }

        var prepared: [TempMove] = []

        for op in plan.operations {
            if !(statuses[op.id] ?? "").isEmpty { continue }

            let tmpName = ".munirename-tmp-\(UUID().uuidString)-\(op.sourceURL.lastPathComponent)"
            let tmpURL = op.sourceURL.deletingLastPathComponent().appendingPathComponent(tmpName)

            do {
                try FileManager.default.moveItem(at: op.sourceURL, to: tmpURL)
                prepared.append(TempMove(operation: op, tempURL: tmpURL))
            } catch {
                statuses[op.id] = "Erreur preparation: \(error.localizedDescription)"
                errorCount += 1
            }
        }

        for item in prepared {
            let op = item.operation
            if !(statuses[op.id] ?? "").isEmpty {
                if FileManager.default.fileExists(atPath: item.tempURL.path) {
                    _ = try? FileManager.default.moveItem(at: item.tempURL, to: op.sourceURL)
                }
                continue
            }

            do {
                try FileManager.default.moveItem(at: item.tempURL, to: op.destinationURL)
                undoActions.append(.move(from: op.destinationURL, to: op.sourceURL))
                renamedCount += 1
            } catch {
                statuses[op.id] = "Erreur deplacement: \(error.localizedDescription)"
                errorCount += 1

                if FileManager.default.fileExists(atPath: item.tempURL.path) {
                    _ = try? FileManager.default.moveItem(at: item.tempURL, to: op.sourceURL)
                }
            }
        }

        return RenameExecutionResult(
            statuses: statuses,
            undoActions: undoActions,
            errorCount: errorCount,
            renamedCount: renamedCount
        )
    }

    private static func buildPlan(
        entries: [FileEntry],
        selection: Set<UUID>,
        outputNames: [UUID: String],
        rules: RenameRules
    ) -> RenamePlan {
        let targets: [FileEntry] = selection.isEmpty ? entries : entries.filter { selection.contains($0.id) }
        let targetSourceURLs = Set(targets.map { $0.url.standardizedFileURL })

        var statuses: [UUID: String] = [:]
        var operations: [PlannedRename] = []
        var collisions: [URL: [UUID]] = [:]

        for entry in targets {
            let outputName = outputNames[entry.id] ?? entry.originalName

            if let validationError = validateFilename(outputName) {
                statuses[entry.id] = validationError
                continue
            }

            let destinationDir: URL =
                rules.destination.enabled
                    ? (rules.destination.url ?? entry.url.deletingLastPathComponent())
                    : entry.url.deletingLastPathComponent()
            let destinationURL = destinationDir.appendingPathComponent(outputName).standardizedFileURL
            let sourceURL = entry.url.standardizedFileURL

            if !rules.destination.copyInsteadOfMove && sourceURL == destinationURL {
                statuses[entry.id] = ""
                continue
            }

            collisions[destinationURL, default: []].append(entry.id)
            operations.append(
                PlannedRename(
                    id: entry.id,
                    sourceURL: sourceURL,
                    destinationURL: destinationURL,
                    outputName: outputName
                )
            )
        }

        for (destinationURL, ids) in collisions where ids.count > 1 {
            for id in ids {
                statuses[id] = "Collision interne: \(destinationURL.lastPathComponent)"
            }
        }

        for op in operations {
            if !(statuses[op.id] ?? "").isEmpty { continue }

            let destinationExists = FileManager.default.fileExists(atPath: op.destinationURL.path)
            if !destinationExists { continue }

            if rules.destination.copyInsteadOfMove {
                statuses[op.id] = "Existant: \(op.destinationURL.lastPathComponent)"
                continue
            }

            if !targetSourceURLs.contains(op.destinationURL.standardizedFileURL) {
                statuses[op.id] = "Existant: \(op.destinationURL.lastPathComponent)"
            }
        }

        return RenamePlan(operations: operations, statuses: statuses)
    }

    private static func buildOutputName(
        for entry: FileEntry,
        numberingIndex: Int?,
        directoryURL: URL?,
        rules: RenameRules
    ) -> String {
        var base = entry.baseName

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
            let stamp = formatter.string(from: Date())

            if rules.date.usePrefix { base = stamp + " " + base }
            if rules.date.useAtPosition {
                let idx0 = max(0, min(rules.date.atIndex - 1, base.count))
                base.insert(contentsOf: stamp, at: base.index(base.startIndex, offsetBy: idx0))
            }
            if rules.date.useSuffix { base = base + " " + stamp }
        }

        if rules.num.enabled, let numberingIndex {
            let n = rules.num.start + numberingIndex * rules.num.step
            let numberToken = formatNumber(n, using: rules.num)
            base = rules.num.asPrefix ? numberToken + rules.num.sep + base : base + rules.num.sep + numberToken
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

        if rules.folder.enabled, let parentName = directoryURL?.lastPathComponent {
            let insertion = parentName + rules.folder.sep
            base = rules.folder.addParentAsPrefix ? insertion + base : base + rules.folder.sep + parentName
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

        var extensionPart = entry.ext
        if rules.ext.enabled {
            if !rules.ext.newExt.isEmpty {
                extensionPart = rules.ext.newExt.replacingOccurrences(of: ".", with: "")
            }

            switch rules.ext.caseChange {
            case .none:
                break
            case .lower:
                extensionPart = extensionPart.lowercased()
            case .upper:
                extensionPart = extensionPart.uppercased()
            }
        }

        return extensionPart.isEmpty ? base : "\(base).\(extensionPart)"
    }

    private static func formatNumber(_ value: Int, using rules: NumberingSec) -> String {
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
