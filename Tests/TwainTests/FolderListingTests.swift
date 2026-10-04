import Testing
import Foundation
@testable import Twain

struct FolderListingTests {
    private func makeTempFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("twain-folder-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func makeDirectory(_ name: String, in folder: URL) throws {
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent(name),
            withIntermediateDirectories: false
        )
    }

    private func touch(_ name: String, in folder: URL) throws {
        try Data().write(to: folder.appendingPathComponent(name))
    }

    @Test func listsOnlyMarkdownFiles() throws {
        let folder = try makeTempFolder()
        for name in ["a.md", "b.markdown", "c.mdown", "d.mkd", "e.txt", "f.pdf", "g"] {
            try touch(name, in: folder)
        }
        let names = FolderListing.entries(in: folder)?.map(\.name)
        #expect(names == ["a.md", "b.markdown", "c.mdown", "d.mkd"])
    }

    @Test func matchesExtensionsCaseInsensitively() throws {
        let folder = try makeTempFolder()
        try touch("README.MD", in: folder)
        try touch("Notes.Markdown", in: folder)
        let names = FolderListing.entries(in: folder)?.map(\.name)
        #expect(names?.count == 2)
    }

    @Test func directoryWithMarkdownNameIsListedAsDirectory() throws {
        let folder = try makeTempFolder()
        try makeDirectory("fake.md", in: folder)
        try touch("real.md", in: folder)
        let entries = FolderListing.entries(in: folder)
        #expect(entries?.map(\.name) == ["fake.md", "real.md"])
        #expect(entries?.map(\.isDirectory) == [true, false])
    }

    @Test func listsDirectoriesBeforeFiles() throws {
        let folder = try makeTempFolder()
        try touch("a.md", in: folder)
        try makeDirectory("zeta", in: folder)
        try makeDirectory("Beta", in: folder)
        let entries = FolderListing.entries(in: folder)
        #expect(entries?.map(\.name) == ["Beta", "zeta", "a.md"])
        #expect(entries?.map(\.isDirectory) == [true, true, false])
    }

    @Test func readsOnlyOneLevel() throws {
        let folder = try makeTempFolder()
        try makeDirectory("sub", in: folder)
        try touch("nested.md", in: folder.appendingPathComponent("sub"))
        #expect(FolderListing.entries(in: folder)?.map(\.name) == ["sub"])
        let sub = try #require(FolderListing.entries(in: folder)?.first)
        #expect(FolderListing.entries(in: sub.url)?.map(\.name) == ["nested.md"])
    }

    @Test func skipsPackagesAndHiddenDirectories() throws {
        let folder = try makeTempFolder()
        try makeDirectory("Tool.app", in: folder)
        try makeDirectory(".git", in: folder)
        try makeDirectory("docs", in: folder)
        #expect(FolderListing.entries(in: folder)?.map(\.name) == ["docs"])
    }

    @Test func skipsSymlinkedDirectories() throws {
        let folder = try makeTempFolder()
        try makeDirectory("real", in: folder)
        try FileManager.default.createSymbolicLink(
            at: folder.appendingPathComponent("loop"),
            withDestinationURL: folder
        )
        #expect(FolderListing.entries(in: folder)?.map(\.name) == ["real"])
    }

    @Test func descendantCheckRequiresPathBoundary() {
        let folder = URL(fileURLWithPath: "/tmp/docs")
        #expect(FolderListing.isDescendant(URL(fileURLWithPath: "/tmp/docs/a/b.md"), of: folder))
        #expect(!FolderListing.isDescendant(URL(fileURLWithPath: "/tmp/docs-old/b.md"), of: folder))
        #expect(!FolderListing.isDescendant(folder, of: folder))
    }

    @Test func skipsHiddenFiles() throws {
        let folder = try makeTempFolder()
        try touch(".hidden.md", in: folder)
        try touch("visible.md", in: folder)
        let names = FolderListing.entries(in: folder)?.map(\.name)
        #expect(names == ["visible.md"])
    }

    @Test func sortsAlphabetically() throws {
        let folder = try makeTempFolder()
        for name in ["zebra.md", "Apple.md", "mango.md"] {
            try touch(name, in: folder)
        }
        let names = FolderListing.entries(in: folder)?.map(\.name)
        #expect(names == ["Apple.md", "mango.md", "zebra.md"])
    }

    @Test func emptyFolderIsEmptyNotNil() throws {
        let folder = try makeTempFolder()
        #expect(FolderListing.entries(in: folder) == [])
    }

    @Test func missingFolderIsNil() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("twain-folder-tests-missing-\(UUID().uuidString)")
        #expect(FolderListing.entries(in: missing) == nil)
    }
}
