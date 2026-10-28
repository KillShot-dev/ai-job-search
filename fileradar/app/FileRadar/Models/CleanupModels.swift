import Foundation

/// A Cleanup card: one decision, one group of files, one action (Trash).
/// Principle 2 (Cleanup = decisions) and principle 10 (Trash only, never
/// outright delete; bulk actions confirm first — enforced in CleanupView).
enum CleanupCardType: String, CaseIterable, Codable {
    case oldInstallers = "Old installers"
    case forgottenDownloads = "Forgotten downloads"
    case oldScreenshots = "Old screenshots"
    case bigOldVideos = "Big old videos"
    case unusedApps = "Unused apps"

    var explanation: String {
        switch self {
        case .oldInstallers: return "Installer files you no longer need once the app is installed."
        case .forgottenDownloads: return "Files in Downloads untouched for over 90 days."
        case .oldScreenshots: return "Screenshots older than 90 days."
        case .bigOldVideos: return "Videos over 500 MB not opened in over a year."
        case .unusedApps: return "Apps not opened in over a year. Moving an app to Trash keeps it recoverable."
        }
    }
}

struct CleanupCard: Identifiable {
    let id = UUID()
    var type: CleanupCardType
    var files: [FileItem]
    var totalSize: Int64 { files.reduce(0) { $0 + $1.size } }
}

/// A duplicate group. `.exact` = identical SHA-256. `.lookAlike` = Vision
/// feature-print similarity (photos that look alike, not byte-identical).
struct DuplicateGroup: Identifiable {
    let id = UUID()
    var kind: Kind
    var files: [FileItem]
    var keeper: FileItem?

    enum Kind { case exact, lookAlike }
    var title: String { kind == .exact ? "Identical files" : "Photos that look alike" }
}

/// A version stack: v1 / v2 / final files grouped by a shared base name.
struct VersionStack: Identifiable {
    let id = UUID()
    var baseName: String
    var files: [FileItem] // newest first
}

/// One file-health finding. Nothing here deletes anything on its own.
struct HealthIssue: Identifiable {
    let id = UUID()
    var file: FileItem
    var kind: Kind
    enum Kind: String {
        case zeroByte = "Empty file (0 bytes)"
        case legacyFormat = "Legacy format"
        case possiblyCorrupt = "May not open correctly"
    }
    var suggestion: String {
        switch kind {
        case .zeroByte: return "This file is empty. You can move it to Trash if you no longer need it."
        case .legacyFormat: return "This format is no longer widely supported. Consider converting it."
        case .possiblyCorrupt: return "This file could not be read fully. Try opening it before deciding."
        }
    }
}

/// A node in the disk-map treemap (a folder and its contents by size).
struct DiskNode: Identifiable {
    let id = UUID()
    var name: String
    var url: URL?
    var size: Int64
    var children: [DiskNode]
    var isFile: Bool
}
