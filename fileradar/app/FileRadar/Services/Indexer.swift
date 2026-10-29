import Foundation

/// On-device file index. Runs on a background queue and never blocks the UI
/// (principle 10). Search reads the in-memory index, so it feels instant
/// once indexed. iCloud-only files are recorded but never downloaded:
/// `isICloudOnly` is set from the ubiquitous-item downloading status and
/// those entries are excluded from OCR, hashing, and preview reads that
/// would trigger a download.
@MainActor
final class FileStore: ObservableObject {
    @Published var files: [FileItem] = []
    @Published var isIndexing = false
    @Published var indexedCount = 0
    @Published var cardSize: CGFloat = 140
    @Published var viewMode: ViewMode = .grid
    @Published var sort: SortOrder = .date
    @Published var selectedIDs = Set<String>()
    @Published var pinnedFolderURLs: [URL] = []
    @Published var recentURLs: [URL] = []
    /// Optional lookup for manual tags (set by FileRadarApp). Paths → tag names.
    /// Kept as a closure so FileStore does not hard-depend on ManualTagStore.
    var manualTagNames: ((String) -> [String])?

    enum ViewMode: String, CaseIterable { case grid, list, columns }
    enum SortOrder: String, CaseIterable { case name, date, size, kind, dateAdded }

    /// Sort a list with the current sort order (iteration 1: shared by
    /// search results and by every file collection, so sort keys behave
    /// the same everywhere: name, date modified, size, kind, date added).
    func sorted(_ files: [FileItem]) -> [FileItem] {
        files.sorted(by: sortComparator)
    }

    private let indexer = Indexer()

    var recents: [FileItem] {
        files.sorted { $0.modifiedDate > $1.modifiedDate }.prefix(50).map { $0 }
    }

    var shelves: [(FileKind, [FileItem])] {
        [.image, .video, .audio, .document, .archive, .app].map { kind in
            (kind, files.filter { $0.kind == kind })
        }
    }

    var downloads: [FileItem] {
        guard let dl = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return [] }
        return files.filter { $0.url.path.hasPrefix(dl.path) }
            .sorted { $0.createdDate > $1.createdDate }
    }

    func startIndexing(folders: [URL]) {
        guard !isIndexing else { return }
        isIndexing = true
        Task.detached { [indexer] in
            let found = await indexer.index(folders: folders) { _ in }
            await MainActor.run {
                self.files = found
                self.indexedCount = found.count
                self.isIndexing = false
            }
        }
    }

    func search(_ parsed: ParsedQuery) -> [FileItem] {
        files.filter { item in matches(item, parsed) }.sorted(by: sortComparator)
    }

    private var sortComparator: (FileItem, FileItem) -> Bool {
        switch sort {
        case .name: return { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .date: return { $0.modifiedDate > $1.modifiedDate }
        case .size: return { $0.size > $1.size }
        case .kind: return { $0.kind.displayName < $1.kind.displayName }
        case .dateAdded: return { $0.createdDate > $1.createdDate }
        }
    }

    private func matches(_ item: FileItem, _ parsed: ParsedQuery) -> Bool {
        for chip in parsed.chips {
            switch chip.kind {
            case .fileKind(let kind): guard item.kind == kind else { return false }
            case .dateRange(let range):
                let cal = Calendar.current
                switch range {
                case .today: guard cal.isDateInToday(item.modifiedDate) else { return false }
                case .yesterday: guard cal.isDateInYesterday(item.modifiedDate) else { return false }
                case .lastWeek: guard item.modifiedDate > Date().addingTimeInterval(-7 * 86400) else { return false }
                case .lastMonth: guard item.modifiedDate > Date().addingTimeInterval(-30 * 86400) else { return false }
                case .lastYear: guard item.modifiedDate > Date().addingTimeInterval(-365 * 86400) else { return false }
                case .olderThanYear: guard item.modifiedDate < Date().addingTimeInterval(-365 * 86400) else { return false }
                }
            case .minSize(let min): guard item.size >= min else { return false }
            case .maxSize(let max): guard item.size <= max else { return false }
            case .source(let source): guard item.downloadSource == source else { return false }
            case .text(let text): guard matchesText(item, text) else { return false }
            case .tag(let name):
                let auto = item.tags.contains(where: { $0.name.lowercased() == name.lowercased() })
                let manual = manualTagNames?(item.url.path).contains(where: { $0.lowercased() == name.lowercased() }) ?? false
                guard auto || manual else { return false }
            }
        }
        if !parsed.freeText.isEmpty { guard matchesText(item, parsed.freeText) else { return false } }
        return true
    }

    private func matchesText(_ item: FileItem, _ text: String) -> Bool {
        let t = text.lowercased()
        let manual = manualTagNames?(item.url.path) ?? []
        return item.name.lowercased().contains(t)
            || item.tags.contains { $0.name.lowercased().contains(t) }
            || manual.contains { $0.lowercased().contains(t) }
            || (item.ocrText?.lowercased().contains(t) ?? false)
    }
}

/// Background enumerator. Skips hidden files, package contents it cannot
/// read, and anything the sandbox has not been granted access to — those
/// simply do not appear, rather than erroring the whole index.
struct Indexer {
    func index(folders: [URL], progress: @escaping (Int) -> Void) async -> [FileItem] {
        var results: [FileItem] = []
        let fm = FileManager.default
        for folder in folders {
            guard let enumerator = fm.enumerator(at: folder, includingPropertiesForKeys: [
                .isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey,
                .ubiquitousItemDownloadingStatusKey,
            ], options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in enumerator {
                guard let values = try? url.resourceValues(forKeys: [
                    .isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey,
                    .ubiquitousItemDownloadingStatusKey, .isSymbolicLinkKey,
                ]) else { continue }
                // Symlinks are never followed into: indexing through one
                // would pull in files outside the folder the user granted,
                // and a symlink loop could spin the enumerator forever.
                if values.isSymbolicLink == true {
                    if values.isDirectory == true { enumerator.skipDescendants() }
                    continue
                }
                let isDir = values.isDirectory ?? false
                let status = values.ubiquitousItemDownloadingStatus
                let isICloudOnly = status == URLUbiquitousItemDownloadingStatus.notDownloaded
                let item = FileItem(
                    url: url,
                    kind: FileKind.from(url: url, isDirectory: isDir),
                    size: Int64(values.fileSize ?? 0),
                    modifiedDate: values.contentModificationDate ?? .distantPast,
                    createdDate: values.creationDate ?? .distantPast,
                    downloadSource: DownloadSourceDetector.source(for: url),
                    tags: [],
                    isICloudOnly: isICloudOnly
                )
                results.append(item)
                if results.count % 500 == 0 { progress(results.count) }
            }
        }
        return results
    }
}
