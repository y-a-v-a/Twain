import SwiftUI
import Textual

struct ThemeColor: Codable {
    var light: String
    var dark: String

    var dynamicColor: DynamicColor {
        DynamicColor(light: Color(hex: light), dark: Color(hex: dark))
    }
}

struct Theme: Codable {
    var colors: ThemeColors
    var headings: ThemeHeadings
    var codeBlock: ThemeCodeBlock
    var blockQuote: ThemeBlockQuote
    var paragraph: ThemeParagraph

    struct ThemeColors: Codable {
        var primary: ThemeColor
        var secondary: ThemeColor
        var tertiary: ThemeColor
        var background: ThemeColor
        var secondaryBackground: ThemeColor
        var link: ThemeColor
        var border: ThemeColor
        var divider: ThemeColor
    }

    struct ThemeHeadings: Codable {
        var fontScales: [CGFloat]
        var fontWeight: String
    }

    struct ThemeCodeBlock: Codable {
        var background: ThemeColor
        var cornerRadius: CGFloat
        var padding: CGFloat
        var fontScale: CGFloat
    }

    struct ThemeBlockQuote: Codable {
        var borderColor: ThemeColor
        var borderWidth: CGFloat
    }

    struct ThemeParagraph: Codable {
        var lineSpacingScale: CGFloat
        var bottomSpacing: CGFloat
    }
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
            lineSpacingScale: 0.25,
            bottomSpacing: 16
        )
    )

    static func load() -> Theme {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/twain/theme.json")
        guard FileManager.default.fileExists(atPath: path.path),
              let data = try? Data(contentsOf: path),
              let theme = try? JSONDecoder().decode(Theme.self, from: data)
        else {
            return .default
        }
        return theme
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
