import Foundation

/// "Downloaded From" detection from macOS quarantine extended attributes.
///
/// macOS records, per downloaded file:
///   com.apple.quarantine — agent name + timestamp (e.g. "com.google.Chrome")
///   com.apple.metadata:kMDItemWhereFroms — plist array: [referrer URL, direct URL]
/// We read WhereFroms first (it names the actual site/service), fall back
/// to the quarantine agent, and map known hosts to the named sources.
/// Anything else becomes `.website(host)`. Nothing is uploaded; this is a
/// local xattr read. Files without either attribute are `.unknown`.
/// Reading xattrs requires only read access to the file itself.
/// This detector is READ-ONLY: it never writes, removes, or strips a
/// quarantine attribute, and nothing in the app executes a downloaded
/// file on its own — opening is always the user's explicit Open action,
/// so macOS Gatekeeper still applies. (Archive extraction separately
/// propagates quarantine onto extracted files; see ArchiveBrowser.)
enum DownloadSourceDetector {
    static func source(for url: URL) -> DownloadSource {
        if let whereFroms = whereFroms(for: url), let first = whereFroms.first {
            return source(forHost: URL(string: first)?.host?.lowercased())
        }
        if let agent = quarantineAgent(for: url) {
            return source(forHost: agent.lowercased())
        }
        return .unknown
    }

    private static func source(forHost host: String?) -> DownloadSource {
        guard let host else { return .unknown }
        if host.contains("mail.google") || host.contains("gmail") { return .gmail }
        if host.contains("drive.google") { return .googleDrive }
        if host.contains("chatgpt") || host.contains("openai") { return .chatGPT }
        if host.contains("canva") { return .canva }
        if host.contains("x.com") || host.contains("twitter") { return .x }
        if host.contains("slack") { return .slack }
        if host.contains("whatsapp") { return .whatsApp }
        if host.contains("github") { return .gitHub }
        return .website(host)
    }

    /// kMDItemWhereFroms is a binary plist stored as an xattr.
    static func whereFroms(for url: URL) -> [String]? {
        guard let data = xattr(url: url, name: "com.apple.metadata:kMDItemWhereFroms"),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let array = plist as? [String] else { return nil }
        return array
    }

    static func quarantineAgent(for url: URL) -> String? {
        guard let data = xattr(url: url, name: "com.apple.quarantine"),
              let text = String(data: data, encoding: .utf8) else { return nil }
        // Format: "0081;...;AgentName;UUID" — agent is the third field.
        let parts = text.split(separator: ";")
        guard parts.count >= 3 else { return nil }
        return String(parts[2])
    }

    private static func xattr(url: URL, name: String) -> Data? {
        let path = url.path
        let size = getxattr(path, name, nil, 0, 0, 0)
        guard size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        let read = getxattr(path, name, &buffer, size, 0, 0)
        guard read == size else { return nil }
        return Data(buffer)
    }
}
