import SwiftUI
import Textual

struct ContentView: View {
    let document: MarkdownDocument
    let fileURL: URL?
    let theme: Theme
    @AppStorage("fontSize") private var fontSize: Double = 16
    @AppStorage("useSerifFont") private var useSerifFont: Bool = false
    @State private var text: String = ""

    private var font: Font {
        let family = useSerifFont ? theme.serifFontFamily : theme.sansSerifFontFamily
        if let family {
            return .custom(family, size: fontSize)
        }
        return .system(size: fontSize)
    }

    var body: some View {
        ScrollView {
            StructuredText(markdown: text)
                .font(font)
                .fontDesign(useSerifFont && theme.serifFontFamily == nil ? .serif : .default)
                .textual.textSelection(.enabled)
                .textual.highlighterTheme(theme.highlighterTheme)
                .padding(32)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textual.structuredTextStyle(ThemedStructuredTextStyle(theme: theme))
        }
        .foregroundStyle(theme.colors.primary.dynamicColor)
        .scrollContentBackground(.hidden)
        .frame(minWidth: 500, idealWidth: 720, minHeight: 600, idealHeight: 800)
        .background(theme.colors.background.dynamicColor)
        .onAppear { text = document.text }
        .focusedValue(\.refresh, {
            guard let url = fileURL,
                  let data = try? Data(contentsOf: url),
                  let string = String(data: data, encoding: .utf8)
                      ?? String(data: data, encoding: .utf16)
                      ?? String(data: data, encoding: .isoLatin1)
            else { return }
            text = string
        })
    }
}
