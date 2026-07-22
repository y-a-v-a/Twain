import SwiftUI
import Textual

public struct ThemeColor: Codable, Equatable, Sendable {
    public var light: String
    public var dark: String

    public var dynamicColor: DynamicColor {
        DynamicColor(light: Color(hex: light), dark: Color(hex: dark))
    }
}

public struct Theme: Codable, Equatable, Sendable {
    public var colors: ThemeColors
    public var headings: ThemeHeadings
    public var codeBlock: ThemeCodeBlock
    public var blockQuote: ThemeBlockQuote
    public var paragraph: ThemeParagraph
    public var table: ThemeTable?
    public var list: ThemeList?
    public var layout: ThemeLayout?
    public var serifFontFamily: String?
    public var sansSerifFontFamily: String?

    public struct ThemeColors: Codable, Equatable, Sendable {
        public var primary: ThemeColor
        public var secondary: ThemeColor
        public var tertiary: ThemeColor
        public var background: ThemeColor
        public var secondaryBackground: ThemeColor
        public var link: ThemeColor
        public var border: ThemeColor
        public var divider: ThemeColor
    }

    public struct ThemeHeadings: Codable, Equatable, Sendable {
        public var fontScales: [CGFloat]
        public var fontWeight: String
        // Optional: absent in theme files predating these keys.
        public var topSpacing: CGFloat?
        public var bottomSpacing: CGFloat?

        static let defaultTopSpacing: CGFloat = 24
        static let defaultBottomSpacing: CGFloat = 16
    }

    public struct ThemeCodeBlock: Codable, Equatable, Sendable {
        public var background: ThemeColor
        public var cornerRadius: CGFloat
        public var padding: CGFloat
        public var fontScale: CGFloat
        // Optional: absent in theme files predating this key.
        public var lineSpacingScale: CGFloat?

        static let defaultLineSpacingScale: CGFloat = 0.225
    }

    public struct ThemeTable: Codable, Equatable, Sendable {
        public var cellVerticalPadding: CGFloat
        public var cellHorizontalPadding: CGFloat

        static let fallback = ThemeTable(cellVerticalPadding: 6, cellHorizontalPadding: 13)
    }

    public struct ThemeList: Codable, Equatable, Sendable {
        /// Horizontal gap between a list marker and its item content, in font-relative units.
        public var markerSpacing: CGFloat
        /// Vertical gap between list items, in font-relative units.
        /// Optional: absent in theme files predating this key.
        public var itemSpacing: CGFloat?

        static let defaultItemSpacing: CGFloat = 0.25
        public var resolvedItemSpacing: CGFloat { itemSpacing ?? Self.defaultItemSpacing }

        static let fallback = ThemeList(markerSpacing: 0.5, itemSpacing: defaultItemSpacing)
    }

    public struct ThemeBlockQuote: Codable, Equatable, Sendable {
        public var borderColor: ThemeColor
        public var borderWidth: CGFloat
    }

    public struct ThemeParagraph: Codable, Equatable, Sendable {
        public var lineSpacingScale: CGFloat
        public var bottomSpacing: CGFloat
    }

    public struct ThemeLayout: Codable, Equatable, Sendable {
        public var contentInset: CGFloat
    }

    /// Padding around the rendered content. Falls back to the built-in default when a
    /// custom `theme.json` predates the `layout` section.
    public var contentInset: CGFloat { layout?.contentInset ?? Theme.defaultContentInset }

    static let defaultContentInset: CGFloat = 32

    /// Sections added after the first release; a custom `theme.json` predating them
    /// must still decode, so they resolve to their fallbacks here.
    public var resolvedTable: ThemeTable { table ?? .fallback }
    public var resolvedList: ThemeList { list ?? .fallback }
}

extension Theme {
    public static let `default` = Theme(
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
            fontWeight: "semibold",
            topSpacing: ThemeHeadings.defaultTopSpacing,
            bottomSpacing: ThemeHeadings.defaultBottomSpacing
        ),
        codeBlock: ThemeCodeBlock(
            background: ThemeColor(light: "#f5f5f8", dark: "#1f1f24"),
            cornerRadius: 6,
            padding: 16,
            fontScale: 0.85,
            lineSpacingScale: ThemeCodeBlock.defaultLineSpacingScale
        ),
        blockQuote: ThemeBlockQuote(
            borderColor: ThemeColor(light: "#e4e4e8", dark: "#42444e"),
            borderWidth: 0.2
        ),
        paragraph: ThemeParagraph(
            lineSpacingScale: 0.4,
            bottomSpacing: 16
        ),
        table: .fallback,
        list: .fallback,
        layout: ThemeLayout(
            contentInset: defaultContentInset
        )
    )

    /// Location of the user's theme file. Single source of truth shared by `load()`, the
    /// file watcher in `ThemeStore`, and the "Edit Theme" settings action. The
    /// `TWAIN_CONFIG_DIR` environment variable overrides the directory so test harnesses
    /// can isolate the app from the real `~/.config/twain` (a plain `$HOME` override is
    /// not enough — `homeDirectoryForCurrentUser` ignores it).
    public static let userThemeURL: URL = {
        if let dir = ProcessInfo.processInfo.environment["TWAIN_CONFIG_DIR"], !dir.isEmpty {
            return URL(fileURLWithPath: dir).appendingPathComponent("theme.json")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/twain/theme.json")
    }()

    public static func load() -> Theme {
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
    public static func syncUserThemeFile(at url: URL = userThemeURL) {
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
