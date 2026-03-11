import Foundation
import MuniRenameCore

enum CLIError: Error, CustomStringConvertible {
    case usage(String)
    case runtime(String)

    var description: String {
        switch self {
        case .usage(let message):
            return message
        case .runtime(let message):
            return message
        }
    }
}

struct CLIConfiguration {
    enum Command: String {
        case preview
        case apply
        case validatePreset = "validate-preset"
    }

    var command: Command
    var directory: URL?
    var presetFile: URL
    var recursive: Bool
    var includeHidden: Bool
    var dryRun: Bool
}

func printUsage() {
    let usage = """
    MuniRename CLI (manuel, sans Xcode)

    Usage:
      munirename-cli preview --preset <preset.json> --directory <folder> [--recursive] [--include-hidden]
      munirename-cli apply --preset <preset.json> --directory <folder> [--recursive] [--include-hidden] [--dry-run]
      munirename-cli validate-preset --preset <preset.json>

    Notes:
      - Outil de renommage en lot manuel.
      - --dry-run affiche le plan sans modifier les fichiers.
    """
    print(usage)
}

func parseArguments(_ args: [String]) throws -> CLIConfiguration {
    guard let commandArg = args.dropFirst().first,
          let command = CLIConfiguration.Command(rawValue: commandArg) else {
        throw CLIError.usage("Commande manquante ou invalide. Utilise: preview | apply | validate-preset")
    }

    var presetPath: String?
    var directoryPath: String?
    var recursive = false
    var includeHidden = false
    var dryRun = false

    var idx = 2
    while idx < args.count {
        let token = args[idx]
        switch token {
        case "--preset":
            idx += 1
            guard idx < args.count else { throw CLIError.usage("--preset attend un chemin") }
            presetPath = args[idx]
        case "--directory":
            idx += 1
            guard idx < args.count else { throw CLIError.usage("--directory attend un chemin") }
            directoryPath = args[idx]
        case "--recursive":
            recursive = true
        case "--include-hidden":
            includeHidden = true
        case "--dry-run":
            dryRun = true
        case "--help", "-h":
            throw CLIError.usage("")
        default:
            throw CLIError.usage("Argument inconnu: \(token)")
        }
        idx += 1
    }

    guard let presetPath else {
        throw CLIError.usage("--preset est obligatoire")
    }

    if command != .validatePreset, directoryPath == nil {
        throw CLIError.usage("--directory est obligatoire pour preview/apply")
    }

    return CLIConfiguration(
        command: command,
        directory: directoryPath.map { URL(fileURLWithPath: $0) },
        presetFile: URL(fileURLWithPath: presetPath),
        recursive: recursive,
        includeHidden: includeHidden,
        dryRun: dryRun
    )
}

func loadPreset(from fileURL: URL) throws -> RenamePreset {
    let data = try Data(contentsOf: fileURL)
    return try PresetCodec.decodePreset(from: data)
}

func run() throws {
    let args = CommandLine.arguments

    if args.count == 1 || args.contains("--help") || args.contains("-h") {
        printUsage()
        return
    }

    let config = try parseArguments(args)
    let preset = try loadPreset(from: config.presetFile)
    let issues = PresetValidator.validate(preset)

    if config.command == .validatePreset {
        if issues.isEmpty {
            print("Preset valide: \(preset.name)")
            return
        }

        print("Preset invalide (\(issues.count) probleme(s)):")
        for issue in issues {
            print("- [\(issue.field)] \(issue.message)")
        }
        throw CLIError.runtime("Validation preset echouee")
    }

    if !issues.isEmpty {
        print("Preset invalide (\(issues.count) probleme(s)):")
        for issue in issues {
            print("- [\(issue.field)] \(issue.message)")
        }
        throw CLIError.runtime("Corrige le preset avant execution")
    }

    guard let directory = config.directory else {
        throw CLIError.runtime("Dossier source manquant")
    }

    var effectiveRules = preset.rules
    if config.recursive { effectiveRules.filters.recursive = true }
    if config.includeHidden { effectiveRules.filters.includeHidden = true }

    let items = try FileInventoryService.collectFiles(directory: directory, filters: effectiveRules.filters)
    if items.isEmpty {
        print("Aucun fichier trouve")
        return
    }

    let preview = RenameEngine.computePreview(
        items: items,
        directoryURL: directory,
        selection: [],
        previewOnlySelection: false,
        rules: effectiveRules
    )

    print("Preset: \(preset.name)")
    print("Fichiers analyses: \(items.count)")

    for item in items {
        let entry = preview.byID[item.id]!
        let marker = entry.status.isEmpty ? "OK" : "WARN"
        let statusSuffix = entry.status.isEmpty ? "" : " [\(entry.status)]"
        print("\(marker) | \(item.originalName) -> \(entry.outputName)\(statusSuffix)")
    }

    if config.command == .preview || config.dryRun {
        let warningCount = preview.byID.values.filter { !$0.status.isEmpty }.count
        print("\nPreview termine. Warnings: \(warningCount)")
        return
    }

    let outputNames = Dictionary(uniqueKeysWithValues: preview.byID.map { ($0.key, $0.value.outputName) })
    let plan = RenameEngine.buildPlan(items: items, selection: [], outputNames: outputNames, rules: effectiveRules)
    let report = RenameEngine.apply(plan: plan, rules: effectiveRules)

    print("\nExecution terminee: \(report.renamedCount) fichier(s) traite(s), \(report.errorCount) erreur(s)")
    if report.errorCount > 0 {
        throw CLIError.runtime("Certaines operations ont echoue")
    }
}

do {
    try run()
} catch let error as CLIError {
    if case .usage(let message) = error, message.isEmpty {
        printUsage()
        exit(0)
    }

    if case .usage = error {
        print(error.description)
        printUsage()
        exit(2)
    }

    fputs("Erreur: \(error.description)\n", stderr)
    exit(1)
} catch {
    fputs("Erreur inattendue: \(error.localizedDescription)\n", stderr)
    exit(1)
}
