import SwiftUI
import AppKit

// MARK: - FileRadar icon system (docs/fileradar-icon-system.md)
//
// Not bare SF Symbol outlines. Every glyph is a multi-layer composition:
// colored tile or depth stack, primary + secondary symbols, highlight sheen,
// and chrome-aware accent. Asset-catalog PDFs (FRKind*) supply vector
// fallbacks; SwiftUI stacks are the live standard.

enum FRIconSize {
    case sidebar   // 18
    case list      // 22
    case toolbar   // 16
    case hero      // 36
    case micro     // 12

    var point: CGFloat {
        switch self {
        case .sidebar: return 18
        case .list: return 22
        case .toolbar: return 16
        case .hero: return 36
        case .micro: return 12
        }
    }

    var tile: CGFloat {
        switch self {
        case .sidebar: return 26
        case .list: return 30
        case .toolbar: return 22
        case .hero: return 48
        case .micro: return 16
        }
    }
}

/// Shared palette for kind / place tiles (light + dark adaptive).
enum FRIconPalette {
    static func kindColors(_ kind: FileKind) -> (top: Color, bottom: Color, glyph: Color) {
        switch kind {
        case .folder:
            return (Color(red: 0.35, green: 0.72, blue: 1.0),
                    Color(red: 0.10, green: 0.42, blue: 0.92),
                    .white)
        case .image:
            return (Color(red: 1.0, green: 0.62, blue: 0.78),
                    Color(red: 0.86, green: 0.22, blue: 0.48),
                    .white)
        case .video:
            return (Color(red: 0.72, green: 0.55, blue: 1.0),
                    Color(red: 0.42, green: 0.18, blue: 0.86),
                    .white)
        case .audio:
            return (Color(red: 1.0, green: 0.55, blue: 0.45),
                    Color(red: 0.92, green: 0.28, blue: 0.22),
                    .white)
        case .document:
            return (Color(red: 0.55, green: 0.78, blue: 1.0),
                    Color(red: 0.18, green: 0.45, blue: 0.92),
                    .white)
        case .archive:
            return (Color(red: 0.95, green: 0.78, blue: 0.40),
                    Color(red: 0.82, green: 0.48, blue: 0.08),
                    .white)
        case .app:
            return (Color(red: 0.55, green: 0.92, blue: 0.72),
                    Color(red: 0.12, green: 0.62, blue: 0.42),
                    .white)
        case .other:
            return (Color(red: 0.72, green: 0.75, blue: 0.80),
                    Color(red: 0.42, green: 0.46, blue: 0.52),
                    .white)
        }
    }

    static func placeColors(_ place: FRPlaceKind) -> (top: Color, bottom: Color, glyph: Color) {
        switch place {
        case .desktop:
            return (Color(red: 0.45, green: 0.78, blue: 1.0),
                    Color(red: 0.12, green: 0.38, blue: 0.88), .white)
        case .downloads:
            return (Color(red: 0.45, green: 0.92, blue: 0.72),
                    Color(red: 0.08, green: 0.58, blue: 0.42), .white)
        case .documents:
            return (Color(red: 0.98, green: 0.78, blue: 0.42),
                    Color(red: 0.88, green: 0.48, blue: 0.10), .white)
        case .pictures:
            return (Color(red: 1.0, green: 0.62, blue: 0.82),
                    Color(red: 0.82, green: 0.22, blue: 0.52), .white)
        case .music:
            return (Color(red: 1.0, green: 0.58, blue: 0.52),
                    Color(red: 0.90, green: 0.22, blue: 0.28), .white)
        case .movies:
            return (Color(red: 0.72, green: 0.58, blue: 1.0),
                    Color(red: 0.40, green: 0.20, blue: 0.82), .white)
        case .home:
            return (Color(red: 0.55, green: 0.85, blue: 1.0),
                    Color(red: 0.15, green: 0.48, blue: 0.92), .white)
        case .favorite:
            return (Color(red: 1.0, green: 0.85, blue: 0.35),
                    Color(red: 0.95, green: 0.55, blue: 0.08), .white)
        case .pin:
            return (Color(red: 0.70, green: 0.78, blue: 0.95),
                    Color(red: 0.35, green: 0.42, blue: 0.72), .white)
        }
    }
}

enum FRPlaceKind: String {
    case desktop, downloads, documents, pictures, music, movies, home, favorite, pin

    static func from(url: URL) -> FRPlaceKind {
        switch url.lastPathComponent {
        case "Desktop": return .desktop
        case "Downloads": return .downloads
        case "Documents": return .documents
        case "Pictures": return .pictures
        case "Music": return .music
        case "Movies", "Videos": return .movies
        default: return .home
        }
    }

    var primarySymbol: String {
        switch self {
        case .desktop: return "desktopcomputer"
        case .downloads: return "arrow.down.circle.fill"
        case .documents: return "doc.fill"
        case .pictures: return "photo.fill"
        case .music: return "music.note"
        case .movies: return "film.fill"
        case .home: return "house.fill"
        case .favorite: return "star.fill"
        case .pin: return "pin.fill"
        }
    }

    var secondarySymbol: String? {
        switch self {
        case .desktop: return "sparkle"
        case .downloads: return "tray.fill"
        case .documents: return "text.alignleft"
        case .pictures: return "camera.fill"
        case .music: return "waveform"
        case .movies: return "play.fill"
        case .home: return nil
        case .favorite: return nil
        case .pin: return nil
        }
    }
}

/// Soft rounded tile with vertical gradient + top sheen.
struct FRIconTile: View {
    var size: CGFloat
    var top: Color
    var bottom: Color
    var corner: CGFloat = 7

    var body: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(
                LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.38), Color.white.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                    .allowsHitTesting(false)
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8)
            )
            .shadow(color: bottom.opacity(0.35), radius: size * 0.12, y: size * 0.06)
            .frame(width: size, height: size)
    }
}

/// Rich file-kind glyph — gradient tile + layered symbols (not a thin outline).
struct FRKindIcon: View {
    var kind: FileKind
    var size: FRIconSize = .list
    /// Optional asset-catalog image name (FRKindFolder, …).
    private var assetName: String {
        switch kind {
        case .folder: return "FRKindFolder"
        case .image: return "FRKindImage"
        case .video: return "FRKindVideo"
        case .audio: return "FRKindAudio"
        case .document: return "FRKindDocument"
        case .archive: return "FRKindArchive"
        case .app: return "FRKindApp"
        case .other: return "FRKindOther"
        }
    }

    var body: some View {
        let colors = FRIconPalette.kindColors(kind)
        let tile = size.tile
        // Live UI prefers multi-layer SF stacks; catalog PDFs (FRKind*) are
        // vector fallbacks / export sources documented in the icon system doc.
        ZStack {
            FRIconTile(size: tile, top: colors.top, bottom: colors.bottom,
                       corner: tile * 0.28)
            kindLayers(glyph: colors.glyph, tile: tile)
        }
        .frame(width: tile, height: tile)
        .accessibilityHidden(true)
        // assetName retained for catalog PDF pairing (FRKind*).
        .help(assetName)
    }

    @ViewBuilder
    private func kindLayers(glyph: Color, tile: CGFloat) -> some View {
        let primary = size.point * 0.72
        switch kind {
        case .folder:
            Image(systemName: "folder.fill")
                .font(.system(size: primary, weight: .semibold))
                .foregroundStyle(glyph.opacity(0.95))
                .shadow(color: .black.opacity(0.18), radius: 1, y: 1)
            Image(systemName: "sparkle")
                .font(.system(size: primary * 0.32, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.9))
                .offset(x: tile * 0.18, y: -tile * 0.16)
        case .image:
            Image(systemName: "photo.fill")
                .font(.system(size: primary, weight: .semibold))
                .foregroundStyle(glyph)
            Image(systemName: "mountain.2.fill")
                .font(.system(size: primary * 0.38, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.85))
                .offset(y: tile * 0.08)
        case .video:
            Image(systemName: "film.fill")
                .font(.system(size: primary * 0.9, weight: .semibold))
                .foregroundStyle(glyph)
            Image(systemName: "play.circle.fill")
                .font(.system(size: primary * 0.55, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.95))
                .shadow(color: .black.opacity(0.25), radius: 1)
        case .audio:
            Image(systemName: "music.note.list")
                .font(.system(size: primary * 0.85, weight: .bold))
                .foregroundStyle(glyph)
            Image(systemName: "waveform")
                .font(.system(size: primary * 0.35, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.75))
                .offset(y: tile * 0.22)
        case .document:
            Image(systemName: "doc.richtext.fill")
                .font(.system(size: primary, weight: .semibold))
                .foregroundStyle(glyph)
            Image(systemName: "text.alignleft")
                .font(.system(size: primary * 0.32, weight: .bold))
                .foregroundStyle(colors.bottom.opacity(0.85))
                .offset(y: tile * 0.06)
        case .archive:
            Image(systemName: "archivebox.fill")
                .font(.system(size: primary, weight: .semibold))
                .foregroundStyle(glyph)
            Image(systemName: "zipper.page")
                .font(.system(size: primary * 0.4, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.8))
                .offset(y: -tile * 0.02)
        case .app:
            Image(systemName: "app.fill")
                .font(.system(size: primary, weight: .semibold))
                .foregroundStyle(glyph)
            Image(systemName: "sparkles")
                .font(.system(size: primary * 0.4, weight: .bold))
                .foregroundStyle(Color.yellow.opacity(0.95))
                .offset(x: tile * 0.16, y: -tile * 0.14)
        case .other:
            Image(systemName: "doc.fill")
                .font(.system(size: primary, weight: .semibold))
                .foregroundStyle(glyph)
            Image(systemName: "ellipsis")
                .font(.system(size: primary * 0.35, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.8))
                .offset(y: tile * 0.08)
        }
    }

    private var colors: (top: Color, bottom: Color, glyph: Color) {
        FRIconPalette.kindColors(kind)
    }
}

struct FRPlaceIcon: View {
    var place: FRPlaceKind
    var size: FRIconSize = .sidebar

    var body: some View {
        let colors = FRIconPalette.placeColors(place)
        let tile = size.tile
        ZStack {
            FRIconTile(size: tile, top: colors.top, bottom: colors.bottom, corner: tile * 0.28)
            Image(systemName: place.primarySymbol)
                .font(.system(size: size.point * 0.7, weight: .semibold))
                .foregroundStyle(colors.glyph)
                .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
            if let secondary = place.secondarySymbol {
                Image(systemName: secondary)
                    .font(.system(size: size.point * 0.28, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .offset(x: tile * 0.2, y: -tile * 0.18)
            }
        }
        .frame(width: tile, height: tile)
        .accessibilityHidden(true)
    }
}

/// Sidebar / tools destinations with depth.
enum FRNavGlyph: String {
    case browser, search, cleanup, duplicates, sync, workspaces
    case shelves, timeline, diskMap, muse, extras, bookmark
    case transfer, settings, home

    var primary: String {
        switch self {
        case .browser: return "rectangle.split.2x1.fill"
        case .search: return "magnifyingglass"
        case .cleanup: return "trash.fill"
        case .duplicates: return "doc.on.doc.fill"
        case .sync: return "arrow.triangle.2.circlepath"
        case .workspaces: return "square.grid.2x2.fill"
        case .shelves: return "square.stack.3d.up.fill"
        case .timeline: return "calendar"
        case .diskMap: return "circle.grid.3x3.fill"
        case .muse: return "sparkles"
        case .extras: return "wand.and.stars"
        case .bookmark: return "bookmark.fill"
        case .transfer: return "arrow.left.arrow.right.circle.fill"
        case .settings: return "gearshape.2.fill"
        case .home: return "house.fill"
        }
    }

    var secondary: String? {
        switch self {
        case .search: return "sparkle"
        case .muse: return "brain.head.profile"
        case .cleanup: return "leaf.fill"
        case .sync: return nil
        case .transfer: return nil
        default: return nil
        }
    }

    var top: Color {
        switch self {
        case .browser: return Color(red: 0.45, green: 0.72, blue: 1.0)
        case .search: return Color(red: 0.55, green: 0.85, blue: 1.0)
        case .cleanup: return Color(red: 1.0, green: 0.55, blue: 0.45)
        case .duplicates: return Color(red: 0.70, green: 0.65, blue: 1.0)
        case .sync: return Color(red: 0.35, green: 0.88, blue: 0.82)
        case .workspaces: return Color(red: 1.0, green: 0.78, blue: 0.40)
        case .shelves: return Color(red: 0.55, green: 0.78, blue: 1.0)
        case .timeline: return Color(red: 0.95, green: 0.65, blue: 0.85)
        case .diskMap: return Color(red: 0.45, green: 0.92, blue: 0.70)
        case .muse: return Color(red: 0.85, green: 0.70, blue: 1.0)
        case .extras: return Color(red: 1.0, green: 0.72, blue: 0.45)
        case .bookmark: return Color(red: 1.0, green: 0.75, blue: 0.35)
        case .transfer: return Color(red: 0.40, green: 0.82, blue: 1.0)
        case .settings: return Color(red: 0.70, green: 0.75, blue: 0.82)
        case .home: return Color(red: 0.50, green: 0.80, blue: 1.0)
        }
    }

    var bottom: Color {
        switch self {
        case .browser: return Color(red: 0.12, green: 0.42, blue: 0.92)
        case .search: return Color(red: 0.15, green: 0.48, blue: 0.88)
        case .cleanup: return Color(red: 0.85, green: 0.22, blue: 0.18)
        case .duplicates: return Color(red: 0.40, green: 0.28, blue: 0.82)
        case .sync: return Color(red: 0.08, green: 0.58, blue: 0.55)
        case .workspaces: return Color(red: 0.88, green: 0.48, blue: 0.08)
        case .shelves: return Color(red: 0.18, green: 0.42, blue: 0.86)
        case .timeline: return Color(red: 0.72, green: 0.22, blue: 0.55)
        case .diskMap: return Color(red: 0.08, green: 0.55, blue: 0.38)
        case .muse: return Color(red: 0.48, green: 0.22, blue: 0.82)
        case .extras: return Color(red: 0.88, green: 0.38, blue: 0.12)
        case .bookmark: return Color(red: 0.90, green: 0.48, blue: 0.05)
        case .transfer: return Color(red: 0.10, green: 0.45, blue: 0.88)
        case .settings: return Color(red: 0.38, green: 0.42, blue: 0.50)
        case .home: return Color(red: 0.12, green: 0.42, blue: 0.88)
        }
    }
}

struct FRNavIcon: View {
    var glyph: FRNavGlyph
    var size: FRIconSize = .sidebar
    var selected: Bool = false
    var accent: Color = FileRadarChrome.accent

    var body: some View {
        let tile = size.tile
        ZStack {
            FRIconTile(
                size: tile,
                top: selected ? accent.opacity(0.95) : glyph.top,
                bottom: selected ? accent.opacity(0.75) : glyph.bottom,
                corner: tile * 0.28
            )
            Image(systemName: glyph.primary)
                .font(.system(size: size.point * 0.68, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
            if let secondary = glyph.secondary {
                Image(systemName: secondary)
                    .font(.system(size: size.point * 0.28, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .offset(x: tile * 0.2, y: -tile * 0.18)
            }
        }
        .frame(width: tile, height: tile)
        .accessibilityHidden(true)
    }
}

/// Chrome-view picker glyphs (A–D).
struct FRChromeGlyph: View {
    var chrome: ChromeView
    var size: FRIconSize = .toolbar
    var accent: Color

    var body: some View {
        let tile = size.tile
        ZStack {
            FRIconTile(size: tile, top: accent.opacity(0.95), bottom: accent.opacity(0.65),
                       corner: tile * 0.3)
            Image(systemName: chrome.systemImage)
                .font(.system(size: size.point * 0.7, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
            Text(chrome.optionLetter)
                .font(.system(size: size.point * 0.32, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.95))
                .offset(x: tile * 0.22, y: tile * 0.2)
        }
        .frame(width: tile, height: tile)
        .accessibilityHidden(true)
    }
}

/// Drop Stack tray mark — layered tray + spark.
struct FRDropStackIcon: View {
    var size: FRIconSize = .sidebar
    var accent: Color = FileRadarChrome.accent

    var body: some View {
        let tile = size.tile
        ZStack {
            FRIconTile(size: tile,
                       top: Color(red: 0.55, green: 0.82, blue: 1.0),
                       bottom: accent.opacity(0.9),
                       corner: tile * 0.28)
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: size.point * 0.72, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.22), radius: 1, y: 1)
            Image(systemName: "plus.circle.fill")
                .font(.system(size: size.point * 0.32, weight: .bold))
                .foregroundStyle(Color.yellow)
                .offset(x: tile * 0.22, y: -tile * 0.2)
        }
        .frame(width: tile, height: tile)
        .accessibilityHidden(true)
    }
}

/// Transfer HUD / Activities mark.
struct FRTransferIcon: View {
    var active: Bool
    var size: FRIconSize = .toolbar
    var accent: Color = FileRadarChrome.accent

    var body: some View {
        let tile = size.tile
        ZStack {
            FRIconTile(
                size: tile,
                top: active ? accent : Color(red: 0.55, green: 0.78, blue: 1.0),
                bottom: active ? accent.opacity(0.75) : Color(red: 0.15, green: 0.42, blue: 0.88),
                corner: tile * 0.3
            )
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: size.point * 0.62, weight: .bold))
                .foregroundStyle(.white)
            if active {
                Circle()
                    .fill(Color.green)
                    .frame(width: tile * 0.22, height: tile * 0.22)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 1))
                    .offset(x: tile * 0.28, y: -tile * 0.28)
            }
        }
        .frame(width: tile, height: tile)
        .accessibilityHidden(true)
    }
}

/// Toolbar dual-pane / appearance / overflow marks with depth.
struct FRToolbarGlyph: View {
    enum Kind {
        case appearance(AppearanceMode)
        case look(AppLook)
        case dualPane(Bool)
        case chrome
        case viewMode(FileStore.ViewMode)
        case sort
        case inspector(Bool)
        case more
    }

    var kind: Kind
    var accent: Color = FileRadarChrome.accent
    var size: FRIconSize = .toolbar

    var body: some View {
        let tile = size.tile
        ZStack {
            FRIconTile(size: tile, top: colors.0, bottom: colors.1, corner: tile * 0.3)
            Image(systemName: symbol)
                .font(.system(size: size.point * 0.68, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.18), radius: 1, y: 1)
        }
        .frame(width: tile, height: tile)
        .accessibilityHidden(true)
    }

    private var symbol: String {
        switch kind {
        case .appearance(let mode): return mode.systemImage
        case .look(let look): return look.systemImage
        case .dualPane(let on): return on ? "rectangle.split.2x1.fill" : "rectangle.split.2x1"
        case .chrome: return "rectangle.on.rectangle.angled"
        case .viewMode(let mode):
            switch mode {
            case .list: return "list.bullet.rectangle.fill"
            case .columns: return "rectangle.split.3x1.fill"
            case .grid: return "square.grid.2x2.fill"
            case .showcase: return "rectangle.portrait.on.rectangle.portrait.fill"
            }
        case .sort: return "arrow.up.arrow.down.circle.fill"
        case .inspector(let on): return on ? "sidebar.trailing" : "sidebar.right"
        case .more: return "ellipsis.circle.fill"
        }
    }

    private var colors: (Color, Color) {
        switch kind {
        case .appearance:
            return (Color(red: 0.55, green: 0.65, blue: 0.95), Color(red: 0.25, green: 0.30, blue: 0.55))
        case .look(let look):
            return (look.accent.opacity(0.95), look.accent.opacity(0.55))
        case .dualPane:
            return (accent.opacity(0.95), accent.opacity(0.65))
        case .chrome:
            return (Color(red: 0.65, green: 0.78, blue: 1.0), accent)
        case .viewMode:
            return (Color(red: 0.50, green: 0.85, blue: 0.95), Color(red: 0.12, green: 0.48, blue: 0.72))
        case .sort:
            return (Color(red: 0.70, green: 0.75, blue: 0.90), Color(red: 0.35, green: 0.40, blue: 0.55))
        case .inspector:
            return (Color(red: 0.60, green: 0.72, blue: 0.95), Color(red: 0.22, green: 0.35, blue: 0.65))
        case .more:
            return (Color(red: 0.72, green: 0.76, blue: 0.85), Color(red: 0.40, green: 0.44, blue: 0.52))
        }
    }
}

/// Label row helper — rich icon + title for sidebars.
struct FRSidebarLabel: View {
    var title: String
    var icon: AnyView

    init(title: String, @ViewBuilder icon: () -> some View) {
        self.title = title
        self.icon = AnyView(icon())
    }

    var body: some View {
        HStack(spacing: 10) {
            icon
            Text(title)
                .font(FileRadarFont.body())
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

extension FileKind {
    /// Prefer rich FR glyph over bare systemImage string in UI.
    var frIcon: some View { FRKindIcon(kind: self, size: .list) }
}
