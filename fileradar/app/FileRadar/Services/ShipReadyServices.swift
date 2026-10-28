import Foundation
import IOKit
import AppKit
import CryptoKit
import Security
import QuickLookThumbnailing

// MARK: - Distribution channel (MAS vs direct / website)

/// How this binary is expected to sell. Detected at runtime from Info.plist
/// (`FRDistribution` = `mas` | `direct`) with a receipt-based fallback.
/// Secrets never live here — only a public product id / licensing base URL.
enum DistributionChannel: String {
    case macAppStore = "mas"
    case direct = "direct"

    static var current: DistributionChannel {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "FRDistribution") as? String,
           let channel = DistributionChannel(rawValue: raw.lowercased()) {
            return channel
        }
        // Receipt present → treat as App Store unless overridden.
        if let url = Bundle.main.appStoreReceiptURL,
           FileManager.default.fileExists(atPath: url.path) {
            return .macAppStore
        }
        return .direct
    }

    /// Public StoreKit product id only (not a secret). Override via Info.plist.
    static var storeKitProductID: String {
        (Bundle.main.object(forInfoDictionaryKey: "FRStoreKitProductID") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
            ?? "com.metaphasicgroup.fileradar.full"
    }

    /// Optional HTTPS licensing API base (website sales). Empty = offline serial only.
    static var licensingBaseURL: URL? {
        guard let raw = (Bundle.main.object(forInfoDictionaryKey: "FRLicensingBaseURL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let url = URL(string: raw),
              url.scheme?.lowercased() == "https" else { return nil }
        return url
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Machine hash (never send raw hardware ids)

enum MachineIdentity {
    /// Stable, non-reversible machine token for activation. SHA-256 of the
    /// IOPlatformUUID (or a random Keychain-backed fallback). The server
    /// stores only this hash — see licensing/store.py.
    static func hashedIdentifier() -> String {
        let raw = platformUUID() ?? fallbackUUID()
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func platformUUID() -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let cf = IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
            return nil
        }
        return cf as? String
    }

    private static func fallbackUUID() -> String {
        let service = "com.metaphasicgroup.fileradar.machine"
        let account = "machine-uuid"
        if let existing = KeychainBlob.read(service: service, account: account),
           let s = String(data: existing, encoding: .utf8), !s.isEmpty {
            return s
        }
        let fresh = UUID().uuidString
        _ = KeychainBlob.write(Data(fresh.utf8), service: service, account: account)
        return fresh
    }
}

/// Tiny Keychain blob helper shared by license serial, trial stamp, and
/// machine UUID. Never logs contents.
enum KeychainBlob {
    static func read(service: String, account: String) -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return data
    }

    static func write(_ data: Data, service: String, account: String) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        var attrs = base
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        let add = SecItemAdd(attrs as CFDictionary, nil)
        if add == errSecSuccess { return true }
        guard add == errSecDuplicateItem else { return false }
        return SecItemUpdate(base as CFDictionary,
                             [kSecValueData as String: data] as CFDictionary) == errSecSuccess
    }

    static func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        _ = SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Trial (local, Keychain-backed, 14 days)

/// Local trial for direct-sale builds. Starts on first launch; stamp lives
/// in Keychain only. MAS builds should prefer StoreKit free trial / intro
/// offers configured in App Store Connect — this path is for website sales.
@MainActor
final class TrialManager: ObservableObject {
    static let durationDays = 14

    private let service = "com.metaphasicgroup.fileradar.trial"
    private let account = "first-launch"

    @Published private(set) var startedAt: Date?
    @Published private(set) var isActive = false
    @Published private(set) var daysRemaining = 0

    init() { refresh() }

    func refresh() {
        if startedAt == nil {
            if let data = KeychainBlob.read(service: service, account: account),
               let raw = String(data: data, encoding: .utf8),
               let interval = TimeInterval(raw) {
                startedAt = Date(timeIntervalSince1970: interval)
            } else {
                let now = Date()
                startedAt = now
                _ = KeychainBlob.write(Data(String(now.timeIntervalSince1970).utf8),
                                       service: service, account: account)
            }
        }
        guard let start = startedAt else {
            isActive = false
            daysRemaining = 0
            return
        }
        let end = start.addingTimeInterval(TimeInterval(Self.durationDays) * 86_400)
        let remaining = max(0, Calendar.current.dateComponents([.day], from: Date(), to: end).day ?? 0)
        daysRemaining = remaining
        isActive = Date() < end
    }
}

// MARK: - Licensing server client (website sales; no secrets in client)

enum LicenseServerClient {
    enum Result: Equatable {
        case ok
        case invalid
        case conflict // already active on another Mac
        case unavailable // no base URL / offline / transport error
    }

    /// Validate that a serial exists and is active on the server.
    /// Fail-closed only when a base URL is configured; when unset, returns
    /// `.unavailable` so local checksum can still unlock for offline demos.
    static func validateSerial(_ serial: String) async -> Result {
        guard let base = DistributionChannel.licensingBaseURL else { return .unavailable }
        return await post(base.appendingPathComponent("validate-serial"),
                          body: ["serial": serial])
    }

    static func activate(_ serial: String) async -> Result {
        guard let base = DistributionChannel.licensingBaseURL else { return .unavailable }
        return await post(base.appendingPathComponent("activate"),
                          body: ["serial": serial,
                                 "machine_hash": MachineIdentity.hashedIdentifier()])
    }

    static func deactivate(_ serial: String) async -> Result {
        guard let base = DistributionChannel.licensingBaseURL else { return .unavailable }
        return await post(base.appendingPathComponent("deactivate"),
                          body: ["serial": serial,
                                 "machine_hash": MachineIdentity.hashedIdentifier()])
    }

    private static func post(_ url: URL, body: [String: String]) async -> Result {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .unavailable }
            switch http.statusCode {
            case 200: return .ok
            case 404, 400: return .invalid
            case 409: return .conflict
            default: return .unavailable
            }
        } catch {
            return .unavailable
        }
    }
}

// MARK: - Async thumbnail cache (fixes sync NSImage stutter)

@MainActor
final class ThumbnailCache: ObservableObject {
    static let shared = ThumbnailCache()
    private var memory: [String: NSImage] = [:]
    private var inflight: Set<String> = []

    func image(for url: URL) -> NSImage? { memory[url.path] }

    func load(url: URL, isICloudOnly: Bool) {
        let key = url.path
        guard !isICloudOnly, memory[key] == nil, !inflight.contains(key) else { return }
        inflight.insert(key)
        let size = CGSize(width: 256, height: 256)
        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: 2.0, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
            Task { @MainActor in
                if let rep {
                    self.memory[key] = rep.nsImage
                }
                self.inflight.remove(key)
                self.objectWillChange.send()
            }
        }
    }

    func clear() { memory.removeAll() }
}

// MARK: - Saved searches (paid)

struct SavedSearch: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var query: String
    var createdAt: Date = Date()
}

@MainActor
final class SavedSearchStore: ObservableObject {
    @Published private(set) var items: [SavedSearch] = []
    private let defaultsKey = "com.metaphasicgroup.fileradar.savedSearches"

    init() { load() }

    func save(name: String, query: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !q.isEmpty else { return }
        items.insert(SavedSearch(name: trimmed, query: q), at: 0)
        persist()
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        persist()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([SavedSearch].self, from: data) else { return }
        items = decoded
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}

// MARK: - Manual tags + favorites (local, no cloud)

@MainActor
final class ManualTagStore: ObservableObject {
    /// path → manual tags (auto-tags stay derived at index time)
    @Published private(set) var tagsByPath: [String: [FileTagRecord]] = [:]
    private let defaultsKey = "com.metaphasicgroup.fileradar.manualTags"

    struct FileTagRecord: Codable, Hashable {
        var name: String
        var color: String
    }

    init() { load() }

    func tags(for path: String) -> [FileTag] {
        (tagsByPath[path] ?? []).map {
            FileTag(name: $0.name,
                    color: TagColor(rawValue: $0.color) ?? .gray,
                    isAuto: false,
                    explanation: nil)
        }
    }

    func add(name: String, color: TagColor, to path: String) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        var list = tagsByPath[path] ?? []
        guard !list.contains(where: { $0.name.lowercased() == cleaned.lowercased() }) else { return }
        list.append(FileTagRecord(name: cleaned, color: color.rawValue))
        tagsByPath[path] = list
        persist()
    }

    func remove(name: String, from path: String) {
        tagsByPath[path]?.removeAll { $0.name.lowercased() == name.lowercased() }
        if tagsByPath[path]?.isEmpty == true { tagsByPath[path] = nil }
        persist()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([String: [FileTagRecord]].self, from: data) else { return }
        tagsByPath = decoded
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(tagsByPath) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}

@MainActor
final class FavoritesStore: ObservableObject {
    @Published private(set) var paths: [String] = []
    private let defaultsKey = "com.metaphasicgroup.fileradar.favorites"

    init() {
        paths = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
    }

    func contains(_ url: URL) -> Bool { paths.contains(url.path) }

    func toggle(_ url: URL) {
        if let idx = paths.firstIndex(of: url.path) {
            paths.remove(at: idx)
        } else {
            paths.insert(url.path, at: 0)
        }
        UserDefaults.standard.set(paths, forKey: defaultsKey)
    }
}
