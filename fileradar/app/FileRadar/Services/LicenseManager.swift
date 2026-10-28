import Foundation
import Security

/// Licensing — real validation, not a stub.
///
/// Serial format: FR-XXXX-XXXX-XXXX-XXXX (16 characters in 4 groups of 4,
/// plus the "FR-" prefix; the prefix is not part of the checksum).
/// Alphabet excludes easily confused characters (no 0/O, 1/I/L):
///   "ABCDEFGHJKMNPQRSTUVWXYZ23456789"  (31 symbols)
/// Checksum — IDENTICAL to the licensing backend (`../licensing/serials.py`).
///
/// Unlock sources (any one unlocks paid features):
///   1. Keychain serial (direct / website) — optional HTTPS server confirm
///      when `FRLicensingBaseURL` is set in Info.plist.
///   2. StoreKit 2 entitlement (Mac App Store) via `StoreKitLicense`.
///   3. Active local trial (`TrialManager`, 14 days, Keychain stamp).
///
/// Secrets never ship in the client. Stripe keys, webhook secrets, and
/// App Store Connect API keys stay on the server / in the developer's
/// keychain profiles only.
enum PaidFeature: String, CaseIterable {
    case ocrCopyAll = "Copy all recognised text"
    case duplicates = "Duplicates"
    case cleanup = "Clean Up"
    case quickSearch = "Quick Search panel"
    case menuBarExtras = "Menu bar downloads"
    case shortcuts = "Shortcuts & Siri actions"
    case savedSearches = "Saved searches"
    case autoCleanupRules = "Automatic clean-up rules"
    case batchRename = "Batch rename"
    case parcelExport = "Parcel export"
    case smartCollections = "Smart Collections"
    case folderSyncCompare = "Folder sync & compare"
    case archiveBrowse = "Archive browsing"
    case workspaces = "Workspaces"

    var lockedMessage: String {
        "This is a full-version feature. Unlock with a serial, an App Store purchase, or the free trial."
    }
}

enum LicenseSource: String {
    case none
    case serial
    case storeKit
    case trial
}

/// Minimal Keychain wrapper for the activation serial only.
private enum KeychainSerialStore {
    private static let service = "com.metaphasicgroup.fileradar.license"
    private static let account = "activation-serial"

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let serial = String(data: data, encoding: .utf8),
              !serial.isEmpty else { return nil }
        return serial
    }

    static func write(_ serial: String) -> Bool {
        guard let data = serial.data(using: .utf8) else { return false }
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        if addStatus == errSecSuccess { return true }
        guard addStatus == errSecDuplicateItem else { return false }
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary,
                                         [kSecValueData as String: data] as CFDictionary)
        return updateStatus == errSecSuccess
    }

    static func delete() {
        _ = SecItemDelete(baseQuery as CFDictionary)
    }
}

@MainActor
final class LicenseManager: ObservableObject {
    @Published private(set) var isUnlocked = false
    @Published private(set) var serial: String?
    @Published private(set) var source: LicenseSource = .none
    @Published private(set) var statusMessage: String?
    @Published private(set) var isBusy = false

    /// Injected from the app; optional so previews/tests still compile.
    weak var storeKit: StoreKitLicense?
    weak var trial: TrialManager?

    static let alphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
    private let legacyDefaultsKey = "com.metaphasicgroup.fileradar.license.serial"
    private var legacyStateFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("FileRadar", isDirectory: true)
            .appendingPathComponent("license.json")
    }

    init() { restore() }

    // MARK: - Validation (pure, testable; mirrors licensing/serials.py)

    /// Normalize user input to the 16-char body, or nil if malformed.
    /// Accepts optional FR/FR- prefix, hyphens, spaces, lowercase.
    static func normalize(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        s = s.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: "")
        if s.hasPrefix("FR") { s = String(s.dropFirst(2)) }
        guard s.count == 16, s.allSatisfy({ alphabet.contains($0) }) else { return nil }
        return s
    }

    static func format(_ body16: String) -> String? {
        guard body16.count == 16 else { return nil }
        let groups = stride(from: 0, to: 16, by: 4).map {
            String(body16[body16.index(body16.startIndex, offsetBy: $0)..<body16.index(body16.startIndex, offsetBy: $0 + 4)])
        }
        return "FR-" + groups.joined(separator: "-")
    }

    /// Canonical FR-XXXX-XXXX-XXXX-XXXX form, or nil if invalid.
    static func canonical(_ raw: String) -> String? {
        guard let body = normalize(raw), validateBody(body), let formatted = format(body) else { return nil }
        return formatted
    }

    static func validate(_ raw: String) -> Bool { canonical(raw) != nil }

    private static func validateBody(_ body: String) -> Bool {
        guard body.count == 16, body.allSatisfy({ alphabet.contains($0) }) else { return false }
        guard let check = checksumChar(for: String(body.prefix(15))) else { return false }
        return check == body.last!
    }

    static func checksumChar(for payload: String) -> Character? {
        let chars = Array(alphabet)
        guard payload.count == 15, payload.allSatisfy({ alphabet.contains($0) }) else { return nil }
        var total = 0
        for (i, ch) in payload.enumerated() {
            guard let idx = chars.firstIndex(of: ch) else { return nil }
            total += (i + 1) * idx
        }
        return chars[total % 31]
    }

    static func makeSerial(payload: String) -> String? {
        guard let check = checksumChar(for: payload) else { return nil }
        let full = payload + String(check)
        let groups = stride(from: 0, to: 16, by: 4).map {
            String(full[full.index(full.startIndex, offsetBy: $0)..<full.index(full.startIndex, offsetBy: $0 + 4)])
        }
        return "FR-" + groups.joined(separator: "-")
    }

    // MARK: - Recompute unlock from all sources

    func refreshEntitlements() {
        trial?.refresh()
        if storeKit?.isEntitled == true {
            source = .storeKit
            isUnlocked = true
            statusMessage = "Unlocked via Mac App Store purchase."
            return
        }
        if let saved = serial, Self.canonical(saved) != nil {
            source = .serial
            isUnlocked = true
            statusMessage = nil
            return
        }
        if trial?.isActive == true {
            source = .trial
            isUnlocked = true
            let days = trial?.daysRemaining ?? 0
            statusMessage = "Trial active — \(days) day\(days == 1 ? "" : "s") left."
            return
        }
        source = .none
        isUnlocked = false
        statusMessage = nil
    }

    // MARK: - Activation (direct / website)

    @discardableResult
    func activate(_ raw: String) -> Bool {
        guard let cleaned = Self.canonical(raw) else {
            statusMessage = "That serial number did not check out."
            return false
        }
        guard KeychainSerialStore.write(cleaned) else {
            statusMessage = "Could not store the serial securely."
            return false
        }
        serial = cleaned
        removeLegacyCopies()
        refreshEntitlements()
        // Best-effort server confirm when configured. Local unlock already
        // succeeded so the user is not blocked offline; a conflict message
        // surfaces without wiping a valid local serial (user can deactivate).
        Task { await confirmWithServerIfConfigured(cleaned) }
        return true
    }

    /// Async activation that prefers server authority when a base URL is set.
    /// Sends `machine_hash` (SHA-256 of hardware UUID) via LicenseServerClient.
    func activateOnline(_ raw: String) async -> Bool {
        guard let cleaned = Self.canonical(raw) else {
            statusMessage = "That serial number did not check out."
            return false
        }
        isBusy = true
        defer { isBusy = false }
        if DistributionChannel.licensingBaseURL != nil {
            let result = await LicenseServerClient.activate(cleaned)
            switch result {
            case .ok:
                break
            case .invalid:
                statusMessage = "That serial is not recognised by the license server."
                return false
            case .conflict:
                statusMessage = "This serial is active on another Mac. Deactivate there first."
                return false
            case .unavailable:
                // Offline / misconfigured: fall through to local-only unlock
                // so a buyer is not locked out of a paid serial.
                statusMessage = "License server unreachable — unlocked on this Mac only."
            }
        }
        guard KeychainSerialStore.write(cleaned) else {
            statusMessage = "Could not store the serial securely."
            return false
        }
        serial = cleaned
        removeLegacyCopies()
        refreshEntitlements()
        return true
    }

    func deactivate() {
        let previous = serial
        serial = nil
        KeychainSerialStore.delete()
        removeLegacyCopies()
        if let previous, DistributionChannel.licensingBaseURL != nil {
            Task { _ = await LicenseServerClient.deactivate(previous) }
        }
        refreshEntitlements()
    }

    /// Online deactivate that always sends machine_hash when a base URL is set.
    func deactivateOnline() async {
        let previous = serial
        serial = nil
        KeychainSerialStore.delete()
        removeLegacyCopies()
        if let previous, DistributionChannel.licensingBaseURL != nil {
            _ = await LicenseServerClient.deactivate(previous)
        }
        refreshEntitlements()
    }

    private func confirmWithServerIfConfigured(_ serial: String) async {
        guard DistributionChannel.licensingBaseURL != nil else { return }
        let result = await LicenseServerClient.activate(serial)
        await MainActor.run {
            switch result {
            case .conflict:
                statusMessage = "Warning: this serial may already be active on another Mac."
            case .invalid:
                statusMessage = "Warning: the license server did not recognise this serial."
            case .ok:
                statusMessage = "Serial confirmed with the license server."
            case .unavailable:
                break
            }
        }
    }

    private func restore() {
        if let saved = KeychainSerialStore.read(), let canon = Self.canonical(saved) {
            serial = canon
        } else {
            var legacy: String?
            if let saved = UserDefaults.standard.string(forKey: legacyDefaultsKey),
               let canon = Self.canonical(saved) {
                legacy = canon
            } else if let url = legacyStateFileURL,
                      let data = try? Data(contentsOf: url),
                      let record = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                      let saved = record["serial"],
                      let canon = Self.canonical(saved) {
                legacy = canon
            }
            if let migrated = legacy, KeychainSerialStore.write(migrated) {
                serial = migrated
                removeLegacyCopies()
            }
        }
        refreshEntitlements()
    }

    private func removeLegacyCopies() {
        UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
        if let url = legacyStateFileURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func isAllowed(_ feature: PaidFeature) -> Bool { isUnlocked }
}
