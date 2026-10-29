import Foundation
import Vision
import AppKit

/// On-device text recognition via Apple Vision. Runs on a background queue;
/// never blocks the UI (principle 10). Nothing leaves the device.
///
/// - Preview / search indexing: recognising text for search is free.
/// - "Copy all recognised text" (copying the full OCR result out of the
///   app) is a paid feature — enforced by callers via LicenseManager,
///   see InspectorView. This service itself only recognises text.
/// Guards a continuation against double-resume when a Vision perform()
/// throws after its completion handler already fired (or vice versa).
final class ResumeOnce<T> {
    private var resumed = false
    private let lock = NSLock()
    private let continuation: CheckedContinuation<T, Never>
    init(_ continuation: CheckedContinuation<T, Never>) { self.continuation = continuation }
    func resume(returning value: T) {
        lock.lock(); defer { lock.unlock() }
        guard !resumed else { return }
        resumed = true
        continuation.resume(returning: value)
    }
}

enum OCRService {
    /// Recognise text in an image file. Returns nil for iCloud-only files
    /// (we must not trigger a download) and for non-images.
    static func recogniseText(in file: FileItem) async -> String? {
        guard !file.isICloudOnly, file.kind == .image else { return nil }
        // Decode off the caller's actor (often MainActor from inspector .task).
        let cgImage: CGImage? = await Task.detached(priority: .utility) {
            guard let image = NSImage(contentsOf: file.url) else { return nil }
            return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }.value
        guard let cgImage else { return nil }
        return await recogniseTextInCGImage(cgImage)
    }

    /// Recognise text on the first pages of a PDF (up to `maxPages`).
    /// PDFKit is used only to rasterise; recognition itself is Vision.
    static func recogniseTextInPDF(_ file: FileItem, maxPages: Int = 5) async -> String? {
        guard !file.isICloudOnly, file.extensionLowercased == "pdf" else { return nil }
        guard let doc = PDFDocumentShim(url: file.url) else { return nil }
        var pages: [String] = []
        for page in doc.pages.prefix(maxPages) {
            if let text = await recogniseTextInCGImage(page) { pages.append(text) }
        }
        let joined = pages.joined(separator: "\n")
        return joined.isEmpty ? nil : joined
    }

    private static func recogniseTextInCGImage(_ cgImage: CGImage) async -> String? {
        await withCheckedContinuation { continuation in
            let once = ResumeOnce(continuation)
            let request = VNRecognizeTextRequest { request, _ in
                let text = request.results?.compactMap { $0 as? VNRecognizedTextObservation }
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                once.resume(returning: text)
            }
            request.recognitionLevel = .fast
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do { try handler.perform([request]) } catch { once.resume(returning: nil) }
            }
        }
    }
}

// Minimal PDF rasteriser wrapper so OCRService does not depend on PDFKit
// types leaking into the model layer. Implemented in Services/PDFShim.swift.
