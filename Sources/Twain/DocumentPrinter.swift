import AppKit
import PDFKit
import SwiftUI
import Textual
import UniformTypeIdentifiers

// MARK: - Print Job

/// Everything needed to reproduce a document window's on-screen rendering for printing,
/// captured as plain values so the print pipeline doesn't reach back into live view state.
struct PrintJob {
    var markdown: String
    var theme: Theme
    var fontSize: Double
    var useSerifFont: Bool
    /// Shown in the print queue and used as the suggested PDF file name.
    var title: String
}

// MARK: - Print Markdown Parser

/// The same parse the document windows use (Apple's Markdown parser plus Twain's task-list
/// marker expansion), without the search-highlight overlay.
struct PrintMarkdownParser: MarkupParser {
    func attributedString(for input: String) throws -> AttributedString {
        try AttributedStringMarkdownParser(baseURL: nil)
            .attributedString(for: input)
            .expandingTaskListMarkers()
    }
}

// MARK: - Pagination

/// Chooses page-break positions in content coordinates (y grows downward, 0 = content top).
/// Pure logic, separated from the rendering machinery so it can be unit tested.
enum PrintPagination {
    /// How far above the natural page bottom a break may move while hunting for a clean row.
    /// A page never shrinks below this fraction of the full page height.
    static let minPageFraction: CGFloat = 0.7

    /// Returns the bottom edge of every page; the last entry is always `contentHeight`.
    ///
    /// `isCleanRow(y)` reports whether the 1-point row at `y` renders as uniform background —
    /// a break placed there cannot slice a line of text. When no clean row exists in the
    /// allowed window (e.g. inside a code block taller than a page), the break falls back to
    /// the natural page bottom.
    static func pageBottoms(
        contentHeight: CGFloat,
        pageHeight: CGFloat,
        isCleanRow: (CGFloat) -> Bool
    ) -> [CGFloat] {
        let contentHeight = max(contentHeight, 1)
        guard pageHeight > 0 else { return [contentHeight] }

        var bottoms: [CGFloat] = []
        var top: CGFloat = 0
        while contentHeight - top > pageHeight {
            let proposed = top + pageHeight
            let limit = top + pageHeight * minPageFraction
            let bottom = snappedBottom(proposed: proposed, limit: limit, isCleanRow: isCleanRow)
                ?? proposed
            bottoms.append(bottom)
            top = bottom
        }
        bottoms.append(contentHeight)
        return bottoms
    }

    /// The clean row nearest to (at or above) `proposed`, but never above `limit`.
    static func snappedBottom(
        proposed: CGFloat,
        limit: CGFloat,
        isCleanRow: (CGFloat) -> Bool
    ) -> CGFloat? {
        var y = proposed.rounded(.down)
        while y >= limit {
            if isCleanRow(y) { return y }
            y -= 1
        }
        return nil
    }
}

// MARK: - Document Printer

/// Renders a document to paginated, vector PDF output. The whole document is laid out once
/// with `ImageRenderer` and composed into PDF pages directly (`makePDFData`), so text in the
/// output stays real, selectable text. `runPrintPanel` shows the native print panel for that
/// PDF (whose PDF menu covers "Save as PDF" and friends); `exportPDF` writes a file directly
/// for the Export as PDF… menu item.
@MainActor
enum DocumentPrinter {
    /// Page margins for printed output, standing in for the theme's on-screen `contentInset`.
    static let pageMargin: CGFloat = 54

    /// Row scans above this many points of content are skipped (the raster would be too
    /// large); page breaks then fall back to natural page-height positions.
    static let maxScanHeight: CGFloat = 100_000

    // MARK: Entry points

    static func runPrintPanel(job: PrintJob, attachedTo window: NSWindow?) {
        guard let data = makePDFData(job: job, paperSize: defaultPaperSize()),
              let document = PDFDocument(data: data)
        else { return }

        let info = NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo()
        // Pages are pre-composed with their own margins; print them 1:1.
        info.topMargin = 0
        info.bottomMargin = 0
        info.leftMargin = 0
        info.rightMargin = 0

        guard let operation = document.printOperation(
            for: info,
            scalingMode: .pageScaleDownToFit,
            autoRotate: false
        ) else { return }

        operation.jobTitle = job.title
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        if let window {
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            operation.run()
        }
    }

    static func presentPDFExportPanel(job: PrintJob, attachedTo window: NSWindow?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = job.title + ".pdf"
        let export: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            exportPDF(job: job, to: url)
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: export)
        } else {
            export(panel.runModal())
        }
    }

    @discardableResult
    static func exportPDF(job: PrintJob, to url: URL, paperSize: CGSize? = nil) -> Bool {
        guard let data = makePDFData(job: job, paperSize: paperSize ?? defaultPaperSize())
        else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    /// The user's default paper size, from the system print settings.
    static func defaultPaperSize() -> CGSize {
        NSPrintInfo.shared.paperSize
    }

    // MARK: PDF composition

    /// Lays the document out once at the paper's body width, splits it at clean rows, and
    /// draws each page slice into a PDF context (translate + clip per page).
    static func makePDFData(
        job: PrintJob,
        paperSize: CGSize,
        margin: CGFloat = pageMargin
    ) -> Data? {
        let bodyWidth = paperSize.width - 2 * margin
        let bodyHeight = paperSize.height - 2 * margin
        guard bodyWidth > 0, bodyHeight > 0 else { return nil }

        let renderer = ImageRenderer(content: AnyView(printContent(job: job, width: bodyWidth)))
        renderer.proposedSize = ProposedViewSize(width: bodyWidth, height: nil)

        // Two ImageRenderer quirks shape the structure here, both found empirically:
        // - The very first render pass reports a pre-settlement layout (text measured
        //   unwrapped), so a warm-up pass runs first and all measurements come from the
        //   second pass. Passes after the first are stable and identical.
        // - The draw closure a render pass hands out renders correctly only on its first
        //   invocation — repeated calls within one pass drop text runs and drift. So the
        //   break scan and every page each run in their own render pass.
        renderer.render { _, _ in }

        var contentSize = CGSize.zero
        var cleanRows: [Bool] = []
        renderer.render { size, draw in
            contentSize = size
            cleanRows = rowScan(contentSize: size, draw: draw)
        }
        guard contentSize.width > 0 else { return nil }

        let bottoms = PrintPagination.pageBottoms(
            contentHeight: contentSize.height,
            pageHeight: bodyHeight
        ) { y in
            let index = Int(y.rounded(.down))
            return cleanRows.indices.contains(index) && cleanRows[index]
        }

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return nil }
        var mediaBox = CGRect(origin: .zero, size: paperSize)
        let metadata = [kCGPDFContextTitle: job.title] as CFDictionary
        guard let pdf = CGContext(consumer: consumer, mediaBox: &mediaBox, metadata)
        else { return nil }

        // The renderer draws the content in Core Graphics coordinates (y up), spanning
        // 0...contentHeight with the content's top at y = contentHeight. Each page
        // translates the content so its slice lands in the page body, then clips to it.
        var top: CGFloat = 0
        for bottom in bottoms {
            renderer.render { _, draw in
                pdf.beginPDFPage(nil)
                pdf.saveGState()
                pdf.clip(to: CGRect(
                    x: margin,
                    y: paperSize.height - margin - (bottom - top),
                    width: bodyWidth,
                    height: bottom - top
                ))
                pdf.translateBy(
                    x: margin,
                    y: paperSize.height - margin - contentSize.height + top
                )
                draw(pdf)
                pdf.restoreGState()
                pdf.endPDFPage()
            }
            top = bottom
        }
        pdf.closePDF()
        return data as Data
    }

    /// Rasterizes the content once at 1× into a grayscale bitmap and marks the rows that are
    /// uniform background — the rows page breaks may land on. Row indices count down from the
    /// content top, matching the pagination coordinates.
    private static func rowScan(
        contentSize: CGSize,
        draw: (CGContext) -> Void
    ) -> [Bool] {
        let width = Int(contentSize.width.rounded())
        let height = Int(contentSize.height.rounded(.up))
        guard width > 0, height > 0, contentSize.height <= maxScanHeight,
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceGray(),
                  bitmapInfo: CGImageAlphaInfo.none.rawValue
              )
        else { return [] }

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        draw(context)

        guard let image = context.makeImage() else { return [] }
        return uniformRows(in: image)
    }

    /// Marks each pixel row of `image` that is a single uniform color; those rows are safe
    /// page-break positions because no glyph or decoration crosses them. Row 0 is the top.
    static func uniformRows(in image: CGImage) -> [Bool] {
        guard let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data)
        else { return [] }

        let width = image.width
        let height = image.height
        let bytesPerRow = image.bytesPerRow
        let bytesPerPixel = image.bitsPerPixel / 8
        guard width > 0, height > 0, bytesPerPixel > 0 else { return [] }

        var rows = [Bool](repeating: false, count: height)
        for y in 0..<height {
            let row = bytes + y * bytesPerRow
            var clean = true
            for x in 1..<width where memcmp(row, row + x * bytesPerPixel, bytesPerPixel) != 0 {
                clean = false
                break
            }
            rows[y] = clean
        }
        return rows
    }

    // MARK: Content

    /// The document view rebuilt for paper: the same parse and themed styles as ContentView's
    /// on-screen stack (keep the modifiers in sync), minus search, with overflowing code blocks
    /// wrapped instead of scrolled, and always in the light color scheme — printing a dark
    /// theme's background would be unreadable on paper.
    static func printContent(job: PrintJob, width: CGFloat) -> some View {
        let theme = job.theme
        let family = job.useSerifFont ? theme.serifFontFamily : theme.sansSerifFontFamily
        let font: Font = family.map { .custom($0, size: job.fontSize) }
            ?? .system(size: job.fontSize)

        return StructuredText(job.markdown, parser: PrintMarkdownParser())
            .font(font)
            .fontDesign(job.useSerifFont && theme.serifFontFamily == nil ? .serif : .default)
            .textual.highlighterTheme(theme.highlighterTheme)
            .textual.structuredTextStyle(ThemedStructuredTextStyle(theme: theme))
            .textual.listItemSpacing(.fontScaled(top: theme.resolvedList.resolvedItemSpacing))
            .textual.overflowMode(.wrap)
            .foregroundStyle(theme.colors.primary.dynamicColor)
            .frame(width: width, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background(theme.colors.background.dynamicColor)
            .environment(\.colorScheme, .light)
    }
}
