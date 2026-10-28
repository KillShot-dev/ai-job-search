import Foundation
import ImageIO
import CoreGraphics
import AppKit
import CoreServices

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

    enum ViewMode: String, CaseIterable { case grid, list, columns, showcase }
    enum SortOrder: String, CaseIterable { case name, date, size, kind, dateAdded }

    private let indexer = Indexer()
    private var folderWatcher: FolderWatcher?

    /// Sort a list with the current sort order (iteration 1: shared by
    /// search results and by every file collection, so sort keys behave
    /// the same everywhere: name, date modified, size, kind, date added).
    func sorted(_ files: [FileItem]) -> [FileItem] {
        files.sorted(by: sortComparator)
    }

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
        let scoped = SecurityBookmarkStore.startAccessing(folders)
        folderWatcher?.stop()
        folderWatcher = FolderWatcher(folders: scoped) { [weak self] in
            Task { @MainActor in self?.refreshIndex() }
        }
        folderWatcher?.start()
        Task.detached { [indexer] in
            let found = await indexer.index(folders: scoped) { _ in }
            await MainActor.run {
                self.files = found
                self.indexedCount = found.count
                self.isIndexing = false
            }
            await MainActor.run { self.enrichInBackground(found) }
        }
    }

    /// Re-index currently pinned + bookmarked folders (FSEvents / Add Folder).
    func refreshIndex() {
        var folders = SecurityBookmarkStore.resolvedFolders()
        folders.append(contentsOf: pinnedFolderURLs)
        if folders.isEmpty {
            let home = FileManager.default.homeDirectoryForCurrentUser
            folders = [home.appendingPathComponent("Downloads"),
                       home.appendingPathComponent("Documents"),
                       home.appendingPathComponent("Desktop")]
        }
        // Deduplicate by path
        var seen = Set<String>()
        folders = folders.filter { seen.insert($0.path).inserted }
        startIndexing(folders: folders)
    }

    /// Add a user-picked folder via security-scoped bookmark and re-index.
    func addFolderInteractive() {
        guard let folder = SecurityBookmarkStore.pickAndStoreFolder() else { return }
        if !pinnedFolderURLs.contains(folder) {
            pinnedFolderURLs.append(folder)
        }
        refreshIndex()
    }

    /// Remove indexed entries by path id and clear selection for them.
    func removeFiles(matching paths: Set<String>) {
        guard !paths.isEmpty else { return }
        files.removeAll { paths.contains($0.id) }
        selectedIDs.subtract(paths)
        indexedCount = files.count
    }

    /// Update a file's URL after rename/move (keeps selection when possible).
    func updateFileURL(from old: URL, to new: URL) {
        let oldPath = old.path
        guard let idx = files.firstIndex(where: { $0.id == oldPath }) else { return }
        var item = files[idx]
        item = FileItem(
            url: new,
            kind: item.kind,
            size: item.size,
            modifiedDate: item.modifiedDate,
            createdDate: item.createdDate,
            downloadSource: item.downloadSource,
            tags: item.tags,
            isICloudOnly: item.isICloudOnly,
            ocrText: item.ocrText,
            width: item.width,
            height: item.height,
            duration: item.duration,
            cameraModel: item.cameraModel
        )
        files[idx] = item
        if selectedIDs.remove(oldPath) != nil {
            selectedIDs.insert(new.path)
        }
    }

    /// Re-insert restored files after Trash undo (paths that exist again).
    func restoreFiles(_ items: [FileItem]) {
        for item in items where !files.contains(where: { $0.id == item.id }) {
            files.append(item)
        }
        indexedCount = files.count
    }

    func search(_ parsed: ParsedQuery) -> [FileItem] {
        files.filter { item in matches(item, parsed) }.sorted(by: sortComparator)
    }

    private func enrichInBackground(_ snapshot: [FileItem]) {
        Task.detached(priority: .utility) {
            var updates: [(String, String?, [FileTag], Int?, Int?, String?)] = []
            for file in snapshot where !file.isICloudOnly {
                var ocr = file.ocrText
                if ocr == nil {
                    if file.kind == .image {
                        ocr = await OCRService.recogniseText(in: file)
                    } else if file.extensionLowercased == "pdf" {
                        ocr = await OCRService.recogniseTextInPDF(file, maxPages: 5)
                    }
                }
                var enriched = file
                enriched.ocrText = ocr
                let tags = TagService.autoTags(for: enriched)
                updates.append((file.id, ocr, tags, file.width, file.height, file.cameraModel))
            }
            await MainActor.run {
                for (id, ocr, tags, _, _, _) in updates {
                    guard let idx = self.files.firstIndex(where: { $0.id == id }) else { continue }
                    self.files[idx].ocrText = ocr
                    self.files[idx].tags = tags
                }
            }
        }
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

/// Security-scoped bookmark store so sandboxed Add Folder grants survive relaunch.
enum SecurityBookmarkStore {
    private static let defaultsKey = "com.metaphasicgroup.fileradar.folderBookmarks"

    static func pickAndStoreFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        store(url)
        _ = url.startAccessingSecurityScopedResource()
        return url
    }

    static func store(_ url: URL) {
        guard let data = try? url.bookmarkData(options: .withSecurityScope,
                                               includingResourceValuesForKeys: nil,
                                               relativeTo: nil) else { return }
        var map = loadMap()
        map[url.path] = data
        if let encoded = try? JSONEncoder().encode(map.map { BookmarkRecord(path: $0.key, data: $0.value) }) {
            UserDefaults.standard.set(encoded, forKey: defaultsKey)
        }
    }

    static func resolvedFolders() -> [URL] {
        var urls: [URL] = []
        for (_, data) in loadMap() {
            var isStale = false
            guard let url = try? URL(resolvingBookmarkData: data,
                                     options: [.withSecurityScope, .withoutUI],
                                     relativeTo: nil,
                                     bookmarkDataIsStale: &isStale) else { continue }
            _ = url.startAccessingSecurityScopedResource()
            urls.append(url)
        }
        return urls
    }

    static func startAccessing(_ folders: [URL]) -> [URL] {
        for url in folders { _ = url.startAccessingSecurityScopedResource() }
        return folders
    }

    private struct BookmarkRecord: Codable {
        var path: String
        var data: Data
    }

    private static func loadMap() -> [String: Data] {
        guard let raw = UserDefaults.standard.data(forKey: defaultsKey),
              let records = try? JSONDecoder().decode([BookmarkRecord].self, from: raw) else { return [:] }
        return Dictionary(uniqueKeysWithValues: records.map { ($0.path, $0.data) })
    }
}

/// Lightweight FSEvents watcher — coalesces bursts then asks FileStore to refresh.
final class FolderWatcher {
    private var stream: FSEventStreamRef?
    private let folders: [URL]
    private let onChange: () -> Void
    private var pending = false

    init(folders: [URL], onChange: @escaping () -> Void) {
        self.folders = folders
        self.onChange = onChange
    }

    func start() {
        stop()
        let paths = folders.map(\.path) as CFArray
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.scheduleRefresh()
        }
        stream = FSEventStreamCreate(nil, callback, &context, paths,
                                     FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                                     1.5,
                                     FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents))
        guard let stream else { return }
        FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func scheduleRefresh() {
        guard !pending else { return }
        pending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.pending = false
            self?.onChange()
        }
    }

    deinit { stop() }
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
                if values.isSymbolicLink == true {
                    if values.isDirectory == true { enumerator.skipDescendants() }
                    continue
                }
                let isDir = values.isDirectory ?? false
                let status = values.ubiquitousItemDownloadingStatus
                let isICloudOnly = status == URLUbiquitousItemDownloadingStatus.notDownloaded
                let kind = FileKind.from(url: url, isDirectory: isDir)
                let meta = ImageMetadata.read(from: url, kind: kind, isICloudOnly: isICloudOnly)
                var item = FileItem(
                    url: url,
                    kind: kind,
                    size: Int64(values.fileSize ?? 0),
                    modifiedDate: values.contentModificationDate ?? .distantPast,
                    createdDate: values.creationDate ?? .distantPast,
                    downloadSource: DownloadSourceDetector.source(for: url),
                    tags: [],
                    isICloudOnly: isICloudOnly,
                    ocrText: nil,
                    width: meta.width,
                    height: meta.height,
                    duration: nil,
                    cameraModel: meta.cameraModel
                )
                item.tags = TagService.autoTags(for: item)
                results.append(item)
                if results.count % 500 == 0 { progress(results.count) }
            }
        }
        return results
    }
}

/// CGImageSource metadata (width / height / camera) — no full decode.
enum ImageMetadata {
    static func read(from url: URL, kind: FileKind, isICloudOnly: Bool) -> (width: Int?, height: Int?, cameraModel: String?) {
        guard kind == .image, !isICloudOnly else { return (nil, nil, nil) }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return (nil, nil, nil)
        }
        let width = props[kCGImagePropertyPixelWidth] as? Int
        let height = props[kCGImagePropertyPixelHeight] as? Int
        var camera: String?
        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            camera = exif[kCGImagePropertyExifLensModel] as? String
        }
        if camera == nil, let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            camera = tiff[kCGImagePropertyTIFFModel] as? String
        }
        return (width, height, camera)
    }
}
