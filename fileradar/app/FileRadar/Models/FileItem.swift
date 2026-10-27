import Foundation

/// One file FileRadar knows about. Never a Finder replacement that moves
/// things behind the user's back: every mutation goes through TrashService
/// (Trash only, never outright delete — principle 10).
struct FileItem: Identifiable, Hashable {
    var id: String { url.path }
    let url: URL
    var name: String { url.lastPathComponent }
    var kind: FileKind
    var size: Int64
    var modifiedDate: Date
    var createdDate: Date
    var downloadSource: DownloadSource
    var tags: [FileTag]
    /// True when the file lives only in iCloud and has not been downloaded.
    /// Such files are listed but NEVER downloaded by FileRadar (principle 10).
    var isICloudOnly: Bool
    var ocrText: String?
    var width: Int?
    var height: Int?
    var duration: TimeInterval?
    var cameraModel: String?

    var extensionLowercased: String { url.pathExtension.lowercased() }

    static func == (lhs: FileItem, rhs: FileItem) -> Bool { lhs.url == rhs.url }
    func hash(into hasher: inout Hasher) { hasher.combine(url) }
}

enum FileKind: String, CaseIterable, Hashable {
    case image, video, audio, document, archive, app, folder, other

    var displayName: String {
        switch self {
        case .image: return "Images"
        case .video: return "Videos"
        case .audio: return "Music"
        case .document: return "Documents"
        case .archive: return "Archives"
        case .app: return "Apps"
        case .folder: return "Folders"
        case .other: return "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .image: return "photo"
        case .video: return "film"
        case .audio: return "music.note"
        case .document: return "doc.text"
        case .archive: return "archivebox"
        case .app: return "app"
        case .folder: return "folder"
        case .other: return "doc"
        }
    }

    static func from(url: URL, isDirectory: Bool) -> FileKind {
        if isDirectory { return .folder }
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "gif", "heic", "webp", "tiff", "bmp", "svg": return .image
        case "mp4", "mov", "mkv", "avi", "webm": return .video
        case "mp3", "wav", "flac", "aac", "m4a", "ogg": return .audio
        case "pdf", "doc", "docx", "txt", "md", "rtf", "pages", "xls", "xlsx", "ppt", "pptx", "csv": return .document
        case "zip", "rar", "7z", "tar", "gz", "dmg", "pkg", "iso": return .archive
        case "app": return .app
        default: return .other
        }
    }
}

/// Where a download came from, read from quarantine / extended attributes.
/// See Services/DownloadSourceDetector.swift. `.website` carries the host
/// so "any website" grouping works without inventing a source.
enum DownloadSource: Hashable {
    case gmail, googleDrive, chatGPT, canva, x, slack, whatsApp, gitHub
    case website(String)
    case unknown

    var displayName: String {
        switch self {
        case .gmail: return "Gmail"
        case .googleDrive: return "Google Drive"
        case .chatGPT: return "ChatGPT"
        case .canva: return "Canva"
        case .x: return "X"
        case .slack: return "Slack"
        case .whatsApp: return "WhatsApp"
        case .gitHub: return "GitHub"
        case .website(let host): return host
        case .unknown: return "Unknown source"
        }
    }

    var groupKey: String { displayName }
}

/// Manual coloured tags plus auto-tags. Auto-tags carry a plain-language
/// explanation (principle 6); they are never presented as "AI" output.
struct FileTag: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var color: TagColor
    var isAuto: Bool
    /// e.g. "Tagged Receipt because the text contains a total and a date."
    var explanation: String?

    var accessibilityLabel: String {
        if let explanation { return "\(name). \(explanation)" }
        return name
    }
}

enum TagColor: String, CaseIterable, Hashable {
    case red, orange, yellow, green, blue, purple, gray
}
