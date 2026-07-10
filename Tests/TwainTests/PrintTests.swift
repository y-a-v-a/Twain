import Testing
import AppKit
import PDFKit
import SwiftUI
@testable import Twain

// MARK: - Pagination logic

struct PrintPaginationTests {
    @Test func singlePageWhenContentFits() {
        let bottoms = PrintPagination.pageBottoms(contentHeight: 300, pageHeight: 700) { _ in true }
        #expect(bottoms == [300])
    }

    @Test func breaksSnapToNearestCleanRowAbove() {
        // Clean bands just above each natural break; the break must snap up into them.
        let bottoms = PrintPagination.pageBottoms(contentHeight: 250, pageHeight: 100) { y in
            (80.0...85.0).contains(y) || (160.0...165.0).contains(y)
        }
        #expect(bottoms == [85, 165, 250])
    }

    @Test func fallsBackToNaturalBreakWhenNoCleanRow() {
        let bottoms = PrintPagination.pageBottoms(contentHeight: 250, pageHeight: 100) { _ in false }
        #expect(bottoms == [100, 200, 250])
    }

    @Test func neverShrinksAPageBelowMinFraction() {
        // The only clean rows sit below 70% of the page; they must not be used.
        let bottoms = PrintPagination.pageBottoms(contentHeight: 150, pageHeight: 100) { y in
            y < 60
        }
        #expect(bottoms == [100, 150])
    }

    // The invariants the print view relies on: bottoms are strictly increasing, no page
    // exceeds the page height, and the final bottom is exactly the content height.
    @Test func bottomsAreMonotonicAndBounded() {
        let contentHeight: CGFloat = 3333
        let pageHeight: CGFloat = 240
        let bottoms = PrintPagination.pageBottoms(
            contentHeight: contentHeight,
            pageHeight: pageHeight
        ) { y in Int(y) % 37 == 0 }

        #expect(bottoms.last == contentHeight)
        var top: CGFloat = 0
        for bottom in bottoms {
            #expect(bottom > top)
            #expect(bottom - top <= pageHeight)
            top = bottom
        }
    }

    @Test func degenerateInputsProduceOneSanePage() {
        #expect(PrintPagination.pageBottoms(contentHeight: 0, pageHeight: 100) { _ in true } == [1])
        #expect(PrintPagination.pageBottoms(contentHeight: 100, pageHeight: 0) { _ in true } == [100])
    }
}

// MARK: - Row scan

@MainActor
struct PrintRowScanTests {
    /// 8×8 white bitmap with a black 2×2 square whose top-left is at raster row 3.
    private func makeImage() throws -> CGImage {
        let context = try #require(CGContext(
            data: nil,
            width: 8,
            height: 8,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        // CGContext y is bottom-up: y 3..<5 covers raster rows 3 and 4 from the top.
        context.fill(CGRect(x: 2, y: 3, width: 2, height: 2))
        return try #require(context.makeImage())
    }

    @Test func uniformRowsFlagsOnlyRowsWithoutContent() throws {
        let rows = DocumentPrinter.uniformRows(in: try makeImage())
        #expect(rows == [true, true, true, false, false, true, true, true])
    }
}

// MARK: - End-to-end PDF export

@MainActor
struct DocumentPrinterTests {
    private static let longMarkdown: String = {
        var parts: [String] = ["# Alpha Marker Heading\n\nOpening paragraph before the sections."]
        for index in 1...40 {
            parts.append("""
            ## Section \(index)

            A paragraph long enough to wrap across several lines when rendered at page \
            width, so that the exported document accumulates real, line-broken text content.

            - first item in section \(index)
            - second item with `inline code`

            ```swift
            let value\(index) = \(index) * 42
            ```
            """)
        }
        parts.append("Closing paragraph with the omega marker phrase.")
        return parts.joined(separator: "\n\n")
    }()

    private func makeJob(markdown: String) -> PrintJob {
        PrintJob(
            markdown: markdown,
            theme: .default,
            fontSize: 16,
            useSerifFont: false,
            title: "PrintTest"
        )
    }

    private func tempPDFURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("twain-print-test-\(UUID().uuidString).pdf")
    }

    @Test func exportedPDFHasPagesAndSelectableText() throws {
        let url = tempPDFURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let success = DocumentPrinter.exportPDF(
            job: makeJob(markdown: Self.longMarkdown),
            to: url,
            paperSize: CGSize(width: 595, height: 842) // A4, independent of local print setup
        )
        #expect(success)

        let document = try #require(PDFDocument(url: url))
        #expect(document.pageCount > 1)

        let text = (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")
        // Text is extractable (vector, not rasterized) and spans the whole document.
        #expect(text.contains("Alpha Marker Heading"))
        #expect(text.contains("Section 40"))
        #expect(text.contains("omega marker phrase"))

        // Every page uses the requested paper size.
        for index in 0..<document.pageCount {
            let bounds = try #require(document.page(at: index)).bounds(for: .mediaBox)
            #expect(abs(bounds.width - 595) < 1)
            #expect(abs(bounds.height - 842) < 1)
        }
    }

    // Pages must tile the document exactly: in order, no gaps, no repeats. The distinctive
    // per-section code lines double as position markers across the whole export.
    @Test func pagesCoverTheDocumentInOrderWithoutRepeats() throws {
        let data = try #require(DocumentPrinter.makePDFData(
            job: makeJob(markdown: Self.longMarkdown),
            paperSize: CGSize(width: 595, height: 842)
        ))
        let document = try #require(PDFDocument(data: data))

        var markers: [Int] = []
        for index in 0..<document.pageCount {
            let pageText = document.page(at: index)?.string ?? ""
            for match in pageText.matches(of: /let value(\d+) =/) {
                markers.append(Int(match.output.1) ?? -1)
            }
        }
        #expect(markers == Array(1...40))
    }

    @Test func exportHandlesEmptyDocument() throws {
        let url = tempPDFURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let success = DocumentPrinter.exportPDF(job: makeJob(markdown: ""), to: url)
        #expect(success)
        let document = try #require(PDFDocument(url: url))
        #expect(document.pageCount == 1)
    }
}
