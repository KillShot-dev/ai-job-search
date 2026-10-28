import Foundation
import AppKit
import UniformTypeIdentifiers

// MARK: - Iteration 1 services (Finder-replacement features, Apple-design lens)
//
// Every service here follows the existing rules: on-device only, no
// network entitlement, no removeItem on a user file, destructive paths go
// through TrashService. Nothing in this file was compiled on a Mac — see
// README UNTESTED. P1 items are marked UNTESTED in their comments.

// MARK: - Drop Stack (Path Finder lesson, principle 4: direct manipulation)
//
// A temporary holding tray: drag files onto it, then place the whole stack
// elsewhere. Session-only by design — a stack is a momentary handful, not
// a collection, so it is deliberately not persisted across launches.

@MainActor
final class DropStack: ObservableObject {
    static let shared = DropStack()
    @Published private(set) var urls: [URL] = []

    func add(_ newURLs: [URL]) {
        for url in newURLs where !urls.contains(url) { urls.append(url) }
    }

    func remove(_ url: URL) { urls.removeAll { $0 == url } }
    func clear() { urls.removeAll() }
}

/// Shared drop helper: turn NSItemProvider file-URL drops into URLs.
/// Used by the Drop Stack tray and by dual-pane drops alike, so a drag
/// behaves the same everywhere (principle 4).
enum DropUtilities {
    private static let lock = NSLock()

    static func loadURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        var found: [URL] = []
        let group = DispatchGroup()
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url = decodeFileURL(item)
                if let url {
                    lock.lock()
                    found.append(url)
                    lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { completion(found) }
    }

    /// NSItemProvider may hand back URL, NSURL, or bookmark/file-URL Data.
    private static func decodeFileURL(_ item: NSSecureCoding?) -> URL? {
        if let url = item as? URL { return url }
        if let ns = item as? NSURL { return ns as URL }
        if let data = item as? Data {
            if let url = URL(dataRepresentation: data, relativeTo: nil) { return url }
            if let s = String(data: data, encoding: .utf8), let url = URL(string: s) { return url }
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale) {
                return url
            }
        }
        return nil
    }
}

// MARK: - Transfer queue (ForkLift lesson, principle 10: bulk work never blocks UI)
//
// Every copy/move enqueued here goes through ONE visible queue with
// progress, pause, and cancel. Work runs off the main thread; the UI only
// ever reads published progress.
//
// Honest limits (UNTESTED, iteration 1):
// - Progress advances per file, not per byte: a single very large file
//   shows as one step. Pause and cancel take effect BETWEEN files, not
//   mid-file, because FileManager copy/move of one file is synchronous.
// - A move that would overwrite an existing file is skipped and reported,
//   never overwritten. No file is ever deleted: moves use FileManager
//   moveItem (a rename, not a delete), and this queue contains no
//   removeItem call at all.

@MainActor
final class TransferQueue: ObservableObject {
    static let shared = TransferQueue()

    enum Status: String { case queued, working, done, cancelled, failed }

    struct TransferItem: Identifiable {
        let id = UUID()
        var sources: [URL]
        var destinationFolder: URL
        var isMove: Bool
        var status: Status = .queued
        var completedFiles = 0
        var error: String?
        var title: String {
            let verb = isMove ? "Move" : "Copy"
            return "\(verb) \(sources.count) file\(sources.count == 1 ? "" : "s") to \(destinationFolder.lastPathComponent)"
        }
        var progress: Double {
            guard !sources.isEmpty else { return 1 }
            return Double(completedFiles) / Double(sources.count)
        }
    }

    @Published private(set) var items: [TransferItem] = []
    @Published var isPaused = false
    private var processing = false
    private var cancelRequested = false

    var activeCount: Int { items.filter { $0.status == .queued || $0.status == .working }.count }

    func enqueueCopy(_ urls: [URL], to folder: URL) { enqueue(urls, to: folder, isMove: false) }
    func enqueueMove(_ urls: [URL], to folder: URL) { enqueue(urls, to: folder, isMove: true) }

    private func enqueue(_ urls: [URL], to folder: URL, isMove: Bool) {
        guard !urls.isEmpty else { return }
        items.append(TransferItem(sources: urls, destinationFolder: folder, isMove: isMove))
        process()
    }

    func cancelAll() {
        cancelRequested = true
        for index in items.indices where items[index].status == .queued {
            items[index].status = .cancelled
        }
    }

    /// Cancel one queued job. A job already `working` finishes the current
    /// file, then stops (same between-file limit as pause/cancel-all).
    func cancelItem(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        if items[index].status == .queued {
            items[index].status = .cancelled
        } else if items[index].status == .working {
            cancelRequested = true
        }
    }

    func clearFinished() {
        items.removeAll { $0.status == .done || $0.status == .cancelled || $0.status == .failed }
    }

    private func process() {
        guard !processing else { return }
        processing = true
        cancelRequested = false
        Task {
            while let index = await nextQueuedIndex() {
                if await isCancelled() { break }
                await waitWhilePaused()
                if await isCancelled() { break }
                await runItem(at: index)
            }
            await MainActor.run { self.processing = false }
        }
    }

    private func nextQueuedIndex() async -> Int? {
        await MainActor.run { items.firstIndex { $0.status == .queued } }
    }

    private func isCancelled() async -> Bool {
        await MainActor.run { cancelRequested }
    }

    private func waitWhilePaused() async {
        while await MainActor.run(resultType: Bool.self, body: { isPaused }) {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    private func runItem(at index: Int) async {
        await MainActor.run { items[index].status = .working }
        let item = await MainActor.run { items[index] }
        var completed = 0
        var firstError: String?
        for source in item.sources {
            if await isCancelled() { break }
            await waitWhilePaused()
            let destination = item.destinationFolder.appendingPathComponent(source.lastPathComponent)
            let result = await Task.detached { () -> String? in
                let fm = FileManager.default
                guard !fm.fileExists(atPath: destination.path) else {
                    return "Skipped \(source.lastPathComponent): a file with that name already exists there."
                }
                // Symlink policy (see PathSafety): a move is a rename, so
                // it stays safe; a copy must not dereference a link and
                // silently duplicate whatever it points at, so symlinked
                // files are skipped on copy and reported, never copied.
                if !item.isMove,
                   let values = try? source.resourceValues(forKeys: [.isSymbolicLinkKey]),
                   values.isSymbolicLink == true {
                    return "Skipped \(source.lastPathComponent): symbolic links are not copied."
                }
                do {
                    if item.isMove {
                        try fm.moveItem(at: source, to: destination)
                    } else {
                        try fm.copyItem(at: source, to: destination)
                    }
                    return nil
                } catch {
                    return "Could not \(item.isMove ? "move" : "copy") \(source.lastPathComponent): \(error.localizedDescription)"
                }
            }.value
            if let error = result, firstError == nil { firstError = error }
            else if result == nil, item.isMove {
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .fileURLDidChange,
                        object: nil,
                        userInfo: ["old": source, "new": destination]
                    )
                }
            }
            completed += 1
            let done = completed
            await MainActor.run { items[index].completedFiles = done }
        }
        await MainActor.run {
            if cancelRequested {
                items[index].status = .cancelled
            } else if let error = firstError {
                items[index].status = .failed
                items[index].error = error
            } else {
                items[index].status = .done
            }
        }
    }
}

// MARK: - Tabs + restoration (all five replacements; principle 1: native tabs)
//
// An in-window tab strip for multiple locations. Tabs (folder URLs) and
// the dual-pane flag are persisted in UserDefaults and restored on
// relaunch, so windows, tabs, and panes come back as the user left them.
//
// Honest gap: this is a SwiftUI tab strip inside the window, not macOS
// NSWindow tabbing (the system tab bar). Wiring NSWindow tabbing is a
// Mac-only AppKit step listed in README UNTESTED; do not describe these
// as system tabs until that step is done and tested.

@MainActor
final class TabState: ObservableObject {
    struct TabItem: Identifiable, Codable, Hashable {
        var id = UUID()
        var folder: URL
        var title: String { folder.lastPathComponent }
    }

    @Published var tabs: [TabItem] = [] {
        didSet { save() }
    }
    @Published var selectedID: UUID? {
        didSet { save() }
    }

    private let key = "com.metaphasicgroup.fileradar.tabs.v2"

    init() {
        // v3 ForkLift-primary: seed Documents | Downloads for dual-pane launch.
        // Ignore empty v2 payloads that cleared tabs for Showcase Home.
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([TabItem].self, from: data),
           !saved.isEmpty {
            tabs = saved
            selectedID = saved.first?.id
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let documents = home.appendingPathComponent("Documents")
            let downloads = home.appendingPathComponent("Downloads")
            tabs = [TabItem(folder: documents), TabItem(folder: downloads)]
            selectedID = tabs.first?.id
            UserDefaults.standard.removeObject(forKey: "com.metaphasicgroup.fileradar.tabs.v1")
        }
    }

    var selectedTab: TabItem? { tabs.first { $0.id == selectedID } ?? tabs.first }

    /// Left dual-pane folder (selected / first tab).
    var firstFolder: URL {
        selectedTab?.folder
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
    }

    /// The second pane's folder: the second tab when there is one, else Downloads.
    var secondFolder: URL {
        if tabs.count > 1 { return tabs[1].folder }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    }

    /// Pin the dual-pane left side to a chosen folder.
    func setFirstFolder(_ folder: URL) {
        if tabs.isEmpty {
            addTab(folder: folder)
            return
        }
        var next = tabs
        next[0].folder = folder
        tabs = next
        selectedID = next[0].id
    }

    /// Pin the dual-pane right side to a chosen folder (creates/selects a tab).
    func setSecondFolder(_ folder: URL) {
        if tabs.count > 1 {
            var next = tabs
            next[1].folder = folder
            tabs = next
        } else if tabs.count == 1 {
            addTab(folder: folder)
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            addTab(folder: home.appendingPathComponent("Documents"))
            addTab(folder: folder)
        }
    }

    func addTab(folder: URL) {
        guard !tabs.contains(where: { $0.folder == folder }) else {
            selectedID = tabs.first { $0.folder == folder }?.id
            return
        }
        let tab = TabItem(folder: folder)
        tabs.append(tab)
        selectedID = tab.id
    }

    func closeTab(_ tab: TabItem) {
        guard tabs.count > 1 else { return }
        tabs.removeAll { $0.id == tab.id }
        if selectedID == tab.id { selectedID = tabs.first?.id }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(tabs) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - Saved workspaces (QSpace / Bloom lesson; PAID feature)
//
// A named layout restoring tabs, the dual-pane flag, and pinned folders
// in one click. Workspaces store folder URLs only — never file contents
// — and applying one never moves, renames, or deletes a file.

struct SavedWorkspace: Identifiable, Codable {
    var id = UUID()
    var name: String
    var tabFolders: [URL]
    var dualPaneEnabled: Bool
    var pinnedFolders: [URL]
}

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published private(set) var workspaces: [SavedWorkspace] = []
    private let key = "com.metaphasicgroup.fileradar.workspaces.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([SavedWorkspace].self, from: data) {
            workspaces = saved
        }
    }

    func save(name: String, tabFolders: [URL], dualPaneEnabled: Bool, pinnedFolders: [URL]) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        workspaces.removeAll { $0.name == trimmed }
        workspaces.append(SavedWorkspace(name: trimmed, tabFolders: tabFolders,
                                         dualPaneEnabled: dualPaneEnabled, pinnedFolders: pinnedFolders))
        persist()
    }

    func delete(_ workspace: SavedWorkspace) {
        workspaces.removeAll { $0.id == workspace.id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(workspaces) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - On-demand folder sizes (Path Finder lesson; principle 10)
//
// Folder sizes are computed in the background, cached, and shown in place
// — never a blocking scan. A folder's size is the sum of its files'
// sizes (iCloud-only files contribute their recorded size, but nothing
// is downloaded to measure them).

/// Folder size cache without a shared ObservableObject — publishing every
/// completed size previously re-rendered every list row that observed it.
@MainActor
final class FolderSizeService {
    static let shared = FolderSizeService()
    private var sizes: [String: Int64] = [:]
    private var computing = Set<String>()
    private var waiters: [String: [CheckedContinuation<Int64?, Never>]] = [:]

    func size(for folder: URL) -> Int64? { sizes[folder.path] }

    func sizeAsync(for folder: URL) async -> Int64? {
        let key = folder.path
        if let cached = sizes[key] { return cached }
        return await withCheckedContinuation { (continuation: CheckedContinuation<Int64?, Never>) in
            if var existing = waiters[key] {
                existing.append(continuation)
                waiters[key] = existing
                return
            }
            waiters[key] = [continuation]
            guard !computing.contains(key) else { return }
            computing.insert(key)
            Task.detached {
                var total: Int64 = 0
                let fm = FileManager.default
                if let enumerator = fm.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) {
                    for case let url as URL in enumerator {
                        if Task.isCancelled { break }
                        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey, .isSymbolicLinkKey]) else { continue }
                        if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                        if values.isDirectory != true { total += Int64(values.fileSize ?? 0) }
                    }
                }
                let sum = total
                await MainActor.run {
                    self.sizes[key] = sum
                    self.computing.remove(key)
                    let pending = self.waiters.removeValue(forKey: key) ?? []
                    for waiter in pending { waiter.resume(returning: sum) }
                }
            }
        }
    }
}

// MARK: - Archive browsing as folders (Commander One lesson; PAID feature)
//
// Read-only listing of ZIP and TAR archives as if they were folders;
// extraction happens only when the user asks, to a folder they choose.
// Listing and extraction use the system tools /usr/bin/unzip, /usr/bin/tar
// and /usr/bin/ditto — no archive library is bundled, and nothing inside
// an archive is ever modified in place. Extraction is staged and
// confinement-validated (see PathSafety and `extract`): neither tool is
// trusted to confine symlinks or `..` entries on its own.
//
// UNTESTED (iteration 1): output parsing for unzip/tar listings and the
// extract flows have not run on a Mac. Entry-level open (opening one
// file from inside an archive without extracting the whole archive) is
// deliberately NOT built — extract the archive, then open the file.

struct ArchiveEntry: Identifiable {
    var id: String { name }
    var name: String
    var size: Int64?
    var isDirectory: Bool { name.hasSuffix("/") }
}

/// Path-confinement checks shared by archive extraction (and, in spirit,
/// by every copy/move path: nothing FileRadar writes may escape the
/// folder the user chose). Symlink policy: REJECT, never resolve-and-
/// follow. A symlink inside an archive that points outside the
/// destination is treated as an escape attempt even if the link itself
/// would be harmless — following it, or letting a later archive entry
/// write through it, is the classic zip-slip-via-symlink attack, and
/// neither ditto nor tar can be trusted to confine on its own, so
/// extraction is staged and the whole tree is validated before anything
/// reaches the user's folder.
enum PathSafety {
    /// An archive entry name is safe only if it is relative and no path
    /// component climbs out with `..`. (Backslash is an ordinary filename
    /// character on macOS, not a separator, so it is not rejected.)
    static func isSafeEntryName(_ name: String) -> Bool {
        guard !name.isEmpty, !name.hasPrefix("/") else { return false }
        return !name.split(separator: "/", omittingEmptySubsequences: true).contains("..")
    }

    /// True when `path` resolves (symlinks included) to `destination`
    /// itself or to something inside it. Compares whole components, so
    /// `/tmp/Dest-evil` never matches destination `/tmp/Dest`.
    static func resolvedIsInside(_ path: URL, destination: URL) -> Bool {
        let resolved = path.standardized.resolvingSymlinksInPath().path
        let dest = destination.standardized.resolvingSymlinksInPath().path
        return resolved == dest || resolved.hasPrefix(dest + "/")
    }

    /// Validates a whole extracted tree: every item's resolved location
    /// must stay inside `root`. Returns the first offending item's name,
    /// or nil when the tree is confined. Symlinks are resolved, not
    /// followed, and a dangling link resolves to its target path, which
    /// is exactly what is checked.
    static func firstEscape(in root: URL) -> String? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil,
                                             options: []) else { return nil }
        for case let url as URL in enumerator {
            if !resolvedIsInside(url, destination: root) { return url.lastPathComponent }
        }
        return nil
    }
}

enum ArchiveBrowser {
    static func isArchive(_ url: URL) -> Bool {
        ["zip", "tar", "gz", "tgz"].contains(url.pathExtension.lowercased())
    }

    static func listEntries(of archive: URL) -> [ArchiveEntry] {
        switch archive.pathExtension.lowercased() {
        case "zip": return listZip(archive)
        default: return listTar(archive)
        }
    }

    private static func run(_ tool: String, _ args: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return "" }
        // Read before waitUntilExit so a full pipe buffer cannot deadlock.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func listZip(_ archive: URL) -> [ArchiveEntry] {
        let output = run("/usr/bin/unzip", ["-l", archive.path])
        var entries: [ArchiveEntry] = []
        for line in output.components(separatedBy: .newlines) {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 4, let size = Int64(parts[0]) else { continue }
            let name = parts.dropFirst(3).joined(separator: " ")
            guard !name.isEmpty else { continue }
            entries.append(ArchiveEntry(name: name, size: size))
        }
        return entries
    }

    private static func listTar(_ archive: URL) -> [ArchiveEntry] {
        let output = run("/usr/bin/tar", ["-tf", archive.path])
        return output.components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .map { ArchiveEntry(name: $0, size: nil) }
    }

    /// Extract the whole archive to a folder the user chose. Returns an
    /// error message, or nil on success. Nothing is written to the
    /// folder until the whole extraction has been proven confined:
    ///   1. Every listed entry name is checked for absolute paths and
    ///      `..` escapes before any tool runs (an unreadable listing
    ///      refuses the extract — extracting blind is how slip happens).
    ///   2. The archive is extracted to a fresh staging directory in the
    ///      app's temporary directory, never straight into the folder.
    ///   3. The staged tree is walked and every item's symlink-resolved
    ///      location must stay inside staging; on any escape the staging
    ///      tree is removed (staging cleanup — an allowed removeItem
    ///      use, like parcel staging) and the folder is untouched.
    ///   4. Quarantine is propagated: if the archive itself carries a
    ///      com.apple.quarantine attribute, every extracted regular file
    ///      is stamped with the same value, so extracted downloads do not
    ///      silently lose their Gatekeeper flag. Quarantine is never
    ///      stripped anywhere in this app.
    ///   5. Only then are the staged top-level items moved into the
    ///      folder — and only if none of their names already exists
    ///      there, matching the app's never-overwrite policy elsewhere.
    /// Messages are deliberately generic: they never echo archive entry
    /// names or paths back into the UI.
    static func extract(_ archive: URL, to folder: URL) -> String? {
        let fm = FileManager.default
        guard let folderValues = try? folder.resourceValues(forKeys: [.isDirectoryKey]),
              folderValues.isDirectory == true,
              fm.fileExists(atPath: archive.path) else {
            return "Extraction needs an existing archive and an existing folder. Nothing was changed."
        }
        let entries = listEntries(of: archive)
        guard !entries.isEmpty else {
            return "This archive listed no entries, or its listing could not be read. Nothing was extracted."
        }
        guard entries.allSatisfy({ PathSafety.isSafeEntryName($0.name) }) else {
            return "This archive contains an entry that would escape the destination folder. Nothing was extracted."
        }
        let staging = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do { try fm.createDirectory(at: staging, withIntermediateDirectories: true) } catch {
            return "Could not prepare extraction. Nothing was changed."
        }
        // Staging cleanup on every exit path below (allowed removeItem:
        // this tree is FileRadar's own staging, never a user file).
        defer { try? fm.removeItem(at: staging) }
        let process = Process()
        if archive.pathExtension.lowercased() == "zip" {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-x", "-k", archive.path, staging.path]
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            process.arguments = ["-xf", archive.path, "-C", staging.path]
        }
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return "Could not start the extraction tool." }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return "Extraction failed (tool exited with status \(process.terminationStatus)). Nothing was moved into the folder."
        }
        if PathSafety.firstEscape(in: staging) != nil {
            return "This archive contains a link that points outside the destination folder. Nothing was extracted."
        }
        propagateQuarantine(from: archive, into: staging)
        guard let topLevel = try? fm.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil) else {
            return "Extraction could not be read back. Nothing was moved into the folder."
        }
        for item in topLevel where fm.fileExists(atPath: folder.appendingPathComponent(item.lastPathComponent).path) {
            return "A file with the same name already exists in the destination folder. Nothing was extracted."
        }
        for item in topLevel {
            do { try fm.moveItem(at: item, to: folder.appendingPathComponent(item.lastPathComponent)) } catch {
                return "Extraction failed while moving files into the folder. Some files may have been moved; the rest were not."
            }
        }
        return nil
    }

    /// Copies the archive's quarantine attribute onto each extracted
    /// regular file. Symlinks are skipped (stamping through a link would
    /// write the attribute onto its target, wherever that points).
    private static func propagateQuarantine(from archive: URL, into staging: URL) {
        let path = archive.path
        let size = getxattr(path, "com.apple.quarantine", nil, 0, 0, 0)
        guard size > 0 else { return }
        var buffer = [UInt8](repeating: 0, count: size)
        guard getxattr(path, "com.apple.quarantine", &buffer, size, 0, 0) == size else { return }
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: staging, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey], options: []) else { return }
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey]),
                  values.isSymbolicLink != true, values.isDirectory != true else { continue }
            _ = buffer.withUnsafeBytes { setxattr(url.path, "com.apple.quarantine", $0.baseAddress, size, 0, 0) }
        }
    }
}

// MARK: - Folder sync / compare, P1 stretch (ForkLift lesson; PAID feature)
//
// Preview only, Trash-only deletions. Compare lists what is only on the
// left, only on the right, or different (by size or modification date).
// Nothing is synced automatically and nothing is deleted outright: the
// only destructive action offered is moving previewed extras to Trash
// through TrashService, after a confirmation alert.
//
// UNTESTED (iteration 1): the compare itself is a straightforward
// filename-keyed diff, but it has not run on a Mac against real folders.

struct SyncComparison {
    var onlyLeft: [URL] = []
    var onlyRight: [URL] = []
    var differing: [URL] = []
    var isEmpty: Bool { onlyLeft.isEmpty && onlyRight.isEmpty && differing.isEmpty }
}

enum SyncCompareService {
    static func compare(left: URL, right: URL) -> SyncComparison {
        func snapshot(_ folder: URL) -> [String: (size: Int64, modified: Date)] {
            var map: [String: (Int64, Date)] = [:]
            let fm = FileManager.default
            guard let enumerator = fm.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) else { return map }
            for case let url as URL in enumerator {
                guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey, .isSymbolicLinkKey]) else { continue }
                // Symlinked entries are never followed (see Indexer).
                if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                guard values.isDirectory != true else { continue }
                // Prefix-strip only: replacingOccurrences would also strip
                // the folder path if it reappeared deeper in the path,
                // silently mis-keying the file (and, via the keys below,
                // pointing a diff entry at the wrong file).
                let prefix = folder.path + "/"
                let relative = url.path.hasPrefix(prefix) ? String(url.path.dropFirst(prefix.count)) : url.lastPathComponent
                map[relative] = (Int64(values.fileSize ?? 0), values.contentModificationDate ?? .distantPast)
            }
            return map
        }
        let leftMap = snapshot(left)
        let rightMap = snapshot(right)
        var result = SyncComparison()
        for (name, leftInfo) in leftMap {
            if let rightInfo = rightMap[name] {
                if rightInfo.size != leftInfo.size || abs(rightInfo.modified.timeIntervalSince(leftInfo.modified)) > 1 {
                    result.differing.append(left.appendingPathComponent(name))
                }
            } else {
                result.onlyLeft.append(left.appendingPathComponent(name))
            }
        }
        for name in rightMap.keys where leftMap[name] == nil {
            result.onlyRight.append(right.appendingPathComponent(name))
        }
        return result
    }

    /// Build FileItems for TrashService from plain URLs (top-level files only).
    static func fileItem(for url: URL) -> FileItem? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .creationDateKey, .isDirectoryKey]) else { return nil }
        return FileItem(url: url,
                        kind: FileKind.from(url: url, isDirectory: values.isDirectory ?? false),
                        size: Int64(values.fileSize ?? 0),
                        modifiedDate: values.contentModificationDate ?? .distantPast,
                        createdDate: values.creationDate ?? .distantPast,
                        downloadSource: .unknown,
                        tags: [],
                        isICloudOnly: false)
    }
}

// MARK: - Git status badges, P1 stretch (ForkLift lesson; read-only, opt-in)
//
// Read-only and OFF by default (Settings toggle, @AppStorage
// "gitBadgesEnabled"). When on, the inspector shows a one-letter badge
// for the selected file, parsed from one `git status --porcelain` run
// per folder (cached per folder path). FileRadar never runs git write
// commands and never stages, commits, or resets anything.
//
// UNTESTED (iteration 1): porcelain parsing and the .git walk-up have
// not run on a Mac, and git may not be installed on every Mac — a
// missing git binary simply yields no badge, never an error surface.

enum GitStatusService {
    /// Cache keyed by repo root path → relative filename → porcelain code.
    private static var cache: [String: [String: String]] = [:]
    private static let lock = NSLock()

    /// Async so `git status --porcelain` never blocks MainActor (inspector `.task`).
    static func badge(for file: URL) async -> String? {
        await Task.detached(priority: .utility) {
            syncBadge(for: file)
        }.value
    }

    private static func syncBadge(for file: URL) -> String? {
        guard let root = repoRoot(for: file) else { return nil }
        lock.lock()
        let cached = cache[root.path]
        lock.unlock()
        let map: [String: String]
        if let cached {
            map = cached
        } else {
            map = statusMap(forRoot: root)
            lock.lock()
            cache[root.path] = map
            lock.unlock()
        }
        // Prefer path relative to repo root; fall back to last path component.
        let relative = file.path.hasPrefix(root.path + "/")
            ? String(file.path.dropFirst(root.path.count + 1))
            : file.lastPathComponent
        return map[relative] ?? map[file.lastPathComponent]
    }

    private static func repoRoot(for file: URL) -> URL? {
        var dir: URL? = file.deletingLastPathComponent()
        for _ in 0..<12 {
            guard let current = dir else { break }
            if FileManager.default.fileExists(atPath: current.appendingPathComponent(".git").path) {
                return current
            }
            let parent = current.deletingLastPathComponent()
            if parent == current { break }
            dir = parent
        }
        return nil
    }

    private static func statusMap(forRoot root: URL) -> [String: String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", root.path, "status", "--porcelain"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [:] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        var map: [String: String] = [:]
        for line in output.components(separatedBy: .newlines) where line.count > 3 {
            let code = String(line.prefix(2)).trimmingCharacters(in: .whitespaces)
            var name = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            if let arrow = name.range(of: " -> ") { name = String(name[arrow.upperBound...]) }
            if name.hasPrefix("\""), name.hasSuffix("\""), name.count >= 2 {
                name = String(name.dropFirst().dropLast())
            }
            if !code.isEmpty, !name.isEmpty {
                map[name] = code
                map[URL(fileURLWithPath: name).lastPathComponent] = code
            }
        }
        return map
    }
}

// MARK: - Command palette actions (Marta / Commander One lesson; principle 1 + 9)
//
// Cmd-K for every action, full keyboard navigation. Actions are plain
// values; ContentView performs them, so the palette itself never touches
// files, licensing, or navigation state directly.

enum PaletteAction: String, CaseIterable, Identifiable {
    case goHome, goSearch, goTimeline, goDiskMap, goWorkspaces, goSyncCompare
    case toggleDualPane, toggleInspector, newTab, toggleViewMode
    case batchRename, quickLookSelection, togglePreviewStrip

    var id: String { rawValue }

    var title: String {
        switch self {
        case .goHome: return "Go to Browser"
        case .goSearch: return "Go to Search"
        case .goTimeline: return "Go to Timeline"
        case .goDiskMap: return "Go to Disk Map"
        case .goWorkspaces: return "Workspaces"
        case .goSyncCompare: return "Compare folders (sync preview)"
        case .toggleDualPane: return "Toggle dual-pane mode"
        case .toggleInspector: return "Toggle inspector"
        case .newTab: return "New tab for this folder"
        case .toggleViewMode: return "Toggle grid / list / columns / showcase"
        case .batchRename: return "Batch rename selection…"
        case .quickLookSelection: return "Quick Look selection"
        case .togglePreviewStrip: return "Toggle preview strip"
        }
    }

    var shortcutHint: String {
        switch self {
        case .goHome, .goSearch, .goTimeline, .goDiskMap, .goWorkspaces, .goSyncCompare: return "Navigate"
        case .toggleDualPane: return "Panes"
        case .toggleInspector: return "Cmd-Opt-I"
        case .newTab: return "Tabs"
        case .toggleViewMode: return "Cmd-1 / Cmd-2 / Cmd-3 / Cmd-4"
        case .batchRename: return "Shift-Cmd-R"
        case .quickLookSelection: return "Space"
        case .togglePreviewStrip: return "Shift-Cmd-P"
        }
    }
}
