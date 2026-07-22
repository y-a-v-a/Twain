import Cocoa
import Quartz

/// Spike: proves a hand-rolled (non-Xcode) Quick Look preview appex loads and
/// gets asked to preview Markdown files. Shows a label instead of rendering.
@objc(PreviewViewController)
final class PreviewViewController: NSViewController, @preconcurrency QLPreviewingController {
    private let label = NSTextField(labelWithString: "Twain Quick Look spike")

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        label.font = .systemFont(ofSize: 24, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        view = container
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        label.stringValue = "Twain spike: \(url.lastPathComponent)"
        handler(nil)
    }
}
