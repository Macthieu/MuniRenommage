import SwiftUI
import AppKit

private enum PresetEditorTab: String, CaseIterable, Identifiable {
    case summary = "Résumé"
    case naming = "Noms"
    case numbering = "Numérotation"
    case files = "Fichiers"

    var id: String { rawValue }
}

struct PresetEditorView: View {
    @EnvironmentObject var store: RenamePresetStore
    @Binding var preset: RenamePreset
    var applyAction: () -> Void

    @State private var tab: PresetEditorTab = .summary

    private var validationIssues: [PresetValidationIssue] {
        store.validationIssues(for: preset)
    }

    private var activeRuleNames: [String] {
        var names: [String] = []
        if preset.replace.enabled { names.append("Remplacer") }
        if preset.remove.enabled { names.append("Retirer") }
        if preset.add.enabled { names.append("Ajouter") }
        if preset.date.enabled { names.append("Date") }
        if preset.num.enabled { names.append("Numérotation") }
        if preset.casing.enabled { names.append("Casse") }
        if preset.ext.enabled { names.append("Extension") }
        if preset.folder.enabled { names.append("Dossier parent") }
        if preset.special.enabled { names.append("Spécial") }
        if preset.destination.enabled { names.append("Destination") }
        if preset.filters.recursive || preset.filters.includeHidden || !preset.filters.includeRegex.isEmpty || !preset.filters.excludeRegex.isEmpty {
            names.append("Filtres")
        }
        return names
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            identityHeader

            if !validationIssues.isEmpty {
                validationPanel
            }

            Picker("Section", selection: $tab) {
                ForEach(PresetEditorTab.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch tab {
                    case .summary:
                        summaryTab
                    case .naming:
                        namingTab
                    case .numbering:
                        numberingTab
                    case .files:
                        filesTab
                    }
                }
                .padding(.vertical, 4)
            }

            actionBar
        }
    }

    private var identityHeader: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Nom du preset", text: $preset.name)
                    .textFieldStyle(.roundedBorder)
                TextField("Catégorie", text: $preset.category)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 10) {
                    Label("Format v\(preset.formatVersion)", systemImage: "doc.text")
                    Label("\(activeRuleNames.count) règles actives", systemImage: "slider.horizontal.3")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        } label: {
            Text("Identité")
        }
    }

    private var validationPanel: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(validationIssues.enumerated()), id: \.offset) { _, issue in
                    Label("\(issue.field): \(issue.message)", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        } label: {
            Text("Validation")
        }
    }

    private var summaryTab: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                if activeRuleNames.isEmpty {
                    Text("Aucune règle active pour le moment.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(activeRuleNames, id: \.self) { name in
                        Label(name, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                Divider()

                Text("Ce preset est un profil de renommage manuel en lot.")
                    .foregroundStyle(.secondary)
                Text("Utilisez les onglets pour ajuster précisément les règles, puis appliquez ou enregistrez.")
                    .foregroundStyle(.secondary)
            }
        } label: {
            Text("Résumé")
        }
    }

    private var namingTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            PresetSectionCard(title: "Remplacer", isActive: $preset.replace.enabled) {
                LabeledField(title: "Rechercher") {
                    TextField("Texte ou regex", text: $preset.replace.find)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledField(title: "Remplacer par") {
                    TextField("Texte", text: $preset.replace.replace)
                        .textFieldStyle(.roundedBorder)
                }
                Toggle("Regex", isOn: $preset.replace.regex).toggleStyle(.checkbox)
                Toggle("Sensible à la casse", isOn: $preset.replace.caseSensitive).toggleStyle(.checkbox)
            }

            PresetSectionCard(title: "Retirer", isActive: $preset.remove.enabled) {
                HStack(spacing: 12) {
                    LabeledField(title: "De") {
                        TextField("", text: optionalIntBinding($preset.remove.from))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                    LabeledField(title: "À") {
                        TextField("", text: optionalIntBinding($preset.remove.to))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                }
                Toggle("Réduire espaces multiples", isOn: $preset.remove.collapseSpaces).toggleStyle(.checkbox)
                Toggle("Supprimer espaces début/fin", isOn: $preset.remove.trimWhitespace).toggleStyle(.checkbox)
            }

            PresetSectionCard(title: "Ajouter", isActive: $preset.add.enabled) {
                Toggle("Préfixe", isOn: $preset.add.usePrefix).toggleStyle(.checkbox)
                TextField("Texte préfixe", text: $preset.add.prefix).textFieldStyle(.roundedBorder)
                Toggle("Suffixe", isOn: $preset.add.useSuffix).toggleStyle(.checkbox)
                TextField("Texte suffixe", text: $preset.add.suffix).textFieldStyle(.roundedBorder)
                TextField("Texte à insérer", text: $preset.add.insertText).textFieldStyle(.roundedBorder)
                Stepper("Position insertion: \(preset.add.insertIndex)", value: $preset.add.insertIndex, in: 1...9999)
            }

            PresetSectionCard(title: "Date auto", isActive: $preset.date.enabled) {
                TextField("Format date (ex: yyyy-MM-dd)", text: $preset.date.format).textFieldStyle(.roundedBorder)
                Toggle("Préfixe", isOn: $preset.date.usePrefix).toggleStyle(.checkbox)
                Toggle("À la position", isOn: $preset.date.useAtPosition).toggleStyle(.checkbox)
                Stepper("Position date: \(preset.date.atIndex)", value: $preset.date.atIndex, in: 1...9999)
                Toggle("Suffixe", isOn: $preset.date.useSuffix).toggleStyle(.checkbox)
            }

            PresetSectionCard(title: "Casse", isActive: $preset.casing.enabled) {
                Picker("Style", selection: $preset.casing.style) {
                    ForEach(CaseStyle.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var numberingTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            PresetSectionCard(title: "Numérotation", isActive: $preset.num.enabled) {
                Toggle("Numéro en préfixe", isOn: $preset.num.asPrefix).toggleStyle(.checkbox)
                Toggle("Seulement la sélection", isOn: $preset.num.onlySelection).toggleStyle(.checkbox)
                Stepper("Départ: \(preset.num.start)", value: $preset.num.start, in: -9999...9999)
                Stepper("Pas: \(preset.num.step)", value: $preset.num.step, in: 1...999)
                Stepper("Padding: \(preset.num.pad)", value: $preset.num.pad, in: 1...12)
                TextField("Séparateur", text: $preset.num.sep).textFieldStyle(.roundedBorder)
                TextField("Patron (utiliser #)", text: $preset.num.pattern).textFieldStyle(.roundedBorder)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Exemples de patron:")
                        .font(.footnote.weight(.semibold))
                    Text("- ##  -> 01, 02, 03")
                    Text("- 2026-##  -> 2026-01, 2026-02")
                    Text("- Vide -> padding simple")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            } label: {
                Text("Aide")
            }
        }
    }

    private var filesTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            PresetSectionCard(title: "Extension", isActive: $preset.ext.enabled) {
                TextField("Nouvelle extension", text: $preset.ext.newExt).textFieldStyle(.roundedBorder)
                Picker("Casse extension", selection: $preset.ext.caseChange) {
                    ForEach(ExtCase.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                .pickerStyle(.segmented)
            }

            PresetSectionCard(title: "Dossier parent", isActive: $preset.folder.enabled) {
                Toggle("Ajouter en préfixe", isOn: $preset.folder.addParentAsPrefix).toggleStyle(.checkbox)
                TextField("Séparateur dossier", text: $preset.folder.sep).textFieldStyle(.roundedBorder)
            }

            PresetSectionCard(title: "Transformations spéciales", isActive: $preset.special.enabled) {
                Toggle("Normaliser Unicode", isOn: $preset.special.normalizeUnicode).toggleStyle(.checkbox)
                Toggle("Supprimer accents", isOn: $preset.special.stripDiacritics).toggleStyle(.checkbox)
                Toggle("Remplacer \" - \" par « – »", isOn: $preset.special.dashToEnDash).toggleStyle(.checkbox)
                Toggle("Remplacer espaces par _", isOn: $preset.special.spacesToUnderscore).toggleStyle(.checkbox)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Récursif", isOn: $preset.filters.recursive).toggleStyle(.checkbox)
                    Toggle("Inclure fichiers cachés", isOn: $preset.filters.includeHidden).toggleStyle(.checkbox)
                    TextField("Regex inclure", text: $preset.filters.includeRegex).textFieldStyle(.roundedBorder)
                    TextField("Regex exclure", text: $preset.filters.excludeRegex).textFieldStyle(.roundedBorder)
                }
            } label: {
                Text("Filtres")
            }

            PresetSectionCard(title: "Destination", isActive: $preset.destination.enabled) {
                if let url = preset.destination.url {
                    Text(url.path)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                HStack(spacing: 10) {
                    Button("Choisir…") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.allowsMultipleSelection = false
                        panel.title = "Choisir un dossier de destination"
                        if panel.runModal() == .OK {
                            preset.destination.url = panel.url
                        }
                    }

                    Button("Effacer") {
                        preset.destination.url = nil
                    }
                }
                Toggle("Copier au lieu de déplacer", isOn: $preset.destination.copyInsteadOfMove).toggleStyle(.checkbox)
            }
        }
    }

    private var actionBar: some View {
        HStack {
            Button("Appliquer ce preset") {
                preset.formatVersion = RenamePreset.currentFormatVersion
                applyAction()
            }

            Button("Réinitialiser ce preset") {
                let preservedID = preset.id
                let preservedName = preset.name
                let preservedCategory = preset.category
                preset = RenamePreset(
                    id: preservedID,
                    formatVersion: RenamePreset.currentFormatVersion,
                    name: preservedName,
                    category: preservedCategory
                )
            }

            Spacer()

            Button("Enregistrer") {
                preset.formatVersion = RenamePreset.currentFormatVersion
                store.save()
            }
        }
    }

    private func optionalIntBinding(_ value: Binding<Int?>) -> Binding<String> {
        Binding<String>(
            get: { value.wrappedValue.map(String.init) ?? "" },
            set: { raw in
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                value.wrappedValue = trimmed.isEmpty ? nil : Int(trimmed)
            }
        )
    }
}

private struct PresetSectionCard<Content: View>: View {
    let title: String
    @Binding var isActive: Bool
    @ViewBuilder var content: Content

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Activer", isOn: $isActive)
                    .toggleStyle(.checkbox)
                if isActive {
                    content
                }
            }
        } label: {
            Text(title)
        }
    }
}

private struct LabeledField<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .frame(width: 90, alignment: .trailing)
            content
        }
    }
}
