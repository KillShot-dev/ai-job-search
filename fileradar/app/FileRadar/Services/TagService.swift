import Foundation

/// Tags: manual coloured tags + plain-language auto-tags (principle 6).
///
/// Auto-tag rules are deliberately transparent and on-device:
/// - "Receipt" — OCR/text contains a currency total and a date.
/// - "Invoice" — text contains the word "invoice" and an amount.
/// - "Draft" — filename contains "draft", "copy", or "untitled".
/// - "Screenshot" — filename starts with "Screenshot" / "Screen Shot" or
///   the file lives in a Screenshots context (see SmartCollections).
/// Every auto-tag carries its explanation in words; the UI shows it on
/// hover / in the inspector. No "AI" branding anywhere.
enum TagService {
    static func autoTags(for file: FileItem) -> [FileTag] {
        var tags: [FileTag] = []
        let name = file.name.lowercased()
        let text = (file.ocrText ?? "").lowercased()

        if name.contains("draft") || name.contains("untitled") || name.contains("copy") {
            tags.append(FileTag(name: "Draft", color: .yellow, isAuto: true,
                                explanation: "Tagged Draft because the name suggests it is not finished."))
        }
        if name.hasPrefix("screenshot") || name.hasPrefix("screen shot") {
            tags.append(FileTag(name: "Screenshot", color: .blue, isAuto: true,
                                explanation: "Tagged Screenshot because the file name says so."))
        }
        if text.contains("invoice") && containsAmount(text) {
            tags.append(FileTag(name: "Invoice", color: .green, isAuto: true,
                                explanation: "Tagged Invoice because the text mentions an invoice and an amount."))
        } else if containsAmount(text) && containsDateWord(text) {
            tags.append(FileTag(name: "Receipt", color: .green, isAuto: true,
                                explanation: "Tagged Receipt because the text contains a total and a date."))
        }
        if file.kind == .image, let ocr = file.ocrText, !ocr.trimmingCharacters(in: .whitespaces).isEmpty {
            tags.append(FileTag(name: "Has text", color: .purple, isAuto: true,
                                explanation: "Tagged Has text because words were recognised inside this image."))
        }
        return tags
    }

    private static func containsAmount(_ text: String) -> Bool {
        // $12.34, £12.34, 12.34 USD — deliberately simple, on-device.
        text.range(of: #"[$£€]\s?\d+\.\d{2}"#, options: .regularExpression) != nil
    }

    private static func containsDateWord(_ text: String) -> Bool {
        text.range(of: #"\b(20\d{2})[-/]\d{1,2}[-/]\d{1,2}\b"#, options: .regularExpression) != nil
            || text.contains("jan") || text.contains("feb") || text.contains("mar")
    }

    // MARK: - Smart Collections (beat-extra, on-device)

    static func smartCollections(in files: [FileItem]) -> [(title: String, explanation: String, files: [FileItem])] {
        let receipts = files.filter { $0.tags.contains { $0.name == "Receipt" } || $0.tags.contains { $0.name == "Invoice" } }
        let drafts = files.filter { $0.tags.contains { $0.name == "Draft" } }
        let screenshotsWithText = files.filter {
            $0.tags.contains { $0.name == "Screenshot" } && ($0.ocrText?.isEmpty == false)
        }
        let large = files.filter { $0.size > 100 * 1_024 * 1_024 }.sorted { $0.size > $1.size }
        return [
            ("Receipts & invoices", "Files whose text looks like a bill or receipt.", receipts),
            ("Unfinished drafts", "Files whose names suggest they are not finished.", drafts),
            ("Screenshots with text", "Screenshots that contain readable words.", screenshotsWithText),
            ("Large files", "Files over 100 MB, largest first.", large),
        ]
    }
}
