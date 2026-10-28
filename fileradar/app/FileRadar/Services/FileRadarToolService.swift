import Foundation
import AppKit

// MARK: - FileRadarToolService: LOCAL tool execution for Muse chat
//
// Every tool here runs on-device against the in-memory FileStore index.
// Nothing is uploaded: tool outputs contain file names, metadata, and
// summaries only. They NEVER contain:
// - full paths (only bare file names and folder display names),
// - file contents,
// - OCR text (note: FileStore's own text search matches OCR text, so
//   searchFiles implements its own filter over name/tags/source/kind
//   and deliberately does NOT call store.search),
// - quarantine, extended attributes, or any other on-disk bytes.
// This file reads no user file bytes at all: no Data reads, no hashing,
// no preview rendering. Anything that would need bytes (exact duplicate
// hashing, look-alike feature prints) belongs in the Duplicates view,
// not in a chat tool result.
//
// Destructive / externally visible actions (trash, move, open) NEVER
// execute inline. `execute` returns `.needsApproval` and the action runs
// only after the user approves it via `approve`. `deny` discards it.
// There is intentionally NO apply/merge/delete action for cleanup or
// duplicates: those tools are previews only, and the user acts in the
// app's own Cleanup / Duplicates views.
//
// Safety reuse:
// - Move destinations are confined by the same policy as
//   IterationServices.PathSafety: traversal (`..`) is REJECTED, never
//   resolved-and-followed, and a destination must resolve to exactly
//   one of the user's pinned folders or the standard
//   Downloads/Documents/Desktop folders. Overwrites are refused and
//   reported as clashes, never performed.
// - Trash goes through TrashService (NSWorkspace recycle, undoable).
//   No code path here removes a user file outright.
// - iCloud-only files are never downloaded by any tool here; tools only
//   read their already-indexed metadata.
// - Licence gating uses the injected `isLicensed` closure so this file
//   never touches LicenseManager internals.
//
// Duplicates note: DuplicateFinder.exactGroups exists and is pure in
// the sense of returning value types, but it READS file bytes to SHA-256
// them. To keep this layer byte-free (see above), duplicatesPreview
// instead groups by (size, name) and labels the summary honestly as
// likely duplicates. The exact check lives in the Duplicates view.
// Cleanup note: cleanUpPreview reuses CleanupEngine.cards(for:) from
// MoreServices verbatim, so its heuristics always match the app's own
// Cleanup view (old installers / forgotten downloads / old screenshots
// / big old videos / unused apps). Card groups can overlap (for example
// old installers are also forgotten downloads); the summary says so.

// MARK: - Pending action storage

@MainActor
final class FileRadarToolService {

    /// What an approved action will do. Stored in memory only, keyed by
    /// the PendingToolAction id shown in the approval UI.
    private enum PendingRequest {
        case trash([FileItem])
        case move([FileItem], URL)
        case open(FileItem)
    }

    private let store: FileStore
    private let trash: TrashService
    private let isLicensed: () -> Bool
    private let onShowFile: (FileItem) -> Void
    private var pending: [UUID: PendingRequest] = [:]

    init(
        store: FileStore,
        trash: TrashService,
        isLicensed: @escaping () -> Bool,
        onShowFile: @escaping (FileItem) -> Void
    ) {
        self.store = store
        self.trash = trash
        self.isLicensed = isLicensed
        self.onShowFile = onShowFile
    }

    // MARK: - Tool schemas (the contract the model sees)

    var toolSchemas: [ToolSchema] {
        [
            ToolSchema(
                name: "searchFiles",
                description: "Search indexed files by name, tag, or download source. Returns names and metadata only, never file contents or paths.",
                parametersJSON: """
                {"type":"object","properties":{"query":{"type":"string"},"kind":{"type":"string","enum":["image","video","audio","document","archive","app","folder","other"]},"limit":{"type":"integer","default":20}},"required":["query"]}
                """
            ),
            ToolSchema(
                name: "listShelf",
                description: "List file names on one shelf (kind), up to 20 names plus a count. Names only, no paths.",
                parametersJSON: """
                {"type":"object","properties":{"kind":{"type":"string","enum":["image","video","audio","document","archive","app","folder","other"]}},"required":["kind"]}
                """
            ),
            ToolSchema(
                name: "getFileInfo",
                description: "Metadata for one file matched by exact name: kind, size, dates, dimensions or duration when present, tags, download source. Metadata only, never contents.",
                parametersJSON: """
                {"type":"object","properties":{"name":{"type":"string"}},"required":["name"]}
                """
            ),
            ToolSchema(
                name: "previewFile",
                description: "Metadata preview for one file matched by exact name, same fields as getFileInfo. Metadata only, never file contents or OCR text.",
                parametersJSON: """
                {"type":"object","properties":{"name":{"type":"string"}},"required":["name"]}
                """
            ),
            ToolSchema(
                name: "trashFiles",
                description: "Stage moving named files to Trash. Nothing moves until the user approves; trashed files stay recoverable.",
                parametersJSON: """
                {"type":"object","properties":{"names":{"type":"array","items":{"type":"string"}}},"required":["names"]}
                """
            ),
            ToolSchema(
                name: "moveFiles",
                description: "Stage moving named files to a destination folder. The destination must be a pinned folder or Downloads, Documents, or Desktop; anything else is refused, and existing same-named files are never overwritten. Nothing moves until the user approves.",
                parametersJSON: """
                {"type":"object","properties":{"names":{"type":"array","items":{"type":"string"}},"destination":{"type":"string"}},"required":["names","destination"]}
                """
            ),
            ToolSchema(
                name: "cleanUpPreview",
                description: "Read-only Clean Up preview: counts and total size per cleanup group plus example names, using the same rules as the app's Cleanup view. Paid feature. No apply action exists.",
                parametersJSON: """
                {"type":"object","properties":{}}
                """
            ),
            ToolSchema(
                name: "duplicatesPreview",
                description: "Read-only duplicates preview grouped by size and name, labelled as likely duplicates. Paid feature. No merge or delete action exists; the full check is in the Duplicates view.",
                parametersJSON: """
                {"type":"object","properties":{}}
                """
            ),
            ToolSchema(
                name: "showInFileRadar",
                description: "Show one named file in FileRadar. Returns a confirmation with the file name only.",
                parametersJSON: """
                {"type":"object","properties":{"name":{"type":"string"}},"required":["name"]}
                """
            ),
            ToolSchema(
                name: "openFile",
                description: "Stage opening one named file in its default app. Nothing opens until the user approves.",
                parametersJSON: """
                {"type":"object","properties":{"name":{"type":"string"}},"required":["name"]}
                """
            ),
        ]
    }

    // MARK: - Execution

    func execute(call: ToolCall) async -> ToolExecutionResult {
        let args = parsedArguments(call.argumentsJSON)
        switch call.name {
        case "searchFiles":
            return searchFiles(args: args)
        case "listShelf":
            return listShelf(args: args)
        case "getFileInfo", "previewFile":
            return fileInfo(args: args)
        case "trashFiles":
            return stageTrash(args: args)
        case "moveFiles":
            return stageMove(args: args)
        case "cleanUpPreview":
            return cleanUpPreview()
        case "duplicatesPreview":
            return duplicatesPreview()
        case "showInFileRadar":
            return showInFileRadar(args: args)
        case "openFile":
            return stageOpen(args: args)
        default:
            return .failed("Unknown tool.")
        }
    }

    /// Runs a previously staged action after the user approved it in the
    /// UI. Unknown or already-resolved ids report honestly and do nothing.
    func approve(action: PendingToolAction) async -> String {
        guard let request = pending.removeValue(forKey: action.id) else {
            return "That action is no longer pending, so nothing was done."
        }
        switch request {
        case .trash(let files):
            return performTrash(files)
        case .move(let files, let folder):
            return performMove(files, to: folder)
        case .open(let file):
            return performOpen(file)
        }
    }

    /// Discards a staged action. Nothing was ever moved, trashed, or opened.
    func deny(action: PendingToolAction) async -> String {
        if pending.removeValue(forKey: action.id) != nil {
            return "Cancelled: \(action.title) was not performed."
        }
        return "That action is no longer pending, so nothing was done."
    }

    // MARK: - Search and listing

    private func searchFiles(args: [String: Any]) -> ToolExecutionResult {
        guard let query = stringArg(args, "query"), !query.isEmpty else {
            return .failed("A search query is needed.")
        }
        let limit = intArg(args, "limit") ?? 20
        let clampedLimit = min(max(limit, 1), 50)
        var kindFilter: FileKind?
        if let kindString = stringArg(args, "kind") {
            guard let kind = FileKind(rawValue: kindString.lowercased()) else {
                return .failed("Unknown file kind.")
            }
            kindFilter = kind
        }
        let needle = query.lowercased()
        let matches = store.files.filter { item in
            if let kindFilter, item.kind != kindFilter { return false }
            // Name, tag names, and download-source display name only.
            // Deliberately NOT OCR text and NOT store.search (which
            // matches OCR text) — OCR text never leaves this device.
            return item.name.lowercased().contains(needle)
                || item.tags.contains { $0.name.lowercased().contains(needle) }
                || item.downloadSource.displayName.lowercased().contains(needle)
        }
        if matches.isEmpty {
            return .completed("No files matched \"\(query)\".")
        }
        let shown = matches.prefix(clampedLimit)
        var lines = ["Found \(matches.count) matching file(s):"]
        lines.append(contentsOf: shown.map { "- \($0.name) (\($0.kind.displayName), \(formatSize($0.size)), modified \(formatDate($0.modifiedDate)), from \($0.downloadSource.displayName))" })
        if matches.count > shown.count {
            lines.append("Showing the first \(shown.count).")
        }
        return .completed(lines.joined(separator: "\n"))
    }

    private func listShelf(args: [String: Any]) -> ToolExecutionResult {
        guard let kindString = stringArg(args, "kind"),
              let kind = FileKind(rawValue: kindString.lowercased()) else {
            return .failed("A valid file kind is needed.")
        }
        let items = store.files.filter { $0.kind == kind }
        if items.isEmpty {
            return .completed("No files on the \(kind.displayName) shelf.")
        }
        let shown = items.prefix(20)
        var lines = ["\(items.count) file(s) on the \(kind.displayName) shelf:"]
        lines.append(contentsOf: shown.map { "- \($0.name)" })
        if items.count > shown.count {
            lines.append("Showing the first \(shown.count) names.")
        }
        return .completed(lines.joined(separator: "\n"))
    }

    // MARK: - Metadata only (getFileInfo / previewFile share this)

    private func fileInfo(args: [String: Any]) -> ToolExecutionResult {
        guard let name = stringArg(args, "name"), !name.isEmpty else {
            return .failed("A file name is needed.")
        }
        let matches = store.files.filter { $0.name == name }
        switch matches.count {
        case 0:
            return .failed("No file named \"\(name)\" was found.")
        case 1:
            return .completed(metadataSummary(for: matches[0]))
        default:
            // Same name in more than one place. Paths are never shown,
            // so disambiguate with metadata the model can quote back.
            var lines = ["\(matches.count) files share the name \"\(name)\". Ask which one, using one of these descriptions:"]
            lines.append(contentsOf: matches.map { "- \($0.kind.displayName), \(formatSize($0.size)), modified \(formatDate($0.modifiedDate))" })
            return .completed(lines.joined(separator: "\n"))
        }
    }

    private func metadataSummary(for item: FileItem) -> String {
        var lines = [
            "Name: \(item.name)",
            "Kind: \(item.kind.displayName)",
            "Size: \(formatSize(item.size))",
            "Modified: \(formatDate(item.modifiedDate))",
            "Created: \(formatDate(item.createdDate))",
        ]
        if let width = item.width, let height = item.height {
            lines.append("Dimensions: \(width) x \(height)")
        }
        if let duration = item.duration {
            lines.append("Duration: \(formatDuration(duration))")
        }
        if !item.tags.isEmpty {
            lines.append("Tags: \(item.tags.map(\.name).joined(separator: ", "))")
        }
        lines.append("Download source: \(item.downloadSource.displayName)")
        // Deliberately absent: path, contents, OCR text, camera model.
        return lines.joined(separator: "\n")
    }

    // MARK: - Trash (approval-gated)

    private func stageTrash(args: [String: Any]) -> ToolExecutionResult {
        guard let names = namesArg(args), !names.isEmpty else {
            return .failed("At least one file name is needed.")
        }
        switch resolve(names: names) {
        case .failed(let message):
            return .failed(message)
        case .resolved(let files):
            let action = PendingToolAction(
                id: UUID(),
                title: "Move to Trash",
                detail: "Move \(files.count) file(s) to Trash (recoverable from Trash):\n" + files.map { "- \($0.name)" }.joined(separator: "\n"),
                toolName: "trashFiles"
            )
            pending[action.id] = .trash(files)
            return .needsApproval(action)
        }
    }

    private func performTrash(_ files: [FileItem]) -> String {
        let moved = trash.trash(files)
        store.removeFiles(matching: Set(moved.map { $0.originalURL.path }))
        let movedIDs = Set(moved.map(\.originalURL))
        let unmoved = files.filter { !movedIDs.contains($0.url) }
        if moved.isEmpty {
            return "Could not move any of the files to Trash. Nothing was changed."
        }
        var summary = "Moved \(moved.count) file(s) to Trash (recoverable from Trash): " + moved.map { $0.originalURL.lastPathComponent }.joined(separator: ", ") + "."
        if !unmoved.isEmpty {
            summary += " Could not move: " + unmoved.map(\.name).joined(separator: ", ") + "."
        }
        return summary
    }

    // MARK: - Move (approval-gated, confined destinations, never overwrite)

    private func stageMove(args: [String: Any]) -> ToolExecutionResult {
        guard let names = namesArg(args), !names.isEmpty else {
            return .failed("At least one file name is needed.")
        }
        guard let destinationRaw = stringArg(args, "destination"), !destinationRaw.isEmpty else {
            return .failed("A destination folder is needed.")
        }
        let files: [FileItem]
        switch resolve(names: names) {
        case .failed(let message):
            return .failed(message)
        case .resolved(let resolved):
            files = resolved
        }
        guard let folder = resolveDestination(destinationRaw) else {
            return .failed("That destination is not allowed. Use a pinned folder, or Downloads, Documents, or Desktop.")
        }
        let clashes = files.filter { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0.name).path) }
        if !clashes.isEmpty {
            return .failed("Nothing was moved: these files already exist in \(folder.lastPathComponent) and would be overwritten: " + clashes.map(\.name).joined(separator: ", ") + ".")
        }
        let action = PendingToolAction(
            id: UUID(),
            title: "Move files",
            detail: "Move \(files.count) file(s) to \(folder.lastPathComponent):\n" + files.map { "- \($0.name)" }.joined(separator: "\n"),
            toolName: "moveFiles"
        )
        pending[action.id] = .move(files, folder)
        return .needsApproval(action)
    }

    private func performMove(_ files: [FileItem], to folder: URL) -> String {
        var moved: [String] = []
        var failed: [String] = []
        for file in files {
            let destination = folder.appendingPathComponent(file.name)
            // Re-check at apply time: the folder may have changed since
            // approval. A clash is reported, never overwritten.
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                failed.append("\(file.name) (already exists there)")
                continue
            }
            // The destination stays inside the approved folder by
            // construction (a single appended file name), and the
            // approved folder itself was confinement-checked at staging.
            do {
                try FileManager.default.moveItem(at: file.url, to: destination)
                store.updateFileURL(from: file.url, to: destination)
                moved.append(file.name)
            } catch {
                failed.append(file.name)
            }
        }
        var summary = ""
        if !moved.isEmpty {
            summary += "Moved \(moved.count) file(s) to \(folder.lastPathComponent): " + moved.joined(separator: ", ") + "."
        }
        if !failed.isEmpty {
            if !summary.isEmpty { summary += " " }
            summary += "Could not move: " + failed.joined(separator: ", ") + "."
        }
        if summary.isEmpty {
            summary = "Nothing was moved."
        }
        return summary
    }

    /// Resolves a destination string to an allowed folder, or nil.
    /// Allowed: pinned folders, plus standard Downloads / Documents /
    /// Desktop. Rules (PathSafety policy):
    /// - Any `..` component is rejected outright, never resolved away.
    /// - An absolute path must standardize (symlinks resolved) to exactly
    ///   one allowed folder — a prefix match is not enough, so a
    ///   sibling like `Downloads-evil` can never pass.
    /// - A bare name must match exactly one allowed folder's display
    ///   name; anything with a separator that is not absolute is rejected.
    /// - The folder must exist and be a directory.
    private func resolveDestination(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let components = trimmed.split(separator: "/").map(String.init)
        guard !components.contains("..") else { return nil }
        let candidates = allowedFolders()
        let resolvedCandidates = candidates.map { $0.standardized.resolvingSymlinksInPath() }
        if trimmed.hasPrefix("/") {
            let resolved = URL(fileURLWithPath: trimmed).standardized.resolvingSymlinksInPath()
            guard let match = resolvedCandidates.first(where: { $0 == resolved }) else { return nil }
            return validatedDirectory(match)
        }
        guard components.count == 1 else { return nil }
        let matches = resolvedCandidates.filter { $0.lastPathComponent.lowercased() == trimmed.lowercased() }
        guard matches.count == 1, let match = matches.first else { return nil }
        return validatedDirectory(match)
    }

    private func validatedDirectory(_ folder: URL) -> URL? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return folder
    }

    private func allowedFolders() -> [URL] {
        var folders = store.pinnedFolderURLs
        let fm = FileManager.default
        for directory in [FileManager.SearchPathDirectory.downloadsDirectory,
                          FileManager.SearchPathDirectory.documentDirectory,
                          FileManager.SearchPathDirectory.desktopDirectory] {
            if let url = fm.urls(for: directory, in: .userDomainMask).first,
               !folders.contains(url) {
                folders.append(url)
            }
        }
        return folders
    }

    // MARK: - Previews (read-only, licence-gated, no apply action)

    private func cleanUpPreview() -> ToolExecutionResult {
        guard isLicensed() else {
            return .locked("Clean Up preview requires a paid licence.")
        }
        let cards = CleanupEngine.cards(for: store.files)
        guard !cards.isEmpty else {
            return .completed("Clean Up preview: nothing to clean up was found.")
        }
        var lines = ["Clean Up preview (read-only — nothing has been moved; groups can overlap):"]
        var totalFiles = 0
        var totalSize: Int64 = 0
        for card in cards {
            totalFiles += card.files.count
            totalSize += card.totalSize
            lines.append("- \(card.type.rawValue): \(card.files.count) file(s), \(formatSize(card.totalSize)). Examples: " + card.files.prefix(3).map(\.name).joined(separator: ", ") + ".")
        }
        lines.append("Total across groups: \(totalFiles) file(s), \(formatSize(totalSize)). Act in the app's Cleanup view.")
        return .completed(lines.joined(separator: "\n"))
    }

    private func duplicatesPreview() -> ToolExecutionResult {
        guard isLicensed() else {
            return .locked("Duplicates preview requires a paid licence.")
        }
        // Byte-free grouping by (size, name) over indexed metadata only.
        // Labelled honestly: same size + same name is suggestive, not proof.
        var groups: [String: [FileItem]] = [:]
        for file in store.files where file.kind != .folder {
            groups["\(file.size)|\(file.name.lowercased())", default: []].append(file)
        }
        let dupes = groups.values.filter { $0.count > 1 }.sorted { $0.count > $1.count }
        guard !dupes.isEmpty else {
            return .completed("Duplicates preview: no likely duplicates by size and name were found.")
        }
        let extraFiles = dupes.reduce(0) { $0 + $1.count - 1 }
        let reclaimable = dupes.reduce(Int64(0)) { $0 + Int64($1.count - 1) * $1[0].size }
        var lines = ["Duplicates preview: \(dupes.count) group(s) of likely duplicates by size and name — full check in the Duplicates view. Keeping one copy of each would free about \(formatSize(reclaimable)) across \(extraFiles) extra file(s). Examples:"]
        for group in dupes.prefix(5) {
            lines.append("- \"\(group[0].name)\" (\(group.count) copies, \(formatSize(group[0].size)) each)")
        }
        lines.append("This is a preview only — nothing was merged or deleted.")
        return .completed(lines.joined(separator: "\n"))
    }

    // MARK: - Show and open

    private func showInFileRadar(args: [String: Any]) -> ToolExecutionResult {
        guard let name = stringArg(args, "name"), !name.isEmpty else {
            return .failed("A file name is needed.")
        }
        let matches = store.files.filter { $0.name == name }
        switch matches.count {
        case 0:
            return .failed("No file named \"\(name)\" was found.")
        case 1:
            onShowFile(matches[0])
            return .completed("Showing \"\(name)\" in FileRadar.")
        default:
            return .failed("More than one file is named \"\(name)\". Ask which one, using its kind, size, or modified date.")
        }
    }

    private func stageOpen(args: [String: Any]) -> ToolExecutionResult {
        guard let name = stringArg(args, "name"), !name.isEmpty else {
            return .failed("A file name is needed.")
        }
        let matches = store.files.filter { $0.name == name }
        switch matches.count {
        case 0:
            return .failed("No file named \"\(name)\" was found.")
        case 1:
            let file = matches[0]
            let action = PendingToolAction(
                id: UUID(),
                title: "Open file",
                detail: "Open \"\(file.name)\" in its default app.",
                toolName: "openFile"
            )
            pending[action.id] = .open(file)
            return .needsApproval(action)
        default:
            return .failed("More than one file is named \"\(name)\". Ask which one, using its kind, size, or modified date.")
        }
    }

    private func performOpen(_ file: FileItem) -> String {
        // External side effect, only ever reached after user approval.
        // iCloud-only files are not downloaded here; NSWorkspace.open on
        // such a file behaves as the system decides, and a failure is
        // reported honestly rather than worked around.
        if NSWorkspace.shared.open(file.url) {
            return "Opened \"\(file.name)\"."
        }
        return "Could not open \"\(file.name)\"."
    }

    // MARK: - Argument and resolution helpers

    /// Parses a tool-call arguments string. An empty string means "no
    /// arguments"; anything unparseable becomes an empty object so the
    /// tool can report its own missing-argument error.
    private func parsedArguments(_ json: String) -> [String: Any] {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            return [:]
        }
        return object
    }

    private func stringArg(_ args: [String: Any], _ key: String) -> String? {
        guard let value = args[key] as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func intArg(_ args: [String: Any], _ key: String) -> Int? {
        (args[key] as? NSNumber)?.intValue
    }

    private func namesArg(_ args: [String: Any]) -> [String]? {
        if let array = args["names"] as? [String] {
            let cleaned = array.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            return cleaned.isEmpty ? nil : cleaned
        }
        if let single = stringArg(args, "names") { return [single] }
        return nil
    }

    private enum Resolution {
        case resolved([FileItem])
        case failed(String)
    }

    /// Exact-name resolution. Ambiguity fails rather than guesses: with
    /// paths withheld, the model cannot tell same-named files apart, so
    /// the failure names the problem and the caller must disambiguate.
    private func resolve(names: [String]) -> Resolution {
        var items: [FileItem] = []
        var seenIDs = Set<String>()
        var missing: [String] = []
        var ambiguous: [String] = []
        for name in names {
            let matches = store.files.filter { $0.name == name }
            if matches.isEmpty {
                missing.append(name)
            } else if matches.count > 1 {
                ambiguous.append(name)
            } else if seenIDs.insert(matches[0].id).inserted {
                items.append(matches[0])
            }
        }
        if !missing.isEmpty || !ambiguous.isEmpty {
            var parts: [String] = []
            if !missing.isEmpty {
                parts.append("not found: " + missing.joined(separator: ", "))
            }
            if !ambiguous.isEmpty {
                parts.append("more than one file with this name (ask which one): " + ambiguous.joined(separator: ", "))
            }
            return .failed("Nothing was changed (" + parts.joined(separator: "; ") + ").")
        }
        return .resolved(items)
    }

    // MARK: - Formatting (display strings only; never paths or contents)

    private func formatSize(_ size: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let total = Int(duration.rounded())
        return "\(total / 60)m \(total % 60)s"
    }
}
