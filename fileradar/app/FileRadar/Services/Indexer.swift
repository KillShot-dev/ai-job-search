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
    /// List is the ForkLift-primary default; Showcase remains for Shelves Home.
    @Published var viewMode: ViewMode = .list
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
    /// `nonisolated` so Indexer (off the main actor) can use the defaults.
    nonisolated static let maxIndexedFiles = 25_000
    nonisolated static let maxOCREnrichments = 120
    nonisolated static let maxOCRBytes: Int64 = 8_000_000

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
        // Canonicalize before walk so FileItem URLs match dual-pane folder tabs
        // (sandbox Downloads symlink → real ~/Downloads).
        let canonical = folders.map { $0.resolvingSymlinksInPath().standardizedFileURL }
        let scoped = SecurityBookmarkStore.startAccessing(canonical)
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
    /// Gated on `FolderAccessConsent` so launch never walks roots (or pops
    /// access UI) before the user confirms once.
    func refreshIndex() {
        // Snapshot / QA bypasses consent so evidence shots still fill shelves.
        let snapshotting = ProcessInfo.processInfo.environment["FILERADAR_SNAPSHOT_PATH"] != nil
        if !snapshotting, !FolderAccessConsent.isCompleted {
            isIndexing = false
            return
        }
        var folders = SecurityBookmarkStore.resolvedFolders()
        folders.append(contentsOf: pinnedFolderURLs)
        if snapshotting {
            let demo = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Downloads/FileRadarDemo")
            if FileManager.default.fileExists(atPath: demo.path) {
                folders = [demo]
            }
        }
        if folders.isEmpty, FolderAccessConsent.useDownloadsEntitlement || snapshotting {
            // Downloads entitlement path — no bookmark / open panel needed.
            folders = [FolderAccessConsent.downloadsURL]
        }
        guard !folders.isEmpty else {
            isIndexing = false
            return
        }
        // Deduplicate by path
        var seen = Set<String>()
        folders = folders.filter { seen.insert($0.path).inserted }
        startIndexing(folders: folders)
    }

    /// Add a user-picked folder via security-scoped bookmark and re-index.
    /// NSOpenPanel must not run synchronously inside a SwiftUI button / AXPress
    /// action — that nested `runModal` during layout throws
    /// `_postWindowNeedsUpdateConstraints` and kills the window (EXC_BREAKPOINT).
    func addFolderInteractive() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let folder = SecurityBookmarkStore.pickAndStoreFolder() else { return }
            let canonical = folder.resolvingSymlinksInPath().standardizedFileURL
            if !self.pinnedFolderURLs.contains(where: {
                $0.resolvingSymlinksInPath().path == canonical.path
            }) {
                self.pinnedFolderURLs.append(canonical)
            }
            self.refreshIndex()
        }
    }

    /// Remove indexed entries by path id and clear selection for them.
    func removeFiles(matching paths: Set<String>) {
        guard !paths.isEmpty else { return }
        files.removeAll { paths.contains($0.id) }
        selectedIDs.subtract(paths)
        indexedCount = files.count
        rebuildRecents()
    }

    /// Convenience: remove by file URLs (Trash / Transfer / Rename / SyncCompare).
    func removeFiles(withURLs urls: [URL]) {
        removeFiles(matching: Set(urls.map(\.path)))
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

    /// Box so enrichment can mutate a batch across `await` without capturing
    /// a mutable local in a `@Sendable` detached task (Swift 6).
    private final class EnrichmentUpdatesBox: @unchecked Sendable {
        var updates: [EnrichmentPatch] = []
    }

    private func enrichInBackground(_ snapshot: [FileItem]) {
        enrichmentTask?.cancel()
        let maxOCR = Self.maxOCREnrichments
        let maxBytes = Self.maxOCRBytes
        // Metadata (xattr + CGImageSource) for the newest slice only.
        let metaBudget = min(snapshot.count, 2_000)
        let newest = snapshot.sorted { $0.modifiedDate > $1.modifiedDate }.prefix(metaBudget)
        enrichmentTask = Task.detached(priority: .utility) {
            let box = EnrichmentUpdatesBox()
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
                box.updates.append(EnrichmentPatch(
                    id: file.id, ocr: ocr, tags: tags, downloadSource: source,
                    width: meta.width, height: meta.height, cameraModel: meta.cameraModel
                ))
                if box.updates.count >= 25 {
                    let batch = box.updates
                    box.updates.removeAll(keepingCapacity: true)
                    await MainActor.run { self.applyEnrichmentBatch(batch) }
                }
            }
            if !box.updates.isEmpty {
                let batch = box.updates
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

/// Single launch consent for folder roots + indexing. Prevents serial TCC /
/// open-panel stacks for Desktop, Documents, Downloads, and index start.
enum FolderAccessConsent {
    static let completedKey = "com.metaphasicgroup.fileradar.folderAccess.v1"
    /// When true, indexing may use the Downloads entitlement without a bookmark.
    static let useDownloadsKey = "com.metaphasicgroup.fileradar.folderAccess.useDownloads"

    static var isCompleted: Bool {
        get {
            if UserDefaults.standard.bool(forKey: completedKey) { return true }
            // Local QA / snapshot automation — never block AX or evidence shots.
            if ProcessInfo.processInfo.environment["FILERADAR_FOLDER_CONSENT"] == "1"
                || ProcessInfo.processInfo.environment["FILERADAR_SNAPSHOT_PATH"] != nil {
                return true
            }
            return false
        }
        set { UserDefaults.standard.set(newValue, forKey: completedKey) }
    }

    static var useDownloadsEntitlement: Bool {
        get {
            if UserDefaults.standard.bool(forKey: useDownloadsKey) { return true }
            if ProcessInfo.processInfo.environment["FILERADAR_FOLDER_CONSENT"] == "1"
                || ProcessInfo.processInfo.environment["FILERADAR_SNAPSHOT_PATH"] != nil {
                return true
            }
            return false
        }
        set { UserDefaults.standard.set(newValue, forKey: useDownloadsKey) }
    }

    static var downloadsURL: URL {
        // Resolve the container Downloads symlink so tabs / index / FolderBrowser
        // share one canonical path (standardizedFileURL alone does not).
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads")
            .resolvingSymlinksInPath()
    }

    /// True when disk listing is safe (won't block main on TCC).
    /// Downloads uses the sandbox entitlement — always listable.
    /// Other roots need a stored security-scoped bookmark.
    static func canBrowse(_ url: URL) -> Bool {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        let downloads = downloadsURL.path
        if path == downloads || path.hasPrefix(downloads + "/") {
            return true
        }
        if SecurityBookmarkStore.storedPaths.contains(where: {
            let root = URL(fileURLWithPath: $0).resolvingSymlinksInPath().standardizedFileURL.path
            return path == root || path.hasPrefix(root + "/")
        }) { return true }
        return false
    }

    static func completeWithDownloadsOnly() {
        useDownloadsEntitlement = true
        isCompleted = true
    }

    static func completeWithBookmarks(_ urls: [URL]) {
        for url in urls { SecurityBookmarkStore.store(url) }
        if urls.contains(where: { $0.standardizedFileURL.path == downloadsURL.path }) {
            useDownloadsEntitlement = true
        }
        isCompleted = true
    }

    /// Escape hatch — enter the app without granting roots or starting index.
    /// User can Add Folder… later; sheet will not reappear.
    static func completeSkipped() {
        isCompleted = true
    }
}

/// Security-scoped bookmark store so sandboxed Add Folder grants survive relaunch.
enum SecurityBookmarkStore {
    private static let defaultsKey = "com.metaphasicgroup.fileradar.folderBookmarks"
    /// Paths already holding an active security scope this process.
    private static var accessingPaths = Set<String>()

    static func pickAndStoreFolder() -> URL? {
        pickAndStoreFolders(allowsMultiple: false)?.first
    }

    /// One NSOpenPanel — multi-select roots for onboarding / Add Folder.
    static func pickAndStoreFolders(allowsMultiple: Bool = true) -> [URL]? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = allowsMultiple
        panel.prompt = allowsMultiple ? "Grant Access" : "Add Folder"
        panel.message = allowsMultiple
            ? "Select the folders FileRadar may index (Desktop, Documents, Downloads, or any others)."
            : nil
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return nil }
        var stored: [URL] = []
        for url in panel.urls {
            store(url)
            startAccessingOnce(url)
            stored.append(url)
        }
        return stored
    }

    static func store(_ url: URL) {
        guard let data = try? url.bookmarkData(options: .withSecurityScope,
                                               includingResourceValuesForKeys: nil,
                                               relativeTo: nil) else { return }
        var map = loadMap()
        map[url.standardizedFileURL.path] = data
        if let encoded = try? JSONEncoder().encode(map.map { BookmarkRecord(path: $0.key, data: $0.value) }) {
            UserDefaults.standard.set(encoded, forKey: defaultsKey)
        }
    }

    static func hasStoredFolders() -> Bool { !loadMap().isEmpty }

    /// Bookmark path keys only — no resolve / startAccessing (safe for UI checks).
    static var storedPaths: [String] { Array(loadMap().keys) }

    static func resolvedFolders() -> [URL] {
        var urls: [URL] = []
        for (_, data) in loadMap() {
            var isStale = false
            guard let url = try? URL(resolvingBookmarkData: data,
                                     options: [.withSecurityScope, .withoutUI],
                                     relativeTo: nil,
                                     bookmarkDataIsStale: &isStale) else { continue }
            startAccessingOnce(url)
            urls.append(url)
        }
        return urls
    }

    static func startAccessing(_ folders: [URL]) -> [URL] {
        for url in folders { startAccessingOnce(url) }
        return folders
    }

    /// Avoid stacking duplicate startAccessingSecurityScopedResource calls for
    /// the same path during launch / refresh storms.
    private static func startAccessingOnce(_ url: URL) {
        let path = url.standardizedFileURL.path
        guard !accessingPaths.contains(path) else { return }
        if url.startAccessingSecurityScopedResource() {
            accessingPaths.insert(path)
        }
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
            // nextObject() — DirectoryEnumerator.makeIterator() is unavailable in async.
            while let url = enumerator.nextObject() as? URL {
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
