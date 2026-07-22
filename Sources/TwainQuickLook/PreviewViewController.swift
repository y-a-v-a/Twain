import Cocoa
import Quartz
import SwiftUI
import Textual
import TwainRendering

/// Quick Look preview: renders the Markdown file with the same Textual styles
/// as the app. Always uses the built-in default theme — the extension is
/// sandboxed and cannot read ~/.config/twain/theme.json. Relative images are
/// not rendered either: Quick Look grants access to the previewed file only.
@objc(PreviewViewController)
final class PreviewViewController: NSViewController, @preconcurrency QLPreviewingController {
    override func loadView() {
        view = NSView()
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        guard let data = try? Data(contentsOf: url),
              let markdown = String(data: data, encoding: .utf8)
                  ?? String(data: data, encoding: .utf16)
                  ?? String(data: data, encoding: .isoLatin1)
        else {
            handler(CocoaError(.fileReadCorruptFile))
            return
        }

        let hosting = NSHostingView(rootView: PreviewContent(markdown: markdown))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        handler(nil)
    }
}

struct PreviewContent: View {
    let markdown: String
    private let theme = Theme.default

    var body: some View {
        ScrollView {
            StructuredText(markdown: markdown)
                .font(.system(size: 16))
                .textual.textSelection(.enabled)
                .textual.highlighterTheme(theme.highlighterTheme)
                .padding(theme.contentInset)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textual.structuredTextStyle(ThemedStructuredTextStyle(theme: theme))
                .textual.listItemSpacing(.fontScaled(top: theme.resolvedList.resolvedItemSpacing))
        }
        .foregroundStyle(theme.colors.primary.dynamicColor)
        .background(theme.colors.background.dynamicColor)
    }
}
