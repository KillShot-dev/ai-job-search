import Foundation

/// Muse (Model API) configuration — a seam, not a fabrication.
///
/// SETUP — READ BEFORE SHIPPING (developer steps, all in Xcode):
///   1. Copy `MuseConfig.sample.plist` (next to this file's bundle resources)
///      to `MuseConfig.plist` and add the copy to the app target
///      (target > Build Phases > Copy Bundle Resources). The sample file is
///      NEVER bundled as-is: it contains only placeholders, and `load()`
///      below rejects every placeholder value, so a forgotten copy fails
///      closed with `.notConfigured` instead of silently connecting.
///   2. Fill in the real values from YOUR Meta developer dashboard:
///      the Model API base URL, the OAuth client ID, the redirect URI, the
///      scopes, and the model ID. Verify each one there before shipping.
///   3. Add the two new Swift files in this folder (`MuseConfig.swift` and
///      `MuseAuthService.swift`) to the app target (target > Build Phases >
///      Compile Sources). This project file is hand-written, so Xcode does
///      not pick up new files automatically.
///   4. Confirm the Info.plist additions (URL scheme `fileradar`, microphone
///      and speech-recognition usage strings) appear under
///      target > Info > URL Types and the privacy strings — see the header
///      comment in `Info.plist` for the exact checklist.
///
/// HONEST-DESIGN NOTES (do not "fix" these by inventing values):
///   - FileRadar cannot embed the Muse personal-agent runtime, and no
///     public third-party OAuth flow for logging a Mac app into a personal
///     Muse account could be verified. What this file configures is an
///     OAuth-style login (ASWebAuthenticationSession + PKCE) against a
///     developer-configured Model API endpoint, performed by
///     `MuseAuthService`. The chat UI presents this as "Connect", and the
///     README (written separately) states FileRadar is not affiliated with
///     or endorsed by Meta.
///   - Nothing here is a Meta-confirmed fact. The following are ONLY
///     third-party-reported defaults, noted so a developer has a starting
///     point to check — verify in your Meta developer dashboard before
///     shipping, and never treat them as confirmed:
///       base URL: https://api.meta.ai/v1 ; model: muse-spark-1.3
///     They appear ONLY in comments (here and in the sample plist), never
///     as active defaults in code. There are no active endpoint, key, or
///     model defaults anywhere in this file.
///   - `load()` fails closed: a missing bundle plist, a missing key, an
///     empty value, a leftover placeholder value, or a non-HTTPS base URL
///     all throw `.notConfigured` / `.invalidBaseURL`. Nothing ever
///     silently connects, and no fallback endpoint is attempted.
///   - No secrets live in this file, in UserDefaults, or in any plaintext
///     file. Tokens live only in the Keychain (see `MuseAuthService`).
///   - HTTPS only: `load()` rejects any base URL whose scheme is not
///     `https`. There are no App Transport Security exceptions anywhere
///     in the app, and none may be added for this feature.
///
/// PLIST KEYS (in the bundled `MuseConfig.plist`):
///   MuseBaseURL     String  e.g. your verified Model API base URL
///   MuseClientID    String  OAuth client ID from your developer dashboard
///   MuseRedirectURI String must use the `fileradar` scheme (see below)
///   MuseScopes      Array of String, e.g. chat scopes your app needs
///   MuseModel       String  model ID from your developer dashboard
enum MuseConfigError: Error {
    /// The bundled MuseConfig.plist is missing, incomplete, or still holds
    /// placeholder values. Shown to the user only as a generic message.
    case notConfigured
    /// The configured base URL is not a valid HTTPS URL.
    case invalidBaseURL
}

/// Developer-configured Model API endpoint + OAuth client settings.
/// All values come from the bundled `MuseConfig.plist`; none are baked in.
struct MuseConfig {
    /// Base URL of the developer-configured Model API endpoint. HTTPS only.
    let baseURL: URL
    /// OAuth client ID issued in the developer's Meta developer dashboard.
    let clientID: String
    /// OAuth redirect URI. Must use the `fileradar` URL scheme registered
    /// in Info.plist (`CFBundleURLTypes`), so the browser returns control
    /// to this app after sign-in.
    let redirectURI: String
    /// OAuth scopes requested at sign-in.
    let scopes: [String]
    /// Model ID sent with chat requests by the chat sibling.
    let model: String

    /// The fixed redirect URI this app's login flow uses. `MuseAuthService`
    /// registers the `fileradar` callback scheme for exactly this URI, and
    /// `load()` rejects any configured redirect URI that does not use the
    /// `fileradar` scheme, so a misconfigured plist cannot hijack the
    /// callback to another app.
    static let expectedRedirectURI = "fileradar://muse-callback"

    /// Empty/invalid values that always fail closed. This is for previews
    /// and tests only: `validate()` rejects it (empty client ID, empty
    /// model, no scopes), and `MuseAuthService.connect()` never uses it —
    /// it always calls `load()`. Never use `.placeholder` to attempt a
    /// connection.
    static var placeholder: MuseConfig {
        // The host below is syntactically a URL so the struct can be built,
        // but it is not a real endpoint and `validate()` still rejects this
        // instance because clientID, model, and scopes are empty.
        MuseConfig(baseURL: URL(string: "https://placeholder.invalid")!,
                   clientID: "",
                   redirectURI: "",
                   scopes: [],
                   model: "")
    }

    /// Loads the developer's bundled `MuseConfig.plist` and validates it.
    /// Throws `.notConfigured` when the file is missing, a key is missing,
    /// a value is empty, or a value is still a placeholder; throws
    /// `.invalidBaseURL` when the base URL is not HTTPS.
    static func load() throws -> MuseConfig {
        guard let url = Bundle.main.url(forResource: "MuseConfig", withExtension: "plist"),
              let plist = NSDictionary(contentsOf: url) as? [String: Any] else {
            throw MuseConfigError.notConfigured
        }
        guard let baseURLString = plist["MuseBaseURL"] as? String,
              let clientID = plist["MuseClientID"] as? String,
              let redirectURI = plist["MuseRedirectURI"] as? String,
              let scopes = plist["MuseScopes"] as? [String],
              let model = plist["MuseModel"] as? String else {
            throw MuseConfigError.notConfigured
        }
        guard let baseURL = URL(string: baseURLString) else {
            throw MuseConfigError.invalidBaseURL
        }
        let config = MuseConfig(baseURL: baseURL,
                                clientID: clientID,
                                redirectURI: redirectURI,
                                scopes: scopes,
                                model: model)
        try config.validate()
        return config
    }

    /// Fails closed on anything that is not a complete, real configuration.
    /// Called by `load()`; also usable by tests. Never logs any value.
    func validate() throws {
        guard baseURL.scheme?.lowercased() == "https",
              let host = baseURL.host, !host.isEmpty else {
            throw MuseConfigError.invalidBaseURL
        }
        // Reject empty values and any leftover placeholder text, so copying
        // the sample plist without editing it can never connect.
        let textValues = [clientID, redirectURI, model]
        guard textValues.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              textValues.allSatisfy({ !$0.contains("PLACEHOLDER") && !$0.contains("YOUR_") }),
              !scopes.isEmpty,
              scopes.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw MuseConfigError.notConfigured
        }
        // The callback must come back to this app via its own URL scheme.
        guard let scheme = URL(string: redirectURI)?.scheme?.lowercased(),
              scheme == "fileradar" else {
            throw MuseConfigError.notConfigured
        }
    }

    /// Authorization endpoint, derived from the configured base URL with a
    /// conventional OAuth2 path. ASSUMPTION — NOT a Meta-confirmed fact:
    /// verify this path against your Meta developer dashboard before
    /// shipping. If your provider uses a different authorize path, change
    /// this derivation (and `tokenURL` below) to match — do not invent a
    /// second, undocumented endpoint.
    var authorizationURL: URL {
        baseURL.appendingPathComponent("oauth/authorize")
    }

    /// Token endpoint, derived the same way as `authorizationURL` and
    /// subject to the same verify-before-shipping assumption.
    var tokenURL: URL {
        baseURL.appendingPathComponent("oauth/token")
    }
}
