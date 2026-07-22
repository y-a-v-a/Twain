import SwiftUI
import TwainRendering
import AppKit

/// App-level appearance override, persisted in UserDefaults. `.system` follows the OS setting;
/// the other cases pin every window (including title bars and this Settings window) via
/// `NSApp.appearance` — theme colors are light/dark pairs, so they resolve per-appearance.
enum Appearance: String, CaseIterable {
    case system, light, dark

    static let defaultsKey = "appearance"

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// The stored choice, falling back to `.system` for a missing or unrecognized value.
    static func stored(in defaults: UserDefaults = .standard) -> Appearance {
        defaults.string(forKey: defaultsKey).flatMap(Appearance.init) ?? .system
    }

    @MainActor
    func apply() {
        NSApp.appearance = switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// Content of the app's Settings window (opened via the "Settings…" item that SwiftUI
/// synthesizes under the Twain menu from the `Settings` scene, with the standard ⌘, shortcut).
struct SettingsView: View {
    @AppStorage(Appearance.defaultsKey) private var appearance: Appearance = .system

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Appearance", selection: $appearance) {
                    ForEach(Appearance.allCases, id: \.self) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: appearance) { _, newValue in
                    newValue.apply()
                }
            }

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
