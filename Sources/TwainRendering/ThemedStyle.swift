import SwiftUI
import Textual

// MARK: - Themed Heading Style

public struct ThemedHeadingStyle: StructuredText.HeadingStyle {
    let theme: Theme

    public func makeBody(configuration: Configuration) -> some View {
        let layout = theme.styleLayout
        let level = max(1, min(configuration.headingLevel, 6))
        let fontScale = level <= layout.headingScales.count ? layout.headingScales[level - 1] : 1.0

        VStack(alignment: .leading, spacing: layout.headingDividerGap) {
            makeLabel(configuration: configuration)
                .textual.fontScale(fontScale)
                .textual.lineSpacing(.fontScaled(0.125))
                .textual.blockSpacing(.init(top: layout.headingTopSpacing, bottom: layout.headingBottomSpacing))
                .fontWeight(theme.headings.weight)
            if level <= layout.headingDividerMaxLevel {
                Divider()
                    .overlay(theme.colors.divider.dynamicColor)
            }
        }
    }

    @ViewBuilder
    private func makeLabel(configuration: Configuration) -> some View {
        if min(configuration.headingLevel, 6) == 6 {
            configuration.label
                .foregroundStyle(theme.colors.tertiary.dynamicColor)
        } else {
            configuration.label
        }
    }
}

// MARK: - Themed Code Block Style

public struct ThemedCodeBlockStyle: StructuredText.CodeBlockStyle {
    let theme: Theme

    public func makeBody(configuration: Configuration) -> some View {
        let layout = theme.styleLayout
        Overflow {
            configuration.label
                .textual.lineSpacing(.fontScaled(layout.codeBlockLineSpacingScale))
                .textual.fontScale(layout.codeBlockFontScale)
                .fixedSize(horizontal: false, vertical: true)
                .monospaced()
                .padding(layout.codeBlockPadding)
        }
        .background(theme.codeBlock.background.dynamicColor)
        .clipShape(RoundedRectangle(cornerRadius: theme.codeBlock.cornerRadius))
        .textual.blockSpacing(.init(top: 0, bottom: layout.codeBlockBottomSpacing))
    }
}

// MARK: - Themed Block Quote Style

public struct ThemedBlockQuoteStyle: StructuredText.BlockQuoteStyle {
    let theme: Theme

    public func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 6)
                .fill(theme.blockQuote.borderColor.dynamicColor)
                .textual.frame(width: .fontScaled(theme.blockQuote.borderWidth))
            configuration.label
                .foregroundStyle(theme.colors.secondary.dynamicColor)
                .textual.padding(.horizontal, .fontScaled(1))
        }
    }
}

// MARK: - Themed Paragraph Style

public struct ThemedParagraphStyle: StructuredText.ParagraphStyle {
    let theme: Theme

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textual.lineSpacing(.fontScaled(theme.paragraph.lineSpacingScale))
            .textual.blockSpacing(.init(top: 0, bottom: theme.styleLayout.paragraphBottomSpacing))
    }
}

// MARK: - Themed Table Style

public struct ThemedTableStyle: StructuredText.TableStyle {
    let theme: Theme

    public func makeBody(configuration: Configuration) -> some View {
        let metrics = theme.styleLayout
        configuration.label
            .textual.tableCellSpacing(horizontal: metrics.tableCellSpacing, vertical: metrics.tableCellSpacing)
            .textual.blockSpacing(.init(top: 0, bottom: metrics.tableBottomSpacing))
            .textual.tableBackground { layout in
                Canvas { context, _ in
                    for bounds in layout.evenRowBounds {
                        context.fill(
                            Path(bounds.integral),
                            with: .style(theme.colors.secondaryBackground.dynamicColor)
                        )
                    }
                }
            }
            .textual.tableOverlay { layout in
                Canvas { context, _ in
                    for divider in layout.dividers() {
                        context.fill(
                            Path(divider),
                            with: .style(theme.colors.border.dynamicColor)
                        )
                    }
                }
            }
            .padding(metrics.tableInnerPadding)
            .border(theme.colors.border.dynamicColor, width: metrics.tableOuterBorderWidth)
    }
}

private extension StructuredText.TableLayout {
    var evenRowBounds: [CGRect] {
        rowIndices
            .dropFirst()
            .filter { $0.isMultiple(of: 2) }
            .map { rowBounds($0) }
    }
}

// MARK: - Themed Table Cell Style

public struct ThemedTableCellStyle: StructuredText.TableCellStyle {
    let theme: Theme

    public func makeBody(configuration: Configuration) -> some View {
        let layout = theme.styleLayout
        configuration.label
            .fontWeight(configuration.row == 0 ? .semibold : .regular)
            .padding(.vertical, layout.tableCellVerticalPadding)
            .padding(.horizontal, layout.tableCellHorizontalPadding)
            .textual.lineSpacing(.fontScaled(0.25))
    }
}

// MARK: - Themed Thematic Break Style

public struct ThemedThematicBreakStyle: StructuredText.ThematicBreakStyle {
    let theme: Theme

    public func makeBody(configuration _: Configuration) -> some View {
        let layout = theme.styleLayout
        Divider()
            .textual.frame(height: .fontScaled(layout.thematicBreakRuleFontScale))
            .overlay(theme.colors.border.dynamicColor)
            .textual.blockSpacing(.init(top: layout.thematicBreakTopSpacing, bottom: layout.thematicBreakBottomSpacing))
    }
}

// MARK: - Themed Structured Text Style

public struct ThemedStructuredTextStyle: StructuredText.Style {
    let theme: Theme

    public init(theme: Theme) {
        self.theme = theme
    }

    public var inlineStyle: InlineStyle {
        InlineStyle()
            .code(.monospaced, .fontScale(0.85), .backgroundColor(theme.codeBlock.background.dynamicColor))
            .strong(.fontWeight(.semibold))
            .link(.foregroundColor(theme.colors.link.dynamicColor))
    }

    public var headingStyle: ThemedHeadingStyle { .init(theme: theme) }
    public var paragraphStyle: ThemedParagraphStyle { .init(theme: theme) }
    public var blockQuoteStyle: ThemedBlockQuoteStyle { .init(theme: theme) }
    public var codeBlockStyle: ThemedCodeBlockStyle { .init(theme: theme) }
    public var listItemStyle: StructuredText.DefaultListItemStyle {
        .default(markerSpacing: .fontScaled(theme.resolvedList.markerSpacing))
    }
    public var unorderedListMarker: StructuredText.HierarchicalSymbolListMarker {
        .hierarchical(.disc, .circle, .square)
    }
    public var orderedListMarker: StructuredText.DecimalListMarker { .decimal }
    public var tableStyle: ThemedTableStyle { .init(theme: theme) }
    public var tableCellStyle: ThemedTableCellStyle { .init(theme: theme) }
    public var thematicBreakStyle: ThemedThematicBreakStyle { .init(theme: theme) }
}

// MARK: - Themed Highlighter Theme

extension Theme {
    public var highlighterTheme: StructuredText.HighlighterTheme {
        .default
    }
}
