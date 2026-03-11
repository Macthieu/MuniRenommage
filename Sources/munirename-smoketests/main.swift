import Foundation
import MuniRenameCore

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

if runner.failures.isEmpty {
    print("\nTous les smoke-tests sont PASS")
    exit(0)
}

print("\nSmoke-tests en echec: \(runner.failures.count)")
for failure in runner.failures {
    print(failure)
}
exit(1)
