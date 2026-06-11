import Testing
import Foundation
@testable import Twain

/// Covers the notification payloads `AgentCommandCenter` emits and the pending-find handoff for
/// `twain://open?…&search=`. The `.open` command itself is not run here — it launches files via
/// `NSWorkspace`, which has no place in a unit test; its pending store is tested directly.
@MainActor
struct AgentCommandCenterTests {
    private final class NotificationLog: @unchecked Sendable {
        private let lock = NSLock()
        private var _userInfos: [[AnyHashable: Any]] = []

        var userInfos: [[AnyHashable: Any]] {
            lock.lock()
            defer { lock.unlock() }
            return _userInfos
        }

        func record(_ userInfo: [AnyHashable: Any]?) {
            lock.lock()
            _userInfos.append(userInfo ?? [:])
            lock.unlock()
        }
    }

    /// Posting with `queue: nil` delivers synchronously on the posting thread, so the log is
    /// complete when `body` returns.
    private func notifications(
        _ name: Notification.Name,
        during body: () -> Void
    ) -> [[AnyHashable: Any]] {
        let log = NotificationLog()
        let token = NotificationCenter.default.addObserver(
            forName: name,
            object: nil,
            queue: nil
        ) { notification in
            log.record(notification.userInfo)
        }
        body()
        NotificationCenter.default.removeObserver(token)
        return log.userInfos
    }

    // MARK: - refresh

    @Test func refreshBroadcastsWithoutPath() {
        let center = AgentCommandCenter()
        let posts = notifications(.twainReloadDocument) {
            center.run(.refresh(path: nil))
        }
        #expect(posts.count == 1)
        #expect(posts[0][AgentCommandCenter.pathKey] == nil)
    }

    @Test func refreshTargetsTheResolvedPath() {
        let center = AgentCommandCenter()
        let posts = notifications(.twainReloadDocument) {
            center.run(.refresh(path: "/tmp/../tmp/notes.md"))
        }
        #expect(posts.count == 1)
        #expect(
            posts[0][AgentCommandCenter.pathKey] as? String
                == AgentCommandCenter.resolvedPath("/tmp/notes.md")
        )
    }

    // MARK: - find

    @Test func findCarriesQueryAndResolvedPath() {
        let center = AgentCommandCenter()
        let posts = notifications(.twainFind) {
            center.run(.find(query: "Install", path: "/docs/a.md"))
        }
        #expect(posts.count == 1)
        #expect(posts[0][AgentCommandCenter.queryKey] as? String == "Install")
        #expect(
            posts[0][AgentCommandCenter.pathKey] as? String
                == AgentCommandCenter.resolvedPath("/docs/a.md")
        )
    }

    @Test func findWithoutPathBroadcasts() {
        let center = AgentCommandCenter()
        let posts = notifications(.twainFind) {
            center.run(.find(query: "Install", path: nil))
        }
        #expect(posts.count == 1)
        #expect(posts[0][AgentCommandCenter.pathKey] == nil)
    }

    // MARK: - pending find (open?file=…&search=…)

    @Test func pendingFindIsConsumedExactlyOnce() {
        let center = AgentCommandCenter()
        center.storePendingFind(query: "Usage", forPath: "/docs/a.md")
        #expect(center.consumePendingFind(forPath: "/docs/a.md") == "Usage")
        #expect(center.consumePendingFind(forPath: "/docs/a.md") == nil)
    }

    @Test func pendingFindIgnoresOtherPaths() {
        let center = AgentCommandCenter()
        center.storePendingFind(query: "Usage", forPath: "/docs/a.md")
        #expect(center.consumePendingFind(forPath: "/docs/b.md") == nil)
        #expect(center.consumePendingFind(forPath: nil) == nil)
        // Misses must not consume the entry.
        #expect(center.consumePendingFind(forPath: "/docs/a.md") == "Usage")
    }

    @Test func newerPendingFindReplacesOlder() {
        let center = AgentCommandCenter()
        center.storePendingFind(query: "first", forPath: "/docs/a.md")
        center.storePendingFind(query: "second", forPath: "/docs/a.md")
        #expect(center.consumePendingFind(forPath: "/docs/a.md") == "second")
    }
}
