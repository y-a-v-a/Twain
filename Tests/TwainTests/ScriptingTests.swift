import Testing
import Foundation
@testable import Twain

/// Covers the testable half of the AppleScript support: the document registry and the command
/// implementations behind the sdef's `refresh`/`search`/`close`. The Cocoa Scripting machinery
/// itself (sdef parsing, specifier resolution, Apple Event dispatch) only runs in the real app —
/// see Tests/applescript/run-tests.sh for the end-to-end checks.
@MainActor
struct ScriptingTests {
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

    // MARK: - Registry

    @Test func registersInWindowOrder() {
        let registry = ScriptingRegistry()
        let first = ScriptableDocument(name: "a.md", path: "/docs/a.md")
        let second = ScriptableDocument(name: "b.md", path: "/docs/b.md")
        registry.register(first)
        registry.register(second)
        #expect(registry.documents.count == 2)
        #expect(registry.index(of: first) == 0)
        #expect(registry.index(of: second) == 1)
    }

    @Test func unregisterRemovesOnlyThatDocument() {
        let registry = ScriptingRegistry()
        let staying = ScriptableDocument(name: "a.md", path: "/docs/a.md")
        let leaving = ScriptableDocument(name: "b.md", path: "/docs/b.md")
        registry.register(staying)
        registry.register(leaving)
        registry.unregister(leaving)
        #expect(registry.documents.count == 1)
        #expect(registry.index(of: staying) == 0)
        #expect(registry.index(of: leaving) == nil)
    }

    @Test func identicalNamesAreDistinctEntries() {
        // Two windows can show files with the same name from different directories.
        let registry = ScriptingRegistry()
        let one = ScriptableDocument(name: "notes.md", path: "/a/notes.md")
        let two = ScriptableDocument(name: "notes.md", path: "/b/notes.md")
        registry.register(one)
        registry.register(two)
        registry.unregister(one)
        #expect(registry.index(of: two) == 0)
    }

    // MARK: - Commands

    @Test func refreshPostsTargetedReload() {
        let document = ScriptableDocument(
            name: "a.md",
            path: AgentCommandCenter.resolvedPath("/docs/a.md")
        )
        let posts = notifications(.twainReloadDocument) { document.performRefresh() }
        #expect(posts.count == 1)
        #expect(
            posts[0][AgentCommandCenter.pathKey] as? String
                == AgentCommandCenter.resolvedPath("/docs/a.md")
        )
    }

    @Test func refreshWithoutFileDoesNotBroadcast() {
        // A nil path must not degrade into .refresh(path: nil), which reloads every document.
        let document = ScriptableDocument(name: "Untitled", path: nil)
        let posts = notifications(.twainReloadDocument) { document.performRefresh() }
        #expect(posts.isEmpty)
    }

    @Test func searchPostsQueryForThisDocument() {
        let document = ScriptableDocument(
            name: "a.md",
            path: AgentCommandCenter.resolvedPath("/docs/a.md")
        )
        let posts = notifications(.twainFind) { document.performSearch(query: "Install") }
        #expect(posts.count == 1)
        #expect(posts[0][AgentCommandCenter.queryKey] as? String == "Install")
        #expect(
            posts[0][AgentCommandCenter.pathKey] as? String
                == AgentCommandCenter.resolvedPath("/docs/a.md")
        )
    }

    @Test func searchWithoutFileDoesNotBroadcast() {
        let document = ScriptableDocument(name: "Untitled", path: nil)
        let posts = notifications(.twainFind) { document.performSearch(query: "Install") }
        #expect(posts.isEmpty)
    }

    @Test func closeInvokesTheWindowHandler() {
        let document = ScriptableDocument(name: "a.md", path: "/docs/a.md")
        var closed = false
        document.onClose = { closed = true }
        document.performClose()
        #expect(closed)
    }

    @Test func textPropertiesFollowUpdates() {
        let document = ScriptableDocument(name: "a.md", path: "/docs/a.md")
        document.sourceText = "# Hello"
        document.renderedText = "Hello"
        #expect(document.sourceText == "# Hello")
        #expect(document.renderedText == "Hello")
    }
}
