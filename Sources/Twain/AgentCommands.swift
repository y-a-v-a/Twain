import AppKit
import Foundation

extension Notification.Name {
    /// Asks open documents to re-read their file from disk. Carries an optional
    /// `AgentCommandCenter.pathKey` to target one file; without it, every document reloads.
    static let twainReloadDocument = Notification.Name("io.vincentb.twain.reload-document")

    /// Asks open documents to show the search bar with `AgentCommandCenter.queryKey` as the
    /// query, jumping to the first match. Optionally targeted via `AgentCommandCenter.pathKey`.
    static let twainFind = Notification.Name("io.vincentb.twain.find")
}

/// A command parsed from a `twain://` URL, the remote-control surface for scripts and agents:
///
///     twain://refresh                              reload every open document from disk
///     twain://refresh?file=/abs/path.md            reload one document
///     twain://search?q=text[&file=/abs/path.md]    search in open documents (or one document)
///     twain://open?file=/abs/path.md               open a file
///         [&search=text]                           …and jump to the first match of `text`
///         [&activate=0]                            …without bringing Twain to the front
///
/// File paths must be absolute; query values are percent-decoded by `URLComponents`.
enum AgentCommand: Equatable {
    case refresh(path: String?)
    case find(query: String, path: String?)
    case open(path: String, searchQuery: String?, activate: Bool)

    static func parse(_ url: URL) -> AgentCommand? {
        guard url.scheme?.lowercased() == "twain",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let command = components.host?.lowercased()
        else { return nil }

        var params: [String: String] = [:]
        for item in components.queryItems ?? [] {
            params[item.name] = item.value ?? ""
        }

        func absolutePath(_ value: String?) -> String? {
            guard let value, value.hasPrefix("/") else { return nil }
            return value
        }

        func nonEmpty(_ value: String?) -> String? {
            guard let value, !value.isEmpty else { return nil }
            return value
        }

        switch command {
        case "refresh":
            return .refresh(path: absolutePath(params["file"]))
        case "search":
            guard let query = nonEmpty(params["q"]) else { return nil }
            return .find(query: query, path: absolutePath(params["file"]))
        case "open":
            guard let path = absolutePath(params["file"]) else { return nil }
            return .open(
                path: path,
                searchQuery: nonEmpty(params["search"]),
                activate: params["activate"] != "0"
            )
        default:
            return nil
        }
    }
}

/// Executes `AgentCommand`s against the running app, bridging to the document windows via
/// `NotificationCenter` (a `DocumentGroup` offers no direct handle on its windows).
@MainActor
final class AgentCommandCenter {
    static let shared = AgentCommandCenter()

    static let pathKey = "path"
    static let queryKey = "query"

    /// Search queries from `twain://open?…&search=` for documents that aren't open yet, keyed by
    /// resolved path. The window created by the open consumes its entry when it appears.
    private var pendingFindByPath: [String: String] = [:]

    func handle(_ url: URL) {
        guard let command = AgentCommand.parse(url) else { return }
        run(command)
    }

    func run(_ command: AgentCommand) {
        switch command {
        case .refresh(let path):
            post(.twainReloadDocument, path: path.map(Self.resolvedPath))

        case .find(let query, let path):
            post(.twainFind, path: path.map(Self.resolvedPath), query: query)

        case .open(let path, let searchQuery, let activate):
            if let searchQuery {
                let resolved = Self.resolvedPath(path)
                storePendingFind(query: searchQuery, forPath: resolved)
                // If the document is already open, this applies the query right away (and the
                // receiving window clears the pending entry). Otherwise the entry waits for the
                // window the open below creates.
                post(.twainFind, path: resolved, query: searchQuery)
            }

            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = activate
            NSWorkspace.shared.open(
                [URL(fileURLWithPath: path).standardizedFileURL],
                withApplicationAt: Bundle.main.bundleURL,
                configuration: configuration
            )
        }
    }

    /// Separate from `run(.open…)` so tests can exercise the pending store without the
    /// `NSWorkspace` side effects of a real open.
    func storePendingFind(query: String, forPath path: String) {
        pendingFindByPath[path] = query
    }

    func consumePendingFind(forPath path: String?) -> String? {
        guard let path else { return nil }
        return pendingFindByPath.removeValue(forKey: path)
    }

    /// Canonical form used to match notification targets against a window's `fileURL`. Resolving
    /// symlinks matters on macOS, where e.g. `/tmp` is a symlink to `/private/tmp`.
    nonisolated static func resolvedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func post(_ name: Notification.Name, path: String?, query: String? = nil) {
        var userInfo: [String: Any] = [:]
        if let path { userInfo[Self.pathKey] = path }
        if let query { userInfo[Self.queryKey] = query }
        NotificationCenter.default.post(name: name, object: nil, userInfo: userInfo)
    }
}

/// Receives `twain://` URLs. The Apple Event handler is registered directly (and re-registered
/// after launch in case the SwiftUI runtime installed its own) because `DocumentGroup` offers no
/// reliable scene to hang `onOpenURL` on; `application(_:open:)` stays as a second route — both
/// funnel into `AgentCommandCenter`, whose commands are idempotent if a URL ever arrives twice.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let internetEventClass = AEEventClass(0x4755_524C) // 'GURL'
    private static let getURLEventID = AEEventID(0x4755_524C) // 'GURL'
    private static let directObjectKeyword = AEKeyword(0x2D2D_2D2D) // '----' (keyDirectObject)

    func applicationWillFinishLaunching(_ notification: Notification) {
        registerURLHandler()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        registerURLHandler()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        handle(urls: urls)
    }

    private func registerURLHandler() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:replyEvent:)),
            forEventClass: Self.internetEventClass,
            andEventID: Self.getURLEventID
        )
    }

    @objc private func handleGetURLEvent(
        _ event: NSAppleEventDescriptor,
        replyEvent: NSAppleEventDescriptor
    ) {
        guard
            let urlString = event
                .paramDescriptor(forKeyword: Self.directObjectKeyword)?
                .stringValue,
            let url = URL(string: urlString)
        else { return }
        handle(urls: [url])
    }

    private func handle(urls: [URL]) {
        for url in urls where url.scheme == "twain" {
            AgentCommandCenter.shared.handle(url)
        }
    }
}
