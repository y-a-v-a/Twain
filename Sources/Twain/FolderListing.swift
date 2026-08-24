import Foundation

/// Enumerates the markdown files a folder window lists in its sidebar.
enum FolderListing {
    static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd"]

    /// The top-level markdown files in `folder`, sorted by name. Returns nil when the folder
    /// is missing or unreadable so callers can distinguish "empty" from "gone".
    static func markdownFiles(in folder: URL) -> [URL]? {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: .skipsHiddenFiles
        ) else { return nil }

        return entries
            .filter { url in
                guard markdownExtensions.contains(url.pathExtension.lowercased()) else {
                    return false
                }
                // Excludes directories with markdown-looking names (e.g. a folder "notes.md").
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
                return values?.isRegularFile == true
            }
            .sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent)
                    == .orderedAscending
            }
    }
}
