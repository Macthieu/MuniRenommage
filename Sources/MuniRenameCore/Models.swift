import Foundation

public struct RenameItem: Hashable, Identifiable {
    public let id: UUID
    public let url: URL

    public init(id: UUID = UUID(), url: URL) {
        self.id = id
        self.url = url
    }

    public var originalName: String { url.lastPathComponent }
    public var baseName: String { url.deletingPathExtension().lastPathComponent }
    public var ext: String { url.pathExtension }
}

public enum CaseStyle: String, CaseIterable, Codable, Sendable {
    case unchanged
    case lower
    case upper
    case title
}

public enum ExtensionCaseStyle: String, CaseIterable, Codable, Sendable {
    case unchanged
    case lower
    case upper
}

public struct ReplaceRule: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var find: String
    public var replace: String
    public var regex: Bool
    public var caseSensitive: Bool

    public init(
        enabled: Bool = false,
        find: String = "",
        replace: String = "",
        regex: Bool = true,
        caseSensitive: Bool = false
    ) {
        self.enabled = enabled
        self.find = find
        self.replace = replace
        self.regex = regex
        self.caseSensitive = caseSensitive
    }
}

public struct RemoveRule: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var from: Int?
    public var to: Int?
    public var collapseSpaces: Bool
    public var trimWhitespace: Bool

    public init(
        enabled: Bool = false,
        from: Int? = nil,
        to: Int? = nil,
        collapseSpaces: Bool = false,
        trimWhitespace: Bool = false
    ) {
        self.enabled = enabled
        self.from = from
        self.to = to
        self.collapseSpaces = collapseSpaces
        self.trimWhitespace = trimWhitespace
    }
}

public struct AddRule: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var usePrefix: Bool
    public var prefix: String
    public var useSuffix: Bool
    public var suffix: String
    public var insertText: String
    public var insertIndex: Int

    public init(
        enabled: Bool = false,
        usePrefix: Bool = false,
        prefix: String = "",
        useSuffix: Bool = false,
        suffix: String = "",
        insertText: String = "",
        insertIndex: Int = 1
    ) {
        self.enabled = enabled
        self.usePrefix = usePrefix
        self.prefix = prefix
        self.useSuffix = useSuffix
        self.suffix = suffix
        self.insertText = insertText
        self.insertIndex = insertIndex
    }
}

public struct DateRule: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var format: String
    public var usePrefix: Bool
    public var useSuffix: Bool
    public var useAtPosition: Bool
    public var atIndex: Int

    public init(
        enabled: Bool = false,
        format: String = "yyyy-MM-dd",
        usePrefix: Bool = false,
        useSuffix: Bool = false,
        useAtPosition: Bool = true,
        atIndex: Int = 1
    ) {
        self.enabled = enabled
        self.format = format
        self.usePrefix = usePrefix
        self.useSuffix = useSuffix
        self.useAtPosition = useAtPosition
        self.atIndex = atIndex
    }
}

public struct NumberingRule: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var asPrefix: Bool
    public var start: Int
    public var step: Int
    public var pad: Int
    public var separator: String
    public var onlySelection: Bool
    public var pattern: String

    public init(
        enabled: Bool = false,
        asPrefix: Bool = true,
        start: Int = 1,
        step: Int = 1,
        pad: Int = 3,
        separator: String = " - ",
        onlySelection: Bool = false,
        pattern: String = ""
    ) {
        self.enabled = enabled
        self.asPrefix = asPrefix
        self.start = start
        self.step = step
        self.pad = pad
        self.separator = separator
        self.onlySelection = onlySelection
        self.pattern = pattern
    }
}

public struct CasingRule: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var style: CaseStyle

    public init(enabled: Bool = false, style: CaseStyle = .unchanged) {
        self.enabled = enabled
        self.style = style
    }
}

public struct ExtensionRule: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var newExtension: String
    public var caseStyle: ExtensionCaseStyle

    public init(
        enabled: Bool = false,
        newExtension: String = "",
        caseStyle: ExtensionCaseStyle = .unchanged
    ) {
        self.enabled = enabled
        self.newExtension = newExtension
        self.caseStyle = caseStyle
    }
}

public struct FolderNameRule: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var addParentAsPrefix: Bool
    public var separator: String

    public init(enabled: Bool = false, addParentAsPrefix: Bool = true, separator: String = " - ") {
        self.enabled = enabled
        self.addParentAsPrefix = addParentAsPrefix
        self.separator = separator
    }
}

public struct SpecialRule: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var normalizeUnicode: Bool
    public var stripDiacritics: Bool
    public var dashToEnDash: Bool
    public var spacesToUnderscore: Bool

    public init(
        enabled: Bool = false,
        normalizeUnicode: Bool = true,
        stripDiacritics: Bool = false,
        dashToEnDash: Bool = false,
        spacesToUnderscore: Bool = false
    ) {
        self.enabled = enabled
        self.normalizeUnicode = normalizeUnicode
        self.stripDiacritics = stripDiacritics
        self.dashToEnDash = dashToEnDash
        self.spacesToUnderscore = spacesToUnderscore
    }
}

public struct FilterRule: Codable, Equatable, Sendable {
    public var recursive: Bool
    public var includeHidden: Bool
    public var includeRegex: String
    public var excludeRegex: String

    public init(
        recursive: Bool = false,
        includeHidden: Bool = false,
        includeRegex: String = "",
        excludeRegex: String = ""
    ) {
        self.recursive = recursive
        self.includeHidden = includeHidden
        self.includeRegex = includeRegex
        self.excludeRegex = excludeRegex
    }
}

public struct DestinationRule: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var url: URL?
    public var copyInsteadOfMove: Bool

    public init(enabled: Bool = false, url: URL? = nil, copyInsteadOfMove: Bool = false) {
        self.enabled = enabled
        self.url = url
        self.copyInsteadOfMove = copyInsteadOfMove
    }
}

public struct RenameRules: Codable, Equatable, Sendable {
    public var replace: ReplaceRule
    public var remove: RemoveRule
    public var add: AddRule
    public var date: DateRule
    public var numbering: NumberingRule
    public var casing: CasingRule
    public var ext: ExtensionRule
    public var folder: FolderNameRule
    public var special: SpecialRule
    public var filters: FilterRule
    public var destination: DestinationRule

    public init(
        replace: ReplaceRule = .init(),
        remove: RemoveRule = .init(),
        add: AddRule = .init(),
        date: DateRule = .init(),
        numbering: NumberingRule = .init(),
        casing: CasingRule = .init(),
        ext: ExtensionRule = .init(),
        folder: FolderNameRule = .init(),
        special: SpecialRule = .init(),
        filters: FilterRule = .init(),
        destination: DestinationRule = .init()
    ) {
        self.replace = replace
        self.remove = remove
        self.add = add
        self.date = date
        self.numbering = numbering
        self.casing = casing
        self.ext = ext
        self.folder = folder
        self.special = special
        self.filters = filters
        self.destination = destination
    }
}

public struct RenamePreset: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var formatVersion: Int
    public var name: String
    public var category: String
    public var rules: RenameRules

    public init(
        id: UUID = UUID(),
        formatVersion: Int = 1,
        name: String = "Sans titre",
        category: String = "Divers",
        rules: RenameRules = .init()
    ) {
        self.id = id
        self.formatVersion = formatVersion
        self.name = name
        self.category = category
        self.rules = rules
    }
}

public struct PresetDocument: Codable, Sendable {
    public var schemaVersion: Int
    public var preset: RenamePreset

    public init(schemaVersion: Int = 1, preset: RenamePreset) {
        self.schemaVersion = schemaVersion
        self.preset = preset
    }
}
