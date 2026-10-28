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

// MARK: - Local / Debug unlock helpers

/// True for Debug builds, ad-hoc/`CODE_SIGN_IDENTITY=-` binaries, and locally
/// signed Apple Development binaries. Keeps the app usable without ASC IAP or
/// a website serial. Mac App Store / Developer ID production certs stay false.
enum LocalDevBuild {
    static var isActive: Bool {
        #if DEBUG
        return true
        #else
        return isAppleDevelopmentSigned || isAdHocOrUnsigned
        #endif
    }

    /// Best-effort: Apple Development leaf certificate in the code signature.
    private static var isAppleDevelopmentSigned: Bool {
        guard let summary = leafCertificateSummary else { return false }
        return summary.hasPrefix("Apple Development:")
    }

    /// Ad-hoc or unsigned local builds (common for `CODE_SIGN_IDENTITY=-`).
    private static var isAdHocOrUnsigned: Bool {
        guard let dict = signingInformation else { return true }
        let certs = dict[kSecCodeInfoCertificates as String] as? [SecCertificate] ?? []
        if certs.isEmpty { return true }
        // Developer ID / Apple Distribution / 3rd Party Mac Developer → not local-dev.
        if let summary = leafCertificateSummary {
            if summary.hasPrefix("Developer ID Application:") { return false }
            if summary.hasPrefix("Apple Distribution:") { return false }
            if summary.hasPrefix("3rd Party Mac Developer Application:") { return false }
        }
        return false
    }

    private static var leafCertificateSummary: String? {
        guard let dict = signingInformation,
              let certs = dict[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let leaf = certs.first else { return nil }
        return SecCertificateCopySubjectSummary(leaf) as String?
    }

    private static var signingInformation: [String: Any]? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
              let staticCode else { return nil }
        var info: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &info) == errSecSuccess else { return nil }
        return info as? [String: Any]
    }
}

// MARK: - Machine hash (never send raw hardware ids)

enum MachineIdentity {
    /// Stable, non-reversible machine token for activation. SHA-256 of the
    /// IOPlatformUUID (or a random Keychain-backed fallback). The server
    /// stores only this hash — see licensing/store.py.
    /// Prefer calling from a background context — Keychain fallback uses SecItem.
    static func hashedIdentifier() -> String {
        let raw = platformUUID() ?? fallbackUUID()
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func hashedIdentifierAsync() async -> String {
        await Task.detached(priority: .utility) { hashedIdentifier() }.value
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
///
/// All SecItem* calls run off the main thread. Keychain decrypt can block
/// for seconds (or wait on authorizationhost); doing that on MainActor
/// freezes every button in the app.
enum KeychainBlob {
    private static let queue = DispatchQueue(label: "com.metaphasicgroup.fileradar.keychain", qos: .utility)

    static func read(service: String, account: String) -> Data? {
        queue.sync { readSync(service: service, account: account) }
    }

    static func write(_ data: Data, service: String, account: String) -> Bool {
        queue.sync { writeSync(data, service: service, account: account) }
    }

    static func delete(service: String, account: String) {
        queue.sync { deleteSync(service: service, account: account) }
    }

    static func readAsync(service: String, account: String) async -> Data? {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: readSync(service: service, account: account))
            }
        }
    }

    static func writeAsync(_ data: Data, service: String, account: String) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: writeSync(data, service: service, account: account))
            }
        }
    }

    private static func readSync(service: String, account: String) -> Data? {
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

    private static func writeSync(_ data: Data, service: String, account: String) -> Bool {
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

    private static func deleteSync(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        _ = SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Trial (local, Keychain-backed, 14 days)

/// Local trial stamp. Stored in Application Support (not Keychain): re-signed
/// Debug / Apple Development builds previously triggered a modal
/// “wants to use your confidential information… trial” Keychain password
/// dialog that looked like an activation wall and blocked the whole UI.
/// Production MAS can still sell via StoreKit; after trial, free browsing
/// remains available and the unlock sheet stays dismissible.
@MainActor
final class TrialManager: ObservableObject {
    static let durationDays = 14
    private static let defaultsKey = "com.metaphasicgroup.fileradar.trial.startedAt"

    @Published private(set) var startedAt: Date?
    @Published private(set) var isActive = false
    @Published private(set) var daysRemaining = 0

    init() {
        Task { await self.refresh() }
    }

    func refresh() async {
        await applyStamp(restart: false)
    }

    /// Ensures a trial stamp exists. When `restartIfExpired` is true and the
    /// current window has ended, rewrite for a fresh 14 days (Debug /
    /// Continue with Trial / empty-StoreKit recovery).
    @discardableResult
    func startTrial(restartIfExpired: Bool = false) async -> Bool {
        await applyStamp(restart: false)
        if !isActive, restartIfExpired {
            await applyStamp(restart: true)
        }
        return isActive
    }

    private func applyStamp(restart: Bool) async {
        let existingStart = restart ? nil : startedAt
        let defaultsKey = Self.defaultsKey
        let resolved: Date = await Task.detached(priority: .utility) {
            if let existingStart { return existingStart }
            if !restart {
                if let saved = UserDefaults.standard.object(forKey: defaultsKey) as? TimeInterval {
                    return Date(timeIntervalSince1970: saved)
                }
                if let url = Self.stampURL,
                   let data = try? Data(contentsOf: url),
                   let raw = String(data: data, encoding: .utf8),
                   let interval = TimeInterval(raw) {
                    UserDefaults.standard.set(interval, forKey: defaultsKey)
                    return Date(timeIntervalSince1970: interval)
                }
                // Do NOT read the legacy Keychain trial item here: re-signed
                // local builds pop a SecurityAgent password dialog that blocks
                // the entire UI (the former “activation wall”).
            }
            let now = Date()
            let interval = now.timeIntervalSince1970
            UserDefaults.standard.set(interval, forKey: defaultsKey)
            Self.writeStampFile(interval)
            return now
        }.value
        startedAt = resolved
        let end = resolved.addingTimeInterval(TimeInterval(Self.durationDays) * 86_400)
        let remaining = max(0, Calendar.current.dateComponents([.day], from: Date(), to: end).day ?? 0)
        daysRemaining = remaining
        isActive = Date() < end
    }

    nonisolated private static var stampURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("FileRadar", isDirectory: true)
            .appendingPathComponent("trial-started.txt")
    }

    nonisolated private static func writeStampFile(_ interval: TimeInterval) {
        guard let url = stampURL else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? Data(String(interval).utf8).write(to: url, options: .atomic)
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
        let hash = await MachineIdentity.hashedIdentifierAsync()
        return await post(base.appendingPathComponent("activate"),
                          body: ["serial": serial, "machine_hash": hash])
    }

    static func deactivate(_ serial: String) async -> Result {
        guard let base = DistributionChannel.licensingBaseURL else { return .unavailable }
        let hash = await MachineIdentity.hashedIdentifierAsync()
        return await post(base.appendingPathComponent("deactivate"),
                          body: ["serial": serial, "machine_hash": hash])
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

// MARK: - Async thumbnail cache (no global ObservableObject fan-out)

/// In-memory QLThumbnail cache. Intentionally NOT an ObservableObject —
/// broadcasting `objectWillChange` from a shared cache re-rendered every
/// visible `AsyncFileThumbnail` on every completion and froze the UI.
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private var memory: [String: NSImage] = [:]
    private var inflight: [String: [CheckedContinuation<NSImage?, Never>]] = [:]

    func image(for url: URL) -> NSImage? { memory[url.path] }

    func load(url: URL, isICloudOnly: Bool) async -> NSImage? {
        let key = url.path
        if isICloudOnly { return nil }
        if let cached = memory[key] { return cached }
        return await withCheckedContinuation { (continuation: CheckedContinuation<NSImage?, Never>) in
            if var waiters = inflight[key] {
                waiters.append(continuation)
                inflight[key] = waiters
                return
            }
            inflight[key] = [continuation]
            let size = CGSize(width: 256, height: 256)
            let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: 2.0, representationTypes: .thumbnail)
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
                Task { @MainActor in
                    let image = rep?.nsImage
                    if let image { self.memory[key] = image }
                    let waiters = self.inflight.removeValue(forKey: key) ?? []
                    for waiter in waiters { waiter.resume(returning: image) }
                }
            }
        }
    }

    func clear() {
        memory.removeAll()
        let waiters = inflight
        inflight.removeAll()
        for (_, list) in waiters {
            for waiter in list { waiter.resume(returning: nil) }
        }
    }
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
