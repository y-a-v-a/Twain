import SwiftUI
import Textual

struct ContentView: View {
    let document: MarkdownDocument
    let fileURL: URL?
    let theme: Theme
    @AppStorage("fontSize") private var fontSize: Double = 16
    @AppStorage("useSerifFont") private var useSerifFont: Bool = false
    @State private var text: String
    @State private var isSearching: Bool = false
    @State private var searchState: SearchState
    @State private var searchCache: HighlightingMarkdownCache

    init(document: MarkdownDocument, fileURL: URL?, theme: Theme) {
        self.document = document
        self.fileURL = fileURL
        self.theme = theme
        let initialFontSize = UserDefaults.standard.object(forKey: "fontSize") as? Double ?? 16
        _text = State(initialValue: document.text)
        _searchState = State(
            initialValue: SearchState(layout: theme.blockLayout(fontSize: CGFloat(initialFontSize)))
        )
        _searchCache = State(initialValue: HighlightingMarkdownCache())
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
                    .id("content")
                    .font(font)
                    .fontDesign(useSerifFont && theme.serifFontFamily == nil ? .serif : .default)
                    .textual.textSelection(.enabled)
                    .textual.highlighterTheme(theme.highlighterTheme)
                    .padding(32)
                    .padding(.top, isSearching ? 36 : 0)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textual.structuredTextStyle(ThemedStructuredTextStyle(theme: theme))
                }

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
        }
        .onChange(of: fontSize, initial: true) {
            searchState.updateLayout(
                theme.blockLayout(fontSize: CGFloat(fontSize)),
                markdown: text,
                using: searchCache
            )
        }
        .focusedValue(\.refresh, {
            guard let url = fileURL,
                  let data = try? Data(contentsOf: url),
                  let string = String(data: data, encoding: .utf8)
                      ?? String(data: data, encoding: .utf16)
                      ?? String(data: data, encoding: .isoLatin1)
            else { return }
            text = string
        })
        .focusedValue(\.find, { isSearching = true })
    }

    private func dismissSearch() {
        isSearching = false
        searchState.reset()
    }

    private func scrollToMatch(proxy: ScrollViewProxy) {
        guard let fraction = searchState.currentMatchFraction else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo("content", anchor: UnitPoint(x: 0, y: fraction))
        }
    }
}
