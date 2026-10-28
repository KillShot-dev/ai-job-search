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
    /// Cached recents — sorting the full index on every SwiftUI body eval freezes Home.
    @Published private(set) var recents: [FileItem] = []
    /// Optional lookup for manual tags (set by FileRadarApp). Paths → tag names.
    /// Kept as a closure so FileStore does not hard-depend on ManualTagStore.
    var manualTagNames: ((String) -> [String])?

    enum ViewMode: String, CaseIterable { case grid, list, columns, showcase }
    enum SortOrder: String, CaseIterable { case name, date, size, kind, dateAdded }

    private let indexer = Indexer()
    private var folderWatcher: FolderWatcher?
    private var indexingTask: Task<Void, Never>?
    private var enrichmentTask: Task<Void, Never>?
    private var refreshQueued = false

    /// Soft caps so a first launch against huge Desktop/Documents trees cannot
    /// pin the main actor with hundreds of thousands of rows + OCR + thumbs.
    static let maxIndexedFiles = 25_000
    static let maxOCREnrichments = 120
    static let maxOCRBytes: Int64 = 8_000_000

    var shelves: [(FileKind, [FileItem])] {
        [.image, .video, .audio, .document, .archive, .app].map { kind in
            (kind, Array(files.filter { $0.kind == kind }.prefix(40)))
        }
    }

    var downloads: [FileItem] {
        guard let dl = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return [] }
        return files.filter { $0.url.path.hasPrefix(dl.path) }
            .sorted { $0.createdDate > $1.createdDate }
    }

    /// Sort a list with the current sort order (iteration 1: shared by
    /// search results and by every file collection, so sort keys behave
    /// the same everywhere: name, date modified, size, kind, date added).
    func sorted(_ files: [FileItem]) -> [FileItem] {
        files.sorted(by: sortComparator)
    }

    func startIndexing(folders: [URL]) {
        indexingTask?.cancel()
        enrichmentTask?.cancel()
        isIndexing = true
        let scoped = SecurityBookmarkStore.startAccessing(folders)
        folderWatcher?.stop()
        folderWatcher = FolderWatcher(folders: scoped) { [weak self] in
            Task { @MainActor in self?.requestRefresh() }
        }
        folderWatcher?.start()

        let maxFiles = Self.maxIndexedFiles
        indexingTask = Task.detached(priority: .utility) { [indexer] in
            let found = await indexer.index(folders: scoped, maxFiles: maxFiles) { _ in }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.applyIndex(found)
            }
            await MainActor.run {
                self.enrichInBackground(found)
            }
        }
    }

    /// Coalesce FSEvents: never start a second walk while one is running.
    func requestRefresh() {
        if isIndexing {
            refreshQueued = true
            return
        }
        refreshIndex()
    }

    /// Re-index currently pinned + bookmarked folders (FSEvents / Add Folder).
    func refreshIndex() {
        var folders = SecurityBookmarkStore.resolvedFolders()
        folders.append(contentsOf: pinnedFolderURLs)
        if folders.isEmpty {
            // Default to Downloads only. Indexing Desktop + Documents on a
            // developer Mac (tens of GB, node_modules, etc.) freezes the UI
            // for minutes even when the walk is off-main — the publish of a
            // huge @Published array + thumbnail storm is what kills clicks.
            let home = FileManager.default.homeDirectoryForCurrentUser
            folders = [home.appendingPathComponent("Downloads")]
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
        rebuildRecents()
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
        rebuildRecents()
    }

    /// Re-insert restored files after Trash undo (paths that exist again).
    func restoreFiles(_ items: [FileItem]) {
        for item in items where !files.contains(where: { $0.id == item.id }) {
            files.append(item)
        }
        indexedCount = files.count
        rebuildRecents()
    }

    func search(_ parsed: ParsedQuery) -> [FileItem] {
        files.filter { item in matches(item, parsed) }.sorted(by: sortComparator)
    }

    private func applyIndex(_ found: [FileItem]) {
        files = found
        indexedCount = found.count
        isIndexing = false
        rebuildRecents()
        if refreshQueued {
            refreshQueued = false
            // Defer so the current main-actor turn finishes first.
            Task { @MainActor in self.refreshIndex() }
        }
    }

    private func rebuildRecents() {
        recents = Array(files.sorted { $0.modifiedDate > $1.modifiedDate }.prefix(50))
    }

    private struct EnrichmentPatch {
        var id: String
        var ocr: String?
        var tags: [FileTag]
        var downloadSource: DownloadSource
        var width: Int?
        var height: Int?
        var cameraModel: String?
    }

    private func enrichInBackground(_ snapshot: [FileItem]) {
        enrichmentTask?.cancel()
        let maxOCR = Self.maxOCREnrichments
        let maxBytes = Self.maxOCRBytes
        // Metadata (xattr + CGImageSource) for the newest slice only.
        let metaBudget = min(snapshot.count, 2_000)
        let newest = snapshot.sorted { $0.modifiedDate > $1.modifiedDate }.prefix(metaBudget)
        enrichmentTask = Task.detached(priority: .utility) {
            var updates: [EnrichmentPatch] = []
            var ocrBudget = maxOCR
            for file in newest where !file.isICloudOnly {
                if Task.isCancelled { return }
                let source = DownloadSourceDetector.source(for: file.url)
                let meta = ImageMetadata.read(from: file.url, kind: file.kind, isICloudOnly: file.isICloudOnly)
                var ocr = file.ocrText
                let wantsOCR = ocr == nil
                    && ocrBudget > 0
                    && file.size <= maxBytes
                    && (file.kind == .image || file.extensionLowercased == "pdf")
                if wantsOCR {
                    if file.kind == .image {
                        ocr = await OCRService.recogniseText(in: file)
                    } else if file.extensionLowercased == "pdf" {
                        ocr = await OCRService.recogniseTextInPDF(file, maxPages: 5)
                    }
                    ocrBudget -= 1
                }
                var enriched = file
                enriched.ocrText = ocr
                enriched.downloadSource = source
                enriched.width = meta.width
                enriched.height = meta.height
                enriched.cameraModel = meta.cameraModel
                let tags = TagService.autoTags(for: enriched)
                updates.append(EnrichmentPatch(
                    id: file.id, ocr: ocr, tags: tags, downloadSource: source,
                    width: meta.width, height: meta.height, cameraModel: meta.cameraModel
                ))
                if updates.count >= 25 {
                    let batch = updates
                    updates.removeAll(keepingCapacity: true)
                    await MainActor.run { self.applyEnrichmentBatch(batch) }
                }
            }
            if !updates.isEmpty {
                let batch = updates
                await MainActor.run { self.applyEnrichmentBatch(batch) }
            }
        }
    }

    private func applyEnrichmentBatch(_ batch: [EnrichmentPatch]) {
        guard !batch.isEmpty else { return }
        for patch in batch {
            guard let idx = files.firstIndex(where: { $0.id == patch.id }) else { continue }
            if let ocr = patch.ocr { files[idx].ocrText = ocr }
            files[idx].tags = patch.tags
            files[idx].downloadSource = patch.downloadSource
            files[idx].width = patch.width
            files[idx].height = patch.height
            files[idx].cameraModel = patch.cameraModel
        }
        rebuildRecents()
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
        // Directory-level events only (not every file write) + longer latency.
        stream = FSEventStreamCreate(nil, callback, &context, paths,
                                     FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                                     3.0,
                                     FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer))
        guard let stream else { return }
        // Background runloop — keep FSEvents off the main thread.
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
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
    /// Directory names that explode walk time on developer machines.
    private static let skipDirectoryNames: Set<String> = [
        "node_modules", ".git", ".svn", ".hg", "DerivedData", "Pods",
        ".build", ".swiftpm", "Carthage", "vendor", ".venv", "venv",
        "__pycache__", ".tox", ".cache", "Library", ".Trash", "Caches"
    ]

    func index(folders: [URL], maxFiles: Int = FileStore.maxIndexedFiles, progress: @escaping (Int) -> Void) async -> [FileItem] {
        var results: [FileItem] = []
        results.reserveCapacity(min(maxFiles, 4096))
        let fm = FileManager.default
        for folder in folders {
            if Task.isCancelled { break }
            guard let enumerator = fm.enumerator(at: folder, includingPropertiesForKeys: [
                .isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey,
                .ubiquitousItemDownloadingStatusKey,
            ], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in enumerator {
                if Task.isCancelled { break }
                if results.count >= maxFiles { break }
                guard let values = try? url.resourceValues(forKeys: [
                    .isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey,
                    .ubiquitousItemDownloadingStatusKey, .isSymbolicLinkKey,
                ]) else { continue }
                if values.isSymbolicLink == true {
                    if values.isDirectory == true { enumerator.skipDescendants() }
                    continue
                }
                let isDir = values.isDirectory ?? false
                if isDir, Self.skipDirectoryNames.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                    continue
                }
                let status = values.ubiquitousItemDownloadingStatus
                let isICloudOnly = status == URLUbiquitousItemDownloadingStatus.notDownloaded
                let kind = FileKind.from(url: url, isDirectory: isDir)
                // Defer image metadata to enrichment — CGImageSource on every
                // file during the walk was a major launch stall on large trees.
                var item = FileItem(
                    url: url,
                    kind: kind,
                    size: Int64(values.fileSize ?? 0),
                    modifiedDate: values.contentModificationDate ?? .distantPast,
                    createdDate: values.creationDate ?? .distantPast,
                    downloadSource: .unknown,
                    tags: [],
                    isICloudOnly: isICloudOnly,
                    ocrText: nil,
                    width: nil,
                    height: nil,
                    duration: nil,
                    cameraModel: nil
                )
                // Cheap tags from name/extension only during the walk.
                item.tags = TagService.autoTags(for: item)
                results.append(item)
                if results.count % 500 == 0 {
                    progress(results.count)
                    await Task.yield()
                }
            }
            if results.count >= maxFiles { break }
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
