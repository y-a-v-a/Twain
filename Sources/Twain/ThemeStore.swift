import Foundation
import Combine

/// Loads the theme and watches `~/.config/twain/theme.json`, re-publishing whenever the
/// file changes so edits apply without restarting the app.
///
/// Backed by a kqueue dispatch source (`DispatchSource.makeFileSystemObjectSource`), which is
/// event-driven — it costs nothing while the file is untouched and only does work on a change.
final class ThemeStore: ObservableObject {
    @Published private(set) var theme: Theme

    private let themeURL: URL
    private var source: DispatchSourceFileSystemObject?
    /// True while we're watching the parent directory (because the file doesn't exist yet)
    /// rather than the file itself.
    private var watchingDirectory = false

    init() {
        themeURL = Theme.userThemeURL
        // Seed the file (and its directory) up front so the watcher can arm directly on it.
        // Otherwise, on a fresh machine ~/.config/twain doesn't exist, arm() finds nothing to
        // watch, and edits made after the first "Edit Theme" wouldn't live-reload until relaunch.
        // For an existing file this also tops up keys added by newer app versions.
        Theme.syncUserThemeFile()
        theme = Theme.load()
        arm()
    }

    deinit { disarm() }

    /// Watch the most specific path available: the theme file if it exists, otherwise its
    /// parent directory so we notice the file being created.
    private func arm() {
        let fileFD = open(themeURL.path, O_EVTONLY)
        if fileFD >= 0 {
            watch(fd: fileFD, isDirectory: false)
            return
        }
        let dirFD = open(themeURL.deletingLastPathComponent().path, O_EVTONLY)
        if dirFD >= 0 {
            watch(fd: dirFD, isDirectory: true)
        }
        // If neither opens (e.g. ~/.config doesn't exist), live reload is simply unavailable
        // until the next launch; the app already fell back to the default theme.
    }

    private func watch(fd: CInt, isDirectory: Bool) {
        watchingDirectory = isDirectory
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename, .revoke],
            queue: .main
        )
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = src.data
            // Only republish when the decoded theme actually changed, so directory-watch noise
            // and no-op saves don't needlessly re-evaluate the view tree (Theme is Equatable).
            let next = Theme.load()
            if next != self.theme { self.theme = next }

            if self.watchingDirectory {
                // A directory entry changed — the file may have just appeared. Once it exists,
                // switch to watching it directly so in-place edits are caught too.
                if FileManager.default.fileExists(atPath: self.themeURL.path) {
                    self.rearm()
                }
            } else if !flags.isDisjoint(with: [.delete, .rename, .revoke]) {
                // Atomic saves (write-temp-then-rename, used by most editors) replace the
                // inode, so re-open the watch on the new file.
                self.rearm()
            }
        }
        // Each source closes its own descriptor, so a re-arm never races over a shared fd.
        src.setCancelHandler { close(fd) }
        source = src
        src.resume()
    }

    private func rearm() {
        // The old source's cancel handler closes its descriptor; opening a fresh one here is
        // safe because each source owns its own fd. After an atomic rename the replacement
        // file already exists at the path, so we can re-open immediately.
        disarm()
        arm()
    }

    private func disarm() {
        source?.cancel()
        source = nil
    }
}
