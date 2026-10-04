import SwiftUI
import TwainRendering

/// A folder window: sidebar tree of the folder's subdirectories and markdown files, selected
/// file rendered in the detail pane. The folder URL arrives via the "folder" WindowGroup's
/// presentation value.
///
/// Subdirectories load lazily: a directory's contents are read (and watched) only while it is
/// expanded. Invariant: `watchers` covers exactly the root plus every directory in `expanded`,
/// and each of those has an entry in `listings`.
struct FolderWindowView: View {
    let folderURL: URL?
    let theme: Theme
    /// Loaded directory levels, keyed by directory URL. A nil value means the directory is
    /// missing/unreadable, as opposed to readable but empty.
    @State private var listings: [URL: [FolderEntry]?] = [:]
    @State private var expanded: Set<URL> = []
    @State private var watchers: [URL: FileWatcher] = [:]
    @State private var selection: URL?

    private var rootEntries: [FolderEntry]? {
        folderURL.flatMap { listings[$0] ?? nil }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                FolderTreeRows(
                    entries: rootEntries ?? [],
                    listings: listings,
                    isExpanded: expansionBinding
                )
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            if let selection {
                // A fresh ContentView per file: its search cache, file watcher, and script
                // handle are all pinned to the URL in init, so identity must change with it.
                ContentView(fileURL: selection, theme: theme)
                    .id(selection)
            } else {
                placeholder
            }
        }
        .navigationTitle(folderURL?.lastPathComponent ?? "Folder")
        // Keyed on the URL, not onAppear: a restored or newly opened window can appear before
        // its presentation value arrives, and onAppear wouldn't run again once it does.
        .task(id: folderURL) { showFolder(folderURL) }
        .onDisappear { showFolder(nil) }
    }

    private var placeholder: some View {
        Group {
            if folderURL.map({ listings[$0] == nil }) == true {
                // Not loaded yet; avoid flashing "not available" before the first read.
                Color.clear
            } else if rootEntries == nil {
                ContentUnavailableView(
                    "Folder Not Available",
                    systemImage: "folder.badge.questionmark",
                    description: Text("The folder is missing or can't be read.")
                )
            } else if rootEntries?.isEmpty == true {
                ContentUnavailableView(
                    "No Markdown Files",
                    systemImage: "folder",
                    description: Text("This folder has no markdown files or subfolders.")
                )
            } else {
                ContentUnavailableView(
                    "No File Selected",
                    systemImage: "doc.text",
                    description: Text("Select a file in the sidebar.")
                )
            }
        }
        // Mirrors ContentView's minimum frame so the window can't collapse with nothing selected.
        .frame(minWidth: 500, idealWidth: 720, minHeight: 600, idealHeight: 800)
        .background(theme.colors.background.dynamicColor)
    }

    /// Resets the tree to just `folder`'s top level (or to nothing), stopping every watcher.
    private func showFolder(_ folder: URL?) {
        watchers.values.forEach { $0.stop() }
        watchers = [:]
        listings = [:]
        expanded = []
        if let selection, folder.map({ FolderListing.isDescendant(selection, of: $0) }) != true {
            self.selection = nil
        }
        if let folder { load(folder) }
    }

    private func expansionBinding(for directory: URL) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(directory) },
            set: { isExpanded in
                if isExpanded {
                    guard !expanded.contains(directory) else { return }
                    expanded.insert(directory)
                    load(directory)
                } else {
                    unload(directory)
                }
            }
        )
    }

    /// Reads one directory level and starts watching it, if it isn't watched already.
    private func load(_ directory: URL) {
        refresh(directory)
        guard watchers[directory] == nil else { return }
        // kqueue on the directory vnode fires on entry add/remove/rename; the watcher's
        // rearm loop also recovers when the folder itself is deleted and later recreated.
        watchers[directory] = FileWatcher(url: directory) {
            DispatchQueue.main.async { refresh(directory) }
        }
    }

    /// Collapses `directory` and forgets everything beneath it, stopping the watchers.
    private func unload(_ directory: URL) {
        let subtree = expanded.filter {
            $0 == directory || FolderListing.isDescendant($0, of: directory)
        }
        for url in subtree {
            expanded.remove(url)
            listings[url] = nil
            watchers.removeValue(forKey: url)?.stop()
        }
    }

    private func refresh(_ directory: URL) {
        // A late watcher callback for a directory that was collapsed in the meantime.
        guard directory == folderURL || expanded.contains(directory) else { return }

        let entries = FolderListing.entries(in: directory)
        listings[directory] = .some(entries)
        let present = Set(entries?.map(\.url) ?? [])

        // Expanded subdirectories that vanished (deleted or renamed): drop their subtrees so
        // their watchers don't keep retrying a path that's gone.
        for url in expanded where isChild(url, of: directory) && !present.contains(url) {
            unload(url)
        }

        if let selection, isChild(selection, of: directory), !present.contains(selection) {
            self.selection = nil
        }
    }

    private func isChild(_ url: URL, of directory: URL) -> Bool {
        url.deletingLastPathComponent().standardizedFileURL.path
            == directory.standardizedFileURL.path
    }
}

/// One level of the sidebar tree; recurses into expanded directories.
private struct FolderTreeRows: View {
    let entries: [FolderEntry]
    let listings: [URL: [FolderEntry]?]
    let isExpanded: (URL) -> Binding<Bool>

    var body: some View {
        ForEach(entries) { entry in
            if entry.isDirectory {
                DisclosureGroup(isExpanded: isExpanded(entry.url)) {
                    children(of: entry.url)
                } label: {
                    // Disabled on the label only: on the DisclosureGroup it would also
                    // disable selection for every file nested inside.
                    Label(entry.name, systemImage: "folder")
                        .contentShape(Rectangle())
                        .onTapGesture { isExpanded(entry.url).wrappedValue.toggle() }
                        .selectionDisabled()
                }
            } else {
                Label(entry.name, systemImage: "doc.text")
                    .tag(entry.url)
            }
        }
    }

    @ViewBuilder
    private func children(of directory: URL) -> some View {
        switch listings[directory] {
        case .none:
            // Expanded but not read yet; loading is synchronous, so this is momentary.
            EmptyView()
        case .some(.none):
            placeholderRow("Can't be read")
        case .some(.some(let children)) where children.isEmpty:
            placeholderRow("No markdown files")
        case .some(.some(let children)):
            FolderTreeRows(entries: children, listings: listings, isExpanded: isExpanded)
        }
    }

    private func placeholderRow(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .selectionDisabled()
    }
}
