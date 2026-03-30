import SwiftUI
import Textual

struct ContentView: View {
    let document: MarkdownDocument
    @AppStorage("fontSize") private var fontSize: Double = 16
    @AppStorage("useSerifFont") private var useSerifFont: Bool = false

    var body: some View {
        ScrollView {
            StructuredText(markdown: document.text)
                .font(.system(size: CGFloat(fontSize), design: useSerifFont ? .serif : .default))
                .textual.textSelection(.enabled)
                .textual.highlighterTheme(.default)
                .padding(32)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textual.structuredTextStyle(.gitHub)
        }
        .scrollContentBackground(.hidden)
        .frame(minWidth: 500, idealWidth: 720, minHeight: 600, idealHeight: 800)
        .background(Color(.textBackgroundColor))
    }
}
