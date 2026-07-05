import SwiftUI
import Textual

struct ThemeColor: Codable, Equatable {
    var light: String
    var dark: String

    var dynamicColor: DynamicColor {
        DynamicColor(light: Color(hex: light), dark: Color(hex: dark))
    }
}

struct Theme: Codable, Equatable {
    var colors: ThemeColors
    var headings: ThemeHeadings
    var codeBlock: ThemeCodeBlock
    var blockQuote: ThemeBlockQuote
    var paragraph: ThemeParagraph
    var layout: ThemeLayout?
    var serifFontFamily: String?
    var sansSerifFontFamily: String?

    struct ThemeColors: Codable, Equatable {
        var primary: ThemeColor
        var secondary: ThemeColor
        var tertiary: ThemeColor
        var background: ThemeColor
        var secondaryBackground: ThemeColor
        var link: ThemeColor
        var border: ThemeColor
        var divider: ThemeColor
    }

    struct ThemeHeadings: Codable, Equatable {
        var fontScales: [CGFloat]
        var fontWeight: String
    }

    struct ThemeCodeBlock: Codable, Equatable {
        var background: ThemeColor
        var cornerRadius: CGFloat
        var padding: CGFloat
        var fontScale: CGFloat
    }

    struct ThemeBlockQuote: Codable, Equatable {
        var borderColor: ThemeColor
        var borderWidth: CGFloat
    }

    struct ThemeParagraph: Codable, Equatable {
        var lineSpacingScale: CGFloat
        var bottomSpacing: CGFloat
    }

    struct ThemeLayout: Codable, Equatable {
        var contentInset: CGFloat
    }

    /// Padding around the rendered content. Falls back to the built-in default when a
    /// custom `theme.json` predates the `layout` section.
    var contentInset: CGFloat { layout?.contentInset ?? Theme.defaultContentInset }

    static let defaultContentInset: CGFloat = 32
}

extension Theme {
    static let `default` = Theme(
        colors: ThemeColors(
            primary: ThemeColor(light: "#060606", dark: "#fbfbfc"),
            secondary: ThemeColor(light: "#6b6e7b", dark: "#9294a0"),
            tertiary: ThemeColor(light: "#6b6e7b", dark: "#6d707d"),
            background: ThemeColor(light: "#ffffff", dark: "#18191d"),
            secondaryBackground: ThemeColor(light: "#f7f7f9", dark: "#25262a"),
            link: ThemeColor(light: "#2c65cf", dark: "#4c8ef8"),
            border: ThemeColor(light: "#e4e4e8", dark: "#42444e"),
            divider: ThemeColor(light: "#d0d0d3", dark: "#333438")
        ),
        headings: ThemeHeadings(
            fontScales: [2, 1.5, 1.25, 1, 0.875, 0.85],
            fontWeight: "semibold"
        ),
        codeBlock: ThemeCodeBlock(
            background: ThemeColor(light: "#f5f5f8", dark: "#1f1f24"),
            cornerRadius: 6,
            padding: 16,
            fontScale: 0.85
        ),
        blockQuote: ThemeBlockQuote(
            borderColor: ThemeColor(light: "#e4e4e8", dark: "#42444e"),
            borderWidth: 0.2
        ),
        paragraph: ThemeParagraph(
            lineSpacingScale: 0.4,
            bottomSpacing: 16
        ),
        layout: ThemeLayout(
            contentInset: defaultContentInset
        )
    )

    /// Location of the user's theme file. Single source of truth shared by `load()`, the
    /// file watcher in `ThemeStore`, and the "Edit Theme" settings action.
    static let userThemeURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/twain/theme.json")

    static func load() -> Theme {
        guard FileManager.default.fileExists(atPath: userThemeURL.path),
              let data = try? Data(contentsOf: userThemeURL),
              let theme = try? JSONDecoder().decode(Theme.self, from: data)
        else {
            return .default
        }
        return theme
    }

    /// Seed the user's theme file from `default` when absent, and top up an existing file
    /// with keys added by newer versions of the app — user values always win, new keys get
    /// their default. The merge happens at the JSON level so keys the decoder doesn't know
    /// about survive a rewrite. A file that doesn't decode as a `Theme` (broken, or mid-edit)
    /// is left untouched. Errors are intentionally swallowed to match `load()`'s tolerant
    /// behavior.
    static func syncUserThemeFile(at url: URL = userThemeURL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let defaultData = try? encoder.encode(Theme.default),
              let defaults = (try? JSONSerialization.jsonObject(with: defaultData)) as? [String: Any]
        else { return }

        guard FileManager.default.fileExists(atPath: url.path) else {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            // Atomic write so an interrupted/failed write can't leave a half-written file that
            // the editor opens and `load()` then rejects. Any failure here is swallowed — a
            // missing file just means the app keeps using the default theme.
            try? defaultData.write(to: url, options: .atomic)
            return
        }

        guard let data = try? Data(contentsOf: url),
              (try? JSONDecoder().decode(Theme.self, from: data)) != nil,
              let user = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return }

        let merged = topUp(user: user, defaults: defaults)
        // Rewrite only when the merge added keys, so an up-to-date file keeps its formatting.
        guard !(merged as NSDictionary).isEqual(to: user) else { return }
        if let out = try? JSONSerialization.data(
            withJSONObject: merged,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            try? out.write(to: url, options: .atomic)
        }
    }

    /// Recursively fill keys missing from `user` with their `defaults` value. Existing user
    /// values are never replaced, including whole nested objects the user has customized.
    static func topUp(user: [String: Any], defaults: [String: Any]) -> [String: Any] {
        var result = user
        for (key, defaultValue) in defaults {
            switch (result[key], defaultValue) {
            case (nil, _):
                result[key] = defaultValue
            case let (userObject as [String: Any], defaultObject as [String: Any]):
                result[key] = topUp(user: userObject, defaults: defaultObject)
            default:
                break
            }
        }
        return result
    }
}

extension Theme.ThemeHeadings {
    var weight: Font.Weight {
        switch fontWeight.lowercased() {
        case "ultralight": .ultraLight
        case "thin": .thin
        case "light": .light
        case "regular": .regular
        case "medium": .medium
        case "semibold": .semibold
        case "bold": .bold
        case "heavy": .heavy
        case "black": .black
        default: .semibold
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&rgb)

        let r, g, b: Double
        switch hex.count {
        case 3: // #RGB -> #RRGGBB (replicate nibble: 0xA -> 0xAA)
            r = Double(((rgb >> 8) & 0xF) * 17) / 255
            g = Double(((rgb >> 4) & 0xF) * 17) / 255
            b = Double(( rgb       & 0xF) * 17) / 255
        case 6: // #RRGGBB
            r = Double((rgb >> 16) & 0xFF) / 255
            g = Double((rgb >> 8) & 0xFF) / 255
            b = Double(rgb & 0xFF) / 255
        default: // invalid or unsupported length — fall back to black
            r = 0; g = 0; b = 0
        }
        self.init(red: r, green: g, blue: b)
    }
}
