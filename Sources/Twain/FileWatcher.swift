import Foundation

/// Watches a single file for on-disk changes so the rendered document can follow the file live.
///
/// Survives atomic save-and-rename cycles (the write pattern of most editors and agents: write a
/// temp file, rename it over the original) by re-opening a descriptor at the same path whenever
/// the watched inode is renamed or deleted.
final class FileWatcher: @unchecked Sendable {
    private let url: URL
    private let queue = DispatchQueue(label: "io.vincentb.twain.filewatcher")
    private let onChange: @Sendable () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var pendingNotify: DispatchWorkItem?
    private var stopped = false

    /// `onChange` is called on the watcher's private queue; callers that touch UI state must hop
    /// to the main actor themselves.
    init(url: URL, onChange: @escaping @Sendable () -> Void) {
        self.url = url
        self.onChange = onChange
        queue.async { [weak self] in self?.watch() }
    }

    deinit {
        // Backstop only — `stop()` is the intended teardown. Cancelling here runs the cancel
        // handler, which closes the descriptor; the rearm is skipped because `weak self` is gone.
        source?.cancel()
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            stopped = true
            pendingNotify?.cancel()
            source?.cancel()
            source = nil
        }
    }

    private func watch() {
        guard !stopped, source == nil else { return }

        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else {
            // The file is missing — likely mid-replace during an atomic save. Retry shortly.
            rearm(after: .milliseconds(250))
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .rename, .delete],
            queue: queue
        )

        source.setEventHandler { [weak self, weak source] in
            guard let self, let source else { return }
            self.scheduleNotify()
            if !source.data.isDisjoint(with: [.rename, .delete]) {
                // The inode we watch is gone; cancel so the cancel handler re-opens at the path.
                source.cancel()
            }
        }

        source.setCancelHandler { [weak self] in
            close(descriptor)
            guard let self, !self.stopped else { return }
            self.source = nil
            self.rearm(after: .milliseconds(100))
        }

        self.source = source
        source.resume()
    }

    private func rearm(after delay: DispatchTimeInterval) {
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.watch()
        }
    }

    /// One logical save often produces a burst of filesystem events; coalesce them into a single
    /// change callback. The delay also lets a writer finish before the document is re-read.
    private func scheduleNotify() {
        pendingNotify?.cancel()
        let work = DispatchWorkItem { [onChange] in onChange() }
        pendingNotify = work
        queue.asyncAfter(deadline: .now() + .milliseconds(100), execute: work)
    }
}
