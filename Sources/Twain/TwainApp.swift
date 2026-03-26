import SwiftUI

@main
struct TwainApp: App {
    var body: some Scene {
        DocumentGroup(viewing: MarkdownDocument.self) { file in
            ContentView(document: file.document)
        }
        .commands {
            FontSizeCommands()
        }
    }
}

struct FontSizeCommands: Commands {
    @FocusedValue(\.fontSize) private var fontSize

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Increase Font Size") {
                guard let fontSize else { return }
                fontSize.wrappedValue = min(fontSize.wrappedValue + 2, 40)
            }
            .keyboardShortcut("+", modifiers: .command)

            Button("Decrease Font Size") {
                guard let fontSize else { return }
                fontSize.wrappedValue = max(fontSize.wrappedValue - 2, 10)
            }
            .keyboardShortcut("-", modifiers: .command)

            Button("Reset Font Size") {
                fontSize?.wrappedValue = 16
            }
            .keyboardShortcut("0", modifiers: .command)
        }
    }
}
