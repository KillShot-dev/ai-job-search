import SwiftUI
import AppKit

/// Optional palette variants. **Modern** is the Apple-native default
/// (electric blue, frosted glass, continuous corners). Layout never changes
/// between looks — only accent, radii, materials, and title design.
///
/// Primary chrome is Appearance (System / Light / Dark), not these looks.
/// Looks stay reachable from Settings / Look & Style as secondary polish.
///
/// Visual direction (intentionally NOT purple-on-white, cream+terracotta,
/// or newspaper density):
/// - Modern — system-like electric blue, ultraThinMaterial glass
/// - Elegant — deep teal + serif titles, larger radii
/// - Colourful — warm copper accent on soft stone materials
/// - Minimal — near-monochrome with hairline separators
enum AppLook: String, CaseIterable, Identifiable {
    case modern = "Modern"
    case elegant = "Elegant"
    case colourful = "Colourful"
    case minimal = "Minimal"

    var id: String { rawValue }

    var accent: Color {
        switch self {
        // Electric blue — close to macOS system accent, not purple.
        case .modern: return FileRadarChrome.accent
        case .elegant: return Color(red: 0.12, green: 0.45, blue: 0.42) // deep teal
        case .colourful: return Color(red: 0.91, green: 0.42, blue: 0.24) // copper
        case .minimal: return .primary
        }
    }

    var cardCorner: CGFloat {
        switch self {
        case .modern: return FileRadarChrome.radiusCard
        case .elegant: return 16
        case .colourful: return FileRadarChrome.radiusCard
        case .minimal: return FileRadarChrome.radiusHairline
        }
    }

    var chromeMaterial: Material {
        switch self {
        case .modern: return .ultraThinMaterial
        case .elegant: return .regularMaterial
        case .colourful: return .ultraThinMaterial
        case .minimal: return .bar
        }
    }

    var titleDesign: Font.Design {
        switch self {
        case .modern: return .default // SF Pro — calm native
        case .colourful: return .rounded
        case .elegant: return .serif
        case .minimal: return .default
        }
    }

    var atmosphereOpacity: Double {
        switch self {
        case .modern: return 0.04
        case .elegant: return 0.07
        case .colourful: return 0.06
        case .minimal: return 0.03
        }
    }

    var systemImage: String {
        switch self {
        case .modern: return "macwindow"
        case .elegant: return "seal.fill"
        case .colourful: return "paintpalette.fill"
        case .minimal: return "circle.lefthalf.filled"
        }
    }
}

/// Window chrome layouts (docs/fileradar-chrome-views.md). Same raw IDs on Mac + Windows.
/// Persisted via `@AppStorage("chromeView")` / UserDefaults key `chromeView`.
enum ChromeView: String, CaseIterable, Identifiable {
    case radarGlass
    case previewTheater
    case commandRail
    case workspaceTabs

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .radarGlass: return "Radar Glass"
        case .previewTheater: return "Preview Theater"
        case .commandRail: return "Command Rail"
        case .workspaceTabs: return "Workspace Tabs"
        }
    }

    /// Mockup letter A–D for docs / screenshots.
    var optionLetter: String {
        switch self {
        case .radarGlass: return "A"
        case .previewTheater: return "B"
        case .commandRail: return "C"
        case .workspaceTabs: return "D"
        }
    }

    var systemImage: String {
        switch self {
        case .radarGlass: return "circle.dotted"
        case .previewTheater: return "rectangle.inset.filled.and.person.filled"
        case .commandRail: return "sidebar.leading"
        case .workspaceTabs: return "rectangle.topthird.inset.filled"
        }
    }

    /// Chrome-specific accent (overrides AppLook accent while this chrome is active).
    var accent: Color {
        switch self {
        case .radarGlass: return FileRadarChrome.accent
        case .previewTheater: return Color(red: 0.20, green: 0.48, blue: 0.92)
        case .commandRail: return Color(red: 0.12, green: 0.72, blue: 0.68) // teal
        case .workspaceTabs: return Color(red: 0.95, green: 0.62, blue: 0.18) // amber
        }
    }

    /// Preferred appearance hint for screenshot / first paint (nil = respect user).
    var preferredAppearance: AppearanceMode? {
        switch self {
        case .previewTheater: return .light
        case .radarGlass, .commandRail, .workspaceTabs: return .dark
        }
    }

    static let storageKey = "chromeView"
    static let `default`: ChromeView = .radarGlass
}

/// System / Light / Dark — primary appearance chrome (toolbar, Settings,
/// View / Appearance menus). Looks are secondary.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var systemImage: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon.fill"
        }
    }
}

final class ThemeSettings: ObservableObject {
    @Published var look: AppLook {
        didSet {
            UserDefaults.standard.set(look.rawValue, forKey: "look")
            FileRadarFont.activeLook = look
        }
    }
    @Published var appearance: AppearanceMode {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "appearanceMode") }
    }
    /// Slightly denser chrome for power users (sidebar + list rows).
    @Published var compactDensity = false {
        didSet { UserDefaults.standard.set(compactDensity, forKey: "compactDensity") }
    }

    var colorScheme: ColorScheme? { appearance.colorScheme }

    /// Cycle Light → Dark → System for the toolbar toggle.
    func cycleAppearance() {
        switch appearance {
        case .light: appearance = .dark
        case .dark: appearance = .system
        case .system: appearance = .light
        }
    }

    /// Toggle Light ↔ Dark (⇧⌘L). System resolves to Dark first.
    func toggleLightDark() {
        switch appearance {
        case .light: appearance = .dark
        case .dark: appearance = .light
        case .system: appearance = .dark
        }
    }

    /// Cycle through the four looks (View → Cycle Look).
    func cycleLook() {
        let all = AppLook.allCases
        guard let idx = all.firstIndex(of: look) else {
            look = .modern
            return
        }
        look = all[(idx + 1) % all.count]
    }

    init() {
        let storedLook = UserDefaults.standard.string(forKey: "look") ?? ""
        let resolvedLook = AppLook(rawValue: storedLook) ?? .modern
        self.look = resolvedLook
        FileRadarFont.activeLook = resolvedLook

        if let raw = UserDefaults.standard.string(forKey: "appearanceMode"),
           let mode = AppearanceMode(rawValue: raw) {
            self.appearance = mode
        } else {
            // Migrate legacy toggles.
            let useSystem = UserDefaults.standard.object(forKey: "useSystemAppearance") as? Bool ?? true
            let forceDark = UserDefaults.standard.bool(forKey: "forceDark")
            if useSystem {
                self.appearance = .system
            } else {
                self.appearance = forceDark ? .dark : .light
            }
        }
        self.compactDensity = UserDefaults.standard.bool(forKey: "compactDensity")
    }
}

/// One type scale used by every view. Design (rounded / serif / default)
/// follows the active look so titles stay coherent with the palette.
enum FileRadarFont {
    /// Updated whenever `ThemeSettings.look` changes.
    static var activeLook: AppLook = .modern

    static func title(_ look: AppLook = activeLook) -> Font {
        .system(size: 26, weight: .bold, design: look.titleDesign)
    }
    static func heading(_ look: AppLook = activeLook) -> Font {
        .system(size: 15, weight: .semibold, design: look == .elegant ? .serif : .default)
    }
    static func body(_ look: AppLook = activeLook) -> Font {
        .system(size: 13, weight: .regular, design: .default)
    }
    static func caption(_ look: AppLook = activeLook) -> Font {
        .system(size: 11, weight: .regular, design: .default)
    }
}

/// Shared motion curves — short, explanatory, never decorative bounce.
enum FileRadarMotion {
    static let chip = Animation.easeOut(duration: 0.22)
    static let selection = Animation.easeInOut(duration: 0.16)
    static let panel = Animation.spring(response: 0.32, dampingFraction: 0.86)
}

// MARK: - Unified look tokens (docs/fileradar-unified-look.md)
//
// Cross-platform contract: Windows matches these names + values.
// Layout never forks per optional AppLook — only accent/material/title design.

enum FileRadarChrome {
    /// Electric system blue — mockup + Bloom/ForkLift restraint (not purple).
    static let accent = Color(red: 0.0, green: 0.478, blue: 1.0)

    static let radiusCard: CGFloat = 12
    static let radiusControl: CGFloat = 8
    static let radiusHairline: CGFloat = 6

    static let spacePage: CGFloat = 20
    static let spaceSection: CGFloat = 28
    static let spaceCardGap: CGFloat = 16
    static let spaceChromeY: CGFloat = 8
    static let spaceHUDPadX: CGFloat = 18
    static let spaceHUDPadY: CGFloat = 12

    static let hudMaxWidth: CGFloat = 440
    static let selectionStroke: CGFloat = 2.5
    static let activePaneStroke: CGFloat = 1.5

    static func selectionWash(_ accent: Color = FileRadarChrome.accent) -> Color {
        accent.opacity(0.08)
    }
    static func sidebarSelectionWash(_ accent: Color = FileRadarChrome.accent) -> Color {
        accent.opacity(0.14)
    }
    static func dropTargetWash(_ accent: Color = FileRadarChrome.accent) -> Color {
        accent.opacity(0.15)
    }
    static func activePaneWash(_ accent: Color = FileRadarChrome.accent) -> Color {
        accent.opacity(0.03)
    }
    static func activePaneStrokeColor(_ accent: Color = FileRadarChrome.accent) -> Color {
        accent.opacity(0.55)
    }
    static let cardFill = Color.primary.opacity(0.04)
    static let chromeBarFill = Color.primary.opacity(0.03)
    static let hairline = Color.primary.opacity(0.10)
    static let hudShadow = Color.black.opacity(0.18)
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
                        look.accent.opacity(look.atmosphereOpacity),
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

/// Aspect ratio for card framing by file kind (images taller, docs square, etc.).
extension FileKind {
    var cardAspect: CGFloat {
        switch self {
        case .image: return 0.75       // 4:3 landscape-ish height/width
        case .video: return 0.5625     // 16:9
        case .audio: return 1.0        // square
        case .document: return 1.25    // portrait page
        case .archive, .app: return 1.0
        case .folder: return 0.85
        case .other: return 0.85
        }
    }
}
