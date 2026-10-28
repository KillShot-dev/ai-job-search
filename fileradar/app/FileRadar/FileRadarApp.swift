import SwiftUI
import AppKit

/// FileRadar entry point.
@main
struct FileRadarApp: App {
    @StateObject private var store = FileStore()
    @StateObject private var license = LicenseManager()
    @StateObject private var theme = ThemeSettings()
    @StateObject private var playback = MusicPlaybackService()
    @StateObject private var museAuth = MuseAuthService()
    private let museClient = MuseClient(config: (try? MuseConfig.load()) ?? MuseConfig.placeholder)
    @StateObject private var museVoice = VoiceService()
    @StateObject private var storeKit = StoreKitLicense()
    @StateObject private var trial = TrialManager()
    @StateObject private var favorites = FavoritesStore()
    @StateObject private var savedSearches = SavedSearchStore()
    @StateObject private var manualTags = ManualTagStore()

    var body: some Scene {
        WindowGroup {
            ContentView(museClient: museClient)
                .environmentObject(store)
                .environmentObject(license)
                .environmentObject(theme)
                .environmentObject(playback)
                .environmentObject(museAuth)
                .environmentObject(museVoice)
                .environmentObject(storeKit)
                .environmentObject(trial)
                .environmentObject(favorites)
                .environmentObject(savedSearches)
                .environmentObject(manualTags)
                .preferredColorScheme(theme.colorScheme)
                .frame(minWidth: 960, minHeight: 640)
                .onAppear {
                    license.attach(storeKit: storeKit, trial: trial)
                    store.manualTagNames = { [manualTags] path in
                        manualTags.tags(for: path).map(\.name)
                    }
                    QuickSearchPanel.shared.configure(store: store, license: license)
                    // Never touch Keychain synchronously here — sample showed
                    // refreshEntitlements → TrialManager.refresh → SecItem
                    // blocking MainActor for the entire open event.
                    Task { await license.refreshEntitlementsAsync() }
                    // Dev-only: optional self-snapshot of the key window (no
                    // Screen Recording TCC). Set FILERADAR_SNAPSHOT_PATH.
                    if LocalDevBuild.isActive,
                       let path = ProcessInfo.processInfo.environment["FILERADAR_SNAPSHOT_PATH"],
                       !path.isEmpty {
                        // Prefer calm Modern + Dark for mockup-matching evidence shots.
                        theme.look = .modern
                        theme.appearance = .dark
                        store.viewMode = .showcase
                        Task { @MainActor in
                            // Wait for demo index + first selection so shelves/inspector fill.
                            for _ in 0..<80 {
                                if !store.files.isEmpty, !store.isIndexing { break }
                                try? await Task.sleep(nanoseconds: 250_000_000)
                            }
                            if store.selectedIDs.isEmpty,
                               let first = store.recents.first ?? store.files.first {
                                store.selectedIDs = [first.id]
                            }
                            try? await Task.sleep(nanoseconds: 1_200_000_000)
                            Self.writeWindowSnapshot(to: path)
                        }
                    }
                }
                .onChange(of: storeKit.isEntitled) { _, _ in
                    Task { await license.refreshEntitlementsAsync() }
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("View") {
                Button("Larger Cards") { store.cardSize = min(store.cardSize + 20, 240) }
                    .keyboardShortcut("+", modifiers: .command)
                Button("Smaller Cards") { store.cardSize = max(store.cardSize - 20, 80) }
                    .keyboardShortcut("-", modifiers: .command)
                Divider()
                Button("Grid View") { store.viewMode = .grid }.keyboardShortcut("1", modifiers: .command)
                Button("List View") { store.viewMode = .list }.keyboardShortcut("2", modifiers: .command)
                Button("Column View") { store.viewMode = .columns }.keyboardShortcut("3", modifiers: .command)
                Button("Showcase View") { store.viewMode = .showcase }.keyboardShortcut("4", modifiers: .command)
                Divider()
                ForEach(AppearanceMode.allCases) { mode in
                    Button(mode.rawValue) { theme.appearance = mode }
                }
                Divider()
                Button("Cycle Look") { theme.cycleLook() }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
            }
            CommandMenu("Appearance") {
                ForEach(AppearanceMode.allCases) { mode in
                    Button(mode.rawValue) { theme.appearance = mode }
                }
                Divider()
                ForEach(AppLook.allCases) { look in
                    Button(look.rawValue) { theme.look = look }
                }
            }
            CommandMenu("Go") {
                Button("Quick Search…") { QuickSearchPanel.shared.show() }
                    .keyboardShortcut(" ", modifiers: [.command, .shift])
            }
            CommandMenu("Actions") {
                Button("Command Palette…") {
                    NotificationCenter.default.post(name: .showCommandPalette, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)
                Button("Toggle Dual Pane") {
                    NotificationCenter.default.post(name: .toggleDualPane, object: nil)
                }
                Button("Toggle Preview Strip") {
                    NotificationCenter.default.post(name: .togglePreviewStrip, object: nil)
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Batch Rename Selection…") {
                    NotificationCenter.default.post(name: .showBatchRename, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Select All Visible") {
                    NotificationCenter.default.post(name: .selectAllVisible, object: nil)
                }
                .keyboardShortcut("a", modifiers: .command)
                Button("Move Selection to Trash") {
                    NotificationCenter.default.post(name: .trashSelection, object: nil)
                }
                .keyboardShortcut(.delete, modifiers: .command)
                Divider()
                Button("Export Parcel…") {
                    NotificationCenter.default.post(name: .exportParcel, object: nil)
                }
                Button("Unlock Full Version…") {
                    NotificationCenter.default.post(name: .showLicenseSheet, object: nil)
                }
            }
        }

        MenuBarExtra("FileRadar", systemImage: "magnifyingglass") {
            MenuBarExtraView()
                .environmentObject(store)
                .environmentObject(license)
                .environmentObject(theme)
                .environmentObject(storeKit)
                .environmentObject(trial)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(theme)
                .environmentObject(license)
                .environmentObject(museAuth)
                .environmentObject(storeKit)
                .environmentObject(trial)
        }
    }

    init() {
        HotkeyService.shared.start()
    }

    /// Captures the key window via AppKit view cache (works without Screen Recording).
    @MainActor
    private static func writeWindowSnapshot(to path: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 400 }),
              let view = window.contentView else { return }
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        view.cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        guard let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? png.write(to: url)
    }
}
