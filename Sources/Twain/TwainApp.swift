import SwiftUI

@main
struct TwainApp: App {
    var body: some Scene {
        DocumentGroup(viewing: MarkdownDocument.self) { file in
            ContentView(document: file.document)
        }
        .commands {
            FontSizeCommands()
            FontStyleCommands()
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
