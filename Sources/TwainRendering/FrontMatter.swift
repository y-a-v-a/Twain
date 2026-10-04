import Foundation

/// YAML front matter at the head of a Markdown document, parsed into an ordered tree.
///
/// Understands the YAML subset front matter uses in practice: block mappings and sequences,
/// plain and quoted scalars, folded (`>`) and literal (`|`) block scalars, flow sequences
/// (`[a, b]`) and comments. Anything else is kept as literal text, so the rendered table always
/// shows what the file says.
public struct FrontMatter: Equatable, Sendable {
    public indirect enum Value: Equatable, Sendable {
        case scalar(String)
        case sequence([Value])
        case mapping([Entry])
    }

    public struct Entry: Equatable, Sendable {
        public var key: String
        public var value: Value

        public init(key: String, value: Value) {
            self.key = key
            self.value = value
        }
    }

    public var entries: [Entry]

    public init(entries: [Entry]) {
        self.entries = entries
    }
}

// MARK: - Extraction

extension FrontMatter {
    /// Splits a leading front-matter block off `markdown`.
    ///
    /// The block must open with `---` on the first line, close with `---` or `...`, and parse
    /// as a YAML mapping; otherwise the document comes back untouched, so a document that
    /// merely opens with a thematic break keeps rendering as Markdown.
    public static func extract(from markdown: String) -> (frontMatter: FrontMatter?, body: String) {
        let lines = markdown.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        guard var opening = lines.first else { return (nil, markdown) }
        if opening.hasPrefix("\u{FEFF}") { opening = opening.dropFirst() }
        guard opening.trimmingCharacters(in: .whitespaces) == "---" else { return (nil, markdown) }

        guard let closingIndex = lines.indices.dropFirst().first(where: { index in
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            return line == "---" || line == "..."
        }) else { return (nil, markdown) }

        guard let entries = YAMLSubset.parseDocument(lines[1..<closingIndex]) else {
            return (nil, markdown)
        }

        let closing = lines[closingIndex]
        let bodyStart = closing.endIndex < markdown.endIndex
            ? markdown.index(after: closing.endIndex)
            : markdown.endIndex
        return (FrontMatter(entries: entries), String(markdown[bodyStart...]))
    }
}

// MARK: - Display

extension FrontMatter.Value {
    /// The value as it reads in a table cell: scalars verbatim, nested structures as indented
    /// YAML-style lines (Textual cannot nest tables inside a cell).
    public var displayText: String {
        displayLines.joined(separator: "\n")
    }

    /// A scalar that is a bare web address, so the cell can link it like GitHub does.
    public var linkURL: URL? {
        guard case .scalar(let text) = self,
              text.hasPrefix("https://") || text.hasPrefix("http://"),
              !text.contains(where: \.isWhitespace)
        else { return nil }
        return URL(string: text)
    }

    var displayLines: [String] {
        switch self {
        case .scalar(let text):
            return text.components(separatedBy: "\n")
        case .sequence(let items):
            return items.flatMap { item -> [String] in
                let lines = item.displayLines
                guard let first = lines.first else { return ["-"] }
                return ["- " + first] + lines.dropFirst().map { "  " + $0 }
            }
        case .mapping(let entries):
            return entries.flatMap { entry -> [String] in
                let lines = entry.value.displayLines
                if case .scalar = entry.value, lines.count == 1 {
                    return [lines[0].isEmpty ? "\(entry.key):" : "\(entry.key): \(lines[0])"]
                }
                return ["\(entry.key):"] + lines.map { "  " + $0 }
            }
        }
    }
}

// MARK: - YAML subset parser

private struct Line {
    let indent: Int
    let content: Substring

    static func parse(_ raw: Substring) -> Line {
        let content = raw.drop(while: { $0 == " " })
        return Line(indent: raw.distance(from: raw.startIndex, to: content.startIndex), content: content)
    }

    var isBlank: Bool { content.allSatisfy(\.isWhitespace) }
    var isIgnorable: Bool { isBlank || content.hasPrefix("#") }
    var isSequenceItem: Bool { content == "-" || content.hasPrefix("- ") }
}

private enum YAMLSubset {
    /// The top-level mapping, or nil when the block is not one (a stray line at the top level
    /// disqualifies the whole block — it was a thematic break, not front matter).
    static func parseDocument(_ raw: ArraySlice<Substring>) -> [FrontMatter.Entry]? {
        var parser = Parser(lines: raw.map(Line.parse))
        guard let first = parser.nextContentIndex() else { return [] }
        guard let entries = parser.parseMapping(indent: parser.lines[first].indent),
              parser.isAtEnd
        else { return nil }
        return entries
    }
}

private struct Parser {
    let lines: [Line]
    var position = 0

    var isAtEnd: Bool { nextContentIndex() == nil }

    func nextContentIndex() -> Int? {
        lines[position...].firstIndex(where: { !$0.isIgnorable })
    }

    /// `key: value` entries whose keys sit at `indent`. A shallower line ends the mapping; a
    /// line at `indent` that is not a key makes the mapping invalid.
    mutating func parseMapping(indent: Int) -> [FrontMatter.Entry]? {
        var entries: [FrontMatter.Entry] = []
        while let index = nextContentIndex() {
            let line = lines[index]
            if line.indent < indent { break }
            guard line.indent == indent, !line.isSequenceItem,
                  let (key, inline) = Self.keyValue(line.content)
            else { return nil }
            position = index + 1
            entries.append(.init(key: key, value: parseValue(inline: inline, indent: indent, sequenceAtIndent: true)))
        }
        return entries
    }

    /// `- item` lines at `indent`. A shallower line ends the sequence; a line at `indent` that
    /// is not an item makes the sequence invalid.
    mutating func parseSequence(indent: Int) -> [FrontMatter.Value]? {
        var items: [FrontMatter.Value] = []
        while let index = nextContentIndex() {
            let line = lines[index]
            if line.indent < indent { break }
            guard line.indent == indent, line.isSequenceItem else { return nil }
            position = index + 1

            let rest = line.content.dropFirst().drop(while: { $0 == " " })
            let restIndent = indent + line.content.distance(from: line.content.startIndex, to: rest.startIndex)
            let restLine = Line(indent: restIndent, content: rest)
            if !rest.isEmpty, restLine.isSequenceItem || Self.keyValue(rest) != nil {
                // `- key: value`: the item's first line shares the dash's line and its
                // siblings follow at the same column.
                items.append(parseBlock(from: position, parentIndent: indent, sequenceAtParent: false, leading: restLine))
            } else {
                items.append(parseValue(inline: rest, indent: indent, sequenceAtIndent: false))
            }
        }
        return items
    }

    /// The value after `key:` or `- `: inline text, a block scalar, or a nested block on the
    /// following lines. `sequenceAtIndent` allows the YAML shorthand of `- item` lines sitting
    /// at the parent key's own indentation.
    private mutating func parseValue(inline: Substring, indent: Int, sequenceAtIndent: Bool) -> FrontMatter.Value {
        let text = inline.trimmingCharacters(in: .whitespaces)
        if text.isEmpty {
            return parseNestedBlock(parentIndent: indent, sequenceAtParent: sequenceAtIndent)
        }
        if let folded = Self.blockScalarFolding(text) {
            return .scalar(parseBlockScalar(folded: folded, parentIndent: indent))
        }
        return parseInlineScalar(text, parentIndent: indent)
    }

    private mutating func parseNestedBlock(parentIndent: Int, sequenceAtParent: Bool) -> FrontMatter.Value {
        guard let index = nextContentIndex() else { return .scalar("") }
        let first = lines[index]
        let startsSequenceAtParent = sequenceAtParent && first.indent == parentIndent && first.isSequenceItem
        guard first.indent > parentIndent || startsSequenceAtParent else { return .scalar("") }
        return parseBlock(from: index, parentIndent: parentIndent, sequenceAtParent: startsSequenceAtParent)
    }

    /// Parses a nested mapping or sequence as one unit: the lines from `start` that belong under
    /// `parentIndent`, optionally preceded by `leading` (the text after `- ` on an item line).
    /// A block that doesn't parse cleanly is kept as literal text rather than dropped.
    private mutating func parseBlock(
        from start: Int,
        parentIndent: Int,
        sequenceAtParent: Bool,
        leading: Line? = nil
    ) -> FrontMatter.Value {
        let end = blockEnd(from: start, parentIndent: parentIndent, sequenceAtParent: sequenceAtParent)
        let blockLines = (leading.map { [$0] } ?? []) + Array(lines[start..<end])
        position = end

        var sub = Parser(lines: blockLines)
        guard let firstIndex = sub.nextContentIndex() else { return .scalar("") }
        let first = sub.lines[firstIndex]
        let parsed: FrontMatter.Value? = first.isSequenceItem
            ? sub.parseSequence(indent: first.indent).map(FrontMatter.Value.sequence)
            : sub.parseMapping(indent: first.indent).map(FrontMatter.Value.mapping)
        if let parsed, sub.isAtEnd { return parsed }
        return .scalar(Self.literalText(blockLines, baseIndent: first.indent))
    }

    /// Index just past the last line that belongs under `parentIndent`, starting at `start`.
    private func blockEnd(from start: Int, parentIndent: Int, sequenceAtParent: Bool) -> Int {
        var end = start
        for index in start..<lines.count {
            let line = lines[index]
            if line.isIgnorable { continue }
            let belongs = line.indent > parentIndent
                || (sequenceAtParent && line.indent == parentIndent && line.isSequenceItem)
            guard belongs else { break }
            end = index + 1
        }
        return end
    }

    /// Folded (`>`) or literal (`|`) block scalar header, allowing chomping and indentation
    /// indicators and a trailing comment; nil for anything else.
    private static func blockScalarFolding(_ text: String) -> Bool? {
        guard let first = text.first, first == "|" || first == ">" else { return nil }
        let indicators = text.dropFirst().drop(while: { $0 == "-" || $0 == "+" || $0.isNumber })
        let remainder = indicators.trimmingCharacters(in: .whitespaces)
        guard remainder.isEmpty || remainder.hasPrefix("#") else { return nil }
        return first == ">"
    }

    private mutating func parseBlockScalar(folded: Bool, parentIndent: Int) -> String {
        var collected: [Line] = []
        while position < lines.count {
            let line = lines[position]
            guard line.isBlank || line.indent > parentIndent else { break }
            collected.append(line)
            position += 1
        }
        while collected.first?.isBlank == true { collected.removeFirst() }
        while collected.last?.isBlank == true { collected.removeLast() }
        guard let blockIndent = collected.first?.indent else { return "" }

        let texts = collected.map { line in
            line.isBlank ? "" : String(repeating: " ", count: max(line.indent - blockIndent, 0)) + line.content
        }
        guard folded else { return texts.joined(separator: "\n") }

        var result = ""
        var previousWasText = false
        for text in texts {
            if text.isEmpty {
                result += "\n"
                previousWasText = false
            } else {
                if previousWasText { result += " " }
                result += text
                previousWasText = true
            }
        }
        return result
    }

    private mutating func parseInlineScalar(_ text: String, parentIndent: Int) -> FrontMatter.Value {
        if let unquoted = Self.unquote(text) {
            return .scalar(unquoted)
        }
        let stripped = Self.strippingComment(text)
        if stripped.hasPrefix("["), stripped.hasSuffix("]") {
            return .sequence(Self.flowSequenceItems(stripped).map(FrontMatter.Value.scalar))
        }

        // A plain scalar may continue on more-indented lines; YAML folds them with spaces.
        var parts = [stripped]
        while let index = nextContentIndex(), lines[index].indent > parentIndent {
            parts.append(Self.strippingComment(String(lines[index].content)))
            position = index + 1
        }
        return .scalar(parts.joined(separator: " "))
    }

    /// Splits `key: value` / `key:`; nil when the line is not a mapping entry.
    private static func keyValue(_ content: Substring) -> (key: String, inline: Substring)? {
        guard let first = content.first, !"#[]{}|>!&*%@`,?".contains(first) else { return nil }

        if first == "\"" || first == "'" {
            let afterOpening = content.index(after: content.startIndex)
            guard let closing = content[afterOpening...].firstIndex(of: first) else { return nil }
            let colon = content.index(after: closing)
            guard colon < content.endIndex, content[colon] == ":" else { return nil }
            let afterColon = content.index(after: colon)
            guard afterColon == content.endIndex || content[afterColon] == " " else { return nil }
            return (String(content[afterOpening..<closing]), content[afterColon...])
        }

        var index = content.startIndex
        while index < content.endIndex {
            if content[index] == ":" {
                let next = content.index(after: index)
                if next == content.endIndex || content[next] == " " || content[next] == "\t" {
                    let key = content[..<index].trimmingCharacters(in: .whitespaces)
                    guard !key.isEmpty else { return nil }
                    return (key, content[next...])
                }
            }
            index = content.index(after: index)
        }
        return nil
    }

    /// The content of a fully quoted scalar; nil when the text is not quoted or the quote
    /// never closes (a multi-line quoted scalar then reads as plain text, quotes included).
    private static func unquote(_ text: String) -> String? {
        guard let quote = text.first, quote == "\"" || quote == "'" else { return nil }
        let chars = Array(text)
        var result = ""
        var index = 1
        while index < chars.count {
            let char = chars[index]
            if quote == "\"", char == "\\", index + 1 < chars.count {
                switch chars[index + 1] {
                case "n": result.append("\n")
                case "t": result.append("\t")
                case let escaped: result.append(escaped)
                }
                index += 2
                continue
            }
            if char == quote {
                if quote == "'", index + 1 < chars.count, chars[index + 1] == "'" {
                    result.append("'")
                    index += 2
                    continue
                }
                return result
            }
            result.append(char)
            index += 1
        }
        return nil
    }

    /// Removes a trailing ` # comment`; a `#` inside quotes or glued to text is content.
    private static func strippingComment(_ text: String) -> String {
        var inSingle = false
        var inDouble = false
        var previous: Character = " "
        for index in text.indices {
            let char = text[index]
            if char == "'", !inDouble {
                inSingle.toggle()
            } else if char == "\"", !inSingle {
                inDouble.toggle()
            } else if char == "#", !inSingle, !inDouble, previous.isWhitespace {
                return text[..<index].trimmingCharacters(in: .whitespaces)
            }
            previous = char
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    /// Items of a single-line flow sequence such as `[a, "b, c", d]`.
    private static func flowSequenceItems(_ text: String) -> [String] {
        var items: [String] = []
        var current = ""
        var inSingle = false
        var inDouble = false
        var depth = 0
        for char in text.dropFirst().dropLast() {
            if char == "'", !inDouble {
                inSingle.toggle()
            } else if char == "\"", !inSingle {
                inDouble.toggle()
            } else if !inSingle, !inDouble {
                if char == "[" || char == "{" {
                    depth += 1
                } else if char == "]" || char == "}" {
                    depth -= 1
                } else if char == ",", depth == 0 {
                    items.append(current)
                    current = ""
                    continue
                }
            }
            current.append(char)
        }
        items.append(current)
        return items.compactMap { item in
            let trimmed = item.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            return unquote(trimmed) ?? trimmed
        }
    }

    /// The block's lines as written, re-based to `baseIndent`, for values the subset parser
    /// does not understand.
    private static func literalText(_ lines: [Line], baseIndent: Int) -> String {
        var texts = lines.map { line in
            line.isBlank ? "" : String(repeating: " ", count: max(line.indent - baseIndent, 0)) + line.content
        }
        while texts.last?.isEmpty == true { texts.removeLast() }
        return texts.joined(separator: "\n")
    }
}
