import SwiftUI
import MarkdownUI

struct ContentView: View {
    let document: MarkdownDocument

    var body: some View {
        ScrollView {
            Markdown(document.text)
                .padding(24)
                .textSelection(.enabled)
        }
        .frame(minWidth: 500, idealWidth: 720, minHeight: 400, idealHeight: 600)
    }
}
