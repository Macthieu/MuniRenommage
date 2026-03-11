import Foundation

public enum FileInventoryService {
    public static func collectFiles(directory: URL, filters: FilterRule) throws -> [RenameItem] {
        var urls: [URL] = []

        if filters.recursive {
            let options: FileManager.DirectoryEnumerationOptions = filters.includeHidden ? [] : [.skipsHiddenFiles]
            let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: options
            )

            while let url = enumerator?.nextObject() as? URL {
                if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                    urls.append(url)
                }
            }
        } else {
            let options: FileManager.DirectoryEnumerationOptions = filters.includeHidden ? [] : [.skipsHiddenFiles]
            urls = try FileManager.default
                .contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: options)
                .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
        }

        var items = urls.map { RenameItem(url: $0) }

        if !filters.includeRegex.isEmpty, let includeRegex = try? NSRegularExpression(pattern: filters.includeRegex) {
            items = items.filter {
                includeRegex.firstMatch(
                    in: $0.originalName,
                    range: NSRange($0.originalName.startIndex..<$0.originalName.endIndex, in: $0.originalName)
                ) != nil
            }
        }

        if !filters.excludeRegex.isEmpty, let excludeRegex = try? NSRegularExpression(pattern: filters.excludeRegex) {
            items = items.filter {
                excludeRegex.firstMatch(
                    in: $0.originalName,
                    range: NSRange($0.originalName.startIndex..<$0.originalName.endIndex, in: $0.originalName)
                ) == nil
            }
        }

        return items.sorted {
            $0.originalName.localizedStandardCompare($1.originalName) == .orderedAscending
        }
    }
}
