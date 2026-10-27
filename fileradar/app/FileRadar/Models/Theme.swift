import SwiftUI
import AppKit

/// Principle 7: two looks from one system. One type scale, one accent
/// system; the look only changes palette and surface treatment, in both
/// light and dark. Never two different layouts.
///
/// Visual direction (intentionally NOT purple-on-white, cream+terracotta,
/// or newspaper density): Colourful = warm amber/copper accent on soft
/// stone materials; Minimal = near-monochrome with hairline separators
/// and slightly tighter radii. Both stay native-macOS, not web-dashboard.
enum AppLook: String, CaseIterable {
    case colourful = "Colourful"
    case minimal = "Minimal"

    var accent: Color {
        switch self {
        case .colourful: return Color(red: 0.91, green: 0.42, blue: 0.24) // copper
        case .minimal: return .primary
        }
    }

    var cardCorner: CGFloat {
        switch self {
        case .colourful: return 12
        case .minimal: return 6
        }
    }

    var chromeMaterial: Material {
        switch self {
        case .colourful: return .ultraThinMaterial
        case .minimal: return .bar
        }
    }
}

final class ThemeSettings: ObservableObject {
    @Published var look: AppLook {
        didSet { UserDefaults.standard.set(look.rawValue, forKey: "look") }
    }
    @Published var useSystemAppearance = true {
        didSet { UserDefaults.standard.set(useSystemAppearance, forKey: "useSystemAppearance") }
    }
    @Published var forceDark = false {
        didSet { UserDefaults.standard.set(forceDark, forKey: "forceDark") }
    }
    /// Slightly denser chrome for power users (sidebar + list rows).
    @Published var compactDensity = false {
        didSet { UserDefaults.standard.set(compactDensity, forKey: "compactDensity") }
    }

    var colorScheme: ColorScheme? {
        if useSystemAppearance { return nil }
        return forceDark ? .dark : .light
    }

    init() {
        self.look = AppLook(rawValue: UserDefaults.standard.string(forKey: "look") ?? "") ?? .colourful
        self.useSystemAppearance = UserDefaults.standard.object(forKey: "useSystemAppearance") as? Bool ?? true
        self.forceDark = UserDefaults.standard.bool(forKey: "forceDark")
        self.compactDensity = UserDefaults.standard.bool(forKey: "compactDensity")
    }
}

/// One type scale used by every view (principle 7). Uses rounded design
/// for titles (warmth) and default for body (legibility) — still system
/// fonts, so Dynamic Type / accessibility sizes apply.
enum FileRadarFont {
    static func title() -> Font { .system(size: 26, weight: .bold, design: .rounded) }
    static func heading() -> Font { .system(size: 15, weight: .semibold, design: .default) }
    static func body() -> Font { .system(size: 13, weight: .regular, design: .default) }
    static func caption() -> Font { .system(size: 11, weight: .regular, design: .default) }
}

/// Shared motion curves — short, explanatory, never decorative bounce.
enum FileRadarMotion {
    static let chip = Animation.easeOut(duration: 0.22)
    static let selection = Animation.easeInOut(duration: 0.16)
    static let panel = Animation.spring(response: 0.32, dampingFraction: 0.86)
}

/// Quiet atmosphere for detail chrome — soft vertical wash, not flat fill
/// and not a purple/glow dashboard look. Uses semantic materials so light
/// and dark stay native.
struct FileRadarAtmosphere: ViewModifier {
    var look: AppLook

    func body(content: Content) -> some View {
        content.background {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                LinearGradient(
                    colors: [
                        look.accent.opacity(look == .colourful ? 0.06 : 0.03),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }
}

extension View {
    func fileRadarAtmosphere(_ look: AppLook) -> some View {
        modifier(FileRadarAtmosphere(look: look))
    }
}
