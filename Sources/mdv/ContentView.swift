import SwiftUI
import Textual

struct ContentView: View {
    let document: MarkdownDocument

    var body: some View {
        ScrollView {
            StructuredText(markdown: document.text)
                .textSelection(.enabled)
                .padding(32)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .frame(minWidth: 500, idealWidth: 720, minHeight: 400, idealHeight: 600)
        .background(Color(.textBackgroundColor))
    }
}
