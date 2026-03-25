import SwiftUI
import MarkdownUI

struct ContentView: View {
    let document: MarkdownDocument

    var body: some View {
        ScrollView {
            Markdown(document.text)
                .markdownTheme(.gitHub)
                .padding(24)
                .textSelection(.enabled)
                .frame(maxWidth: 800, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .frame(minWidth: 500, idealWidth: 720, minHeight: 400, idealHeight: 600)
        .background(Color(.textBackgroundColor))
    }
}
