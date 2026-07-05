import Testing
import Foundation
@testable import Twain

struct ThemeTests {
    // The seed written by `syncUserThemeFile()` must always decode back into a valid
    // theme, otherwise we'd write a file the app then rejects. Uses the same encoder settings.
    @Test func defaultThemeRoundTripsThroughSeedEncoding() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Theme.default)
        let decoded = try JSONDecoder().decode(Theme.self, from: data)
        #expect(decoded == Theme.default)
    }

    // A theme.json predating the `layout` section must still decode (layout is optional) and
    // fall back to the default content inset rather than failing the whole file.
    @Test func themeWithoutLayoutSectionStillDecodes() throws {
        let data = try JSONEncoder().encode(Theme.default)
        var object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object.removeValue(forKey: "layout")
        let trimmed = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(Theme.self, from: trimmed)
        #expect(decoded.layout == nil)
        #expect(decoded.contentInset == Theme.defaultContentInset)
    }

    @Test func contentInsetReadsFromLayoutWhenPresent() {
        var theme = Theme.default
        theme.layout = Theme.ThemeLayout(contentInset: 48)
        #expect(theme.contentInset == 48)
    }

    @Test func contentInsetFallsBackWhenLayoutMissing() {
        var theme = Theme.default
        theme.layout = nil
        #expect(theme.contentInset == Theme.defaultContentInset)
    }
}

struct ThemeSyncTests {
    /// A scratch theme file path inside a fresh temp directory; the directory is deliberately
    /// not created for the seed test, which must create it itself.
    private func scratchURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("twain-theme-tests-\(UUID().uuidString)")
            .appendingPathComponent("theme.json")
    }

    private func defaultsDictionary() throws -> [String: Any] {
        let encoder = JSONEncoder()
        let data = try encoder.encode(Theme.default)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: topUp

    @Test func topUpFillsMissingNestedSection() throws {
        var user = try defaultsDictionary()
        user.removeValue(forKey: "layout")

        let merged = Theme.topUp(user: user, defaults: try defaultsDictionary())
        let layout = try #require(merged["layout"] as? [String: Any])
        #expect(layout["contentInset"] as? Double == Double(Theme.defaultContentInset))
    }

    @Test func topUpNeverOverwritesUserValues() throws {
        var user = try defaultsDictionary()
        var colors = try #require(user["colors"] as? [String: Any])
        colors["primary"] = ["light": "#123456", "dark": "#654321"]
        user["colors"] = colors

        let merged = Theme.topUp(user: user, defaults: try defaultsDictionary())
        let mergedColors = try #require(merged["colors"] as? [String: Any])
        let primary = try #require(mergedColors["primary"] as? [String: String])
        #expect(primary == ["light": "#123456", "dark": "#654321"])
    }

    @Test func topUpPreservesUnknownUserKeys() throws {
        var user = try defaultsDictionary()
        user["futureFeature"] = ["knob": 11]

        let merged = Theme.topUp(user: user, defaults: try defaultsDictionary())
        let future = try #require(merged["futureFeature"] as? [String: Int])
        #expect(future == ["knob": 11])
    }

    // MARK: syncUserThemeFile

    @Test func syncSeedsMissingFile() throws {
        let url = scratchURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        Theme.syncUserThemeFile(at: url)

        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(Theme.self, from: data)
        #expect(decoded == Theme.default)
    }

    @Test func syncTopsUpFileMissingNewSectionAndKeepsUserValues() throws {
        let url = scratchURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )

        // A pre-`layout` file with a customized paragraph spacing.
        var user = try defaultsDictionary()
        user.removeValue(forKey: "layout")
        var paragraph = try #require(user["paragraph"] as? [String: Any])
        paragraph["bottomSpacing"] = 24
        user["paragraph"] = paragraph
        try JSONSerialization.data(withJSONObject: user).write(to: url)

        Theme.syncUserThemeFile(at: url)

        let synced = try JSONDecoder().decode(Theme.self, from: Data(contentsOf: url))
        #expect(synced.layout?.contentInset == Theme.defaultContentInset)
        #expect(synced.paragraph.bottomSpacing == 24)
    }

    @Test func syncLeavesUndecodableFileUntouched() throws {
        let url = scratchURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let broken = Data("{ \"colors\": ".utf8)
        try broken.write(to: url)

        Theme.syncUserThemeFile(at: url)

        #expect(try Data(contentsOf: url) == broken)
    }

    @Test func syncDoesNotRewriteUpToDateFile() throws {
        let url = scratchURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )

        // Complete but compact (non-pretty) — a rewrite would change the bytes.
        let compact = try JSONEncoder().encode(Theme.default)
        try compact.write(to: url)

        Theme.syncUserThemeFile(at: url)

        #expect(try Data(contentsOf: url) == compact)
    }
}
