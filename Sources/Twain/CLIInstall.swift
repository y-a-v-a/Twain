import AppKit
import SwiftUI

struct InstallCLICommands: Commands {
    var body: some Commands {
        CommandGroup(after: .appSettings) {
            Button("Install Command Line Tool…") {
                CLIInstaller.installAndReport()
            }
        }
    }
}

enum CLIInstaller {
    struct ResourceMissingError: LocalizedError {
        var errorDescription: String? {
            "The twain script is missing from the app bundle. Rebuild the app with build.sh."
        }
    }

    /// Copies the bundled `twain` script to `~/.bin/twain` (0755) and returns
    /// the destination. Split from the alert so tests can drive it directly.
    static func install(
        from source: URL? = Bundle.main.url(forResource: "twain", withExtension: nil),
        toDirectory binDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".bin")
    ) throws -> URL {
        guard let source else { throw ResourceMissingError() }
        let fm = FileManager.default
        try fm.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        let destination = binDirectory.appendingPathComponent("twain")
        // Remove first: copyItem refuses to overwrite, and replacing a symlink
        // in place would write through to its target.
        try? fm.removeItem(at: destination)
        try fm.copyItem(at: source, to: destination)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
        return destination
    }

    @MainActor
    static func installAndReport() {
        let alert = NSAlert()
        do {
            let destination = try install()
            alert.messageText = "Command Line Tool Installed"
            alert.informativeText = """
                The twain command was installed to \(destination.path).

                If ~/.bin is not on your PATH, add this to your shell profile:
                export PATH="$HOME/.bin:$PATH"
                """
        } catch {
            alert.alertStyle = .warning
            alert.messageText = "Could Not Install Command Line Tool"
            alert.informativeText = error.localizedDescription
        }
        alert.runModal()
    }
}
