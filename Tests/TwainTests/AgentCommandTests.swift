import Testing
import Foundation
@testable import Twain

struct AgentCommandTests {
    private func parse(_ string: String) -> AgentCommand? {
        guard let url = URL(string: string) else { return nil }
        return AgentCommand.parse(url)
    }

    // MARK: - refresh

    @Test func parsesBroadcastRefresh() {
        #expect(parse("twain://refresh") == .refresh(path: nil))
    }

    @Test func parsesTargetedRefresh() {
        #expect(
            parse("twain://refresh?file=/tmp/notes.md") == .refresh(path: "/tmp/notes.md")
        )
    }

    @Test func refreshIgnoresRelativePath() {
        // Relative paths are meaningless across processes; treat as a broadcast.
        #expect(parse("twain://refresh?file=notes.md") == .refresh(path: nil))
    }

    // MARK: - search

    @Test func parsesSearchInAllDocuments() {
        #expect(parse("twain://search?q=Install") == .find(query: "Install", path: nil))
    }

    @Test func parsesSearchInOneDocument() {
        #expect(
            parse("twain://search?q=Install&file=/docs/a.md")
                == .find(query: "Install", path: "/docs/a.md")
        )
    }

    @Test func searchDecodesPercentEncoding() {
        #expect(
            parse("twain://search?q=hello%20world%26more")
                == .find(query: "hello world&more", path: nil)
        )
    }

    @Test func searchRequiresQuery() {
        #expect(parse("twain://search") == nil)
        #expect(parse("twain://search?q=") == nil)
    }

    // MARK: - open

    @Test func parsesOpen() {
        #expect(
            parse("twain://open?file=/docs/a.md")
                == .open(path: "/docs/a.md", searchQuery: nil, activate: true)
        )
    }

    @Test func parsesOpenWithSearchAndBackground() {
        #expect(
            parse("twain://open?file=/docs/a.md&search=Usage&activate=0")
                == .open(path: "/docs/a.md", searchQuery: "Usage", activate: false)
        )
    }

    @Test func openRequiresAbsolutePath() {
        #expect(parse("twain://open") == nil)
        #expect(parse("twain://open?file=a.md") == nil)
    }

    @Test func openDecodesEncodedPath() {
        #expect(
            parse("twain://open?file=/docs/release%20notes.md")
                == .open(path: "/docs/release notes.md", searchQuery: nil, activate: true)
        )
    }

    // MARK: - open-folder

    @Test func parsesOpenFolder() {
        #expect(
            parse("twain://open-folder?dir=/docs/notes")
                == .openFolder(path: "/docs/notes", activate: true)
        )
    }

    @Test func parsesOpenFolderInBackground() {
        #expect(
            parse("twain://open-folder?dir=/docs/notes&activate=0")
                == .openFolder(path: "/docs/notes", activate: false)
        )
    }

    @Test func openFolderRequiresAbsolutePath() {
        #expect(parse("twain://open-folder") == nil)
        #expect(parse("twain://open-folder?dir=notes") == nil)
    }

    @Test func openFolderDecodesEncodedPath() {
        #expect(
            parse("twain://open-folder?dir=/docs/release%20notes")
                == .openFolder(path: "/docs/release notes", activate: true)
        )
    }

    // MARK: - rejection

    @Test func rejectsUnknownCommand() {
        #expect(parse("twain://close") == nil)
    }

    @Test func rejectsOtherSchemes() {
        #expect(parse("https://refresh") == nil)
        #expect(parse("file:///tmp/notes.md") == nil)
    }

    // MARK: - path resolution

    @Test func resolvedPathCanonicalizesEquivalentPaths() {
        // /tmp is a symlink to /private/tmp on macOS. A notification target and a document
        // window's fileURL may arrive in either form; both must canonicalize identically or
        // targeted refresh/find commands silently miss. This must hold for files that don't
        // exist yet — Foundation's /private handling is existence-dependent on its own.
        #expect(
            AgentCommandCenter.resolvedPath("/tmp/../tmp/notes.md")
                == AgentCommandCenter.resolvedPath("/private/tmp/notes.md")
        )
    }

    @Test func resolvedPathStripsThePrivatePrefix() {
        #expect(AgentCommandCenter.resolvedPath("/private/tmp/notes.md") == "/tmp/notes.md")
        // Only the symlinked roots are rewritten; other /private paths pass through.
        #expect(AgentCommandCenter.resolvedPath("/privateer/log.md") == "/privateer/log.md")
    }
}
