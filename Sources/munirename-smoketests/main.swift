import Foundation
import MuniRenameCore
import MuniRenameInterop
import OrchivisteKitContracts

struct SmokeTestRunner {
    private(set) var failures: [String] = []

    mutating func run(_ name: String, _ body: () throws -> Void) {
        do {
            try body()
            print("PASS | \(name)")
        } catch {
            let message = "FAIL | \(name) | \(error.localizedDescription)"
            failures.append(message)
            print(message)
        }
    }
}

@inline(__always)
func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw NSError(domain: "SmokeTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

func makeTempDir(prefix: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(prefix + UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func makePresetFile(in directory: URL, prefix: String = "PFX_") throws -> URL {
    var preset = RenamePreset(name: "Canonical", category: "QA")
    preset.rules.add = AddRule(enabled: true, usePrefix: true, prefix: prefix, useSuffix: false)

    let data = try PresetCodec.encodePresetDocument(preset)
    let presetURL = directory.appendingPathComponent("preset.json")
    try data.write(to: presetURL)
    return presetURL
}

func makeNeutralPresetFile(in directory: URL) throws -> URL {
    let preset = RenamePreset(name: "Canonical", category: "QA")
    let data = try PresetCodec.encodePresetDocument(preset)
    let presetURL = directory.appendingPathComponent("preset-neutral.json")
    try data.write(to: presetURL)
    return presetURL
}

func makeMuniReglesBundleFile(
    in directory: URL,
    ruleID: String = "rule-default",
    template: String = "{class_code}-{subject}"
) throws -> URL {
    let bundleURL = directory.appendingPathComponent("muniregles-bundle.json")
    let payload = """
    {
      "manifest": {
        "bundle_version": "1.0",
        "module_version": "0.1.0",
        "generated_at": "2026-03-19T00:00:00Z",
        "source_checksums": {
          "naming_and_routing_rules": "abc123"
        }
      },
      "classification_plan": {
        "taxonomy_id": "muni-demo",
        "version": "2026.1",
        "entries": [
          {
            "code": "ADM-100",
            "label": "Administration generale",
            "path": "administration/generale"
          }
        ]
      },
      "naming_and_routing_rules": {
        "version": "2026.1",
        "naming_rules": [
          {
            "id": "\(ruleID)",
            "label": "Regle de nommage de demo",
            "template": "\(template)"
          }
        ],
        "routing_rules": [
          {
            "id": "routing-default",
            "class_code": "ADM-100",
            "destination_template": "administration/{class_code}"
          }
        ]
      },
      "renaming_guide": {
        "title": "Guide",
        "conventions": ["Exemple"],
        "examples": [{"input": "doc", "output": "ADM-100_2026-03-19_doc"}]
      }
    }
    """

    try payload.write(to: bundleURL, atomically: true, encoding: .utf8)
    return bundleURL
}

func makeDocumentMetadataFile(
    in directory: URL,
    entries: [(sourceFile: String, documentType: String, documentSubject: String, documentDate: String)]
) throws -> URL {
    let metadataURL = directory.appendingPathComponent("document-metadata.json")
    let documents = entries.map { entry in
        """
        {
          "source_file": "\(entry.sourceFile)",
          "document_type": "\(entry.documentType)",
          "document_subject": "\(entry.documentSubject)",
          "document_date": "\(entry.documentDate)"
        }
        """
    }.joined(separator: ",\n")

    let payload = """
    {
      "schema_version": "1.0",
      "documents": [
    \(documents)
      ]
    }
    """

    try payload.write(to: metadataURL, atomically: true, encoding: .utf8)
    return metadataURL
}

var runner = SmokeTestRunner()

runner.run("Conserve l'extension") {
    let item = RenameItem(url: URL(fileURLWithPath: "/tmp/report.pdf"))
    var rules = RenameRules()
    rules.add = AddRule(enabled: true, usePrefix: true, prefix: "FINAL_", useSuffix: false)

    let preview = RenameEngine.computePreview(
        items: [item],
        directoryURL: URL(fileURLWithPath: "/tmp"),
        selection: [],
        previewOnlySelection: false,
        rules: rules,
        now: Date(timeIntervalSince1970: 0)
    )

    try expect(preview.byID[item.id]?.outputName == "FINAL_report.pdf", "Mauvais nom genere")
    try expect(preview.byID[item.id]?.status == "", "Le statut devrait etre vide")
}

runner.run("Detecte les collisions internes") {
    let item1 = RenameItem(url: URL(fileURLWithPath: "/tmp/a.txt"))
    let item2 = RenameItem(url: URL(fileURLWithPath: "/tmp/b.txt"))

    let outputNames: [UUID: String] = [
        item1.id: "same.txt",
        item2.id: "same.txt"
    ]

    let plan = RenameEngine.buildPlan(
        items: [item1, item2],
        selection: [],
        outputNames: outputNames,
        rules: RenameRules()
    )

    try expect(plan.statuses[item1.id]?.contains("Collision interne") == true, "Collision non detectee (item1)")
    try expect(plan.statuses[item2.id]?.contains("Collision interne") == true, "Collision non detectee (item2)")
}

runner.run("Detecte les noms vides") {
    let item = RenameItem(url: URL(fileURLWithPath: "/tmp/file"))
    var rules = RenameRules()
    rules.remove = RemoveRule(enabled: true, from: 1, to: 999, collapseSpaces: false, trimWhitespace: true)

    let preview = RenameEngine.computePreview(
        items: [item],
        directoryURL: URL(fileURLWithPath: "/tmp"),
        selection: [],
        previewOnlySelection: false,
        rules: rules
    )

    try expect(preview.byID[item.id]?.status.contains("Nom vide") == true, "Nom vide non detecte")
}

runner.run("Detecte destination existante") {
    let tempDir = try makeTempDir(prefix: "munirename-exists-")
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let src1 = tempDir.appendingPathComponent("first.txt")
    let src2 = tempDir.appendingPathComponent("second.txt")
    try "1".data(using: .utf8)?.write(to: src1)
    try "2".data(using: .utf8)?.write(to: src2)

    let item = RenameItem(url: src1)
    let outputNames: [UUID: String] = [item.id: src2.lastPathComponent]

    let plan = RenameEngine.buildPlan(items: [item], selection: [], outputNames: outputNames, rules: RenameRules())
    try expect(plan.statuses[item.id]?.contains("Existant") == true, "Collision avec existant non detectee")
}

runner.run("Supporte le swap A<->B") {
    let tempDir = try makeTempDir(prefix: "munirename-swap-")
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let aURL = tempDir.appendingPathComponent("a.txt")
    let bURL = tempDir.appendingPathComponent("b.txt")

    try "A".data(using: .utf8)?.write(to: aURL)
    try "B".data(using: .utf8)?.write(to: bURL)

    let itemA = RenameItem(url: aURL)
    let itemB = RenameItem(url: bURL)

    let outputNames: [UUID: String] = [
        itemA.id: "b.txt",
        itemB.id: "a.txt"
    ]

    let rules = RenameRules()
    let plan = RenameEngine.buildPlan(items: [itemA, itemB], selection: [], outputNames: outputNames, rules: rules)
    let report = RenameEngine.apply(plan: plan, rules: rules)

    try expect(report.errorCount == 0, "Le swap devrait passer sans erreur")
    try expect(report.renamedCount == 2, "Le swap devrait traiter 2 fichiers")

    let aData = try Data(contentsOf: aURL)
    let bData = try Data(contentsOf: bURL)
    try expect(String(data: aData, encoding: .utf8) == "B", "a.txt devrait contenir B")
    try expect(String(data: bData, encoding: .utf8) == "A", "b.txt devrait contenir A")
}

runner.run("Codec preset wrapper + brut") {
    let preset = RenamePreset(name: "Test", category: "QA")
    let wrapped = try PresetCodec.encodePresetDocument(preset)
    let decodedWrapped = try PresetCodec.decodePreset(from: wrapped)
    try expect(decodedWrapped.name == "Test", "Decode wrapper invalide")

    let encoder = JSONEncoder()
    let raw = try encoder.encode(preset)
    let decodedRaw = try PresetCodec.decodePreset(from: raw)
    try expect(decodedRaw.category == "QA", "Decode brut invalide")
}

runner.run("Validation preset") {
    var preset = RenamePreset(name: "", category: "")
    preset.rules.numbering.step = 0
    preset.rules.destination.enabled = true

    let issues = PresetValidator.validate(preset)
    try expect(issues.contains(where: { $0.field == "name" }), "Nom vide non detecte")
    try expect(issues.contains(where: { $0.field == "rules.numbering.step" }), "Step invalide non detecte")
    try expect(issues.contains(where: { $0.field == "rules.destination.url" }), "Destination invalide non detectee")
}

runner.run("Canonical apply exige confirmation explicite") {
    let tempDir = try makeTempDir(prefix: "munirename-canonical-apply-")
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let sourceFile = tempDir.appendingPathComponent("doc.txt")
    try "DOC".data(using: .utf8)?.write(to: sourceFile)
    let presetURL = try makePresetFile(in: tempDir, prefix: "REN_")

    let request = ToolRequest(
        requestID: "req-apply-confirm",
        tool: "MuniRenommage",
        action: "apply",
        inputArtifacts: [],
        parameters: [
            "preset_path": .string(presetURL.path),
            "directory_path": .string(tempDir.path),
            "dry_run": .bool(false),
            "confirm_apply": .bool(false)
        ]
    )

    let result = CanonicalRunAdapter.execute(request: request)

    try expect(result.status == .failed, "Le mode canonique doit refuser apply sans confirmation")
    try expect(
        result.errors.contains(where: { $0.code == "EXPLICIT_CONFIRMATION_REQUIRED" }),
        "Le code d'erreur attendu n'est pas present"
    )
    try expect(FileManager.default.fileExists(atPath: sourceFile.path), "Le fichier source ne doit pas etre modifie")
    try expect(
        !FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("REN_doc.txt").path),
        "Aucun renommage ne doit se produire sans confirmation explicite"
    )
}

runner.run("Canonical preview retourne un resultat canonique") {
    let tempDir = try makeTempDir(prefix: "munirename-canonical-preview-")
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let sourceFile = tempDir.appendingPathComponent("sample.txt")
    try "TXT".data(using: .utf8)?.write(to: sourceFile)
    let presetURL = try makePresetFile(in: tempDir, prefix: "PRE_")

    let request = ToolRequest(
        requestID: "req-preview",
        tool: "MuniRenommage",
        action: "preview",
        inputArtifacts: [],
        parameters: [
            "preset_path": .string(presetURL.path),
            "directory_path": .string(tempDir.path)
        ]
    )

    let result = CanonicalRunAdapter.execute(request: request)

    try expect(result.status == .succeeded, "Preview canonique devrait etre en succeeded")
    try expect(result.errors.isEmpty, "Preview canonique ne doit pas produire d'erreurs")
    try expect(result.metadata["action"] == .string("preview"), "Metadata action invalide")
}

runner.run("Canonical preview sans bundle expose fallback_local") {
    let tempDir = try makeTempDir(prefix: "munirename-canonical-no-bundle-")
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let sourceFile = tempDir.appendingPathComponent("sample.txt")
    try "TXT".data(using: .utf8)?.write(to: sourceFile)
    let presetURL = try makePresetFile(in: tempDir, prefix: "PRE_")

    let request = ToolRequest(
        requestID: "req-trace-no-bundle",
        tool: "MuniRenommage",
        action: "preview",
        inputArtifacts: [],
        parameters: [
            "preset_path": .string(presetURL.path),
            "directory_path": .string(tempDir.path)
        ]
    )

    let result = CanonicalRunAdapter.execute(request: request)
    try expect(result.status == .succeeded, "Preview canonique devrait etre en succeeded")
    try expect(result.metadata["regles_source"] == .string("fallback_local"), "Source regles attendue: fallback_local")
}

runner.run("Canonical preview bundle valide sans regles_apply_rule reste en fallback") {
    let tempDir = try makeTempDir(prefix: "munirename-canonical-valid-bundle-")
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let sourceFile = tempDir.appendingPathComponent("sample.txt")
    try "TXT".data(using: .utf8)?.write(to: sourceFile)
    let presetURL = try makePresetFile(in: tempDir, prefix: "PRE_")
    let bundleURL = try makeMuniReglesBundleFile(in: tempDir, ruleID: "rule-qa")

    let request = ToolRequest(
        requestID: "req-trace-valid-bundle",
        tool: "MuniRenommage",
        action: "preview",
        inputArtifacts: [],
        parameters: [
            "preset_path": .string(presetURL.path),
            "directory_path": .string(tempDir.path),
            "regles_bundle_path": .string(bundleURL.path),
            "regles_naming_rule_id": .string("rule-qa")
        ]
    )

    let result = CanonicalRunAdapter.execute(request: request)
    try expect(result.status == .succeeded, "Preview canonique devrait etre en succeeded")
    try expect(result.metadata["regles_source"] == .string("fallback_local"), "Source regles attendue: fallback_local")
    try expect(result.metadata["regles_bundle_version"] == .string("1.0"), "Version de bundle attendue")
    try expect(result.metadata["regles_module_version"] == .string("0.1.0"), "Version module attendue")
    try expect(result.metadata["regles_rule_id"] == .string("rule-qa"), "Rule ID de trace attendu")
    try expect(
        result.metadata["regles_fallback_reason"] == .string("regles_apply_rule_disabled"),
        "Raison de fallback attendue"
    )
}

runner.run("Canonical preview applique une regle MuniRegles supportee") {
    let tempDir = try makeTempDir(prefix: "munirename-canonical-supported-template-")
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let sourceFile = tempDir.appendingPathComponent("sample.txt")
    try "TXT".data(using: .utf8)?.write(to: sourceFile)
    let presetURL = try makePresetFile(in: tempDir, prefix: "PRE_")
    let bundleURL = try makeMuniReglesBundleFile(
        in: tempDir,
        ruleID: "rule-supported",
        template: "{class_code}-{subject}"
    )

    let request = ToolRequest(
        requestID: "req-trace-supported-template",
        tool: "MuniRenommage",
        action: "preview",
        inputArtifacts: [],
        parameters: [
            "preset_path": .string(presetURL.path),
            "directory_path": .string(tempDir.path),
            "regles_bundle_path": .string(bundleURL.path),
            "regles_naming_rule_id": .string("rule-supported"),
            "regles_apply_rule": .bool(true),
            "regles_class_code": .string("ADM-100")
        ]
    )

    let result = CanonicalRunAdapter.execute(request: request)
    try expect(result.status == .succeeded, "Preview canonique devrait etre en succeeded")
    try expect(result.metadata["regles_source"] == .string("muniregles_bundle"), "Source regles attendue: muniregles_bundle")
    try expect(result.metadata["regles_bundle_version"] == .string("1.0"), "Version de bundle attendue")
    try expect(result.metadata["regles_module_version"] == .string("0.1.0"), "Version module attendue")
    try expect(result.metadata["regles_rule_id"] == .string("rule-supported"), "Rule ID de trace attendu")
    try expect(result.metadata["regles_fallback_reason"] == nil, "Aucune raison de fallback attendue")
}

runner.run("Canonical preview applique une regle MuniRegles supportee avec seq") {
    let tempDir = try makeTempDir(prefix: "munirename-canonical-supported-template-seq-")
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let sourceFile = tempDir.appendingPathComponent("sample.txt")
    try "TXT".data(using: .utf8)?.write(to: sourceFile)
    let presetURL = try makePresetFile(in: tempDir, prefix: "PRE_")
    let bundleURL = try makeMuniReglesBundleFile(
        in: tempDir,
        ruleID: "rule-supported-seq",
        template: "{class_code}-{subject}-{seq}"
    )

    let request = ToolRequest(
        requestID: "req-trace-supported-template-seq",
        tool: "MuniRenommage",
        action: "preview",
        inputArtifacts: [],
        parameters: [
            "preset_path": .string(presetURL.path),
            "directory_path": .string(tempDir.path),
            "regles_bundle_path": .string(bundleURL.path),
            "regles_naming_rule_id": .string("rule-supported-seq"),
            "regles_apply_rule": .bool(true),
            "regles_class_code": .string("ADM-100")
        ]
    )

    let result = CanonicalRunAdapter.execute(request: request)
    try expect(result.status == .succeeded, "Preview canonique devrait etre en succeeded")
    try expect(result.metadata["regles_source"] == .string("muniregles_bundle"), "Source regles attendue: muniregles_bundle")
    try expect(result.metadata["regles_fallback_reason"] == nil, "Aucune raison de fallback attendue")
}

runner.run("Canonical preview template documentaire sans metadata conserve fallback") {
    let tempDir = try makeTempDir(prefix: "munirename-canonical-document-template-no-metadata-")
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let sourceFile = tempDir.appendingPathComponent("doc1.pdf")
    try "PDF".data(using: .utf8)?.write(to: sourceFile)
    let presetURL = try makeNeutralPresetFile(in: tempDir)
    let bundleURL = try makeMuniReglesBundleFile(
        in: tempDir,
        ruleID: "rule-document-template",
        template: "{document_type} – {document_subject} – {document_date}"
    )

    let request = ToolRequest(
        requestID: "req-trace-document-template-no-metadata",
        tool: "MuniRenommage",
        action: "preview",
        inputArtifacts: [],
        parameters: [
            "preset_path": .string(presetURL.path),
            "directory_path": .string(tempDir.path),
            "regles_bundle_path": .string(bundleURL.path),
            "regles_naming_rule_id": .string("rule-document-template"),
            "regles_apply_rule": .bool(true)
        ]
    )

    let result = CanonicalRunAdapter.execute(request: request)
    try expect(result.status == .succeeded, "Preview canonique devrait rester en succeeded")
    try expect(result.metadata["regles_source"] == .string("fallback_local"), "Source regles attendue: fallback_local")
    try expect(
        result.metadata["regles_fallback_reason"] == .string("document_metadata_not_provided"),
        "Raison de fallback attendue"
    )
}

runner.run("Canonical apply template documentaire produit les 2 noms exacts") {
    let tempDir = try makeTempDir(prefix: "munirename-canonical-document-template-exact-")
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let sourceFile1 = tempDir.appendingPathComponent("doc1.pdf")
    let sourceFile2 = tempDir.appendingPathComponent("doc2.pdf")
    try "PDF1".data(using: .utf8)?.write(to: sourceFile1)
    try "PDF2".data(using: .utf8)?.write(to: sourceFile2)

    let presetURL = try makeNeutralPresetFile(in: tempDir)
    let bundleURL = try makeMuniReglesBundleFile(
        in: tempDir,
        ruleID: "rule-document-template",
        template: "{document_type} – {document_subject} – {document_date}"
    )
    let metadataURL = try makeDocumentMetadataFile(
        in: tempDir,
        entries: [
            (
                sourceFile: "doc1.pdf",
                documentType: "Résolution NO 2025-54",
                documentSubject: "Extension du délai de construction pour Plantation d’arbres M.M. inc.",
                documentDate: "2025-02-03"
            ),
            (
                sourceFile: "doc2.pdf",
                documentType: "Ordre du jour",
                documentSubject: "Séance du conseil",
                documentDate: "2025-03-17"
            )
        ]
    )

    let request = ToolRequest(
        requestID: "req-document-template-exact",
        tool: "MuniRenommage",
        action: "apply",
        inputArtifacts: [],
        parameters: [
            "preset_path": .string(presetURL.path),
            "directory_path": .string(tempDir.path),
            "regles_bundle_path": .string(bundleURL.path),
            "regles_naming_rule_id": .string("rule-document-template"),
            "regles_apply_rule": .bool(true),
            "document_metadata_path": .string(metadataURL.path),
            "dry_run": .bool(false),
            "confirm_apply": .bool(true)
        ]
    )

    let result = CanonicalRunAdapter.execute(request: request)
    try expect(result.status == .succeeded, "Apply canonique devrait reussir")
    try expect(result.metadata["regles_source"] == .string("muniregles_bundle"), "Source regles attendue: muniregles_bundle")
    try expect(result.metadata["regles_rule_id"] == .string("rule-document-template"), "Rule ID attendu")

    let expectedName1 = "Résolution NO 2025-54 – Extension du délai de construction pour Plantation d’arbres M.M. inc. – 2025-02-03.pdf"
    let expectedName2 = "Ordre du jour – Séance du conseil – 2025-03-17.pdf"

    try expect(
        FileManager.default.fileExists(atPath: tempDir.appendingPathComponent(expectedName1).path),
        "Le premier nom attendu n'a pas ete produit"
    )
    try expect(
        FileManager.default.fileExists(atPath: tempDir.appendingPathComponent(expectedName2).path),
        "Le second nom attendu n'a pas ete produit"
    )
    try expect(!FileManager.default.fileExists(atPath: sourceFile1.path), "doc1.pdf ne doit plus exister")
    try expect(!FileManager.default.fileExists(atPath: sourceFile2.path), "doc2.pdf ne doit plus exister")
}

runner.run("Canonical preview avec template non supporte conserve fallback") {
    let tempDir = try makeTempDir(prefix: "munirename-canonical-unsupported-template-")
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let sourceFile = tempDir.appendingPathComponent("sample.txt")
    try "TXT".data(using: .utf8)?.write(to: sourceFile)
    let presetURL = try makePresetFile(in: tempDir, prefix: "PRE_")
    let bundleURL = try makeMuniReglesBundleFile(
        in: tempDir,
        ruleID: "rule-unsupported",
        template: "{class_code}-{date}-{subject}"
    )

    let request = ToolRequest(
        requestID: "req-trace-unsupported-template",
        tool: "MuniRenommage",
        action: "preview",
        inputArtifacts: [],
        parameters: [
            "preset_path": .string(presetURL.path),
            "directory_path": .string(tempDir.path),
            "regles_bundle_path": .string(bundleURL.path),
            "regles_naming_rule_id": .string("rule-unsupported"),
            "regles_apply_rule": .bool(true),
            "regles_class_code": .string("ADM-100")
        ]
    )

    let result = CanonicalRunAdapter.execute(request: request)
    try expect(result.status == .succeeded, "Preview canonique devrait rester en succeeded")
    try expect(result.metadata["regles_source"] == .string("fallback_local"), "Source regles attendue: fallback_local")
    try expect(result.metadata["regles_rule_id"] == .string("rule-unsupported"), "Rule ID fourni doit etre trace")
    try expect(
        result.metadata["regles_fallback_reason"] == .string("template_not_supported"),
        "Raison de fallback attendue"
    )
}

runner.run("Canonical preview bundle illisible conserve fallback avec raison") {
    let tempDir = try makeTempDir(prefix: "munirename-canonical-invalid-bundle-")
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let sourceFile = tempDir.appendingPathComponent("sample.txt")
    try "TXT".data(using: .utf8)?.write(to: sourceFile)
    let presetURL = try makePresetFile(in: tempDir, prefix: "PRE_")

    let missingBundlePath = tempDir.appendingPathComponent("missing-bundle.json").path
    let request = ToolRequest(
        requestID: "req-trace-invalid-bundle",
        tool: "MuniRenommage",
        action: "preview",
        inputArtifacts: [],
        parameters: [
            "preset_path": .string(presetURL.path),
            "directory_path": .string(tempDir.path),
            "regles_bundle_path": .string(missingBundlePath),
            "regles_naming_rule_id": .string("rule-missing")
        ]
    )

    let result = CanonicalRunAdapter.execute(request: request)
    try expect(result.status == .succeeded, "Preview canonique devrait rester en succeeded")
    try expect(result.metadata["regles_source"] == .string("fallback_local"), "Source regles attendue: fallback_local")
    try expect(result.metadata["regles_rule_id"] == .string("rule-missing"), "Rule ID fourni doit etre trace")
    try expect(
        result.metadata["regles_fallback_reason"] == .string("bundle_unreadable_or_invalid"),
        "Raison de fallback attendue"
    )
}

if runner.failures.isEmpty {
    print("\nTous les smoke-tests sont PASS")
    exit(0)
}

print("\nSmoke-tests en echec: \(runner.failures.count)")
for failure in runner.failures {
    print(failure)
}
exit(1)
