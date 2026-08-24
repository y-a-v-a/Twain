import SwiftUI
import TwainRendering

private struct RefreshActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct FindActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct FindNextActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct FindPreviousActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct PrintDocumentActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct ExportPDFActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var refresh: (() -> Void)? {
        get { self[RefreshActionKey.self] }
        set { self[RefreshActionKey.self] = newValue }
    }

    var find: (() -> Void)? {
        get { self[FindActionKey.self] }
        set { self[FindActionKey.self] = newValue }
    }

    var findNext: (() -> Void)? {
        get { self[FindNextActionKey.self] }
        set { self[FindNextActionKey.self] = newValue }
    }

    var findPrevious: (() -> Void)? {
        get { self[FindPreviousActionKey.self] }
        set { self[FindPreviousActionKey.self] = newValue }
    }

    var printDocument: (() -> Void)? {
        get { self[PrintDocumentActionKey.self] }
        set { self[PrintDocumentActionKey.self] = newValue }
    }

    var exportPDF: (() -> Void)? {
        get { self[ExportPDFActionKey.self] }
        set { self[ExportPDFActionKey.self] = newValue }
    }
}

@main
struct TwainApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var themeStore = ThemeStore()

    var body: some Scene {
        DocumentGroup(viewing: MarkdownDocument.self) { file in
            ContentView(document: file.document, fileURL: file.fileURL, theme: themeStore.theme)
        }
        .commands {
            InstallCLICommands()
            OpenFolderCommands()
            RefreshCommands()
            PrintCommands()
            FindCommands()
            FontSizeCommands()
            FontStyleCommands()
        }

        // Folder windows. `for: URL.self` gives restoration and dedup (reopening the same
        // folder fronts the existing window); `commandsRemoved` keeps this scene from adding
        // its own "New Window" item next to the DocumentGroup's.
        WindowGroup(id: "folder", for: URL.self) { $folderURL in
            FolderWindowView(folderURL: folderURL, theme: themeStore.theme)
        }
        .commandsRemoved()

        Settings {
            SettingsView()
        }
    }
}

struct OpenFolderCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // Registering here (not in a view) keeps the twain://open-folder route alive even when
        // no window exists; commands are built during launch. Idempotent, and the command
        // center queues folder opens that arrive before this runs.
        let _ = AgentCommandCenter.shared.registerFolderWindowOpener { url in
            openWindow(id: "folder", value: url)
        }

        CommandGroup(after: .newItem) {
            Button("Open Folder…") {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.allowsMultipleSelection = false
                panel.prompt = "Open"
                if panel.runModal() == .OK, let url = panel.url {
                    openWindow(id: "folder", value: url.standardizedFileURL)
                }
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
        }
    }
}

struct RefreshCommands: Commands {
    @FocusedValue(\.refresh) private var refresh

    var body: some Commands {
        CommandGroup(after: .saveItem) {
            Button("Refresh") {
                refresh?()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(refresh == nil)
        }
    }
}

struct PrintCommands: Commands {
    @FocusedValue(\.printDocument) private var printDocument
    @FocusedValue(\.exportPDF) private var exportPDF

    var body: some Commands {
        CommandGroup(replacing: .printItem) {
            Button("Export as PDF…") {
                exportPDF?()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(exportPDF == nil)

            Button("Print…") {
                printDocument?()
            }
            .keyboardShortcut("p", modifiers: .command)
            .disabled(printDocument == nil)
        }
    }
}

struct FindCommands: Commands {
    @FocusedValue(\.find) private var find
    @FocusedValue(\.findNext) private var findNext
    @FocusedValue(\.findPrevious) private var findPrevious

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Button("Find…") {
                find?()
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(find == nil)

            Button("Find Next") {
                findNext?()
            }
            .keyboardShortcut("g", modifiers: .command)
            .disabled(findNext == nil)

            Button("Find Previous") {
                findPrevious?()
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .disabled(findPrevious == nil)
        }
    }
}

struct FontStyleCommands: Commands {
    @AppStorage("useSerifFont") private var useSerifFont: Bool = false

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Toggle("Serif Font", isOn: $useSerifFont)
                .keyboardShortcut("f", modifiers: [.command, .shift])
        }
    }
}

struct FontSizeCommands: Commands {
    @AppStorage("fontSize") private var fontSize: Double = 16

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Increase Font Size") {
                fontSize = min(fontSize + 2, 40)
            }
            .keyboardShortcut("+", modifiers: .command)

            Button("Decrease Font Size") {
                fontSize = max(fontSize - 2, 10)
            }
            .keyboardShortcut("-", modifiers: .command)

            Button("Reset Font Size") {
                fontSize = 16
            }
            .keyboardShortcut("0", modifiers: .command)
        }
    }
}
