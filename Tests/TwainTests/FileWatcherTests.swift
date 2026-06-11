import Testing
import Foundation
@testable import Twain

/// End-to-end tests against the real filesystem. Timing-based by nature: the watcher arms
/// asynchronously on its own queue and debounces event bursts, so each step allows generous
/// margins to stay robust on slow CI machines.
struct FileWatcherTests {
    private final class EventCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var _count = 0

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return _count
        }

        func increment() {
            lock.lock()
            _count += 1
            lock.unlock()
        }
    }

    private func makeTempFile(contents: String = "# one\n") throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("twain-watcher-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("doc.md")
        try contents.write(to: file, atomically: false, encoding: .utf8)
        return file
    }

    private func eventually(
        timeout: Duration = .seconds(3),
        _ condition: @Sendable () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    /// Lets the watcher's async arming (and any pending re-arm) settle before the test writes.
    private func letWatcherArm() async throws {
        try await Task.sleep(for: .milliseconds(400))
    }

    @Test func detectsInPlaceWrite() async throws {
        let file = try makeTempFile()
        let counter = EventCounter()
        let watcher = FileWatcher(url: file) { counter.increment() }
        defer { watcher.stop() }

        try await letWatcherArm()
        try "# two\n".write(to: file, atomically: false, encoding: .utf8)

        #expect(await eventually { counter.count >= 1 })
    }

    @Test func survivesAtomicReplace() async throws {
        let file = try makeTempFile()
        let counter = EventCounter()
        let watcher = FileWatcher(url: file) { counter.increment() }
        defer { watcher.stop() }

        try await letWatcherArm()
        // atomically: true writes a temp file and renames it over the original — the pattern
        // of editors and agents that the watcher must survive.
        try "# two\n".write(to: file, atomically: true, encoding: .utf8)
        #expect(await eventually { counter.count >= 1 })

        // The watcher must have re-armed on the new inode and see the next save too.
        try await letWatcherArm()
        let countAfterFirstSave = counter.count
        try "# three\n".write(to: file, atomically: true, encoding: .utf8)
        #expect(await eventually { counter.count > countAfterFirstSave })
    }

    @Test func recoversWhenFileIsDeletedAndRecreated() async throws {
        let file = try makeTempFile()
        let counter = EventCounter()
        let watcher = FileWatcher(url: file) { counter.increment() }
        defer { watcher.stop() }

        try await letWatcherArm()
        try FileManager.default.removeItem(at: file)
        #expect(await eventually { counter.count >= 1 })

        try await letWatcherArm()
        let countAfterDelete = counter.count
        try "# back\n".write(to: file, atomically: false, encoding: .utf8)
        try await Task.sleep(for: .milliseconds(400)) // let the re-arm find the new file
        try "# back again\n".write(to: file, atomically: false, encoding: .utf8)
        #expect(await eventually { counter.count > countAfterDelete })
    }

    @Test func stopSilencesFurtherEvents() async throws {
        let file = try makeTempFile()
        let counter = EventCounter()
        let watcher = FileWatcher(url: file) { counter.increment() }

        try await letWatcherArm()
        watcher.stop()
        try await Task.sleep(for: .milliseconds(200)) // let the stop land on the watcher queue

        try "# two\n".write(to: file, atomically: false, encoding: .utf8)
        try await Task.sleep(for: .milliseconds(500)) // covers the debounce window
        #expect(counter.count == 0)
    }

    @Test func coalescesEventBursts() async throws {
        let file = try makeTempFile()
        let counter = EventCounter()
        let watcher = FileWatcher(url: file) { counter.increment() }
        defer { watcher.stop() }

        try await letWatcherArm()
        for i in 0..<5 {
            try "# revision \(i)\n".write(to: file, atomically: false, encoding: .utf8)
        }

        #expect(await eventually { counter.count >= 1 })
        try await Task.sleep(for: .milliseconds(300))
        // Five back-to-back writes inside one debounce window must not produce five reloads.
        #expect(counter.count < 5)
    }
}
