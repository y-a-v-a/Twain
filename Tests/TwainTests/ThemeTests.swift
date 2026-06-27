import Testing
import Foundation
@testable import Twain

struct ThemeTests {
    // The seed written by `ensureUserThemeFileExists()` must always decode back into a valid
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
