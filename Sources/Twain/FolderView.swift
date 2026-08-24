import SwiftUI
import TwainRendering

/// A folder window: sidebar of the folder's top-level markdown files, selected file rendered
/// in the detail pane. The folder URL arrives via the "folder" WindowGroup's presentation value.
struct FolderWindowView: View {
    let folderURL: URL?
    let theme: Theme
    /// nil means the folder is missing/unreadable, as opposed to readable but empty.
    @State private var files: [URL]?
    @State private var selection: URL?
    @State private var folderWatcher: FileWatcher?

    var body: some View {
        NavigationSplitView {
            List(files ?? [], id: \.self, selection: $selection) { file in
                Text(file.lastPathComponent)
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
        .onAppear {
            refreshListing()
            startWatchingFolder()
        }
        .onDisappear {
            folderWatcher?.stop()
            folderWatcher = nil
        }
    }

    private var placeholder: some View {
        Group {
            if files == nil {
                ContentUnavailableView(
                    "Folder Not Available",
                    systemImage: "folder.badge.questionmark",
                    description: Text("The folder is missing or can't be read.")
                )
            } else if files?.isEmpty == true {
                ContentUnavailableView(
                    "No Markdown Files",
                    systemImage: "folder",
                    description: Text("This folder has no markdown files at its top level.")
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

    private func refreshListing() {
        guard let folderURL else {
            files = nil
            return
        }
        files = FolderListing.markdownFiles(in: folderURL)
        if let selection, files?.contains(selection) != true {
            self.selection = nil
        }
    }

    private func startWatchingFolder() {
        guard folderWatcher == nil, let folderURL else { return }
        // kqueue on the directory vnode fires on entry add/remove/rename; the watcher's
        // rearm loop also recovers when the folder itself is deleted and later recreated.
        folderWatcher = FileWatcher(url: folderURL) {
            DispatchQueue.main.async { refreshListing() }
        }
    }
}
