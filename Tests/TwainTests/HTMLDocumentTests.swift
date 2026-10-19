import Testing
import Foundation
@testable import Twain

struct HTMLDocumentTests {
    private let document = URL(fileURLWithPath: "/tmp/site/index.html")

    private func decide(
        _ string: String,
        isMainFrame: Bool = true,
        isUserLink: Bool = true
    ) -> HTMLNavigationPolicy.Decision {
        HTMLNavigationPolicy.decide(
            url: URL(string: string),
            documentURL: document,
            isMainFrame: isMainFrame,
            isUserLink: isUserLink
        )
    }

    // MARK: DocumentKind

    @Test func documentKindFollowsExtension() {
        #expect(DocumentKind(url: URL(fileURLWithPath: "/a/page.html")) == .html)
        #expect(DocumentKind(url: URL(fileURLWithPath: "/a/PAGE.HTM")) == .html)
        #expect(DocumentKind(url: URL(fileURLWithPath: "/a/notes.md")) == .markdown)
        #expect(DocumentKind(url: URL(fileURLWithPath: "/a/html")) == .markdown)
        #expect(DocumentKind(url: nil) == .markdown)
    }

    // MARK: Navigation policy

    @Test func allowsTheDocumentItself() {
        #expect(decide("file:///tmp/site/index.html", isUserLink: false) == .allow)
    }

    @Test func allowsFragmentJumpsWithinTheDocument() {
        #expect(decide("file:///tmp/site/index.html#section-2") == .allow)
        #expect(decide("file:///tmp/site/./index.html#top") == .allow)
    }

    @Test func clickedWebLinksOpenExternally() {
        let url = URL(string: "https://example.com/docs")!
        #expect(decide("https://example.com/docs") == .openExternally(url))
        #expect(decide("mailto:someone@example.com") == .openExternally(URL(string: "mailto:someone@example.com")!))
    }

    @Test func clickedLocalViewableFilesOpenInTwain() {
        let page = URL(string: "file:///tmp/site/other.html")!
        let notes = URL(string: "file:///tmp/site/notes.md")!
        #expect(decide(page.absoluteString) == .openInTwain(page))
        #expect(decide(notes.absoluteString) == .openInTwain(notes))
    }

    @Test func clickedOtherLocalFilesOpenExternally() {
        let pdf = URL(string: "file:///tmp/site/report.pdf")!
        #expect(decide(pdf.absoluteString) == .openExternally(pdf))
    }

    @Test func nonUserMainFrameNavigationsAreCancelled() {
        // Script redirects and form posts never replace the document.
        #expect(decide("https://example.com", isUserLink: false) == .cancel)
        #expect(decide("file:///tmp/site/other.html", isUserLink: false) == .cancel)
    }

    @Test func unknownSchemesAreCancelled() {
        #expect(decide("javascript:alert(1)") == .cancel)
        #expect(decide("data:text/html,hi") == .cancel)
    }

    @Test func iframeLoadsAreAllowed() {
        #expect(decide("https://www.example.com/embed", isMainFrame: false, isUserLink: false) == .allow)
        #expect(decide("about:srcdoc", isMainFrame: false, isUserLink: false) == .allow)
    }

    @Test func linksClickedInsideIframesLeaveTheWindow() {
        let url = URL(string: "https://example.com/elsewhere")!
        #expect(decide(url.absoluteString, isMainFrame: false) == .openExternally(url))
    }

    @Test func missingURLIsCancelled() {
        #expect(HTMLNavigationPolicy.decide(
            url: nil, documentURL: document, isMainFrame: true, isUserLink: true
        ) == .cancel)
    }
}
