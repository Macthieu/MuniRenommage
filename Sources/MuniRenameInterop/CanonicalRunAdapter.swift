import Foundation
import MuniRenameCore
import OrchivisteKitContracts

public enum CanonicalRunAdapterError: Error, Sendable {
    case unsupportedAction(String)
    case missingParameter(String)
    case invalidParameter(String, String)
    case presetLoadFailed(String)
    case explicitConfirmationRequired
    case runtimeFailure(String)

    var toolError: ToolError {
        switch self {
        case .unsupportedAction(let action):
            return ToolError(
                code: "UNSUPPORTED_ACTION",
                message: "Unsupported action: \(action)",
                retryable: false
            )
        case .missingParameter(let parameter):
            return ToolError(
                code: "MISSING_PARAMETER",
                message: "Missing required parameter: \(parameter)",
                retryable: false
            )
        case .invalidParameter(let parameter, let reason):
            return ToolError(
                code: "INVALID_PARAMETER",
                message: "Invalid parameter \(parameter): \(reason)",
                retryable: false
            )
        case .presetLoadFailed(let reason):
            return ToolError(
                code: "PRESET_LOAD_FAILED",
                message: reason,
                retryable: false
            )
        case .explicitConfirmationRequired:
            return ToolError(
                code: "EXPLICIT_CONFIRMATION_REQUIRED",
                message: "Destructive apply requires confirm_apply=true and dry_run=false.",
                retryable: false
            )
        case .runtimeFailure(let reason):
            return ToolError(
                code: "RUNTIME_FAILURE",
                message: reason,
                retryable: false
            )
        }
    }
}

private enum CanonicalAction: String, Sendable {
    case preview
    case apply
    case validatePreset = "validate-preset"
}

private struct MuniReglesBundleManifestPayload: Codable, Sendable {
    let bundleVersion: String?
    let moduleVersion: String?

    enum CodingKeys: String, CodingKey {
        case bundleVersion = "bundle_version"
        case moduleVersion = "module_version"
    }
}

private struct MuniReglesNamingRulePayload: Codable, Sendable {
    let id: String
    let template: String
}

private struct MuniReglesNamingAndRoutingRulesPayload: Codable, Sendable {
    let namingRules: [MuniReglesNamingRulePayload]

    enum CodingKeys: String, CodingKey {
        case namingRules = "naming_rules"
    }
}

private struct MuniReglesBundlePayload: Codable, Sendable {
    let manifest: MuniReglesBundleManifestPayload
    let namingAndRoutingRules: MuniReglesNamingAndRoutingRulesPayload

    enum CodingKeys: String, CodingKey {
        case manifest
        case namingAndRoutingRules = "naming_and_routing_rules"
    }
}

private struct MuniReglesTraceContext: Sendable {
    let source: String
    let bundleVersion: String?
    let moduleVersion: String?
    let ruleID: String?
    let fallbackReason: String?
    let applyRuleRequested: Bool
}

private struct DocumentMetadataEntryPayload: Codable, Sendable {
    let sourceFile: String
    let documentType: String
    let documentSubject: String
    let documentDate: String

    enum CodingKeys: String, CodingKey {
        case sourceFile = "source_file"
        case documentType = "document_type"
        case documentSubject = "document_subject"
        case documentDate = "document_date"
    }
}

private struct DocumentMetadataPayload: Codable, Sendable {
    let documents: [DocumentMetadataEntryPayload]
}

private struct CanonicalExecutionContext: Sendable {
    let action: CanonicalAction
    let preset: RenamePreset
    let effectiveRules: RenameRules
    let directory: URL?
    let recursive: Bool
    let includeHidden: Bool
    let dryRun: Bool
    let confirmApply: Bool
    let reglesTrace: MuniReglesTraceContext
    let documentMetadataBySourceFile: [String: DocumentMetadataEntryPayload]
    let usesDocumentMetadataTemplate: Bool
}

public enum CanonicalRunAdapter {
    public static func execute(request: ToolRequest) -> ToolResult {
        let startedAt = isoTimestamp()

        do {
            let context = try parseContext(from: request)
            let completed = try execute(request: request, context: context, startedAt: startedAt)
            return completed
        } catch let adapterError as CanonicalRunAdapterError {
            let finishedAt = isoTimestamp()
            return makeFailureResult(
                request: request,
                startedAt: startedAt,
                finishedAt: finishedAt,
                errors: [adapterError.toolError],
                summary: "Canonical request failed before completion."
            )
        } catch {
            let finishedAt = isoTimestamp()
            let toolError = CanonicalRunAdapterError.runtimeFailure(error.localizedDescription).toolError
            return makeFailureResult(
                request: request,
                startedAt: startedAt,
                finishedAt: finishedAt,
                errors: [toolError],
                summary: "Canonical request failed with an unexpected runtime error."
            )
        }
    }

    private static func execute(
        request: ToolRequest,
        context: CanonicalExecutionContext,
        startedAt: String
    ) throws -> ToolResult {
        let validationIssues = PresetValidator.validate(context.preset)

        if context.action == .validatePreset {
            let finishedAt = isoTimestamp()
            if validationIssues.isEmpty {
                return makeResult(
                    request: request,
                    status: .succeeded,
                    startedAt: startedAt,
                    finishedAt: finishedAt,
                    summary: "Preset validation succeeded.",
                    errors: [],
                    metadata: withReglesTraceMetadata(
                        [
                        "action": .string("validate-preset"),
                        "issue_count": .number(0)
                        ],
                        context: context
                    )
                )
            }

            let errors = validationIssues.map { issue in
                ToolError(
                    code: "PRESET_VALIDATION_FAILED",
                    message: "[\(issue.field)] \(issue.message)",
                    details: ["field": .string(issue.field)],
                    retryable: false
                )
            }
            return makeFailureResult(
                request: request,
                startedAt: startedAt,
                finishedAt: finishedAt,
                errors: errors,
                summary: "Preset validation failed.",
                additionalMetadata: withReglesTraceMetadata([:], context: context)
            )
        }

        if !validationIssues.isEmpty {
            let finishedAt = isoTimestamp()
            let errors = validationIssues.map { issue in
                ToolError(
                    code: "PRESET_VALIDATION_FAILED",
                    message: "[\(issue.field)] \(issue.message)",
                    details: ["field": .string(issue.field)],
                    retryable: false
                )
            }
            return makeFailureResult(
                request: request,
                startedAt: startedAt,
                finishedAt: finishedAt,
                errors: errors,
                summary: "Preset is invalid for execution.",
                additionalMetadata: withReglesTraceMetadata([:], context: context)
            )
        }

        guard let directory = context.directory else {
            throw CanonicalRunAdapterError.missingParameter("directory_path")
        }

        var effectiveRules = context.effectiveRules
        if context.recursive { effectiveRules.filters.recursive = true }
        if context.includeHidden { effectiveRules.filters.includeHidden = true }

        let items = try FileInventoryService.collectFiles(directory: directory, filters: effectiveRules.filters)
        let preview = RenameEngine.computePreview(
            items: items,
            directoryURL: directory,
            selection: [],
            previewOnlySelection: false,
            rules: effectiveRules
        )
        let outputNameResolution = resolveOutputNames(
            from: preview,
            items: items,
            context: context
        )
        let outputNames = outputNameResolution.names
        let plan = RenameEngine.buildPlan(items: items, selection: [], outputNames: outputNames, rules: effectiveRules)
        let warningCount = plan.statuses.values.filter { !$0.isEmpty }.count

        if context.action == .preview || context.dryRun {
            let finishedAt = isoTimestamp()
            let status: ToolStatus = warningCount > 0 ? .needsReview : .succeeded
            let summary = context.action == .apply
                ? "Apply request executed in dry-run mode."
                : "Preview completed."
            return makeResult(
                request: request,
                status: status,
                startedAt: startedAt,
                finishedAt: finishedAt,
                summary: summary,
                errors: [],
                metadata: withReglesTraceMetadata(
                    [
                    "action": .string(context.action.rawValue),
                    "dry_run": .bool(context.dryRun),
                    "files_analyzed": .number(Double(items.count)),
                    "warning_count": .number(Double(warningCount)),
                    "regles_document_metadata_applied_count": .number(Double(outputNameResolution.metadataAppliedCount))
                    ],
                    context: context
                )
            )
        }

        guard context.confirmApply else {
            throw CanonicalRunAdapterError.explicitConfirmationRequired
        }

        let report = RenameEngine.apply(plan: plan, rules: effectiveRules)
        let finishedAt = isoTimestamp()

        let operationErrors = report.statuses
            .filter { !$0.value.isEmpty }
            .map { id, message in
                ToolError(
                    code: "RENAME_OPERATION_FAILED",
                    message: message,
                    details: ["item_id": .string(id.uuidString)],
                    retryable: false
                )
            }

        if report.errorCount > 0 {
            return makeFailureResult(
                request: request,
                startedAt: startedAt,
                finishedAt: finishedAt,
                errors: operationErrors.isEmpty ? [CanonicalRunAdapterError.runtimeFailure("Rename apply failed.").toolError] : operationErrors,
                summary: "Apply completed with errors.",
                additionalMetadata: withReglesTraceMetadata([:], context: context)
            )
        }

        return makeResult(
            request: request,
            status: .succeeded,
            startedAt: startedAt,
            finishedAt: finishedAt,
            summary: "Apply completed successfully.",
            errors: [],
            metadata: withReglesTraceMetadata(
                [
                "action": .string("apply"),
                "dry_run": .bool(false),
                "files_analyzed": .number(Double(items.count)),
                "renamed_count": .number(Double(report.renamedCount)),
                "error_count": .number(Double(report.errorCount)),
                "warning_count": .number(Double(warningCount)),
                "regles_document_metadata_applied_count": .number(Double(outputNameResolution.metadataAppliedCount))
                ],
                context: context
            )
        )
    }

    private static func parseContext(from request: ToolRequest) throws -> CanonicalExecutionContext {
        let action = try parseAction(request.action)

        let presetPath = try requiredStringParameter("preset_path", in: request)
        let presetURL = URL(fileURLWithPath: presetPath)
        let preset: RenamePreset
        do {
            let data = try Data(contentsOf: presetURL)
            preset = try PresetCodec.decodePreset(from: data)
        } catch {
            throw CanonicalRunAdapterError.presetLoadFailed("Unable to read preset at \(presetPath): \(error.localizedDescription)")
        }

        let directoryPath = try optionalStringParameter("directory_path", in: request)
        let directoryURL = directoryPath.map { URL(fileURLWithPath: $0) }
        let recursive = try optionalBoolParameter("recursive", in: request) ?? false
        let includeHidden = try optionalBoolParameter("include_hidden", in: request) ?? false

        let dryRun: Bool
        if action == .apply {
            dryRun = try optionalBoolParameter("dry_run", in: request) ?? true
        } else {
            dryRun = true
        }

        let confirmApply = try optionalBoolParameter("confirm_apply", in: request) ?? false

        if action != .validatePreset, directoryURL == nil {
            throw CanonicalRunAdapterError.missingParameter("directory_path")
        }

        let reglesResolution = try resolveMuniReglesTrace(from: request, baseRules: preset.rules)

        return CanonicalExecutionContext(
            action: action,
            preset: preset,
            effectiveRules: reglesResolution.effectiveRules,
            directory: directoryURL,
            recursive: recursive,
            includeHidden: includeHidden,
            dryRun: dryRun,
            confirmApply: confirmApply,
            reglesTrace: reglesResolution.trace,
            documentMetadataBySourceFile: reglesResolution.documentMetadataBySourceFile,
            usesDocumentMetadataTemplate: reglesResolution.usesDocumentMetadataTemplate
        )
    }

    private static func parseAction(_ rawValue: String) throws -> CanonicalAction {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")

        switch normalized {
        case "preview":
            return .preview
        case "apply":
            return .apply
        case "validate-preset":
            return .validatePreset
        default:
            throw CanonicalRunAdapterError.unsupportedAction(rawValue)
        }
    }

    private static func requiredStringParameter(_ key: String, in request: ToolRequest) throws -> String {
        guard let value = try optionalStringParameter(key, in: request) else {
            throw CanonicalRunAdapterError.missingParameter(key)
        }
        return value
    }

    private static func optionalRawStringParameter(_ key: String, in request: ToolRequest) throws -> String? {
        guard let value = request.parameters[key] else {
            return nil
        }

        switch value {
        case .string(let stringValue):
            let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        default:
            throw CanonicalRunAdapterError.invalidParameter(key, "expected string")
        }
    }

    private static func optionalStringParameter(_ key: String, in request: ToolRequest) throws -> String? {
        guard let value = request.parameters[key] else {
            return nil
        }

        switch value {
        case .string(let stringValue):
            let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return nil
            }
            return resolvePathFromURIOrPath(trimmed)
        default:
            throw CanonicalRunAdapterError.invalidParameter(key, "expected string")
        }
    }

    private static func optionalBoolParameter(_ key: String, in request: ToolRequest) throws -> Bool? {
        guard let value = request.parameters[key] else {
            return nil
        }

        switch value {
        case .bool(let boolValue):
            return boolValue
        default:
            throw CanonicalRunAdapterError.invalidParameter(key, "expected boolean")
        }
    }

    private static func resolveMuniReglesTrace(
        from request: ToolRequest,
        baseRules: RenameRules
    ) throws -> (
        trace: MuniReglesTraceContext,
        effectiveRules: RenameRules,
        documentMetadataBySourceFile: [String: DocumentMetadataEntryPayload],
        usesDocumentMetadataTemplate: Bool
    ) {
        let applyRule = try optionalBoolParameter("regles_apply_rule", in: request) ?? false
        let requestedRuleID = try optionalRawStringParameter("regles_naming_rule_id", in: request)
        let requestedClassCode = try optionalRawStringParameter("regles_class_code", in: request)
            ?? (try optionalRawStringParameter("class_code", in: request))
        let bundlePath = try resolveMuniReglesBundlePath(from: request)

        guard let bundlePath else {
            return (
                MuniReglesTraceContext(
                    source: "fallback_local",
                    bundleVersion: nil,
                    moduleVersion: nil,
                    ruleID: requestedRuleID,
                    fallbackReason: applyRule ? "bundle_not_provided" : nil,
                    applyRuleRequested: applyRule
                ),
                baseRules,
                [:],
                false
            )
        }

        guard let bundle = try? parseMuniReglesBundle(fromPath: bundlePath) else {
            return (
                MuniReglesTraceContext(
                    source: "fallback_local",
                    bundleVersion: nil,
                    moduleVersion: nil,
                    ruleID: requestedRuleID,
                    fallbackReason: "bundle_unreadable_or_invalid",
                    applyRuleRequested: applyRule
                ),
                baseRules,
                [:],
                false
            )
        }

        let bundleVersion = normalizeNonEmpty(bundle.manifest.bundleVersion)
        let moduleVersion = normalizeNonEmpty(bundle.manifest.moduleVersion)
        let namingRules = bundle.namingAndRoutingRules.namingRules

        guard !namingRules.isEmpty else {
            return (
                MuniReglesTraceContext(
                    source: "fallback_local",
                    bundleVersion: bundleVersion,
                    moduleVersion: moduleVersion,
                    ruleID: requestedRuleID,
                    fallbackReason: "bundle_contains_no_naming_rules",
                    applyRuleRequested: applyRule
                ),
                baseRules,
                [:],
                false
            )
        }

        guard let requestedRuleID, !requestedRuleID.isEmpty else {
            let fallbackReason = applyRule ? "regles_naming_rule_id_missing" : nil
            return (
                MuniReglesTraceContext(
                    source: "fallback_local",
                    bundleVersion: bundleVersion,
                    moduleVersion: moduleVersion,
                    ruleID: nil,
                    fallbackReason: fallbackReason,
                    applyRuleRequested: applyRule
                ),
                baseRules,
                [:],
                false
            )
        }

        guard let selectedRule = namingRules.first(where: { $0.id == requestedRuleID }) else {
            return (
                MuniReglesTraceContext(
                    source: "fallback_local",
                    bundleVersion: bundleVersion,
                    moduleVersion: moduleVersion,
                    ruleID: requestedRuleID,
                    fallbackReason: "rule_not_found_in_bundle",
                    applyRuleRequested: applyRule
                ),
                baseRules,
                [:],
                false
            )
        }

        guard applyRule else {
            return (
                MuniReglesTraceContext(
                    source: "fallback_local",
                    bundleVersion: bundleVersion,
                    moduleVersion: moduleVersion,
                    ruleID: requestedRuleID,
                    fallbackReason: "regles_apply_rule_disabled",
                    applyRuleRequested: false
                ),
                baseRules,
                [:],
                false
            )
        }

        let normalizedTemplate = normalizeTemplate(selectedRule.template)
        if normalizedTemplate == "{document_type}-{document_subject}-{document_date}" {
            guard let metadataPath = try resolveDocumentMetadataPath(from: request) else {
                return (
                    MuniReglesTraceContext(
                        source: "fallback_local",
                        bundleVersion: bundleVersion,
                        moduleVersion: moduleVersion,
                        ruleID: requestedRuleID,
                        fallbackReason: "document_metadata_not_provided",
                        applyRuleRequested: true
                    ),
                    baseRules,
                    [:],
                    false
                )
            }

            guard let documentMetadata = try? parseDocumentMetadataMap(fromPath: metadataPath) else {
                return (
                    MuniReglesTraceContext(
                        source: "fallback_local",
                        bundleVersion: bundleVersion,
                        moduleVersion: moduleVersion,
                        ruleID: requestedRuleID,
                        fallbackReason: "document_metadata_unreadable_or_invalid",
                        applyRuleRequested: true
                    ),
                    baseRules,
                    [:],
                    false
                )
            }

            return (
                MuniReglesTraceContext(
                    source: "muniregles_bundle",
                    bundleVersion: bundleVersion,
                    moduleVersion: moduleVersion,
                    ruleID: requestedRuleID,
                    fallbackReason: nil,
                    applyRuleRequested: true
                ),
                baseRules,
                documentMetadata,
                true
            )
        }

        guard let classCode = normalizeNonEmpty(requestedClassCode) else {
            return (
                MuniReglesTraceContext(
                    source: "fallback_local",
                    bundleVersion: bundleVersion,
                    moduleVersion: moduleVersion,
                    ruleID: requestedRuleID,
                    fallbackReason: "regles_class_code_missing",
                    applyRuleRequested: true
                ),
                baseRules,
                [:],
                false
            )
        }

        var effectiveRules = baseRules
        guard applySupportedMuniReglesTemplate(
            normalizedTemplate,
            classCode: classCode,
            to: &effectiveRules
        ) else {
            return (
                MuniReglesTraceContext(
                    source: "fallback_local",
                    bundleVersion: bundleVersion,
                    moduleVersion: moduleVersion,
                    ruleID: requestedRuleID,
                    fallbackReason: "template_not_supported",
                    applyRuleRequested: true
                ),
                baseRules,
                [:],
                false
            )
        }

        return (
            MuniReglesTraceContext(
                source: "muniregles_bundle",
                bundleVersion: bundleVersion,
                moduleVersion: moduleVersion,
                ruleID: requestedRuleID,
                fallbackReason: nil,
                applyRuleRequested: true
            ),
            effectiveRules,
            [:],
            false
        )
    }

    private static func resolveMuniReglesBundlePath(from request: ToolRequest) throws -> String? {
        if let explicit = try optionalStringParameter("regles_bundle_path", in: request) {
            return explicit
        }

        if let legacy = try optionalStringParameter("bundle_path", in: request) {
            return legacy
        }

        let bundleArtifactIDs: Set<String> = ["regles_bundle", "bundle"]
        if let artifact = request.inputArtifacts.first(where: { bundleArtifactIDs.contains($0.id.lowercased()) }) {
            let resolved = resolvePathFromURIOrPath(artifact.uri)
            let trimmed = resolved.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        return nil
    }

    private static func parseMuniReglesBundle(fromPath path: String) throws -> MuniReglesBundlePayload {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONDecoder().decode(MuniReglesBundlePayload.self, from: data)
    }

    private static func resolveDocumentMetadataPath(from request: ToolRequest) throws -> String? {
        if let explicit = try optionalStringParameter("document_metadata_path", in: request) {
            return explicit
        }

        let metadataArtifactIDs: Set<String> = ["document_metadata", "metadata"]
        if let artifact = request.inputArtifacts.first(where: { metadataArtifactIDs.contains($0.id.lowercased()) }) {
            let resolved = resolvePathFromURIOrPath(artifact.uri)
            let trimmed = resolved.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        return nil
    }

    private static func parseDocumentMetadataMap(fromPath path: String) throws -> [String: DocumentMetadataEntryPayload] {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let payload = try JSONDecoder().decode(DocumentMetadataPayload.self, from: data)

        var map: [String: DocumentMetadataEntryPayload] = [:]
        for document in payload.documents {
            let sourceFile = document.sourceFile.trimmingCharacters(in: .whitespacesAndNewlines)
            let documentType = document.documentType.trimmingCharacters(in: .whitespacesAndNewlines)
            let documentSubject = document.documentSubject.trimmingCharacters(in: .whitespacesAndNewlines)
            let documentDate = document.documentDate.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !sourceFile.isEmpty, !documentType.isEmpty, !documentSubject.isEmpty, !documentDate.isEmpty else {
                throw CanonicalRunAdapterError.invalidParameter(
                    "document_metadata_path",
                    "document entries require source_file, document_type, document_subject and document_date"
                )
            }

            let normalizedEntry = DocumentMetadataEntryPayload(
                sourceFile: sourceFile,
                documentType: documentType,
                documentSubject: documentSubject,
                documentDate: documentDate
            )
            for key in metadataLookupKeys(for: sourceFile) {
                map[key] = normalizedEntry
            }
        }

        guard !map.isEmpty else {
            throw CanonicalRunAdapterError.invalidParameter("document_metadata_path", "documents is empty")
        }

        return map
    }

    private static func metadataLookupKeys(for sourceFile: String) -> [String] {
        let trimmed = sourceFile.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var keys = Set<String>()
        keys.insert(trimmed.lowercased())

        let lastComponent = URL(fileURLWithPath: trimmed).lastPathComponent
        let normalizedLastComponent = lastComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedLastComponent.isEmpty {
            keys.insert(normalizedLastComponent.lowercased())
        }

        return Array(keys)
    }

    private static func normalizeNonEmpty(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizeTemplate(_ template: String) -> String {
        template
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: " ", with: "")
    }

    private static func resolveOutputNames(
        from preview: RenamePreview,
        items: [RenameItem],
        context: CanonicalExecutionContext
    ) -> (names: [UUID: String], metadataAppliedCount: Int) {
        var outputNames = Dictionary(uniqueKeysWithValues: preview.byID.map { ($0.key, $0.value.outputName) })

        guard context.usesDocumentMetadataTemplate else {
            return (outputNames, 0)
        }

        var metadataAppliedCount = 0
        for item in items {
            let itemPathKey = item.url.path.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let itemNameKey = item.originalName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard let metadata = context.documentMetadataBySourceFile[itemNameKey]
                ?? context.documentMetadataBySourceFile[itemPathKey] else {
                continue
            }

            let newName = formattedDocumentMetadataName(
                metadata: metadata,
                sourceFileExtension: item.url.pathExtension
            )
            outputNames[item.id] = newName
            metadataAppliedCount += 1
        }

        return (outputNames, metadataAppliedCount)
    }

    private static func formattedDocumentMetadataName(
        metadata: DocumentMetadataEntryPayload,
        sourceFileExtension: String
    ) -> String {
        let documentType = metadata.documentType.trimmingCharacters(in: .whitespacesAndNewlines)
        let documentSubject = metadata.documentSubject.trimmingCharacters(in: .whitespacesAndNewlines)
        let documentDate = metadata.documentDate.trimmingCharacters(in: .whitespacesAndNewlines)

        let baseName = "\(documentType) – \(documentSubject) – \(documentDate)"
        let trimmedExtension = sourceFileExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedExtension.isEmpty else {
            return baseName
        }
        return "\(baseName).\(trimmedExtension)"
    }

    private static func applySupportedMuniReglesTemplate(
        _ template: String,
        classCode: String,
        to rules: inout RenameRules
    ) -> Bool {
        let normalizedClassCode = classCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedClassCode.isEmpty else {
            return false
        }

        switch template {
        case "{class_code}-{subject}":
            rules.add = AddRule(
                enabled: true,
                usePrefix: true,
                prefix: "\(normalizedClassCode)-",
                useSuffix: false,
                suffix: "",
                insertText: "",
                insertIndex: 1
            )
            rules.numbering = NumberingRule(
                enabled: false,
                asPrefix: false,
                start: 1,
                step: 1,
                pad: 3,
                separator: "-",
                onlySelection: false,
                pattern: ""
            )
            return true

        case "{class_code}-{subject}-{seq}":
            rules.add = AddRule(
                enabled: true,
                usePrefix: true,
                prefix: "\(normalizedClassCode)-",
                useSuffix: false,
                suffix: "",
                insertText: "",
                insertIndex: 1
            )
            rules.numbering = NumberingRule(
                enabled: true,
                asPrefix: false,
                start: 1,
                step: 1,
                pad: 3,
                separator: "-",
                onlySelection: false,
                pattern: ""
            )
            return true

        default:
            return false
        }
    }

    private static func withReglesTraceMetadata(
        _ metadata: [String: JSONValue],
        context: CanonicalExecutionContext
    ) -> [String: JSONValue] {
        var merged = metadata
        merged["regles_source"] = .string(context.reglesTrace.source)

        if let bundleVersion = context.reglesTrace.bundleVersion {
            merged["regles_bundle_version"] = .string(bundleVersion)
        }
        if let moduleVersion = context.reglesTrace.moduleVersion {
            merged["regles_module_version"] = .string(moduleVersion)
        }
        if let ruleID = context.reglesTrace.ruleID {
            merged["regles_rule_id"] = .string(ruleID)
        }
        if let fallbackReason = context.reglesTrace.fallbackReason {
            merged["regles_fallback_reason"] = .string(fallbackReason)
        }
        merged["regles_apply_rule"] = .bool(context.reglesTrace.applyRuleRequested)

        return merged
    }

    private static func makeResult(
        request: ToolRequest,
        status: ToolStatus,
        startedAt: String,
        finishedAt: String,
        summary: String,
        errors: [ToolError],
        metadata: [String: JSONValue]
    ) -> ToolResult {
        let progressEvents = [
            ProgressEvent(
                requestID: request.requestID,
                status: .running,
                stage: "rename_pipeline",
                percent: 10,
                message: "Execution started.",
                occurredAt: startedAt
            ),
            ProgressEvent(
                requestID: request.requestID,
                status: status,
                stage: "rename_pipeline_complete",
                percent: 100,
                message: summary,
                occurredAt: finishedAt
            )
        ]

        return ToolResult(
            requestID: request.requestID,
            tool: request.tool,
            status: status,
            startedAt: startedAt,
            finishedAt: finishedAt,
            progressEvents: progressEvents,
            outputArtifacts: [],
            errors: errors,
            summary: summary,
            metadata: metadata
        )
    }

    private static func makeFailureResult(
        request: ToolRequest,
        startedAt: String,
        finishedAt: String,
        errors: [ToolError],
        summary: String,
        additionalMetadata: [String: JSONValue] = [:]
    ) -> ToolResult {
        var metadata: [String: JSONValue] = ["action": .string(request.action)]
        for (key, value) in additionalMetadata {
            metadata[key] = value
        }

        return makeResult(
            request: request,
            status: .failed,
            startedAt: startedAt,
            finishedAt: finishedAt,
            summary: summary,
            errors: errors,
            metadata: metadata
        )
    }

    private static func resolvePathFromURIOrPath(_ candidate: String) -> String {
        guard let url = URL(string: candidate), url.isFileURL else {
            return candidate
        }
        return url.path
    }

    private static func isoTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
