import SwiftUI

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
}

@main
struct TwainApp: App {
    private let theme = Theme.load()

    var body: some Scene {
        DocumentGroup(viewing: MarkdownDocument.self) { file in
            ContentView(document: file.document, fileURL: file.fileURL, theme: theme)
        }
        .commands {
            RefreshCommands()
            FindCommands()
            FontSizeCommands()
            FontStyleCommands()
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
