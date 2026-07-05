import SwiftUI
import AppKit

/// Content of the app's Settings window (opened via the "Settings…" item that SwiftUI
/// synthesizes under the Twain menu from the `Settings` scene, with the standard ⌘, shortcut).
struct SettingsView: View {
    var body: some View {
        Form {
            Section("Theme") {
                LabeledContent("Configuration file") {
                    Text(Theme.userThemeURL.path)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Button("Edit Theme…") { editTheme() }
            }

            Section {
                Text("Edits to the theme file are applied live — no need to restart Twain.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Open the user's theme file in their default editor for JSON, creating it from the
    /// default theme first if it doesn't exist yet (so the editor always has a valid file)
    /// and topping up any keys added since the file was written.
    private func editTheme() {
        Theme.syncUserThemeFile()
        NSWorkspace.shared.open(Theme.userThemeURL)
    }
}
