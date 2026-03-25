import SwiftUI
import Textual

struct ContentView: View {
    let document: MarkdownDocument
    @SceneStorage("fontSize") private var fontSize: Double = 16

    var body: some View {
        ScrollView {
            StructuredText(markdown: document.text)
                .font(.system(size: CGFloat(fontSize)))
                .textSelection(.enabled)
                .padding(32)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .frame(minWidth: 500, idealWidth: 720, minHeight: 400, idealHeight: 600)
        .background(Color(.textBackgroundColor))
        .focusedSceneValue(\.fontSize, $fontSize)
    }
}

struct FontSizeKey: FocusedValueKey {
    typealias Value = Binding<Double>
}

extension FocusedValues {
    var fontSize: Binding<Double>? {
        get { self[FontSizeKey.self] }
        set { self[FontSizeKey.self] = newValue }
    }
}
