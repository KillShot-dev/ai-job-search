import AppKit
import AuthenticationServices
import CryptoKit
import Foundation
import Security

/// Muse sign-in for FileRadar — secure login only, no chat logic here.
///
/// SETUP — READ BEFORE SHIPPING (developer steps, all in Xcode):
///   1. Add this file and `MuseConfig.swift` to the app target
///      (target > Build Phases > Compile Sources). This project file is
///      hand-written, so Xcode does not pick up new files automatically.
///   2. Copy `MuseConfig.sample.plist` to `MuseConfig.plist`, fill in real
///      values from YOUR Meta developer dashboard, and add the copy to the
///      app target (target > Build Phases > Copy Bundle Resources). See
///      the header comment in `MuseConfig.swift` for the full checklist.
///   3. Confirm the Info.plist URL scheme `fileradar` and the microphone /
///      speech-recognition usage strings (target > Info), and the Release
///      entitlements additions (network client, audio input, and the
///      speech-recognition key flagged VERIFY-IN-XCODE in
///      `FileRadar.entitlements`).
///
/// WHAT THIS IS (honest design — do not over-claim it):
///   FileRadar cannot embed the Muse personal-agent runtime, and no public
///   third-party OAuth flow for logging a Mac app into a personal Muse
///   account could be verified. This service therefore performs an
///   OAuth-style login (ASWebAuthenticationSession + PKCE S256) against
///   the developer-configured Model API endpoint from `MuseConfig`. The
///   chat UI sibling presents this as "Connect", and the README (written
///   separately) states FileRadar is not affiliated with or endorsed by
///   Meta. Nothing here claims Meta endorsement, and no Meta-confirmed
///   endpoint, key, or flow is asserted: the authorize/token paths derived
///   in `MuseConfig` are conventional OAuth2 paths that the developer must
///   verify in their Meta developer dashboard before shipping.
///
/// SECURITY POSTURE (mirrors `LicenseManager`'s Keychain pattern, with
/// biometric access control added for tokens):
///   - Tokens live ONLY in the macOS Keychain, service
///     `com.metaphasicgroup.fileradar.muse`, accounts `muse-access-token`
///     (JSON `{token, expiresAt}`) and `muse-refresh-token` (the token
///     string). No access group, so no extra entitlement is needed, and
///     items are never synced.
///   - Access control: SecAccessControl with `.biometryCurrentSet` and
///     `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — this-device-only,
///     and items become inaccessible if the biometric enrollment set
///     changes, in which case refresh fails closed (tokens wiped, user
///     reconnects) rather than silently falling back to weaker storage.
///   - NOTHING secret is ever written to UserDefaults, logs, analytics,
///     crash reports, or plaintext files. Error strings shown to the user
///     are generic: server response bodies, URLs containing authorization
///     codes, and tokens are never echoed, logged, or stored.
///   - HTTPS only: `MuseConfig.load()` rejects any non-HTTPS base URL, and
///     this service never issues a non-HTTPS request. There are no App
///     Transport Security exceptions anywhere in the app.
///   - Access-token expiry is handled in memory (via the stored
///     `expiresAt`) plus the Keychain data; tokens are never stored in
///     plaintext files. `logout()` wipes ALL Muse tokens from the Keychain.
///     Chat-history deletion is NOT part of logout: it is the chat UI
///     sibling's separate, explicit button, so signing out never silently
///     destroys the user's local history.
///   - Keychain failures fail closed with a generic error, exactly like
///     `LicenseManager`'s bare-Bool pattern: a failed store never reports
///     success, and a failed refresh wipes tokens and disconnects.
///
/// STATE / NONCE VALIDATION (exactly what is checked, no more):
///   - `state`: a fresh random value per login attempt, sent with the
///     authorization request and required to match EXACTLY on callback.
///     A mismatch aborts the login before any code exchange.
///   - `nonce`: a fresh random value per login attempt, sent with the
///     authorization request (standard OIDC practice). It is validated
///     against the `nonce` claim of an `id_token` WHEN the token response
///     includes one; a mismatch wipes any stored tokens and fails the
///     login. Providers that return access/refresh tokens only (no
///     `id_token`) have no nonce claim to check, so those flows rely on
///     the state check plus PKCE instead — the nonce is not faked into
///     the callback, because no provider returns it there.
///   - PKCE: `code_verifier` is 43–128 characters from the unreserved set;
///     `code_challenge` is base64url(SHA256(verifier)) with method S256.
///     The verifier never leaves the app except in the token exchange,
///     and it is discarded after use.
///
/// TOKEN LIFECYCLE:
///   - `validAccessToken()` returns the stored access token while it has
///     more than 60 seconds of life left; otherwise it refreshes with the
///     stored refresh token. Rotation is honored: when the provider
///     returns a new refresh token, the stored one is replaced.
///   - On ANY refresh failure the stored tokens are wiped, `isConnected`
///     becomes false, and a generic error is thrown — the app never keeps
///     retrying with a dead token and never reports itself connected
///     without a usable token.
///   - The token endpoint is called with `application/x-www-form-urlencoded`
///     bodies as a public client (PKCE, no client secret embedded in the
///     app — embedding a secret in a shipped binary would not be secret).
///
/// THREADING: this class is `@MainActor` because ASWebAuthenticationSession
/// must be presented from the main thread and `@Published` state must be
/// updated there. Callers (e.g. the chat sibling) may call from any task;
/// Swift hops to the main actor automatically.
enum MuseAuthError: Error {
    /// Configuration missing/incomplete (see `MuseConfigError`).
    case notConfigured
    /// No usable tokens are stored; the user must connect.
    case notConnected
    /// Sign-in, code exchange, or refresh failed. Generic by design:
    /// never carries a server body, URL, code, or token.
    case authenticationFailed
}

/// Codable form of the stored access token: the token plus its absolute
/// expiry, so `validAccessToken()` can decide refresh without a clock
/// skew guess on the provider side. Stored as JSON data in the Keychain.
private struct StoredAccessToken: Codable {
    let token: String
    let expiresAt: Date
}

/// Minimal Keychain wrapper for Muse tokens only. Follows the
/// `LicenseManager` pattern (SecItemAdd/Update/CopyMatching/Delete, bare
/// success flags, no secret in any error), plus biometric access control.
/// A missing item counts as absent, not an error, for reads and deletes.
private enum MuseTokenStore {
    private static let service = "com.metaphasicgroup.fileradar.muse"
    private static let accessAccount = "muse-access-token"
    private static let refreshAccount = "muse-refresh-token"

    /// Biometric access control: current biometric set only, unlocked
    /// device only, never synced. Creation failure means "fail closed":
    /// callers treat a nil control as a store failure.
    private static func accessControl() -> SecAccessControl? {
        SecAccessControlCreateWithFlags(nil,
                                        kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                                        .biometryCurrentSet,
                                        nil)
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    /// Presence check WITHOUT loading the secret into memory.
    private static func exists(account: String) -> Bool {
        var query = baseQuery(account: account)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    static func accessTokenExists() -> Bool { exists(account: accessAccount) }
    static func refreshTokenExists() -> Bool { exists(account: refreshAccount) }

    private static func readData(account: String) -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, !data.isEmpty else { return nil }
        return data
    }

    private static func writeData(_ data: Data, account: String) -> Bool {
        guard let control = accessControl() else { return false }
        var attributes = baseQuery(account: account)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessControl as String] = control
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        if addStatus == errSecSuccess { return true }
        guard addStatus == errSecDuplicateItem else { return false }
        // Update path must carry the same access control, or the item
        // would keep whatever control it was created with.
        let updateStatus = SecItemUpdate(baseQuery(account: account) as CFDictionary,
                                         [kSecValueData as String: data,
                                          kSecAttrAccessControl as String: control] as CFDictionary)
        return updateStatus == errSecSuccess
    }

    private static func delete(account: String) {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        _ = status // errSecItemNotFound and any other status both mean "not stored"
    }

    static func readAccessToken() -> StoredAccessToken? {
        guard let data = readData(account: accessAccount) else { return nil }
        return try? JSONDecoder().decode(StoredAccessToken.self, from: data)
    }

    static func writeAccessToken(_ stored: StoredAccessToken) -> Bool {
        guard let data = try? JSONEncoder().encode(stored) else { return false }
        return writeData(data, account: accessAccount)
    }

    static func readRefreshToken() -> String? {
        guard let data = readData(account: refreshAccount),
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty else { return nil }
        return token
    }

    static func writeRefreshToken(_ token: String) -> Bool {
        guard let data = token.data(using: .utf8) else { return false }
        return writeData(data, account: refreshAccount)
    }

    /// Wipes ALL Muse tokens. Used by `logout()` and by refresh failure.
    static func deleteAll() {
        delete(account: accessAccount)
        delete(account: refreshAccount)
    }
}

@MainActor
final class MuseAuthService: NSObject, ObservableObject {
    /// True when a refresh token is stored (i.e. a previous sign-in has
    /// not been logged out and refresh has not failed). This is a local
    /// presence flag, not proof the token is still valid — the first
    /// `validAccessToken()` call refreshes if needed and disconnects on
    /// failure.
    @Published private(set) var isConnected = false
    /// True only while the browser sign-in session is in flight.
    @Published private(set) var isConnecting = false
    /// Generic, user-safe message for the last failure, or nil. Never
    /// contains a server body, URL, code, or token.
    @Published private(set) var lastError: String?

    /// Kept alive for the duration of the browser session; without a
    /// strong reference the session would deallocate mid-sign-in.
    private var authSession: ASWebAuthenticationSession?
    /// Expected callback state for the in-flight login; cleared on finish.
    private var expectedState: String?
    /// Expected nonce for the in-flight login; cleared on finish.
    private var expectedNonce: String?

    override init() {
        super.init()
        // Presence only — no secret is loaded into memory at launch.
        isConnected = MuseTokenStore.refreshTokenExists()
    }

    // MARK: - Sign-in

    /// Starts the browser sign-in flow (ASWebAuthenticationSession +
    /// PKCE S256). On success, tokens are stored in the Keychain and
    /// `isConnected` becomes true. On any failure, `lastError` holds a
    /// generic message and no tokens are left half-stored.
    func connect() async {
        guard !isConnecting else { return }
        isConnecting = true
        lastError = nil
        defer {
            isConnecting = false
            authSession = nil
            expectedState = nil
            expectedNonce = nil
        }
        let config: MuseConfig
        do {
            config = try MuseConfig.load()
        } catch {
            lastError = "Muse sign-in is not configured. Ask the developer to set up MuseConfig.plist."
            return
        }
        let verifier = Self.makeCodeVerifier()
        let challenge = Self.codeChallenge(for: verifier)
        let state = Self.randomToken(length: 32)
        let nonce = Self.randomToken(length: 32)
        expectedState = state
        expectedNonce = nonce

        var components = URLComponents(url: config.authorizationURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "scope", value: config.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        guard let authURL = components?.url else {
            lastError = "Muse sign-in failed. Please try again."
            return
        }

        // The callback URL and any authorization code in it are handled
        // inside this closure only: they are never logged or stored.
        let callbackURL: URL?
        do {
            callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: "fileradar") { url, error in
                    if let url {
                        continuation.resume(returning: url)
                    } else if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(throwing: MuseAuthError.authenticationFailed)
                    }
                }
                session.presentationContextProvider = self
                self.authSession = session
                if !session.start() {
                    continuation.resume(throwing: MuseAuthError.authenticationFailed)
                }
            }
        } catch {
            lastError = Self.genericMessage(for: error)
            return
        }
        guard let callbackURL,
              let callbackComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let returnedState = callbackComponents.queryItems?.first(where: { $0.name == "state" })?.value,
              returnedState == expectedState,
              let code = callbackComponents.queryItems?.first(where: { $0.name == "code" })?.value,
              !code.isEmpty else {
            // Covers: provider error responses, missing code, and state
            // mismatch (possible CSRF) — all reported generically.
            lastError = "Muse sign-in failed. Please try again."
            return
        }
        // Exchange the code. The verifier is used once, here, then dropped.
        do {
            try await exchangeCode(code, verifier: verifier, config: config, expectedNonce: nonce)
            isConnected = true
        } catch {
            // Never leave half-stored tokens behind after a failed exchange.
            MuseTokenStore.deleteAll()
            isConnected = false
            lastError = "Muse sign-in failed. Please try again."
        }
    }

    // MARK: - Token access for the chat sibling

    /// Returns a usable access token: the stored one while it has more
    /// than 60 seconds of life left, otherwise a refreshed one. On refresh
    /// failure, tokens are wiped, `isConnected` becomes false, and a
    /// generic error is thrown. Throws `.notConnected` when no tokens
    /// are stored at all. The returned token must be used only in an
    /// `Authorization` header for the configured HTTPS endpoint and must
    /// never be logged or persisted elsewhere.
    func validAccessToken() async throws -> String {
        if let stored = MuseTokenStore.readAccessToken(),
           stored.expiresAt.timeIntervalSinceNow > 60 {
            return stored.token
        }
        guard let refreshToken = MuseTokenStore.readRefreshToken() else {
            isConnected = false
            throw MuseAuthError.notConnected
        }
        let config: MuseConfig
        do {
            config = try MuseConfig.load()
        } catch {
            throw MuseAuthError.notConfigured
        }
        do {
            let fresh = try await refresh(refreshToken: refreshToken, config: config)
            isConnected = true
            return fresh
        } catch {
            // Refresh failure is terminal for this session: wipe, so a
            // stale token can never be retried or reported as connected.
            MuseTokenStore.deleteAll()
            isConnected = false
            throw MuseAuthError.authenticationFailed
        }
    }

    // MARK: - Sign-out

    /// Wipes ALL Muse tokens from the Keychain and disconnects. Chat
    /// history is untouched: its deletion is the chat UI sibling's
    /// separate, explicit button, not a side effect of signing out.
    func logout() async {
        MuseTokenStore.deleteAll()
        isConnected = false
        lastError = nil
    }

    // MARK: - Token endpoint calls (private)

    /// Exchanges an authorization code for tokens and stores them.
    /// Throws on any HTTP, JSON, or Keychain failure; the caller wipes
    /// tokens on failure, so this method never needs to clean up.
    private func exchangeCode(_ code: String, verifier: String, config: MuseConfig, expectedNonce: String) async throws {
        let body: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": config.redirectURI,
            "client_id": config.clientID,
            "code_verifier": verifier,
        ]
        let response = try await postForm(to: config.tokenURL, body: body)
        try storeTokenResponse(response, expectedNonce: expectedNonce)
    }

    /// Refreshes with the stored refresh token. Rotation honored: when the
    /// provider returns a new refresh token, it replaces the stored one.
    /// Returns the new access token. Throws on any failure.
    private func refresh(refreshToken: String, config: MuseConfig) async throws -> String {
        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": config.clientID,
        ]
        let response = try await postForm(to: config.tokenURL, body: body)
        try storeTokenResponse(response, expectedNonce: nil)
        guard let stored = MuseTokenStore.readAccessToken() else {
            throw MuseAuthError.authenticationFailed
        }
        return stored.token
    }

    /// Validates a token response, checks the nonce claim of an `id_token`
    /// when one is present (see the header comment for why the check is
    /// conditional), and stores the tokens. Throws on any failure; on a
    /// nonce mismatch, anything just stored is deleted before throwing.
    private func storeTokenResponse(_ json: [String: Any], expectedNonce: String?) throws {
        guard let accessToken = json["access_token"] as? String, !accessToken.isEmpty else {
            throw MuseAuthError.authenticationFailed
        }
        // `expires_in` may arrive as a number or a numeric string.
        let expiresIn: TimeInterval
        if let seconds = json["expires_in"] as? TimeInterval {
            expiresIn = seconds
        } else if let seconds = json["expires_in"] as? Int {
            expiresIn = TimeInterval(seconds)
        } else if let text = json["expires_in"] as? String, let seconds = TimeInterval(text) {
            expiresIn = seconds
        } else {
            throw MuseAuthError.authenticationFailed
        }
        // Conditional nonce check: only when the provider returned an
        // id_token. The payload is decoded, never trusted for identity,
        // and a mismatch fails the login outright.
        if let expectedNonce,
           let idToken = json["id_token"] as? String,
           let claimNonce = Self.nonceClaim(fromIDToken: idToken),
           claimNonce != expectedNonce {
            MuseTokenStore.deleteAll()
            throw MuseAuthError.authenticationFailed
        }
        let stored = StoredAccessToken(token: accessToken,
                                       expiresAt: Date().addingTimeInterval(expiresIn))
        guard MuseTokenStore.writeAccessToken(stored) else {
            throw MuseAuthError.authenticationFailed
        }
        // Rotation: replace the stored refresh token only when the provider
        // returned a new one; otherwise keep the existing one.
        if let newRefresh = json["refresh_token"] as? String, !newRefresh.isEmpty {
            guard MuseTokenStore.writeRefreshToken(newRefresh) else {
                MuseTokenStore.deleteAll()
                throw MuseAuthError.authenticationFailed
            }
        }
    }

    /// POSTs a form-encoded body over HTTPS and returns the JSON object.
    /// Throws on any transport error, non-2xx status, or non-JSON body.
    /// Response bodies are parsed only for the token fields above and are
    /// never logged, surfaced, or stored.
    private func postForm(to url: URL, body: [String: String]) async throws -> [String: Any] {
        guard url.scheme?.lowercased() == "https" else {
            throw MuseAuthError.notConfigured
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body
            .map { key, value in
                let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                return "\(key)=\(encoded)"
            }
            .joined(separator: "&")
            .data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MuseAuthError.authenticationFailed
        }
        return json
    }

    // MARK: - PKCE / randomness helpers (private, testable in isolation)

    /// 43–128 characters from the RFC 7636 unreserved set, via the system
    /// CSPRNG. Length 64 sits comfortably inside the allowed range.
    private static func makeCodeVerifier() -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var bytes = [UInt8](repeating: 0, count: 64)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            // CSPRNG failure must not degrade to a predictable verifier:
            // fall back to UUID-derived entropy rather than a fixed value.
            return (0..<2).map { _ in UUID().uuidString.replacingOccurrences(of: "-", with: "") }.joined()
        }
        return bytes.map { String(alphabet[Int($0) % alphabet.count]) }.joined()
    }

    /// base64url(SHA256(verifier)), without padding, per RFC 7636 S256.
    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Hex string of `length` random bytes (2 * length characters), via
    /// the system CSPRNG, for `state` and `nonce`.
    private static func randomToken(length: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Extracts the `nonce` claim from an `id_token` payload WITHOUT
    /// trusting the token for identity (no signature verification is
    /// performed here — the claim is used only as a match check against
    /// the nonce this app sent, and tokens are accepted on the strength
    /// of the PKCE code exchange, not the id_token). Returns nil when the
    /// token is malformed or carries no nonce claim, in which case the
    /// caller skips the conditional check.
    private static func nonceClaim(fromIDToken idToken: String) -> String? {
        let parts = idToken.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload.append("=") }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let nonce = json["nonce"] as? String else { return nil }
        return nonce
    }

    /// Maps any failure to a generic, user-safe message. Server bodies,
    /// URLs, codes, and tokens are never included — including for
    /// cancellations, which are reported as a plain cancellation.
    private static func genericMessage(for error: Error) -> String {
        if let authError = error as? ASWebAuthenticationSessionError,
           authError.code == .canceledLogin {
            return "Muse sign-in was cancelled."
        }
        return "Muse sign-in failed. Please try again."
    }
}

// MARK: - ASWebAuthenticationSession presentation (macOS)

extension MuseAuthService: ASWebAuthenticationPresentationContextProviding {
    @objc func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Prefer the key window, fall back to main, then any window, so
        // the browser sheet always has an anchor even from the menu bar.
        if let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first {
            return window
        }
        return ASPresentationAnchor()
    }
}
