import SwiftUI
import Textual

struct ContentView: View {
    let document: MarkdownDocument
    let fileURL: URL?
    let theme: Theme
    @AppStorage("fontSize") private var fontSize: Double = 16
    @AppStorage("useSerifFont") private var useSerifFont: Bool = false
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var isSearching: Bool = false
    @State private var searchState: SearchState
    @State private var searchCache: HighlightingMarkdownCache
    /// Measured size of the scroll viewport and the full scrollable content. Both feed the
    /// search scroll-to so the active match is positioned by real pixels, not just an estimate.
    @State private var viewportSize: CGSize = .zero
    @State private var contentHeight: CGFloat = 0
    @State private var fileWatcher: FileWatcher?
    /// This window's entry in the AppleScript `documents` collection.
    @State private var scriptHandle: ScriptableDocument?
    /// Search query from a `twain://open?…&search=` launch, held until the first layout pass so
    /// the scroll-to-match estimate has real geometry to work with.
    @State private var pendingFindQuery: String?

    /// Padding around the rendered content inside the scroll view. Mirrors the `.padding` modifiers
    /// below; used to map the estimated text fraction onto the measured content height. Sourced from
    /// the theme so it stays in sync with the rest of the styling.
    private var contentInset: CGFloat { theme.contentInset }
    private static let searchTopInset: CGFloat = 36

    init(document: MarkdownDocument, fileURL: URL?, theme: Theme) {
        self.document = document
        self.fileURL = fileURL
        self.theme = theme
        let initialFontSize = UserDefaults.standard.object(forKey: "fontSize") as? Double ?? 16
        _text = State(initialValue: document.text)
        _searchState = State(
            initialValue: SearchState(layout: theme.blockLayout(fontSize: CGFloat(initialFontSize)))
        )
        _searchCache = State(initialValue: HighlightingMarkdownCache(baseURL: fileURL))
    }

    private var font: Font {
        let family = useSerifFont ? theme.serifFontFamily : theme.sansSerifFontFamily
        if let family {
            return .custom(family, size: fontSize)
        }
        return .system(size: fontSize)
    }

    /// Markup string passed to StructuredText. When searching, a trigger suffix is appended
    /// so that changes to the query or current match index cause StructuredText's
    /// `onChange(of: markup)` to fire and re‑parse **in place** — no view destruction needed.
    private var displayText: String {
        guard isSearching, !searchState.query.isEmpty else { return text }
        let sep = HighlightingMarkdownParser.separator
        return text + "\(sep)\(searchState.renderRevision)"
    }

    private var parser: HighlightingMarkdownParser {
        HighlightingMarkdownParser(
            markdown: text,
            cache: searchCache,
            matches: isSearching ? searchState.matches : [],
            currentMatchIndex: searchState.currentMatchIndex
        )
    }

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .top) {
                ScrollView {
                    StructuredText(
                        displayText,
                        parser: parser
                    )
                    // Textual caches the resolved list item spacing in view state and only
                    // re-resolves it when a block's spacing preference changes, so a live theme
                    // edit of `list.itemSpacing` would otherwise render with the stale value.
                    // Keying the subtree's identity on the value forces a fresh resolve; the
                    // outer "content" id that search scrolling targets is unaffected.
                    .id(theme.resolvedList.resolvedItemSpacing)
                    .id("content")
                    .font(font)
                    .fontDesign(useSerifFont && theme.serifFontFamily == nil ? .serif : .default)
                    .textual.textSelection(.enabled)
                    .textual.highlighterTheme(theme.highlighterTheme)
                    .padding(contentInset)
                    .padding(.top, isSearching ? Self.searchTopInset : 0)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textual.structuredTextStyle(ThemedStructuredTextStyle(theme: theme))
                    .textual.listItemSpacing(.fontScaled(top: theme.resolvedList.resolvedItemSpacing))
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                        contentHeight = $0
                        applyPendingFindIfReady()
                    }
                }
                .onGeometryChange(for: CGSize.self) { $0.size } action: { viewportSize = $0 }

                if isSearching {
                    SearchBar(
                        searchState: searchState,
                        onDismiss: { dismissSearch() }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.15), value: isSearching)
            .onChange(of: searchState.scrollTarget) {
                guard isSearching, searchState.hasMatches else { return }
                scrollToMatch(proxy: proxy)
            }
            .focusedValue(\.findNext, {
                guard isSearching else { return }
                searchState.nextMatch()
            })
            .focusedValue(\.findPrevious, {
                guard isSearching else { return }
                searchState.previousMatch()
            })
        }
        .foregroundStyle(theme.colors.primary.dynamicColor)
        .scrollContentBackground(.hidden)
        .frame(minWidth: 500, idealWidth: 720, minHeight: 600, idealHeight: 800)
        .background(theme.colors.background.dynamicColor)
        .onChange(of: text, initial: true) {
            searchState.updateDocument(markdown: text, using: searchCache)
            scriptHandle?.sourceText = text
            scriptHandle?.renderedText = searchCache.plainText
        }
        .onChange(of: fontSize, initial: true) { pushLayout() }
        .onChange(of: viewportSize.width) { pushLayout() }
        .onChange(of: theme) { pushLayout() }
        .focusedValue(\.refresh, { reloadFromDisk() })
        .focusedValue(\.find, { isSearching = true })
        .focusedValue(\.printDocument, {
            let job = printJob
            let window = NSApp.keyWindow
            Task { await DocumentPrinter.runPrintPanel(job: job, attachedTo: window) }
        })
        .focusedValue(\.exportPDF, {
            DocumentPrinter.presentPDFExportPanel(job: printJob, attachedTo: NSApp.keyWindow)
        })
        .onAppear {
            startWatchingFile()
            registerScriptHandle()
            pendingFindQuery = AgentCommandCenter.shared.consumePendingFind(forPath: resolvedFilePath)
            applyPendingFindIfReady()
        }
        .onDisappear {
            fileWatcher?.stop()
            fileWatcher = nil
            if let scriptHandle {
                ScriptingRegistry.shared.unregister(scriptHandle)
            }
            scriptHandle = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .twainReloadDocument)) { notification in
            guard matchesThisDocument(notification) else { return }
            reloadFromDisk()
        }
        .onReceive(NotificationCenter.default.publisher(for: .twainFind)) { notification in
            guard matchesThisDocument(notification),
                  let query = notification.userInfo?[AgentCommandCenter.queryKey] as? String,
                  !query.isEmpty
            else { return }
            // Also clears any pending entry an `open` command stored for this file, so the query
            // doesn't resurface the next time a window for it appears.
            _ = AgentCommandCenter.shared.consumePendingFind(forPath: resolvedFilePath)
            beginSearch(query: query)
        }
    }

    /// Snapshot of everything the print pipeline needs to reproduce this window's rendering.
    private var printJob: PrintJob {
        PrintJob(
            markdown: text,
            baseURL: fileURL,
            theme: theme,
            fontSize: fontSize,
            useSerifFont: useSerifFont,
            title: fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
        )
    }

    private var resolvedFilePath: String? {
        fileURL.map { AgentCommandCenter.resolvedPath($0.path) }
    }

    /// Notifications without a path are broadcasts; with a path they target one file.
    private func matchesThisDocument(_ notification: Notification) -> Bool {
        guard let path = notification.userInfo?[AgentCommandCenter.pathKey] as? String else {
            return true
        }
        return path == resolvedFilePath
    }

    private func reloadFromDisk() {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let string = String(data: data, encoding: .utf8)
                  ?? String(data: data, encoding: .utf16)
                  ?? String(data: data, encoding: .isoLatin1)
        else { return }
        text = string
    }

    private func startWatchingFile() {
        guard fileWatcher == nil, let path = resolvedFilePath else { return }
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
        let handle = ScriptableDocument(
            name: fileURL?.lastPathComponent ?? "Untitled",
            path: resolvedFilePath
        )
        handle.sourceText = text
        handle.renderedText = searchCache.plainText
        handle.onClose = { dismiss() }
        ScriptingRegistry.shared.register(handle)
        scriptHandle = handle
    }

    private func beginSearch(query: String) {
        isSearching = true
        searchState.updateQuery(query)
    }

    private func applyPendingFindIfReady() {
        guard let query = pendingFindQuery, contentHeight > 0 else { return }
        pendingFindQuery = nil
        beginSearch(query: query)
    }

    private func dismissSearch() {
        isSearching = false
        searchState.reset()
    }

    private func pushLayout() {
        let textWidth = max(viewportSize.width - 2 * contentInset, 0)
        searchState.updateLayout(
            theme.blockLayout(fontSize: CGFloat(fontSize), contentWidth: textWidth),
            markdown: text,
            using: searchCache
        )
    }

    private func scrollToMatch(proxy: ScrollViewProxy) {
        guard let fraction = searchState.currentMatchFraction else { return }

        let viewport = viewportSize.height
        let content = contentHeight

        // `scrollTo(anchor:)` aligns the content point at `anchor.y` with the same fraction of the
        // viewport, so the on-screen error is the estimate error times (content - viewport). To keep
        // that bounded we choose the anchor that lands the *measured* match position a little below
        // the top (clearing the search bar), clamped so the ends of the document still scroll fully.
        let anchorY: CGFloat
        if content > viewport, viewport > 0 {
            let topInset = contentInset + (isSearching ? Self.searchTopInset : 0)
            let textHeight = max(content - topInset - contentInset, 1)
            let matchY = topInset + fraction * textHeight

            let targetWithinViewport: CGFloat = 0.3
            anchorY = min(max((matchY - targetWithinViewport * viewport) / (content - viewport), 0), 1)
        } else {
            anchorY = fraction
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo("content", anchor: UnitPoint(x: 0, y: anchorY))
        }
    }
}
