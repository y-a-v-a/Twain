import Foundation

/// One row in a folder window's sidebar: a subdirectory or a markdown file.
struct FolderEntry: Hashable, Identifiable {
    let url: URL
    let isDirectory: Bool

    var id: URL { url }
    var name: String { url.lastPathComponent }
}

/// Enumerates what a folder window lists in its sidebar for a single directory level.
enum FolderListing {
    static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd"]

    /// The subdirectories and markdown files directly inside `folder`: directories first, then
    /// files, each sorted by name. Returns nil when the folder is missing or unreadable so
    /// callers can distinguish "empty" from "gone".
    ///
    /// Only one level is read — the sidebar loads deeper levels lazily as they're expanded.
    /// Symlinks are skipped (their resource values describe the link, not the target), which
    /// also keeps the tree free of cycles. Packages such as `.app` bundles aren't listed.
    static func entries(in folder: URL) -> [FolderEntry]? {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isPackageKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: keys,
            options: .skipsHiddenFiles
        ) else { return nil }

        var directories: [FolderEntry] = []
        var files: [FolderEntry] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isDirectory == true {
                if values.isPackage != true {
                    directories.append(FolderEntry(url: url, isDirectory: true))
                }
            } else if values.isRegularFile == true,
                      markdownExtensions.contains(url.pathExtension.lowercased()) {
                files.append(FolderEntry(url: url, isDirectory: false))
            }
        }
        return sortedByName(directories) + sortedByName(files)
    }

    /// Whether `url` lies strictly inside `folder` (at any depth).
    static func isDescendant(_ url: URL, of folder: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(folder.standardizedFileURL.path + "/")
    }

    private static func sortedByName(_ entries: [FolderEntry]) -> [FolderEntry] {
        entries.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
