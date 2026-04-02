import SwiftUI
import Textual

// MARK: - Themed Heading Style

struct ThemedHeadingStyle: StructuredText.HeadingStyle {
    let theme: Theme

    func makeBody(configuration: Configuration) -> some View {
        let level = max(1, min(configuration.headingLevel, 6))
        let scales = theme.headings.fontScales
        let fontScale = level <= scales.count ? scales[level - 1] : 1.0

        VStack(alignment: .leading, spacing: 4) {
            makeLabel(configuration: configuration)
                .textual.fontScale(fontScale)
                .textual.lineSpacing(.fontScaled(0.125))
                .textual.blockSpacing(.init(top: 24, bottom: 16))
                .fontWeight(theme.headings.weight)
            if level <= 2 {
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

struct ThemedCodeBlockStyle: StructuredText.CodeBlockStyle {
    let theme: Theme

    func makeBody(configuration: Configuration) -> some View {
        Overflow {
            configuration.label
                .textual.lineSpacing(.fontScaled(0.225))
                .textual.fontScale(theme.codeBlock.fontScale)
                .fixedSize(horizontal: false, vertical: true)
                .monospaced()
                .padding(theme.codeBlock.padding)
        }
        .background(theme.codeBlock.background.dynamicColor)
        .clipShape(RoundedRectangle(cornerRadius: theme.codeBlock.cornerRadius))
        .textual.blockSpacing(.init(top: 0, bottom: 16))
    }
}

// MARK: - Themed Block Quote Style

struct ThemedBlockQuoteStyle: StructuredText.BlockQuoteStyle {
    let theme: Theme

    func makeBody(configuration: Configuration) -> some View {
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

struct ThemedParagraphStyle: StructuredText.ParagraphStyle {
    let theme: Theme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textual.lineSpacing(.fontScaled(theme.paragraph.lineSpacingScale))
            .textual.blockSpacing(.init(top: 0, bottom: theme.paragraph.bottomSpacing))
    }
}

// MARK: - Themed Table Style

struct ThemedTableStyle: StructuredText.TableStyle {
    let theme: Theme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textual.tableCellSpacing(horizontal: 1, vertical: 1)
            .textual.blockSpacing(.init(top: 0, bottom: 16))
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
            .padding(1)
            .border(theme.colors.border.dynamicColor, width: 1)
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

struct ThemedTableCellStyle: StructuredText.TableCellStyle {
    let theme: Theme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(configuration.row == 0 ? .semibold : .regular)
            .padding(.vertical, 6)
            .padding(.horizontal, 13)
            .textual.lineSpacing(.fontScaled(0.25))
    }
}

// MARK: - Themed Thematic Break Style

struct ThemedThematicBreakStyle: StructuredText.ThematicBreakStyle {
    let theme: Theme

    func makeBody(configuration _: Configuration) -> some View {
        Divider()
            .textual.frame(height: .fontScaled(0.25))
            .overlay(theme.colors.border.dynamicColor)
            .textual.blockSpacing(.init(top: 24, bottom: 24))
    }
}

// MARK: - Themed Structured Text Style

struct ThemedStructuredTextStyle: StructuredText.Style {
    let theme: Theme

    var inlineStyle: InlineStyle {
        InlineStyle()
            .code(.monospaced, .fontScale(0.85), .backgroundColor(theme.codeBlock.background.dynamicColor))
            .strong(.fontWeight(.semibold))
            .link(.foregroundColor(theme.colors.link.dynamicColor))
    }

    var headingStyle: ThemedHeadingStyle { .init(theme: theme) }
    var paragraphStyle: ThemedParagraphStyle { .init(theme: theme) }
    var blockQuoteStyle: ThemedBlockQuoteStyle { .init(theme: theme) }
    var codeBlockStyle: ThemedCodeBlockStyle { .init(theme: theme) }
    var listItemStyle: StructuredText.DefaultListItemStyle { .default }
    var unorderedListMarker: StructuredText.HierarchicalSymbolListMarker {
        .hierarchical(.disc, .circle, .square)
    }
    var orderedListMarker: StructuredText.DecimalListMarker { .decimal }
    var tableStyle: ThemedTableStyle { .init(theme: theme) }
    var tableCellStyle: ThemedTableCellStyle { .init(theme: theme) }
    var thematicBreakStyle: ThemedThematicBreakStyle { .init(theme: theme) }
}

// MARK: - Themed Highlighter Theme

extension Theme {
    var highlighterTheme: StructuredText.HighlighterTheme {
        .default
    }
}
