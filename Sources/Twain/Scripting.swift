import AppKit
import Foundation

/// The scripting face of one open document window, vended to Cocoa Scripting as the `document`
/// class declared in `Twain.sdef`. A `DocumentGroup` app has no `NSDocument`, so each
/// `ContentView` registers one of these on appear and keeps its text properties current.
///
/// The Apple Event machinery calls into this class on the main thread; the `@objc` entry points
/// are nonisolated only because actor isolation cannot be added to `NSObject` overrides, and
/// immediately hop into `MainActor.assumeIsolated`.
@objc(ScriptableDocument)
final class ScriptableDocument: NSObject {
    /// Display name (the file name); resolves `document "README.md"` name specifiers via the
    /// sdef's `pnam` property.
    @objc let name: String

    /// Canonical absolute path (`AgentCommandCenter.resolvedPath` form), or nil for a document
    /// without a file. Scripting sees `missing value` for nil.
    @objc let path: String?

    /// The raw Markdown currently shown — follows Cmd+R and live reloads.
    @objc var sourceText: String = ""

    /// The plain text after Markdown parsing (the same string search runs against).
    @objc var renderedText: String = ""

    /// Closes the window this document belongs to; wired to SwiftUI's `dismiss` by the view.
    @MainActor var onClose: (() -> Void)?

    init(name: String, path: String?) {
        self.name = name
        self.path = path
    }

    override var objectSpecifier: NSScriptObjectSpecifier? {
        MainActor.assumeIsolated {
            guard
                let appDescription = NSApplication.shared.classDescription
                    as? NSScriptClassDescription,
                let index = ScriptingRegistry.shared.index(of: self)
            else { return nil }
            return NSIndexSpecifier(
                containerClassDescription: appDescription,
                containerSpecifier: nil,
                key: "scriptableDocuments",
                index: index
            )
        }
    }

    // MARK: - Command handlers (sdef responds-to)

    @objc(handleRefreshScriptCommand:)
    func handleRefreshScriptCommand(_ command: NSScriptCommand) -> Any? {
        MainActor.assumeIsolated { performRefresh() }
        return nil
    }

    @objc(handleSearchScriptCommand:)
    func handleSearchScriptCommand(_ command: NSScriptCommand) -> Any? {
        guard let query = command.evaluatedArguments?["query"] as? String, !query.isEmpty else {
            command.scriptErrorNumber = NSRequiredArgumentsMissingScriptError
            command.scriptErrorString = "A non-empty search string is required (search … for \"text\")."
            return nil
        }
        MainActor.assumeIsolated { performSearch(query: query) }
        return nil
    }

    @objc(handleCloseScriptCommand:)
    func handleCloseScriptCommand(_ command: NSScriptCommand) -> Any? {
        MainActor.assumeIsolated { performClose() }
        return nil
    }

    // MARK: - Implementations (separate so tests can call them without an NSScriptCommand)

    /// Routed through the same notification as twain://refresh so every window showing the file
    /// reloads. A document without a file is a no-op — `.refresh(path: nil)` would broadcast.
    @MainActor func performRefresh() {
        guard let path else { return }
        AgentCommandCenter.shared.run(.refresh(path: path))
    }

    @MainActor func performSearch(query: String) {
        guard let path else { return }
        AgentCommandCenter.shared.run(.find(query: query, path: path))
    }

    @MainActor func performClose() {
        onClose?()
    }
}

/// Open-document roster backing the application's `documents` scripting element, in window
/// registration order (`document 1` is the longest-open window).
@MainActor
final class ScriptingRegistry {
    static let shared = ScriptingRegistry()

    private(set) var documents: [ScriptableDocument] = []

    func register(_ document: ScriptableDocument) {
        documents.append(document)
    }

    func unregister(_ document: ScriptableDocument) {
        documents.removeAll { $0 === document }
    }

    func index(of document: ScriptableDocument) -> Int? {
        documents.firstIndex { $0 === document }
    }
}

extension NSApplication {
    /// The `documents` element of the sdef's application class. Declared on `NSApplication`
    /// itself so Cocoa Scripting's KVC lookup finds it directly on `NSApp` — the alternative,
    /// `application(_:delegateHandlesKey:)`, depends on SwiftUI's internal delegate forwarding.
    @objc var scriptableDocuments: [ScriptableDocument] {
        MainActor.assumeIsolated { ScriptingRegistry.shared.documents }
    }
}
