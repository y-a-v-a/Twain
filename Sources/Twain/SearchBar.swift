import SwiftUI
import Textual

// MARK: - Highlighting Markdown Parser

@MainActor
final class HighlightingMarkdownCache {
    private let baseParser = AttributedStringMarkdownParser(baseURL: nil)

    private(set) var markdown: String = ""
    private(set) var attributedString = AttributedString()
    private(set) var plainText: String = ""

    func prepare(markdown: String) throws {
        guard markdown != self.markdown else { return }

        let parsed = try baseParser.attributedString(for: markdown)
        self.markdown = markdown
        attributedString = parsed
        plainText = String(parsed.characters)
    }
}

struct HighlightingMarkdownParser: MarkupParser {
    /// Private Use Area character used to separate real content from the search trigger suffix.
    static let separator: Character = "\u{E000}"

    let matches: [Range<Int>]
    let currentMatchIndex: Int
    private let baseParser = AttributedStringMarkdownParser(baseURL: nil)

    func attributedString(for input: String) throws -> AttributedString {
        var result = try baseParser.attributedString(for: Self.markdown(from: input))

        guard !matches.isEmpty else { return result }

        for (index, match) in matches.enumerated() {
            let lowerBound = result.characters.index(result.startIndex, offsetBy: match.lowerBound)
            let upperBound = result.characters.index(result.startIndex, offsetBy: match.upperBound)
            let isCurrent = index == currentMatchIndex

            result[lowerBound..<upperBound].swiftUI.backgroundColor =
                isCurrent ? .orange.opacity(0.5) : .yellow.opacity(0.25)
        }

        return result
    }

    static func markdown(from input: String) -> String {
        guard let separatorIndex = input.firstIndex(of: separator) else {
            return input
        }

        return String(input[..<separatorIndex])
    }
}

// MARK: - Search State

struct SearchScrollTarget: Equatable {
    let query: String
    let lowerBound: Int?
    let documentRevision: Int
}

private struct RenderedBlock {
    enum LayoutModel {
        case character
        case explicitLines(lineStartOffsets: [Int])
    }

    let range: Range<Int>
    let topSurround: CGFloat
    let contentHeight: CGFloat
    let bottomSurround: CGFloat
    let layoutModel: LayoutModel

    var weight: CGFloat { topSurround + contentHeight + bottomSurround }

    func contains(_ offset: Int) -> Bool {
        range.contains(offset)
    }

    func localFraction(for offset: Int) -> CGFloat {
        guard weight > 0 else { return 0 }
        let localOffset = max(0, min(offset - range.lowerBound, max(range.count - 1, 0)))

        let positionWithinContent: CGFloat = {
            switch layoutModel {
            case .character:
                let denom = CGFloat(max(range.count, 1))
                return contentHeight * CGFloat(localOffset) / denom
            case .explicitLines(let lineStartOffsets):
                guard !lineStartOffsets.isEmpty else { return 0 }
                let lineIndex = CGFloat(lineStartOffsets.lastIndex(where: { $0 <= localOffset }) ?? 0)
                let lineCount = CGFloat(lineStartOffsets.count)
                return contentHeight * (lineIndex + 0.5) / lineCount
            }
        }()

        return (topSurround + positionWithinContent) / weight
    }
}

@MainActor @Observable
final class SearchState {
    var query: String = ""

    private(set) var matches: [Range<Int>] = []
    private(set) var currentMatchIndex: Int = 0

    private var renderedText: String = ""
    private var blocks: [RenderedBlock] = []
    private var documentRevision: Int = 0
    private(set) var renderRevision: Int = 0

    private let layout: BlockLayoutMetrics

    init(layout: BlockLayoutMetrics) {
        self.layout = layout
    }

    var matchCount: Int { matches.count }
    var hasMatches: Bool { !matches.isEmpty }

    var scrollTarget: SearchScrollTarget {
        SearchScrollTarget(
            query: query,
            lowerBound: hasMatches ? matches[currentMatchIndex].lowerBound : nil,
            documentRevision: documentRevision
        )
    }

    func updateDocument(markdown: String, using cache: HighlightingMarkdownCache) {
        do {
            try cache.prepare(markdown: markdown)
            renderedText = cache.plainText
            blocks = Self.makeBlocks(from: cache.attributedString, layout: layout)
            documentRevision += 1
            rebuildMatches(resetSelection: false)
            renderRevision += 1
        } catch {
            renderedText = ""
            blocks = []
            matches = []
            currentMatchIndex = 0
            documentRevision += 1
            renderRevision += 1
        }
    }

    func updateQuery(_ query: String) {
        guard self.query != query else { return }
        self.query = query
        rebuildMatches(resetSelection: true)
        renderRevision += 1
    }

    func nextMatch() {
        guard hasMatches else { return }
        currentMatchIndex = (currentMatchIndex + 1) % matchCount
        renderRevision += 1
    }

    func previousMatch() {
        guard hasMatches else { return }
        currentMatchIndex = (currentMatchIndex - 1 + matchCount) % matchCount
        renderRevision += 1
    }

    func reset() {
        query = ""
        matches = []
        currentMatchIndex = 0
        renderRevision += 1
    }

    /// Approximate vertical position (0.0–1.0) of the current match within the rendered document.
    var currentMatchFraction: CGFloat? {
        guard hasMatches, !renderedText.isEmpty else { return nil }

        let matchOffset = matches[currentMatchIndex].lowerBound

        guard let blockIndex = Self.blockIndex(containing: matchOffset, in: blocks) else {
            return CGFloat(matchOffset) / CGFloat(max(renderedText.count, 1))
        }

        let totalWeight = blocks.reduce(CGFloat.zero) { $0 + $1.weight }
        guard totalWeight > 0 else {
            return CGFloat(matchOffset) / CGFloat(max(renderedText.count, 1))
        }

        let block = blocks[blockIndex]
        let weightBefore = blocks[..<blockIndex].reduce(CGFloat.zero) { $0 + $1.weight }
        let localFraction = block.localFraction(for: matchOffset)
        let weightedFraction = (weightBefore + (localFraction * block.weight)) / totalWeight

        // Bias slightly upward so the active hit lands below the search bar more often.
        return min(max(weightedFraction - 0.03, 0), 1)
    }

    private func rebuildMatches(resetSelection: Bool) {
        guard !query.isEmpty, !renderedText.isEmpty else {
            matches = []
            currentMatchIndex = 0
            return
        }

        let previousLowerBound = hasMatches ? matches[currentMatchIndex].lowerBound : nil
        matches = Self.findMatches(of: query, in: renderedText)

        guard hasMatches else {
            currentMatchIndex = 0
            return
        }

        if resetSelection {
            currentMatchIndex = 0
            return
        }

        if let previousLowerBound,
           let existingIndex = matches.firstIndex(where: { $0.lowerBound >= previousLowerBound })
        {
            currentMatchIndex = existingIndex
        } else {
            currentMatchIndex = min(currentMatchIndex, matches.count - 1)
        }
    }

    private static func findMatches(of query: String, in text: String) -> [Range<Int>] {
        var found: [Range<Int>] = []
        var searchRange = text.startIndex..<text.endIndex

        while let range = text.range(of: query, options: .caseInsensitive, range: searchRange) {
            let lowerBound = text.distance(from: text.startIndex, to: range.lowerBound)
            let upperBound = text.distance(from: text.startIndex, to: range.upperBound)

            found.append(lowerBound..<upperBound)
            searchRange = range.upperBound..<text.endIndex
        }

        return found
    }

    private static func makeBlocks(
        from attributedString: AttributedString,
        layout: BlockLayoutMetrics
    ) -> [RenderedBlock] {
        let runs = topLevelBlockRuns(in: attributedString)

        let blocks = runs.compactMap { run -> RenderedBlock? in
            let lowerBound = attributedString.characters.distance(
                from: attributedString.startIndex,
                to: run.range.lowerBound
            )
            let upperBound = attributedString.characters.distance(
                from: attributedString.startIndex,
                to: run.range.upperBound
            )

            guard upperBound > lowerBound else { return nil }

            let blockText = String(attributedString[run.range].characters)
            return makeRenderedBlock(
                range: lowerBound..<upperBound,
                text: blockText,
                intent: run.intent,
                tableRowCount: run.tableRowCount,
                layout: layout
            )
        }

        if blocks.isEmpty, !attributedString.characters.isEmpty {
            let text = String(attributedString.characters)
            return [
                makeRenderedBlock(
                    range: 0..<text.count,
                    text: text,
                    intent: nil,
                    tableRowCount: 0,
                    layout: layout
                )
            ]
        }

        return blocks
    }

    private static func blockIndex(containing offset: Int, in blocks: [RenderedBlock]) -> Int? {
        guard !blocks.isEmpty else { return nil }

        if let exactIndex = blocks.firstIndex(where: { $0.contains(offset) }) {
            return exactIndex
        }

        if let nearestPreviousIndex = blocks.lastIndex(where: { $0.range.lowerBound <= offset }) {
            return nearestPreviousIndex
        }

        return blocks.startIndex
    }

    private static func makeRenderedBlock(
        range: Range<Int>,
        text: String,
        intent: PresentationIntent.IntentType?,
        tableRowCount: Int,
        layout: BlockLayoutMetrics
    ) -> RenderedBlock {
        let pt = layout.pointsPerLineUnit

        switch intent?.kind {
        case .header(let level):
            let scales = layout.headingScales
            let clamped = max(1, min(level, max(scales.count, 1)))
            let scale = scales.isEmpty ? 1.0 : scales[clamped - 1]
            let dividerExtra: CGFloat = (level <= layout.headingDividerMaxLevel)
                ? (layout.headingDividerGap + layout.headingDividerThickness)
                : 0
            return RenderedBlock(
                range: range,
                topSurround: layout.headingTopSpacing / pt,
                contentHeight: estimatedLineUnits(for: text) * scale,
                bottomSurround: (layout.headingBottomSpacing + dividerExtra) / pt,
                layoutModel: .character
            )
        case .codeBlock:
            let offsets = lineStartOffsets(for: text)
            let lineCount = CGFloat(max(offsets.count, 1))
            return RenderedBlock(
                range: range,
                topSurround: layout.codeBlockPadding / pt,
                contentHeight: lineCount * layout.codeBlockFontScale,
                bottomSurround: (layout.codeBlockPadding + layout.codeBlockBottomSpacing) / pt,
                layoutModel: .explicitLines(lineStartOffsets: offsets)
            )
        case .table:
            // Row-based: one content line + cell vertical padding + row divider, per row.
            // Character-based fallback (72-chars-per-line) doesn't apply — cells are 2D, not flowing.
            let rows = CGFloat(max(tableRowCount, 1))
            let perRowPoints = pt
                + (2 * layout.tableCellVerticalPadding)
                + layout.tableCellSpacing
            let frame = layout.tableInnerPadding + layout.tableOuterBorderWidth
            return RenderedBlock(
                range: range,
                topSurround: frame / pt,
                contentHeight: rows * perRowPoints / pt,
                bottomSurround: (frame + layout.tableBottomSpacing) / pt,
                layoutModel: .character
            )
        case .thematicBreak:
            return RenderedBlock(
                range: range,
                topSurround: layout.thematicBreakTopSpacing / pt,
                contentHeight: layout.thematicBreakRuleFontScale,
                bottomSurround: layout.thematicBreakBottomSpacing / pt,
                layoutModel: .character
            )
        case .paragraph, nil:
            return RenderedBlock(
                range: range,
                topSurround: 0,
                contentHeight: estimatedLineUnits(for: text),
                bottomSurround: layout.paragraphBottomSpacing / pt,
                layoutModel: .character
            )
        case .blockQuote, .orderedList, .unorderedList, .listItem,
             .tableHeaderRow, .tableRow, .tableCell:
            return RenderedBlock(
                range: range,
                topSurround: 0,
                contentHeight: estimatedLineUnits(for: text),
                bottomSurround: 0,
                layoutModel: .character
            )
        @unknown default:
            return RenderedBlock(
                range: range,
                topSurround: 0,
                contentHeight: estimatedLineUnits(for: text),
                bottomSurround: 0,
                layoutModel: .character
            )
        }
    }

    private static func estimatedLineUnits(for text: String) -> CGFloat {
        let approximateCharactersPerLine = 72.0
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)

        let wrappedLineCount = lines.reduce(into: 0) { total, line in
            total += max(Int(ceil(Double(max(line.count, 1)) / approximateCharactersPerLine)), 1)
        }

        return CGFloat(max(wrappedLineCount, 1))
    }

    private static func lineStartOffsets(for text: String) -> [Int] {
        guard !text.isEmpty else { return [0] }

        var offsets: [Int] = [0]
        for (offset, character) in text.enumerated() where character.isNewline {
            let nextOffset = offset + 1
            if nextOffset < text.count {
                offsets.append(nextOffset)
            }
        }

        return offsets
    }

    private static func topLevelBlockRuns(
        in attributedString: AttributedString
    ) -> [(
        intent: PresentationIntent.IntentType?,
        range: Range<AttributedString.Index>,
        tableRowCount: Int
    )] {
        struct Boundary {
            let index: AttributedString.Runs.Index
            let intent: PresentationIntent.IntentType?
        }

        let runs = attributedString.runs
        var boundaries: [Boundary] = []
        var lastIntent: PresentationIntent.IntentType?

        for index in runs.indices {
            // Prefer the enclosing table (if any) over the innermost intent so that every
            // cell of a table collapses into one block — otherwise each cell becomes its
            // own vertically-stacked block and the table's height is wildly overcounted.
            let components = runs[index].presentationIntent?.components
            let tableIntent = components?.first { component in
                if case .table = component.kind { return true }
                return false
            }
            let intent = tableIntent ?? components?.last

            if boundaries.isEmpty || intent != lastIntent {
                boundaries.append(Boundary(index: index, intent: intent))
                lastIntent = intent
            }
        }

        return boundaries.enumerated().map { offset, boundary in
            let nextRunIndex =
                (offset + 1 < boundaries.count)
                ? boundaries[offset + 1].index
                : runs.endIndex
            let lastRunIndex = runs.index(before: nextRunIndex)
            let lowerBound = runs[boundary.index].range.lowerBound
            let upperBound = runs[lastRunIndex].range.upperBound

            var tableRowCount = 0
            if case .table = boundary.intent?.kind {
                var identities: Set<Int> = []
                var cursor = boundary.index
                while cursor < nextRunIndex {
                    if let components = runs[cursor].presentationIntent?.components {
                        for component in components {
                            switch component.kind {
                            case .tableHeaderRow, .tableRow:
                                identities.insert(component.identity)
                            default:
                                break
                            }
                        }
                    }
                    cursor = runs.index(after: cursor)
                }
                tableRowCount = identities.count
            }

            return (boundary.intent, lowerBound..<upperBound, tableRowCount)
        }
    }
}

struct SearchBar: View {
    @Bindable var searchState: SearchState
    @FocusState private var isFieldFocused: Bool
    var onDismiss: () -> Void

    private var queryBinding: Binding<String> {
        Binding(
            get: { searchState.query },
            set: { searchState.updateQuery($0) }
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))

                TextField("Search…", text: queryBinding)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isFieldFocused)
                    .onSubmit {
                        if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                            searchState.previousMatch()
                        } else {
                            searchState.nextMatch()
                        }
                    }

                if !searchState.query.isEmpty {
                    Text(matchLabel)
                        .foregroundStyle(.secondary)
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .layoutPriority(1)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.thickMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(.quaternary, lineWidth: 0.5)
            )

            Button(action: { searchState.previousMatch() }) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.borderless)
            .disabled(!searchState.hasMatches)

            Button(action: { searchState.nextMatch() }) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.borderless)
            .disabled(!searchState.hasMatches)

            Button("", systemImage: "xmark", action: onDismiss)
                .buttonStyle(.borderless)
                .font(.system(size: 11, weight: .medium))
                .labelStyle(.iconOnly)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
        .onAppear { isFieldFocused = true }
    }

    private var matchLabel: String {
        if searchState.matches.isEmpty {
            return "No matches"
        }

        return "\(searchState.currentMatchIndex + 1) of \(searchState.matchCount)"
    }
}
