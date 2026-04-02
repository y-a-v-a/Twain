import SwiftUI
import Textual

struct ContentView: View {
    let document: MarkdownDocument
    let theme: Theme
    @AppStorage("fontSize") private var fontSize: Double = 16
    @AppStorage("useSerifFont") private var useSerifFont: Bool = false

    var body: some View {
        ScrollView {
            StructuredText(markdown: document.text)
                .font(.system(size: fontSize))
                .fontDesign(useSerifFont ? .serif : .default)
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
    }
}
