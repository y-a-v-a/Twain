import Testing
import Foundation
@testable import Twain

struct AppearanceTests {
    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "AppearanceTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test func storedReadsEachCase() throws {
        let defaults = try makeDefaults()
        for choice in Appearance.allCases {
            defaults.set(choice.rawValue, forKey: Appearance.defaultsKey)
            #expect(Appearance.stored(in: defaults) == choice)
        }
    }

    @Test func missingValueFallsBackToSystem() throws {
        #expect(try Appearance.stored(in: makeDefaults()) == .system)
    }

    @Test func unrecognizedValueFallsBackToSystem() throws {
        let defaults = try makeDefaults()
        defaults.set("sepia", forKey: Appearance.defaultsKey)
        #expect(Appearance.stored(in: defaults) == .system)
    }
}
