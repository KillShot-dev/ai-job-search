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
                    license.storeKit = storeKit
                    license.trial = trial
                    license.refreshEntitlements()
                    store.manualTagNames = { [manualTags] path in
                        manualTags.tags(for: path).map(\.name)
                    }
                    QuickSearchPanel.shared.configure(store: store, license: license)
                }
                .onChange(of: storeKit.isEntitled) { _, _ in
                    license.refreshEntitlements()
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
}
