import Foundation

/// A visible filter chip parsed out of a natural-language query.
/// Principle 5 + 6: chips animate in from the query text and read like
/// sentences, e.g. "Images from last week over 100 MB".
struct SearchChip: Identifiable, Hashable {
    let id = UUID()
    var kind: ChipKind
    var sentence: String

    enum ChipKind: Hashable {
        case fileKind(FileKind)
        case dateRange(DateIntervalKind)
        case minSize(Int64)
        case maxSize(Int64)
        case source(DownloadSource)
        case text(String)
        case tag(String)
    }

    enum DateIntervalKind: Hashable {
        case today, yesterday, lastWeek, lastMonth, lastYear, olderThanYear
    }
}

struct ParsedQuery {
    var chips: [SearchChip]
    var freeText: String

    /// Sentence form shown above results, e.g. "Images from last week over 100 MB".
    var sentence: String {
        chips.map(\.sentence).joined(separator: " ")
    }
}

/// Plain-language parser. Deliberately rule-based and on-device: it matches
/// kind words, date words, size phrases ("over 100 MB"), and source names.
/// Anything it cannot parse stays as free text matched against filenames,
/// tags, and indexed file text — it never guesses a filter silently.
enum SearchQueryParser {
    static func parse(_ raw: String) -> ParsedQuery {
        let lower = raw.lowercased()
        var chips: [SearchChip] = []
        var remainder = raw

        let kindWords: [(String, FileKind)] = [
            ("images", .image), ("image", .image), ("photos", .image),
            ("videos", .video), ("video", .video),
            ("music", .audio), ("audio", .audio), ("songs", .audio),
            ("documents", .document), ("docs", .document),
            ("archives", .archive), ("apps", .app),
        ]
        for (word, kind) in kindWords where lower.contains(word) {
            chips.append(SearchChip(kind: .fileKind(kind), sentence: kind.displayName))
            remainder = remainder.replacingOccurrences(of: word, with: "", options: .caseInsensitive)
        }

        let dateWords: [(String, SearchChip.DateIntervalKind, String)] = [
            ("last week", .lastWeek, "from last week"),
            ("last month", .lastMonth, "from last month"),
            ("last year", .lastYear, "from last year"),
            ("today", .today, "from today"),
            ("yesterday", .yesterday, "from yesterday"),
        ]
        for (word, kind, sentence) in dateWords where lower.contains(word) {
            chips.append(SearchChip(kind: .dateRange(kind), sentence: sentence))
            remainder = remainder.replacingOccurrences(of: word, with: "", options: .caseInsensitive)
        }

        // "over 100 MB" / "under 10 MB" / "larger than 1 GB"
        if let size = parseSize(in: lower, prefixes: ["over ", "larger than ", "more than "]) {
            chips.append(SearchChip(kind: .minSize(size.bytes), sentence: "over \(size.label)"))
        }
        if let size = parseSize(in: lower, prefixes: ["under ", "smaller than ", "less than "]) {
            chips.append(SearchChip(kind: .maxSize(size.bytes), sentence: "under \(size.label)"))
        }

        let sourceWords: [(String, DownloadSource, String)] = [
            ("gmail", .gmail, "from Gmail"), ("google drive", .googleDrive, "from Google Drive"),
            ("chatgpt", .chatGPT, "from ChatGPT"), ("canva", .canva, "from Canva"),
            ("slack", .slack, "from Slack"), ("whatsapp", .whatsApp, "from WhatsApp"),
            ("github", .gitHub, "from GitHub"),
        ]
        for (word, source, sentence) in sourceWords where lower.contains(word) {
            chips.append(SearchChip(kind: .source(source), sentence: sentence))
            remainder = remainder.replacingOccurrences(of: word, with: "", options: .caseInsensitive)
        }

        let freeText = remainder
            .replacingOccurrences(of: "over ", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "under ", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespaces)
        return ParsedQuery(chips: chips, freeText: freeText)
    }

    private struct ParsedSize { var bytes: Int64; var label: String }

    private static func parseSize(in text: String, prefixes: [String]) -> ParsedSize? {
        // Matches e.g. "over 100 mb", "over 1.5 gb", "under 500 kb".
        let pattern = "(?:\(prefixes.joined(separator: "|")))(\\d+(?:\\.\\d+)?)\\s*(kb|mb|gb)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let numRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text),
              let value = Double(text[numRange]) else { return nil }
        let unit = text[unitRange]
        let multiplier: Int64 = unit == "kb" ? 1_024 : unit == "mb" ? 1_024 * 1_024 : 1_024 * 1_024 * 1_024
        return ParsedSize(bytes: Int64(value * Double(multiplier)), label: "\(text[numRange]) \(unit.uppercased())")
    }
}
