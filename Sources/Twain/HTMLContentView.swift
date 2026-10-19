import AppKit
import SwiftUI
import TwainRendering
import WebKit

/// Routes a document window to its renderer by file kind. Used by both the `DocumentGroup` and
/// the folder window's detail pane.
struct DocumentWindowContent: View {
    let document: MarkdownDocument?
    let fileURL: URL?
    let theme: Theme

    init(document: MarkdownDocument, fileURL: URL?, theme: Theme) {
        self.document = document
        self.fileURL = fileURL
        self.theme = theme
    }

    /// Folder-window entry point: the file is loaded directly, bypassing `FileDocument`.
    init(fileURL: URL, theme: Theme) {
        self.document = nil
        self.fileURL = fileURL
        self.theme = theme
    }

    var body: some View {
        if let fileURL, DocumentKind(url: fileURL) == .html {
            HTMLContentView(fileURL: fileURL)
        } else if let document {
            ContentView(document: document, fileURL: fileURL, theme: theme)
        } else if let fileURL {
            ContentView(fileURL: fileURL, theme: theme)
        }
    }
}

// MARK: - Navigation policy

/// Twain shows one local HTML file per window; it is not a browser. The only main-frame load
/// allowed is the document itself (initial load, reloads, `#fragment` jumps). Clicked links leave
/// the window: viewable local files open in Twain, everything else in its default app. Script
/// redirects, form submissions, and other non-user navigations are dropped.
///
/// Pure logic, separated from the WebKit delegate so it can be unit tested.
enum HTMLNavigationPolicy {
    enum Decision: Equatable {
        case allow
        case openInTwain(URL)
        case openExternally(URL)
        case cancel
    }

    static let externalSchemes: Set<String> = ["http", "https", "mailto"]

    static func decide(
        url: URL?,
        documentURL: URL,
        isMainFrame: Bool,
        isUserLink: Bool
    ) -> Decision {
        guard let url else { return .cancel }

        if isSameDocument(url, documentURL) {
            return .allow
        }

        // Iframes keep their own browsing (embeds, srcdoc demos); only a click that would take
        // over the window is redirected.
        if !isMainFrame && !isUserLink {
            return .allow
        }

        guard isUserLink else { return .cancel }

        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "file" {
            let ext = url.pathExtension.lowercased()
            return FolderListing.viewableExtensions.contains(ext)
                ? .openInTwain(url)
                : .openExternally(url)
        }
        return externalSchemes.contains(scheme) ? .openExternally(url) : .cancel
    }

    /// Same file, ignoring fragment and query (a query on a file URL doesn't change the file).
    static func isSameDocument(_ url: URL, _ documentURL: URL) -> Bool {
        guard url.isFileURL, documentURL.isFileURL else { return false }
        return url.standardizedFileURL.path == documentURL.standardizedFileURL.path
    }
}

// MARK: - Page controller

/// Owns one document window's `WKWebView` and serves as its navigation/UI delegate. Lives in the
/// view's `@State`, created on first appearance.
@MainActor
final class HTMLPage: NSObject, WKNavigationDelegate, WKUIDelegate {
    let fileURL: URL
    let webView: WKWebView

    /// Called after every completed load (initial and reloads).
    var onLoad: (() -> Void)?

    /// Scroll offset captured before a reload, restored once the new load finishes.
    private var pendingScroll: CGPoint?

    init(fileURL: URL, zoom: Double) {
        self.fileURL = fileURL
        let configuration = WKWebViewConfiguration()
        configuration.preferences.isElementFullscreenEnabled = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsMagnification = true
        // Right-click → Inspect Element: these pages are often generated and iterated on.
        webView.isInspectable = true
        webView.pageZoom = zoom
        load()
    }

    /// Read access covers the file's folder so sibling stylesheets, scripts, and images load.
    private func load() {
        webView.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
    }

    /// Reloads from disk, keeping the scroll position so an agent's repeated writes don't throw
    /// the reader back to the top. Skipped while the file is missing (mid atomic replace, or
    /// deleted) so the last good render stays up.
    func reload() async {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        if let offset = try? await webView.callAsyncJavaScript(
            "return [window.scrollX, window.scrollY];",
            contentWorld: .defaultClient
        ) as? [Double], offset.count == 2 {
            pendingScroll = CGPoint(x: offset[0], y: offset[1])
        }
        load()
    }

    /// The page's visible text, for the scripting `rendered text` property.
    func renderedText() async -> String {
        let text = try? await webView.callAsyncJavaScript(
            "return document.body ? document.body.innerText : '';",
            contentWorld: .defaultClient
        )
        return text as? String ?? ""
    }

    // MARK: Find

    /// Finds `query`, selecting and scrolling to the match. `restart` clears the selection first
    /// so an edited query searches from the top rather than past the previous match. Returns the
    /// approximate number of occurrences in the page text, or nil when WebKit found none.
    func find(_ query: String, backwards: Bool = false, restart: Bool = false) async -> Int? {
        guard !query.isEmpty else { return nil }
        if restart {
            _ = try? await webView.callAsyncJavaScript(
                "window.getSelection()?.removeAllRanges();",
                contentWorld: .defaultClient
            )
        }
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.caseSensitive = false
        configuration.wraps = true
        guard let result = try? await webView.find(query, configuration: configuration),
              result.matchFound
        else { return nil }
        // WebKit's matcher and innerText can disagree (hidden text, diacritics); never report
        // fewer than the one match WebKit just selected.
        let count = await countMatches(query)
        return max(count, 1)
    }

    /// Case-insensitive occurrences of `query` in the page's visible text. Doesn't move the
    /// selection or scroll position.
    func countMatches(_ query: String) async -> Int {
        guard !query.isEmpty else { return 0 }
        let count = try? await webView.callAsyncJavaScript(
            """
            const text = (document.body ? document.body.innerText : '').toLocaleLowerCase();
            const needle = query.toLocaleLowerCase();
            let count = 0;
            for (let i = text.indexOf(needle); i !== -1; i = text.indexOf(needle, i + needle.length)) {
                count++;
            }
            return count;
            """,
            arguments: ["query": query],
            contentWorld: .defaultClient
        )
        return count as? Int ?? 0
    }

    // MARK: Print

    /// WebKit lays the page out for print itself (honoring `@media print`). The print view needs
    /// a real frame or the output comes out blank.
    func printOperation(info: NSPrintInfo, title: String) -> NSPrintOperation {
        info.verticalPagination = .automatic
        let operation = webView.printOperation(with: info)
        operation.view?.frame = webView.bounds
        operation.jobTitle = title
        return operation
    }

    // MARK: WKNavigationDelegate

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        let decision = HTMLNavigationPolicy.decide(
            url: navigationAction.request.url,
            documentURL: fileURL,
            isMainFrame: navigationAction.targetFrame?.isMainFrame ?? true,
            isUserLink: navigationAction.navigationType == .linkActivated
        )
        perform(decision)
        return decision == .allow ? .allow : .cancel
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let offset = pendingScroll {
            pendingScroll = nil
            Task {
                _ = try? await webView.callAsyncJavaScript(
                    "window.scrollTo(x, y);",
                    arguments: ["x": offset.x, "y": offset.y],
                    contentWorld: .defaultClient
                )
            }
        }
        onLoad?()
    }

    // MARK: WKUIDelegate

    /// `target="_blank"` links and `window.open`: never a new web view, same policy as clicks.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        let decision = HTMLNavigationPolicy.decide(
            url: navigationAction.request.url,
            documentURL: fileURL,
            isMainFrame: true,
            isUserLink: navigationAction.navigationType == .linkActivated
        )
        perform(decision)
        return nil
    }

    private func perform(_ decision: HTMLNavigationPolicy.Decision) {
        switch decision {
        case .allow, .cancel:
            break
        case .openInTwain(let url):
            NSWorkspace.shared.open(
                [url],
                withApplicationAt: Bundle.main.bundleURL,
                configuration: NSWorkspace.OpenConfiguration()
            )
        case .openExternally(let url):
            NSWorkspace.shared.open(url)
        }
    }
}

private struct HTMLWebView: NSViewRepresentable {
    let page: HTMLPage

    func makeNSView(context: Context) -> WKWebView { page.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

// MARK: - Window content

/// An HTML document window. The page renders with its own styling — Twain's theme doesn't
/// apply — while refresh, live reload, find, print, export, font size (as page zoom), and the
/// `twain://` and AppleScript surfaces behave as in Markdown windows.
struct HTMLContentView: View {
    let fileURL: URL
    @AppStorage("fontSize") private var fontSize: Double = 16
    @Environment(\.dismiss) private var dismiss
    @State private var page: HTMLPage?
    @State private var isSearching = false
    @State private var findQuery = ""
    /// Occurrences of `findQuery`; nil when nothing was found.
    @State private var findCount: Int?
    @State private var fileWatcher: FileWatcher?
    @State private var scriptHandle: ScriptableDocument?
    /// Search query from a `twain://open?…&search=` launch, applied once the page has loaded.
    @State private var pendingFindQuery: String?

    private var zoom: Double { fontSize / 16 }

    var body: some View {
        ZStack(alignment: .top) {
            if let page {
                HTMLWebView(page: page)
                    .padding(.top, isSearching ? 44 : 0)
            }

            if isSearching {
                FindBar(
                    query: $findQuery,
                    status: findQuery.isEmpty ? nil : findStatus,
                    canNavigate: findCount != nil,
                    onNext: { find(backwards: false) },
                    onPrevious: { find(backwards: true) },
                    onDismiss: { isSearching = false }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isSearching)
        .frame(minWidth: 500, idealWidth: 720, minHeight: 600, idealHeight: 800)
        .onChange(of: findQuery) { find(backwards: false, restart: true) }
        .onChange(of: fontSize) { page?.webView.pageZoom = zoom }
        .focusedSceneValue(\.refresh, { reload() })
        .focusedSceneValue(\.find, { isSearching = true })
        .focusedSceneValue(\.findNext, {
            guard isSearching else { return }
            find(backwards: false)
        })
        .focusedSceneValue(\.findPrevious, {
            guard isSearching else { return }
            find(backwards: true)
        })
        .focusedSceneValue(\.printDocument, { runPrintPanel() })
        .focusedSceneValue(\.exportPDF, { presentPDFExportPanel() })
        .onAppear {
            if page == nil {
                page = HTMLPage(fileURL: fileURL, zoom: zoom)
            }
            // Cleared on disappear: the closure captures this view's state, which holds the page.
            page?.onLoad = { pageDidLoad() }
            startWatchingFile()
            registerScriptHandle()
            pendingFindQuery = AgentCommandCenter.shared.consumePendingFind(forPath: resolvedFilePath)
        }
        .onDisappear {
            page?.onLoad = nil
            fileWatcher?.stop()
            fileWatcher = nil
            if let scriptHandle {
                ScriptingRegistry.shared.unregister(scriptHandle)
            }
            scriptHandle = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .twainReloadDocument)) { notification in
            guard matchesThisDocument(notification) else { return }
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .twainFind)) { notification in
            guard matchesThisDocument(notification),
                  let query = notification.userInfo?[AgentCommandCenter.queryKey] as? String,
                  !query.isEmpty
            else { return }
            _ = AgentCommandCenter.shared.consumePendingFind(forPath: resolvedFilePath)
            beginSearch(query: query)
        }
    }

    private var findStatus: String {
        guard let findCount else { return "No matches" }
        return findCount == 1 ? "1 match" : "\(findCount) matches"
    }

    private var title: String {
        fileURL.deletingPathExtension().lastPathComponent
    }

    private var resolvedFilePath: String {
        AgentCommandCenter.resolvedPath(fileURL.path)
    }

    /// Notifications without a path are broadcasts; with a path they target one file.
    private func matchesThisDocument(_ notification: Notification) -> Bool {
        guard let path = notification.userInfo?[AgentCommandCenter.pathKey] as? String else {
            return true
        }
        return path == resolvedFilePath
    }

    private func reload() {
        guard let page else { return }
        Task { await page.reload() }
    }

    private func pageDidLoad() {
        scriptHandle?.sourceText = MarkdownText.load(from: fileURL) ?? ""
        if let page {
            Task { scriptHandle?.renderedText = await page.renderedText() }
        }
        if let query = pendingFindQuery {
            pendingFindQuery = nil
            beginSearch(query: query)
        } else if isSearching, !findQuery.isEmpty, let page {
            // Recount against the reloaded page without re-finding: a find would scroll to the
            // first match and undo the restored scroll position.
            let query = findQuery
            Task {
                let count = await page.countMatches(query)
                guard query == findQuery else { return }
                findCount = count > 0 ? count : nil
            }
        }
    }

    private func beginSearch(query: String) {
        isSearching = true
        if findQuery == query {
            find(backwards: false, restart: true)
        } else {
            findQuery = query // onChange runs the search
        }
    }

    private func find(backwards: Bool, restart: Bool = false) {
        guard let page else { return }
        let query = findQuery
        guard !query.isEmpty else {
            findCount = nil
            return
        }
        Task {
            let count = await page.find(query, backwards: backwards, restart: restart)
            // Drop results for a query the user has typed past.
            guard query == findQuery else { return }
            findCount = count
        }
    }

    private func runPrintPanel() {
        guard let page else { return }
        let info = NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo()
        let operation = page.printOperation(info: info, title: title)
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        if let window = NSApp.keyWindow {
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            operation.run()
        }
    }

    private func presentPDFExportPanel() {
        guard let page else { return }
        let window = NSApp.keyWindow
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = title + ".pdf"
        let title = self.title
        let export: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            // Run after the save sheet has closed; a print operation can't run modal on a
            // window that is still presenting a sheet.
            Task { @MainActor in
                let info = NSPrintInfo(dictionary: [.jobSavingURL: url])
                info.jobDisposition = .save
                let operation = page.printOperation(info: info, title: title)
                operation.showsPrintPanel = false
                operation.showsProgressPanel = false
                if let window {
                    operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
                } else {
                    operation.run()
                }
            }
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: export)
        } else {
            export(panel.runModal())
        }
    }

    private func startWatchingFile() {
        guard fileWatcher == nil else { return }
        let path = resolvedFilePath
        // Routed through the same notification as twain://refresh so every window showing this
        // file reloads, and on the main run loop where onReceive expects it.
        fileWatcher = FileWatcher(url: URL(fileURLWithPath: path)) {
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .twainReloadDocument,
                    object: nil,
                    userInfo: [AgentCommandCenter.pathKey: path]
                )
            }
        }
    }

    private func registerScriptHandle() {
        guard scriptHandle == nil else { return }
        let handle = ScriptableDocument(name: fileURL.lastPathComponent, path: resolvedFilePath)
        handle.sourceText = MarkdownText.load(from: fileURL) ?? ""
        handle.onClose = { dismiss() }
        ScriptingRegistry.shared.register(handle)
        scriptHandle = handle
    }
}
