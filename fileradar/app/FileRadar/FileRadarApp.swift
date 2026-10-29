import SwiftUI
import AppKit

/// Ensures a regular activation policy and a key main window so clicks
/// reach content views. MenuBarExtra / Settings scenes must not steal
/// first-responder focus at launch.
final class FileRadarAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.activateMainWindow()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Only now is makeKeyAndOrderFront reliable — while `isActive` is
        // false (common at launch beside MenuBarExtra / other agents),
        // makeKey silently fails and toolbar mouse + AX content stay dead.
        Self.keyContentWindow(attempt: 0)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Self.activateMainWindow()
        return true
    }

    @MainActor
    static func activateMainWindow() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        NSApplication.shared.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            Self.keyContentWindow(attempt: 0)
        }
    }

    @MainActor
    static func keyContentWindow(attempt: Int) {
        // Never steal key from an attached sheet / active modal.
        if let key = NSApp.keyWindow, key.attachedSheet != nil { return }
        if NSApp.modalWindow != nil { return }

        let main = NSApplication.shared.windows.first(where: { window in
            guard window.canBecomeKey,
                  window.frame.width >= 400,
                  window.frame.height >= 300 else { return false }
            if window is NSPanel { return false }
            if window.styleMask.contains(.nonactivatingPanel) { return false }
            if window.isSheet { return false }
            return true
        })

        // If we are not the active app yet, wait for applicationDidBecomeActive
        // rather than spinning makeKey while inactive (it cannot succeed).
        guard NSApp.isActive else { return }
        guard let main else {
            if attempt < 6 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    Self.keyContentWindow(attempt: attempt + 1)
                }
            }
            return
        }
        if main.isKeyWindow { return }

        main.ignoresMouseEvents = false
        main.orderFrontRegardless()
        main.makeKeyAndOrderFront(nil)
        if main.firstResponder == nil || main.firstResponder === main {
            main.makeFirstResponder(main.contentView)
        }

        if !main.isKeyWindow, attempt < 8 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                Self.keyContentWindow(attempt: attempt + 1)
            }
        }
    }
}

/// FileRadar entry point.
@main
struct FileRadarApp: App {
    @NSApplicationDelegateAdaptor(FileRadarAppDelegate.self) private var appDelegate
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
                    FileRadarAppDelegate.activateMainWindow()
                    license.attach(storeKit: storeKit, trial: trial)
                    store.manualTagNames = { [manualTags] path in
                        manualTags.tags(for: path).map(\.name)
                    }
                    QuickSearchPanel.shared.configure(store: store, license: license, theme: theme)
                    // Never touch Keychain synchronously here — sample showed
                    // refreshEntitlements → TrialManager.refresh → SecItem
                    // blocking MainActor for the entire open event.
                    Task { await license.refreshEntitlementsAsync() }
                    // Dev-only: optional self-snapshot of the key window (no
                    // Screen Recording TCC). Set FILERADAR_SNAPSHOT_PATH.
                    let snapPath = ProcessInfo.processInfo.environment["FILERADAR_SNAPSHOT_PATH"] ?? ""
                    if !snapPath.isEmpty, LocalDevBuild.isActive || ProcessInfo.processInfo.environment["FILERADAR_FORCE_UNLOCK"] == "1" {
                        // ForkLift-primary evidence: dual-pane list Browser, not Shelves Home.
                        theme.look = .modern
                        store.viewMode = .list
                        let chromeRaw = ProcessInfo.processInfo.environment["FILERADAR_CHROME_VIEW"]
                            ?? ChromeView.default.rawValue
                        if let chrome = ChromeView(rawValue: chromeRaw) {
                            UserDefaults.standard.set(chrome.rawValue, forKey: ChromeView.storageKey)
                            if let preferred = chrome.preferredAppearance {
                                theme.appearance = preferred
                            } else {
                                theme.appearance = .dark
                            }
                            NotificationCenter.default.post(name: .setChromeView, object: chrome.rawValue)
                        } else {
                            theme.appearance = .dark
                        }
                        Task { @MainActor in
                            NSApp.activate(ignoringOtherApps: true)
                            // Sandboxed Debug can read Downloads; pin demo folders there for shots.
                            let demo = FileManager.default.homeDirectoryForCurrentUser
                                .appendingPathComponent("Downloads/FileRadarDemo")
                            let demoInbox = demo.appendingPathComponent("Inbox")
                            let hasDemo = FileManager.default.fileExists(atPath: demo.path)
                            if hasDemo {
                                if let data = try? JSONEncoder().encode([
                                    TabState.TabItem(folder: demo),
                                    TabState.TabItem(folder: demoInbox)
                                ]) {
                                    UserDefaults.standard.set(data, forKey: "com.metaphasicgroup.fileradar.tabs.v2")
                                }
                                store.pinnedFolderURLs = [demo, demoInbox]
                                store.refreshIndex()
                            }
                            try? await Task.sleep(nanoseconds: 600_000_000)
                            if hasDemo {
                                NotificationCenter.default.post(name: .pinDemoFoldersForSnapshot,
                                                                object: [demo, demoInbox])
                            }
                            for _ in 0..<80 {
                                if !store.files.isEmpty, !store.isIndexing { break }
                                try? await Task.sleep(nanoseconds: 250_000_000)
                            }
                            if store.selectedIDs.isEmpty,
                               let first = store.files.first {
                                store.selectedIDs = [first.id]
                            }
                            // Seed a demo transfer so docked / strip / pill chrome is visible.
                            if ProcessInfo.processInfo.environment["FILERADAR_SNAPSHOT_TRANSFER"] == "1" {
                                let dest = FileManager.default.temporaryDirectory
                                TransferQueue.shared.enqueueCopy(
                                    [URL(fileURLWithPath: "/System/Library/CoreServices/SystemVersion.plist")],
                                    to: dest
                                )
                            }
                            try? await Task.sleep(nanoseconds: 1_800_000_000)
                            for _ in 0..<20 {
                                if Self.writeWindowSnapshot(to: snapPath) { break }
                                try? await Task.sleep(nanoseconds: 300_000_000)
                            }
                            try? await Task.sleep(nanoseconds: 300_000_000)
                            NSApp.terminate(nil)
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
                Menu("Chrome") {
                    ForEach(ChromeView.allCases) { chrome in
                        Button("\(chrome.optionLetter) · \(chrome.displayName)") {
                            UserDefaults.standard.set(chrome.rawValue, forKey: ChromeView.storageKey)
                            NotificationCenter.default.post(name: .setChromeView, object: chrome.rawValue)
                        }
                    }
                    Divider()
                    Button("Cycle Chrome") {
                        NotificationCenter.default.post(name: .setChromeView, object: nil)
                    }
                    .keyboardShortcut("c", modifiers: [.command, .option])
                }
                Divider()
                ForEach(AppearanceMode.allCases) { mode in
                    Button(mode.rawValue) { theme.appearance = mode }
                }
                Button("Toggle Light / Dark") { theme.toggleLightDark() }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                Divider()
                Button("Cycle Look") { theme.cycleLook() }
            }
            CommandMenu("Appearance") {
                ForEach(AppearanceMode.allCases) { mode in
                    Button(mode.rawValue) { theme.appearance = mode }
                }
                Button("Toggle Light / Dark") { theme.toggleLightDark() }
                Divider()
                ForEach(AppLook.allCases) { look in
                    Button(look.rawValue) { theme.look = look }
                }
                Button("Cycle Look") { theme.cycleLook() }
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

        // Menu style (not .window) so the extra never steals key-window focus
        // from the main Browser at launch or when clicked in the menu bar.
        MenuBarExtra("FileRadar", systemImage: "magnifyingglass") {
            MenuBarExtraView()
                .environmentObject(store)
                .environmentObject(license)
                .environmentObject(theme)
                .environmentObject(storeKit)
                .environmentObject(trial)
        }
        .menuBarExtraStyle(.menu)

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
    @discardableResult
    private static func writeWindowSnapshot(to path: String) -> Bool {
        let window = NSApp.keyWindow
            ?? NSApp.mainWindow
            ?? NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 400 })
        guard let window,
              let view = window.contentView ?? window.contentViewController?.view else {
            fputs("FileRadar snapshot: no window yet\n", stderr)
            return false
        }
        window.makeKeyAndOrderFront(nil)
        view.layoutSubtreeIfNeeded()
        let bounds = view.bounds
        guard bounds.width > 10, bounds.height > 10,
              let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else {
            fputs("FileRadar snapshot: bad bounds\n", stderr)
            return false
        }
        view.cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        guard let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            fputs("FileRadar snapshot: encode failed\n", stderr)
            return false
        }
        let url = URL(fileURLWithPath: path)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try png.write(to: url)
            fputs("FileRadar snapshot: wrote \(path) (\(png.count) bytes)\n", stderr)
            return true
        } catch {
            fputs("FileRadar snapshot: write error \(error)\n", stderr)
            return false
        }
    }
}
