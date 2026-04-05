import SwiftUI

private struct RefreshActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var refresh: (() -> Void)? {
        get { self[RefreshActionKey.self] }
        set { self[RefreshActionKey.self] = newValue }
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
