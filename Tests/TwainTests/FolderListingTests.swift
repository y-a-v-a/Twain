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

    private func touch(_ name: String, in folder: URL) throws {
        try Data().write(to: folder.appendingPathComponent(name))
    }

    @Test func listsOnlyMarkdownFiles() throws {
        let folder = try makeTempFolder()
        for name in ["a.md", "b.markdown", "c.mdown", "d.mkd", "e.txt", "f.pdf", "g"] {
            try touch(name, in: folder)
        }
        let names = FolderListing.markdownFiles(in: folder)?.map(\.lastPathComponent)
        #expect(names == ["a.md", "b.markdown", "c.mdown", "d.mkd"])
    }

    @Test func matchesExtensionsCaseInsensitively() throws {
        let folder = try makeTempFolder()
        try touch("README.MD", in: folder)
        try touch("Notes.Markdown", in: folder)
        let names = FolderListing.markdownFiles(in: folder)?.map(\.lastPathComponent)
        #expect(names?.count == 2)
    }

    @Test func excludesDirectoriesWithMarkdownNames() throws {
        let folder = try makeTempFolder()
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent("fake.md"),
            withIntermediateDirectories: false
        )
        try touch("real.md", in: folder)
        let names = FolderListing.markdownFiles(in: folder)?.map(\.lastPathComponent)
        #expect(names == ["real.md"])
    }

    @Test func skipsHiddenFiles() throws {
        let folder = try makeTempFolder()
        try touch(".hidden.md", in: folder)
        try touch("visible.md", in: folder)
        let names = FolderListing.markdownFiles(in: folder)?.map(\.lastPathComponent)
        #expect(names == ["visible.md"])
    }

    @Test func sortsAlphabetically() throws {
        let folder = try makeTempFolder()
        for name in ["zebra.md", "Apple.md", "mango.md"] {
            try touch(name, in: folder)
        }
        let names = FolderListing.markdownFiles(in: folder)?.map(\.lastPathComponent)
        #expect(names == ["Apple.md", "mango.md", "zebra.md"])
    }

    @Test func emptyFolderIsEmptyNotNil() throws {
        let folder = try makeTempFolder()
        #expect(FolderListing.markdownFiles(in: folder) == [])
    }

    @Test func missingFolderIsNil() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("twain-folder-tests-missing-\(UUID().uuidString)")
        #expect(FolderListing.markdownFiles(in: missing) == nil)
    }
}
