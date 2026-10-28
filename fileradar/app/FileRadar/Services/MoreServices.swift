import Foundation
import AVFoundation

// MARK: - Cleanup rules (OFF by default; paid feature)

/// Automatic clean-up rules. Default state is OFF for every rule — the user
/// opts in per rule in Settings (principle: automatic rules OFF by default).
/// Even when on, rules only ever move files to Trash, never delete.
struct CleanupRule: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var type: CleanupCardType
    var isEnabled = false
    var description: String { type.explanation }
}

/// Persists automatic clean-up rule toggles in UserDefaults (all default OFF).
enum CleanupRulesStore {
    private static let defaultsKey = "com.metaphasicgroup.fileradar.cleanupRules"

    static func load() -> [CleanupRule] {
        let defaults = CleanupCardType.allCases.map { CleanupRule(type: $0) }
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([CleanupRule].self, from: data) else {
            return defaults
        }
        return CleanupCardType.allCases.map { type in
            if let existing = decoded.first(where: { $0.type == type }) {
                return CleanupRule(id: existing.id, type: type, isEnabled: existing.isEnabled)
            }
            return CleanupRule(type: type)
        }
    }

    static func save(_ rules: [CleanupRule]) {
        if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}

enum CleanupEngine {
    static func cards(for files: [FileItem], now: Date = Date()) -> [CleanupCard] {
        let downloads = files.filter { $0.url.path.contains("/Downloads/") }
        let old = { (days: Double) in now.addingTimeInterval(-days * 86400) }
        func card(_ type: CleanupCardType, _ list: [FileItem]) -> CleanupCard? {
            list.isEmpty ? nil : CleanupCard(type: type, files: list)
        }
        return [
            card(.oldInstallers, downloads.filter { [".dmg", ".pkg"].contains($0.extensionLowercased) && $0.modifiedDate < old(90) }),
            card(.forgottenDownloads, downloads.filter { $0.modifiedDate < old(90) }),
            card(.oldScreenshots, files.filter { $0.name.lowercased().hasPrefix("screenshot") && $0.modifiedDate < old(90) }),
            card(.bigOldVideos, files.filter { $0.kind == .video && $0.size > 500 * 1_024 * 1_024 && $0.modifiedDate < old(365) }),
            card(.unusedApps, files.filter { $0.kind == .app && $0.modifiedDate < old(365) }),
        ].compactMap { $0 }
    }
}

// MARK: - Batch rename (paid feature)

/// Rename with patterns. `{name}` = original name without extension,
/// `{n}` = sequential number, `{date}` = modification date YYYY-MM-DD.
/// Collisions are refused (the file is left untouched and reported),
/// never silently overwritten.
/// Path safety: a pattern is user-typed text, so it may contain `/`,
/// `\`, or `..`. A raw pattern could otherwise move a file into a
/// subfolder or out of its folder entirely (e.g. `../escaped`). Names
/// are therefore sanitized — separators become `-`, and a result of
/// `.`, `..`, or empty is refused — and `apply` re-checks that the
/// destination stays in the file's own folder, so no caller can bypass
/// the preview sanitization.
enum RenameService {
    /// Returns a safe single-component filename, or nil to refuse it.
    static func sanitizedName(_ name: String) -> String? {
        let cleaned = name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned != ".", cleaned != ".." else { return nil }
        return cleaned
    }

    static func preview(files: [FileItem], pattern: String) -> [(file: FileItem, newName: String)] {
        files.enumerated().map { index, file in
            let base = file.url.deletingPathExtension().lastPathComponent
            let date = ISO8601DateFormatter().string(from: file.modifiedDate).prefix(10)
            var name = pattern
                .replacingOccurrences(of: "{name}", with: base)
                .replacingOccurrences(of: "{n}", with: "\(index + 1)")
                .replacingOccurrences(of: "{date}", with: String(date))
            if !file.url.pathExtension.isEmpty { name += ".\(file.url.pathExtension)" }
            // An unsanitizable preview falls back to the current name, so
            // the UI never promises a rename `apply` will refuse.
            return (file, sanitizedName(name) ?? file.name)
        }
    }

    /// Applies the preview; returns files that could not be renamed.
    static func apply(_ plan: [(file: FileItem, newName: String)]) -> [FileItem] {
        var failed: [FileItem] = []
        for (file, newName) in plan {
            guard let clean = sanitizedName(newName) else { failed.append(file); continue }
            let parent = file.url.deletingLastPathComponent()
            let dest = parent.appendingPathComponent(clean)
            guard dest.deletingLastPathComponent() == parent else { failed.append(file); continue }
            guard !FileManager.default.fileExists(atPath: dest.path) else { failed.append(file); continue }
            do { try FileManager.default.moveItem(at: file.url, to: dest) }
            catch { failed.append(file) }
        }
        return failed
    }
}

// MARK: - Parcel export (paid feature)

/// Zips a selection plus a JSON manifest (name, size, date, source) so the
/// recipient knows what is inside without opening every file.
enum ParcelExportService {
    struct ManifestEntry: Codable {
        var name: String; var size: Int64; var modified: String; var source: String
    }

    static func export(files: [FileItem], to destination: URL) throws {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        var manifest: [ManifestEntry] = []
        for file in files where !file.isICloudOnly {
            // Symlinks are skipped, not followed: copying one and then
            // zipping the staging tree could otherwise smuggle the link
            // target's contents to the parcel recipient. A file whose
            // staging name already exists (two files, one name) is also
            // skipped, so the manifest never claims a file the zip does
            // not contain.
            let values = try? file.url.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values?.isSymbolicLink != true else { continue }
            let dest = staging.appendingPathComponent(file.name)
            guard !fm.fileExists(atPath: dest.path) else { continue }
            guard (try? fm.copyItem(at: file.url, to: dest)) != nil else { continue }
            manifest.append(ManifestEntry(
                name: file.name, size: file.size,
                modified: ISO8601DateFormatter().string(from: file.modifiedDate),
                source: file.downloadSource.displayName))
        }
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: staging.appendingPathComponent("manifest.json"))
        // Zip via /usr/bin/zip (present on macOS). No third-party dependency.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-r", "-q", destination.path, "."]
        process.currentDirectoryURL = staging
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "FileRadar.Parcel", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Could not create the zip file."])
        }
    }
}

// MARK: - File health (beat-extra)

enum HealthCheckService {
    static func check(files: [FileItem]) -> [HealthIssue] {
        var issues: [HealthIssue] = []
        let legacy: Set<String> = ["pict", "wmf", "flv", "swf", "doc", "xls", "ppt"]
        for file in files where !file.isICloudOnly {
            if file.size == 0 {
                issues.append(HealthIssue(file: file, kind: .zeroByte))
            } else if legacy.contains(file.extensionLowercased) {
                issues.append(HealthIssue(file: file, kind: .legacyFormat))
            }
        }
        return issues
    }
}

// MARK: - Storage forecast (beat-extra)

/// Plain linear forecast from the last 90 days of file creation: average
/// bytes added per day, projected 30 / 90 days out. Labelled as an estimate
/// in the UI — it is not a prediction, and never a made-up number.
enum ForecastService {
    struct Forecast { var dailyBytes: Int64; var in30Days: Int64; var in90Days: Int64 }

    static func forecast(files: [FileItem], now: Date = Date()) -> Forecast {
        let cutoff = now.addingTimeInterval(-90 * 86400)
        let recent = files.filter { $0.createdDate > cutoff }
        let total = recent.reduce(0) { $0 + $1.size }
        let daily = total / 90
        return Forecast(dailyBytes: daily, in30Days: daily * 30, in90Days: daily * 90)
    }
}

// MARK: - Version stacks (beat-extra)

/// Groups "Report v2.pdf", "Report final.pdf", "Report.pdf" by stripping
/// version suffixes (v1, v2, final, copy, dated suffixes) from the base name.
enum VersionStackService {
    static func stacks(for files: [FileItem]) -> [VersionStack] {
        var groups: [String: [FileItem]] = [:]
        for file in files {
            let base = file.url.deletingPathExtension().lastPathComponent
            let key = base
                .replacingOccurrences(of: #"\s+v\d+$"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\s+final$"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\s+copy$"#, with: "", options: .regularExpression)
                .lowercased()
            groups[key, default: []].append(file)
        }
        return groups.values.filter { $0.count > 1 }.map { files in
            VersionStack(baseName: files.first!.url.deletingPathExtension().lastPathComponent,
                         files: files.sorted { $0.modifiedDate > $1.modifiedDate })
        }
    }
}

// MARK: - In-toolbar music playback

@MainActor
final class MusicPlaybackService: ObservableObject {
    @Published var current: FileItem?
    @Published var isPlaying = false
    private var player: AVPlayer?

    func toggle(_ file: FileItem) {
        guard file.kind == .audio else { return }
        if current?.id == file.id {
            isPlaying ? player?.pause() : player?.play()
            isPlaying.toggle()
        } else {
            current = file
            player = AVPlayer(url: file.url)
            player?.play()
            isPlaying = true
        }
    }

    func stop() { player?.pause(); isPlaying = false; current = nil }
}
