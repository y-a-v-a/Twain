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

    /// Ensure the user's theme file exists, seeding it from `default` (and creating the
    /// parent directory) when absent, so the editor always has a valid file to open.
    /// Errors are intentionally swallowed to match `load()`'s tolerant behavior.
    static func ensureUserThemeFileExists() {
        guard !FileManager.default.fileExists(atPath: userThemeURL.path) else { return }
        try? FileManager.default.createDirectory(
            at: userThemeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(Theme.default) {
            // Atomic write so an interrupted/failed write can't leave a half-written file that
            // the editor opens and `load()` then rejects. Any failure here is swallowed — a
            // missing file just means the app keeps using the default theme.
            try? data.write(to: userThemeURL, options: .atomic)
        }
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
