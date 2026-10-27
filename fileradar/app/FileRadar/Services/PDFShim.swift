import Foundation
import PDFKit
import AppKit

/// Thin wrapper over PDFKit: renders each page to a CGImage for Vision OCR.
/// Kept separate so OCRService stays readable.
struct PDFDocumentShim {
    var pages: [CGImage] = []

    init?(url: URL) {
        guard let doc = PDFDocument(url: url) else { return nil }
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let rect = page.bounds(for: .mediaBox)
            guard let image = page.thumbnail(of: CGSize(width: rect.width, height: rect.height), for: .mediaBox) else { continue }
            if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                pages.append(cg)
            }
        }
    }
}
