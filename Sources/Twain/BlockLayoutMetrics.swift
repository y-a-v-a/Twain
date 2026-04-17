import SwiftUI

/// Layout values shared between the markdown renderer (`ThemedStyle.swift`) and the
/// scroll-position estimator (`SearchBar.swift`). Keeping them here prevents the
/// estimator from drifting when a spacing tweak lands only on the render side.
struct BlockLayoutMetrics {
    /// Approximate rendered height of one text line, in points. Used to convert
    /// absolute spacings to the line-unit basis the estimator operates in. Not
    /// font-size-aware: 20pt matches the default 16pt font with lineSpacingScale 0.25.
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
}

extension Theme {
    var blockLayout: BlockLayoutMetrics {
        BlockLayoutMetrics(
            pointsPerLineUnit: 20,
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
            tableBottomSpacing: 16,
            tableInnerPadding: 1,
            tableOuterBorderWidth: 1,
            tableCellSpacing: 1,
            tableCellVerticalPadding: 6,
            thematicBreakTopSpacing: 24,
            thematicBreakBottomSpacing: 24,
            thematicBreakRuleFontScale: 0.25
        )
    }
}
