import SwiftUI

/// Layout values shared between the markdown renderer (`ThemedStyle.swift`) and the
/// scroll-position estimator (`SearchBar.swift`). Keeping them here prevents the
/// estimator from drifting when a spacing tweak lands only on the render side.
struct BlockLayoutMetrics {
    /// Base font size used to derive point-based estimates for the current viewer zoom level.
    var baseFontSize: CGFloat

    /// Approximate rendered height of one text line, in points. Used to convert
    /// absolute spacings to the line-unit basis the estimator operates in.
    /// Derived from the active font size and paragraph line-spacing scale.
    var pointsPerLineUnit: CGFloat

    var headingScales: [CGFloat]
    var headingTopSpacing: CGFloat
    var headingBottomSpacing: CGFloat
    /// Heading levels at or below this value get a Divider rendered below the title.
    var headingDividerMaxLevel: Int
    /// VStack spacing between heading label and its divider.
    var headingDividerGap: CGFloat
    /// Approximate rendered thickness of the divider under h1/h2.
    var headingDividerThickness: CGFloat

    var paragraphBottomSpacing: CGFloat

    var codeBlockPadding: CGFloat
    var codeBlockBottomSpacing: CGFloat
    var codeBlockFontScale: CGFloat
    var codeBlockLineSpacingScale: CGFloat

    var tableBottomSpacing: CGFloat
    /// Inside the table, outside the cells (`.padding(1)` in `ThemedTableStyle`).
    var tableInnerPadding: CGFloat
    /// Outermost table border.
    var tableOuterBorderWidth: CGFloat
    /// Gap between cells in both directions (`tableCellSpacing`).
    var tableCellSpacing: CGFloat
    /// Vertical padding applied inside each cell.
    var tableCellVerticalPadding: CGFloat

    var thematicBreakTopSpacing: CGFloat
    var thematicBreakBottomSpacing: CGFloat
    var thematicBreakRuleFontScale: CGFloat

    /// Width available to wrapping text, in points. Zero when the viewport hasn't been measured
    /// yet, in which case the estimator falls back to a fixed characters-per-line guess.
    var contentWidth: CGFloat
    /// Average glyph advance as a fraction of the font size, used to estimate where text wraps.
    var averageCharacterWidthScale: CGFloat

    /// Estimated number of characters that fit on one rendered line for text drawn at `fontScale`
    /// times the base font size. Width-aware so the scroll estimate tracks the actual window
    /// width and zoom instead of assuming a fixed line length.
    func charactersPerLine(fontScale: CGFloat = 1) -> CGFloat {
        guard contentWidth > 0 else { return 72 }
        let glyphWidth = baseFontSize * fontScale * averageCharacterWidthScale
        return max(contentWidth / max(glyphWidth, 1), 1)
    }
}

extension Theme {
    /// Layout metrics for the render-side `StructuredText` styles in `ThemedStyle.swift`.
    ///
    /// Those styles read only the size-*independent* fields (spacing constants, font scales,
    /// heading scales); the size-derived fields (`baseFontSize`, `pointsPerLineUnit`) are
    /// irrelevant to them because SwiftUI applies the live font size through the environment.
    /// Only the scroll estimator in `SearchBar.swift` needs the size-derived fields, and it calls
    /// `blockLayout(fontSize:)` with the actual font size. The 16 here is therefore an arbitrary
    /// placeholder, not the rendered size.
    var styleLayout: BlockLayoutMetrics { blockLayout(fontSize: 16) }

    func blockLayout(fontSize: CGFloat, contentWidth: CGFloat = 0) -> BlockLayoutMetrics {
        let resolvedFontSize = max(fontSize, 1)
        let pointsPerLineUnit = resolvedFontSize * (1 + paragraph.lineSpacingScale)

        return BlockLayoutMetrics(
            baseFontSize: resolvedFontSize,
            pointsPerLineUnit: pointsPerLineUnit,
            headingScales: headings.fontScales,
            headingTopSpacing: 24,
            headingBottomSpacing: 16,
            headingDividerMaxLevel: 2,
            headingDividerGap: 4,
            headingDividerThickness: 1,
            paragraphBottomSpacing: paragraph.bottomSpacing,
            codeBlockPadding: codeBlock.padding,
            codeBlockBottomSpacing: 16,
            codeBlockFontScale: codeBlock.fontScale,
            codeBlockLineSpacingScale: 0.225,
            tableBottomSpacing: 16,
            tableInnerPadding: 1,
            tableOuterBorderWidth: 1,
            tableCellSpacing: 1,
            tableCellVerticalPadding: 6,
            thematicBreakTopSpacing: 24,
            thematicBreakBottomSpacing: 24,
            thematicBreakRuleFontScale: 0.25,
            contentWidth: contentWidth,
            averageCharacterWidthScale: 0.5
        )
    }
}
