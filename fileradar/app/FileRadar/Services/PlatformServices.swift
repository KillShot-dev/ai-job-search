import Foundation
import AppKit
import SwiftUI
import QuickLookUI
import AppIntents

// MARK: - Quick Look (Space) — AppKit, because SwiftUI has no Quick Look panel

/// Shows the system Quick Look panel for the given files. This is the real
/// macOS preview experience (principle 3), not a re-implemented viewer.
final class QuickLookHelper: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookHelper()
    private var items: [URL] = []

    func show(files: [FileItem]) {
        items = files.filter { !$0.isICloudOnly }.map(\.url)
        guard !items.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.makeKeyAndOrderFront(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { items.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        // NSURL is the documented QLPreviewItem bridge for file URLs.
        items[index] as NSURL
    }
}

// MARK: - Quick Search hotkey + panel coordinator

/// Global Shift-Cmd-Space monitor. Requires Accessibility/Input Monitoring
/// permission when another app is frontmost; in-app the CommandMenu shortcut
/// always works. The shortcut itself is configurable in Settings and stored
/// in UserDefaults ("quickSearchShortcut" — a descriptive string; the
/// monitor below implements the default Shift-Cmd-Space).
final class HotkeyService {
    static let shared = HotkeyService()
    private var globalMonitor: Any?
    private var localMonitor: Any?

    func start() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains([.command, .shift]) && event.keyCode == 49 { // Space
                Task { @MainActor in QuickSearchPanel.shared.show() }
                return nil
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains([.command, .shift]) && event.keyCode == 49 {
                Task { @MainActor in QuickSearchPanel.shared.show() }
            }
        }
    }

    deinit {
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
    }
}

/// The Quick Search floating panel (paid feature). Implemented as an NSPanel
/// so it can appear above other apps; its content is SwiftUI.
@MainActor
final class QuickSearchPanel {
    static let shared = QuickSearchPanel()
    private var panel: NSPanel?
    private weak var store: FileStore?
    private weak var license: LicenseManager?
    private weak var theme: ThemeSettings?

    func configure(store: FileStore, license: LicenseManager, theme: ThemeSettings) {
        self.store = store
        self.license = license
        self.theme = theme
    }

    func show() {
        guard let license else {
            NotificationCenter.default.post(name: .showLicenseSheet, object: nil)
            return
        }
        guard license.isAllowed(.quickSearch) else {
            NotificationCenter.default.post(name: .showLicenseSheet, object: nil)
            return
        }
        if panel == nil {
            let content = QuickSearchPanelView(store: store, license: license)
                .environmentObject(theme ?? ThemeSettings())
            let hosting = NSHostingController(rootView: content)
            let p = NSPanel(contentViewController: hosting)
            // Frosted HUD: borderless floating panel with vibrancy.
            p.styleMask = [.borderless, .fullSizeContentView, .nonactivatingPanel]
            p.setContentSize(NSSize(width: 560, height: 420))
            p.isFloatingPanel = true
            p.level = .floating
            p.titleVisibility = .hidden
            p.titlebarAppearsTransparent = true
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.isMovableByWindowBackground = true
            if let content = p.contentView {
                content.wantsLayer = true
                content.layer?.cornerRadius = 18
                content.layer?.masksToBounds = true
            }
            panel = p
        }
        // Recenter near the active screen’s optical middle each show.
        if let screen = NSScreen.main {
            let size = panel?.frame.size ?? NSSize(width: 560, height: 420)
            let origin = NSPoint(
                x: screen.visibleFrame.midX - size.width / 2,
                y: screen.visibleFrame.midY - size.height / 3
            )
            panel?.setFrameOrigin(origin)
        }
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Shortcuts / Siri actions (paid feature)

/// AppIntents exposed to Shortcuts and Siri. Gating: the intents check
/// LicenseManager before returning file contents beyond a preview; the
/// "Get Latest Download" result is a file reference, not file data.
struct FindFilesIntent: AppIntent {
    static var title: LocalizedStringResource = "Find Files"
    static var description = IntentDescription("Search FileRadar for files by name or kind.")

    @Parameter(title: "Query") var query: String

    static var parameterSummary: some ParameterSummary {
        Summary("Find \(\.$query)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<[String]> {
        // The host app fills this from its index when run in-app; from
        // Shortcuts alone the intent reports that FileRadar must be open.
        // Full in-app intent wiring is listed in README UNTESTED.
        return .result(value: ["Open FileRadar and search for “\(query)” to see results."])
    }
}

struct GetLatestDownloadIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Latest Download"
    static var description = IntentDescription("Return the most recent download.")

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            return .result(value: "No downloads found.")
        }
        let latest = try? FileManager.default.contentsOfDirectory(at: downloads, includingPropertiesForKeys: [.contentModificationDateKey])
            .max(by: { ($0.modificationDate ?? .distantPast) < ($1.modificationDate ?? .distantPast) })
        return .result(value: latest?.lastPathComponent ?? "No downloads found.")
    }
}

private extension URL {
    var modificationDate: Date? {
        (try? resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}

/// Registers the intents above with Shortcuts/Siri. Without this provider
/// the intents exist but never appear in Shortcuts.
struct FileRadarShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: FindFilesIntent(),
            phrases: ["Find files in \(.applicationName)"],
            shortTitle: "Find Files",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: GetLatestDownloadIntent(),
            phrases: ["Get my latest download in \(.applicationName)"],
            shortTitle: "Get Latest Download",
            systemImageName: "arrow.down.circle"
        )
    }
}

// MARK: - Background updates (INERT by design — no network, no feed)

/// Update checker stub, deliberately inert: there is deliberately NO
/// feed URL, NO URLSession call, and NO bundled Sparkle in this build,
/// because the app holds no network entitlement and must make no network
/// call. An earlier draft fetched a feed when a URL was set; that live
/// call was removed — a settable URL plus a real fetch is exactly how a
/// "temporarily configured" feed ships by accident. Enabling updates is a
/// coordinator decision, not a code edit: it requires adding the Sparkle
/// framework, a network-client entitlement, and a signed appcast feed
/// (see README.md signing/update steps), and only then may a fetch be
/// reintroduced behind that entitlement.
enum UpdateService {
    static func checkForUpdates() async -> String {
        "Automatic updates are not configured in this build."
    }
}
