import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Iteration 1 views (Finder-replacement features, Apple-design lens)
//
// One job per view (principle 2), native controls only, chrome kept to a
// minimum (principle: beauty by removal). Paid surfaces use the existing
// LockedFeatureView pattern; nothing here invents a new lock screen.

// MARK: - Drop Stack tray (sidebar; principle 4)

struct DropStackView: View {
    @ObservedObject var stack = DropStack.shared
    @ObservedObject var queue = TransferQueue.shared
    @EnvironmentObject var theme: ThemeSettings
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                FRDropStackIcon(size: .sidebar, accent: theme.look.accent)
                Text("Drop Stack")
                    .font(FileRadarFont.body())
                Spacer()
                if !stack.urls.isEmpty {
                    Button("Clear") { stack.clear() }
                        .buttonStyle(.plain).font(FileRadarFont.caption())
                        .accessibilityLabel("Clear the Drop Stack")
                }
            }
            if stack.urls.isEmpty {
                Text("Drag files here to hold them, then place the whole stack elsewhere.")
                    .font(FileRadarFont.caption()).foregroundStyle(.secondary)
            } else {
                ForEach(stack.urls, id: \.self) { url in
                    HStack {
                        FRKindIcon(kind: FileKind.from(url: url, isDirectory: url.hasDirectoryPath), size: .micro)
                        Text(url.lastPathComponent).font(FileRadarFont.caption()).lineLimit(1)
                        Spacer()
                        Button(action: { stack.remove(url) }) {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.plain).font(FileRadarFont.caption())
                        .accessibilityLabel("Remove \(url.lastPathComponent) from the Drop Stack")
                    }
                    .onDrag { NSItemProvider(object: url as NSURL) }
                }
                Button("Place stack in a folder…") { placeStack() }
                    .font(FileRadarFont.caption())
                    .accessibilityHint("Choose a folder; the stacked files are moved there through the transfer queue.")
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: FileRadarChrome.radiusControl, style: .continuous)
                .fill(isTargeted ? FileRadarChrome.dropTargetWash(theme.look.accent) : FileRadarChrome.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: FileRadarChrome.radiusControl, style: .continuous)
                .strokeBorder(isTargeted ? theme.look.accent.opacity(0.35) : FileRadarChrome.hairline.opacity(0.5), lineWidth: 1)
                .allowsHitTesting(false)
        )
        // Drop target is scoped to this tray row only — never a full-window
        // plate that would swallow sidebar / detail clicks.
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            DropUtilities.loadURLs(from: providers) { stack.add($0) }
            return true
        }
        .accessibilityLabel("Drop Stack: a temporary tray for files you are moving.")
    }

    private func placeStack() {
        // Defer NSOpenPanel out of the SwiftUI action turn (modal + layout crash).
        DispatchQueue.main.async {
            guard let folder = SecurityBookmarkStore.pickAndStoreFolder() else { return }
            let canonical = folder.resolvingSymlinksInPath().standardizedFileURL
            queue.enqueueMove(stack.urls, to: canonical)
            stack.clear()
        }
    }
}

// MARK: - Transfer queue (sidebar strip + progress; principle 10)

struct TransferQueueView: View {
    @ObservedObject var queue = TransferQueue.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                FRTransferIcon(active: queue.activeCount > 0, size: .sidebar, accent: FileRadarChrome.accent)
                Text("Transfers")
                    .font(FileRadarFont.body())
                Spacer()
                if queue.activeCount > 0 {
                    Button(queue.isPaused ? "Resume" : "Pause") { queue.isPaused.toggle() }
                        .buttonStyle(.plain).font(FileRadarFont.caption())
                    Button("Cancel") { queue.cancelAll() }
                        .buttonStyle(.plain).font(FileRadarFont.caption())
                } else if !queue.items.isEmpty {
                    Button("Clear") { queue.clearFinished() }
                        .buttonStyle(.plain).font(FileRadarFont.caption())
                }
            }
            if queue.items.isEmpty {
                Text("Copies and moves appear here with progress. Nothing is running.")
                    .font(FileRadarFont.caption()).foregroundStyle(.secondary)
            }
            ForEach(queue.items) { item in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(item.title).font(FileRadarFont.caption()).lineLimit(1)
                        Spacer(minLength: 4)
                        if item.status == .queued || item.status == .working {
                            Button(action: { queue.cancelItem(id: item.id) }) {
                                Image(systemName: "xmark.circle")
                            }
                            .buttonStyle(.plain)
                            .font(FileRadarFont.caption())
                            .accessibilityLabel("Cancel this transfer")
                        }
                    }
                    ProgressView(value: item.progress)
                    HStack {
                        Text(statusLabel(for: item)).font(FileRadarFont.caption()).foregroundStyle(.secondary)
                        if let error = item.error {
                            Text(error).font(FileRadarFont.caption()).foregroundStyle(.red).lineLimit(1)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: FileRadarChrome.radiusControl, style: .continuous)
                .fill(FileRadarChrome.cardFill)
        )
        .accessibilityLabel("Transfer queue.")
    }

    private func statusLabel(for item: TransferQueue.TransferItem) -> String {
        switch item.status {
        case .working:
            return "Working · \(item.completedFiles)/\(item.sources.count)"
        case .queued, .done, .cancelled, .failed:
            return item.status.rawValue.capitalized
        }
    }
}

/// ForkLift-style transfer HUD: floats over the detail when jobs are active
/// so bulk work never feels buried in the sidebar alone.
struct TransferHUDView: View {
    @ObservedObject var queue = TransferQueue.shared
    @EnvironmentObject var theme: ThemeSettings

    private var headline: String {
        let n = max(queue.activeCount, 1)
        if queue.isPaused { return "Paused · \(n) item\(n == 1 ? "" : "s")" }
        let verb = queue.items.contains(where: { $0.title.lowercased().contains("copy") }) ? "Copying" : "Moving"
        return "\(verb) \(n) item\(n == 1 ? "" : "s")"
    }

    private var aggregateProgress: Double {
        let active = queue.items.filter { $0.status == .working || $0.status == .queued }
        guard !active.isEmpty else {
            return queue.items.first(where: { $0.status == .failed })?.progress ?? 0
        }
        return active.map(\.progress).reduce(0, +) / Double(active.count)
    }

    var body: some View {
        if queue.activeCount > 0 || queue.items.contains(where: { $0.status == .failed }) {
            HStack(spacing: 12) {
                FRTransferIcon(active: !queue.isPaused && queue.activeCount > 0, size: .list, accent: theme.look.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(headline).font(FileRadarFont.heading()).lineLimit(1)
                    ProgressView(value: aggregateProgress)
                        .tint(theme.look.accent)
                }
                Text("\(Int((aggregateProgress * 100).rounded()))%")
                    .font(.system(size: 11, weight: .semibold, design: .default))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(minWidth: 36, alignment: .trailing)
                Button(queue.isPaused ? "Resume" : "Pause") { queue.isPaused.toggle() }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                Button("Cancel") { queue.cancelAll() }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                if queue.activeCount == 0 {
                    Button("Dismiss") { queue.clearFinished() }
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, FileRadarChrome.spaceHUDPadX)
            .padding(.vertical, FileRadarChrome.spaceHUDPadY)
            .frame(maxWidth: FileRadarChrome.hudMaxWidth)
            .background(theme.look.chromeMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(FileRadarChrome.hairline, lineWidth: 1))
            .shadow(color: FileRadarChrome.hudShadow, radius: 16, y: 6)
            .padding(.horizontal, FileRadarChrome.spaceCardGap)
            .padding(.bottom, 14)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(FileRadarMotion.panel, value: queue.activeCount)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Transfer progress")
        }
    }
}

/// Always-visible Activities strip (ForkLift signature) — idle or working.
struct ActivitiesStripView: View {
    @ObservedObject var queue = TransferQueue.shared
    @EnvironmentObject var theme: ThemeSettings
    var onShowQueue: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            FRTransferIcon(active: queue.activeCount > 0, size: .toolbar, accent: theme.look.accent)
            if queue.activeCount > 0 {
                Text(queue.isPaused ? "Activities · Paused" : "Activities · \(queue.activeCount) running")
                    .font(FileRadarFont.caption())
                ProgressView(value: aggregateProgress)
                    .tint(theme.look.accent)
                    .frame(maxWidth: 160)
                Button(queue.isPaused ? "Resume" : "Pause") { queue.isPaused.toggle() }
                    .controlSize(.mini)
                    .buttonStyle(.bordered)
                Button("Cancel") { queue.cancelAll() }
                    .controlSize(.mini)
                    .buttonStyle(.bordered)
            } else {
                Text("Activities · Idle")
                    .font(FileRadarFont.caption())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            Button("Queue") { onShowQueue() }
                .controlSize(.mini)
                .buttonStyle(.borderless)
                .font(FileRadarFont.caption())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(FileRadarChrome.chromeBarFill)
        .overlay(alignment: .top) {
            Rectangle().fill(FileRadarChrome.hairline).frame(height: 1)
                .allowsHitTesting(false)
        }
        .accessibilityLabel("Activities")
    }

    private var aggregateProgress: Double {
        let active = queue.items.filter { $0.status == .working || $0.status == .queued }
        guard !active.isEmpty else { return 0 }
        return active.map(\.progress).reduce(0, +) / Double(active.count)
    }
}

/// Breadcrumb path bar above each dual-pane browser (ForkLift path/status).
struct PathBarView: View {
    var folder: URL
    var isActive: Bool
    var itemCount: Int
    var onNavigate: (URL) -> Void
    var onChooseFolder: () -> Void
    @EnvironmentObject var theme: ThemeSettings

    private var crumbs: [(String, URL)] {
        var urls: [URL] = []
        var current = folder.standardizedFileURL
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        while true {
            urls.append(current)
            if current.path == home.path || current.path == "/" { break }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }
        return urls.reversed().map { url in
            if url.path == home.path { return ("Home", url) }
            let name = url.lastPathComponent
            return (name.isEmpty ? url.path : name, url)
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onChooseFolder) {
                Image(systemName: "folder")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(isActive ? theme.look.accent : .secondary)
            .help("Choose folder…")
            .accessibilityLabel("Choose folder")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array(crumbs.enumerated()), id: \.offset) { index, crumb in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        Button(crumb.0) { onNavigate(crumb.1) }
                            .buttonStyle(.plain)
                            .font(FileRadarFont.caption())
                            .foregroundStyle(index == crumbs.count - 1
                                             ? (isActive ? AnyShapeStyle(theme.look.accent) : AnyShapeStyle(.primary))
                                             : AnyShapeStyle(.secondary))
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 8)
            Text("\(itemCount)")
                .font(FileRadarFont.caption())
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .help("\(itemCount) items")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(isActive ? FileRadarChrome.activePaneWash(theme.look.accent) : FileRadarChrome.chromeBarFill)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(isActive ? theme.look.accent.opacity(0.35) : FileRadarChrome.hairline)
                .frame(height: isActive ? 1.5 : 1)
        }
    }
}

// MARK: - Tab strip (restored on relaunch via TabState)

struct TabBarView: View {
    @ObservedObject var tabState: TabState
    var onSelectFolder: (URL) -> Void
    @EnvironmentObject var theme: ThemeSettings

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabState.tabs) { tab in
                HStack(spacing: 4) {
                    FRPlaceIcon(place: FRPlaceKind.from(url: tab.folder), size: .micro)
                    Button(tab.title) {
                        tabState.selectedID = tab.id
                        onSelectFolder(tab.folder)
                    }
                    .buttonStyle(.plain)
                    .font(FileRadarFont.caption())
                    .help(tab.folder.path)
                    if tabState.tabs.count > 1 {
                        Button(action: { tabState.closeTab(tab) }) {
                            Image(systemName: "xmark").font(.system(size: 8, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close tab \(tab.title)")
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(tabState.selectedID == tab.id
                              ? theme.look.accent.opacity(0.16)
                              : Color.primary.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(tabState.selectedID == tab.id
                                      ? theme.look.accent.opacity(0.35)
                                      : Color.clear, lineWidth: 1)
                )
            }
            Button(action: {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.prompt = "Open in new tab"
                if panel.runModal() == .OK, let folder = panel.url {
                    tabState.addTab(folder: folder)
                    onSelectFolder(folder)
                }
            }) {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .padding(6)
            .accessibilityLabel("Open a folder in a new tab")
            Spacer()
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(theme.look.chromeMaterial)
    }
}

// MARK: - Dual pane (ForkLift-primary default)
//
// Two folder browsers side by side with path bars. Drag between panes
// enqueues copy/move via TransferQueue (never silent overwrite). Active
// pane is highlighted; Jump Panes (Ctrl-Tab) flips focus.

struct DualPaneView: View {
    var leftFolder: URL
    var leftFiles: [FileItem]
    var rightFolder: URL
    var rightFiles: [FileItem]
    @Binding var activeIsRight: Bool
    var onNavigateLeft: (URL) -> Void
    var onNavigateRight: (URL) -> Void
    var onChooseLeftFolder: () -> Void
    var onChooseRightFolder: () -> Void
    var onSyncCompare: (() -> Void)? = nil
    /// When set, path bars / chrome toolbar adapt to the active ChromeView.
    var chromeView: ChromeView = .radarGlass
    var accent: Color = FileRadarChrome.accent
    @EnvironmentObject var store: FileStore
    @EnvironmentObject var theme: ThemeSettings
    @State private var preferCopy = true

    private var showsTopChromeBar: Bool {
        chromeView == .radarGlass || chromeView == .workspaceTabs
    }

    private var showsSyncPill: Bool {
        chromeView == .commandRail
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsTopChromeBar {
                HStack(spacing: 8) {
                    Label("Dual pane", systemImage: "rectangle.split.2x1")
                        .font(FileRadarFont.caption())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        transferSelection(toRight: true, copy: true)
                    } label: {
                        Label("Copy →", systemImage: "doc.on.doc")
                    }
                    .controlSize(.small)
                    .disabled(store.selectedIDs.isEmpty)
                    .help("Copy selection to the opposite pane")
                    Button {
                        transferSelection(toRight: true, copy: false)
                    } label: {
                        Label("Move →", systemImage: "arrow.right")
                    }
                    .controlSize(.small)
                    .disabled(store.selectedIDs.isEmpty)
                    .help("Move selection to the opposite pane")
                    Toggle("Drop copies", isOn: $preferCopy)
                        .toggleStyle(.checkbox)
                        .font(FileRadarFont.caption())
                        .help("When on, drops copy instead of move. Name clashes are skipped, never overwritten.")
                    if let onSyncCompare {
                        Button {
                            onSyncCompare()
                        } label: {
                            Label("Sync", systemImage: "arrow.left.arrow.right")
                        }
                        .controlSize(.small)
                        .help("Compare / sync the two pane folders")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, FileRadarChrome.spaceChromeY)
                .background(FileRadarChrome.chromeBarFill)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(FileRadarChrome.hairline).frame(height: 1)
                }
            }

            HStack(alignment: .top, spacing: 0) {
                pane(folder: leftFolder, files: leftFiles, isActive: !activeIsRight, sideLabel: "Left",
                     onNavigate: onNavigateLeft, onChoose: onChooseLeftFolder,
                     onActivate: { activeIsRight = false })
                if showsSyncPill {
                    PaneSyncPill(
                        accent: accent,
                        onCopyRight: { transferSelection(toRight: true, copy: true) },
                        onCopyLeft: { transferSelection(toRight: false, copy: true) },
                        onSync: { onSyncCompare?() }
                    )
                } else {
                    Rectangle().fill(FileRadarChrome.hairline).frame(width: 1)
                }
                pane(folder: rightFolder, files: rightFiles, isActive: activeIsRight, sideLabel: "Right",
                     onNavigate: onNavigateRight, onChoose: onChooseRightFolder,
                     onActivate: { activeIsRight = true })
            }
        }
    }

    private func pane(folder: URL, files: [FileItem], isActive: Bool, sideLabel: String,
                      onNavigate: @escaping (URL) -> Void,
                      onChoose: @escaping () -> Void,
                      onActivate: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            // Path-bar Buttons already call onActivate. Do not wrap them in
            // an outer onTapGesture — it competed with crumb / house hits.
            ZStack(alignment: .trailing) {
                Group {
                    if chromeView == .radarGlass {
                        PillPathBarView(folder: folder, isActive: isActive, itemCount: files.count,
                                        onNavigate: { url in onActivate(); onNavigate(url) },
                                        onChooseFolder: { onActivate(); onChoose() },
                                        accent: accent)
                    } else {
                        PathBarView(folder: folder, isActive: isActive, itemCount: files.count,
                                    onNavigate: { url in onActivate(); onNavigate(url) },
                                    onChooseFolder: { onActivate(); onChoose() })
                    }
                }
                Text(sideLabel)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(accent)
                    .padding(.trailing, 10)
                    .allowsHitTesting(false)
            }
            .accessibilityAddTraits(isActive ? .isSelected : [])
            .accessibilityLabel("\(folder.lastPathComponent) pane")

            FileCollectionView(title: folder.lastPathComponent, files: files,
                               dropTargetFolder: folder, preferCopyOnDrop: preferCopy,
                               showsHeader: false,
                               onOpenFolder: { url in
                                   onActivate()
                                   onNavigate(url)
                               })
                .overlay(
                    RoundedRectangle(cornerRadius: theme.look.cardCorner, style: .continuous)
                        .strokeBorder(
                            isActive ? FileRadarChrome.activePaneStrokeColor(accent) : Color.clear,
                            lineWidth: FileRadarChrome.activePaneStroke
                        )
                        .padding(2)
                        .allowsHitTesting(false)
                )
                .background(isActive ? FileRadarChrome.activePaneWash(accent) : Color.clear)
        }
    }

    private func transferSelection(toRight: Bool, copy: Bool) {
        let target = toRight ? rightFolder : leftFolder
        let sources = store.files.filter { store.selectedIDs.contains($0.id) }.map(\.url)
        guard !sources.isEmpty else { return }
        if copy {
            TransferQueue.shared.enqueueCopy(sources, to: target)
        } else {
            TransferQueue.shared.enqueueMove(sources, to: target)
        }
    }
}

/// Immediate children of a folder for dual-pane browsing (index + disk fallback).
enum FolderBrowser {
    /// Sandbox `homeDirectory/Downloads` is a symlink into the real Downloads
    /// tree. `standardizedFileURL` does not resolve it, so container tabs never
    /// matched indexed children under `/Users/…/Downloads` — empty dual panes
    /// with live chrome that looked dead.
    static func canonicalPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    static func children(of folder: URL, indexed: [FileItem]) -> [FileItem] {
        let folderPath = canonicalPath(folder)
        let fromIndex = indexed.filter {
            canonicalPath($0.url.deletingLastPathComponent()) == folderPath
        }
        // Index only. A contentsOfDirectory fallback here ran on the main actor
        // during every body eval and blocked in open() on Files-and-Folders TCC
        // (or a huge Downloads tree) — freezing the UI so buttons looked dead.
        return fromIndex
    }
}

// MARK: - Workspaces (PAID; QSpace / Bloom lesson)

struct WorkspacesView: View {
    @ObservedObject var tabState: TabState
    @Binding var dualPaneEnabled: Bool
    @EnvironmentObject var store: FileStore
    @EnvironmentObject var license: LicenseManager
    @StateObject private var workspaceStore = WorkspaceStore()
    @State private var newName = ""
    @State private var showLicense = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Workspaces").font(FileRadarFont.title()).padding(.horizontal)
            if !license.isAllowed(.workspaces) {
                LockedFeatureView(feature: .workspaces) { showLicense = true }
            } else {
                Text("A workspace restores your tabs, panes, and pinned folders in one click. Workspaces remember locations only — they never move files.")
                    .font(FileRadarFont.body()).foregroundStyle(.secondary).padding(.horizontal)
                HStack {
                    TextField("Workspace name — e.g. Photos, Projects", text: $newName)
                        .textFieldStyle(.roundedBorder)
                    Button("Save current layout") {
                        workspaceStore.save(name: newName,
                                            tabFolders: tabState.tabs.map(\.folder),
                                            dualPaneEnabled: dualPaneEnabled,
                                            pinnedFolders: store.pinnedFolderURLs)
                        newName = ""
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.padding(.horizontal)
                if workspaceStore.workspaces.isEmpty {
                    EmptyStateView(title: "No workspaces yet",
                                   message: "Arrange your tabs and panes, then save the layout under a name like Photos or Projects.")
                } else {
                    List(workspaceStore.workspaces) { workspace in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(workspace.name).font(FileRadarFont.heading())
                                Text("\(workspace.tabFolders.count) tab\(workspace.tabFolders.count == 1 ? "" : "s") · \(workspace.dualPaneEnabled ? "dual pane" : "single pane")")
                                    .font(FileRadarFont.caption()).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Restore") { apply(workspace) }
                            Button("Delete") { workspaceStore.delete(workspace) }
                                .accessibilityHint("Deletes only the saved workspace name, not any files.")
                        }.padding(.vertical, 4)
                    }
                }
            }
        }
        .sheet(isPresented: $showLicense) { LicenseEntryView() }
    }

    private func apply(_ workspace: SavedWorkspace) {
        tabState.tabs = workspace.tabFolders.map { TabState.TabItem(folder: $0) }
        tabState.selectedID = tabState.tabs.first?.id
        dualPaneEnabled = workspace.dualPaneEnabled
        store.pinnedFolderURLs = workspace.pinnedFolders
    }
}

// MARK: - Archive browser (PAID; Commander One lesson; read-only listing)

struct ArchiveBrowserView: View {
    var archive: URL
    @EnvironmentObject var license: LicenseManager
    @State private var entries: [ArchiveEntry] = []
    @State private var listing = false
    @State private var extracting = false
    @State private var extractMessage: String?
    @State private var showLicense = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(archive.lastPathComponent).font(FileRadarFont.title()).padding(.horizontal)
            if !license.isAllowed(.archiveBrowse) {
                LockedFeatureView(feature: .archiveBrowse) { showLicense = true }
            } else {
                Text("Browsing read-only, as if this archive were a folder. Nothing inside it is changed. Extract only when you ask.")
                    .font(FileRadarFont.body()).foregroundStyle(.secondary).padding(.horizontal)
                Button(extracting ? "Extracting…" : "Extract archive to a folder…") { extract() }
                    .padding(.horizontal)
                    .disabled(extracting || listing)
                if let message = extractMessage {
                    Text(message).font(FileRadarFont.body()).padding(.horizontal)
                }
                if listing {
                    ProgressView("Listing archive…")
                        .padding(.horizontal)
                } else if entries.isEmpty {
                    EmptyStateView(title: "No entries listed",
                                   message: "This archive listed no entries, or its listing could not be read. Nothing was changed.")
                } else {
                    List(entries) { entry in
                        HStack {
                            Image(systemName: entry.isDirectory ? "folder" : "doc")
                            Text(entry.name).font(FileRadarFont.body()).lineLimit(1)
                            Spacer()
                            if let size = entry.size {
                                Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                                    .font(FileRadarFont.caption()).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showLicense) { LicenseEntryView() }
        // Never list archives on MainActor — unzip/tar pipes can fill and deadlock.
        .task(id: archive) {
            guard license.isAllowed(.archiveBrowse) else {
                entries = []
                return
            }
            listing = true
            let listed = await ArchiveBrowser.listEntriesAsync(of: archive)
            entries = listed
            listing = false
        }
    }

    private func extract() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Extract here"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        extracting = true
        extractMessage = nil
        let archiveURL = archive
        Task {
            let error = await ArchiveBrowser.extractAsync(archiveURL, to: folder)
            extracting = false
            if let error {
                extractMessage = error
            } else {
                extractMessage = "Extracted to \(folder.lastPathComponent). The archive itself was not changed."
            }
        }
    }
}

// MARK: - Folder sync / compare, P1 stretch (PAID; preview + Trash-only)

struct SyncCompareView: View {
    @EnvironmentObject var license: LicenseManager
    @EnvironmentObject var store: FileStore
    @StateObject private var trash = TrashService()
    @State private var leftFolder: URL?
    @State private var rightFolder: URL?
    @State private var comparison: SyncComparison?
    @State private var comparing = false
    @State private var confirmingTrash = false
    @State private var showLicense = false
    @State private var doneMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Compare folders").font(FileRadarFont.title()).padding(.horizontal)
            if !license.isAllowed(.folderSyncCompare) {
                LockedFeatureView(feature: .folderSyncCompare) { showLicense = true }
            } else {
                Text("Preview only: see what differs between two folders before anything moves. The only action offered is moving previewed extras to Trash — nothing is deleted outright, and nothing syncs on its own.")
                    .font(FileRadarFont.body()).foregroundStyle(.secondary).padding(.horizontal)
                HStack {
                    Button("Choose left folder…") { leftFolder = pickFolder() }
                    Text(leftFolder?.lastPathComponent ?? "No folder chosen").font(FileRadarFont.caption()).foregroundStyle(.secondary)
                    Button("Choose right folder…") { rightFolder = pickFolder() }
                    Text(rightFolder?.lastPathComponent ?? "No folder chosen").font(FileRadarFont.caption()).foregroundStyle(.secondary)
                    Button(comparing ? "Comparing…" : "Compare") { runCompare() }
                        .disabled(leftFolder == nil || rightFolder == nil || comparing)
                }.padding(.horizontal)
                if let doneMessage {
                    Text(doneMessage).font(FileRadarFont.body()).padding(.horizontal)
                }
                if let comparison {
                    if comparison.isEmpty {
                        EmptyStateView(title: "Folders match",
                                       message: "No files are only on one side, and no shared file differs in size or date.")
                    } else {
                        List {
                            if !comparison.onlyLeft.isEmpty {
                                Section("Only on the left (\(comparison.onlyLeft.count))") {
                                    ForEach(comparison.onlyLeft, id: \.self) { Text($0.lastPathComponent) }
                                }
                            }
                            if !comparison.onlyRight.isEmpty {
                                Section("Only on the right (\(comparison.onlyRight.count))") {
                                    ForEach(comparison.onlyRight, id: \.self) { Text($0.lastPathComponent) }
                                }
                            }
                            if !comparison.differing.isEmpty {
                                Section("Different (\(comparison.differing.count))") {
                                    ForEach(comparison.differing, id: \.self) { Text($0.lastPathComponent) }
                                }
                            }
                        }
                        Button("Move left-only files to Trash") { confirmingTrash = true }
                            .padding(.horizontal)
                            .disabled(comparison.onlyLeft.isEmpty)
                            .accessibilityHint("Moves only the previewed left-only files to Trash, where they can be restored.")
                    }
                }
            }
        }
        .sheet(isPresented: $showLicense) { LicenseEntryView() }
        .alert("Move these files to Trash?", isPresented: $confirmingTrash) {
            Button("Move to Trash", role: .destructive) { trashLeftOnly() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Files in Trash can be restored. This does not delete anything outright, and it does not touch the right folder.")
        }
    }

    private func pickFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    private func runCompare() {
        guard let left = leftFolder, let right = rightFolder else { return }
        comparing = true
        Task.detached {
            let result = SyncCompareService.compare(left: left, right: right)
            await MainActor.run {
                comparison = result
                comparing = false
            }
        }
    }

    private func trashLeftOnly() {
        guard let urls = comparison?.onlyLeft else { return }
        let items = urls.compactMap { SyncCompareService.fileItem(for: $0) }
        let moved = trash.trash(items)
        store.removeFiles(matching: Set(moved.map { $0.originalURL.path }))
        doneMessage = "\(moved.count) file\(moved.count == 1 ? "" : "s") moved to Trash. Restore them from Finder if needed."
        comparison = nil
    }
}

// MARK: - Command palette (Cmd-K; principle 1 + 9)

struct CommandPaletteView: View {
    var onSelect: (PaletteAction) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var query = ""
    @State private var selection: PaletteAction?

    private var filtered: [PaletteAction] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return PaletteAction.allCases }
        return PaletteAction.allCases.filter { $0.title.lowercased().contains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Type an action — e.g. dual pane, workspaces, tabs", text: $query)
                .textFieldStyle(.roundedBorder)
                .font(FileRadarFont.body())
                .accessibilityLabel("Command palette search")
                .onSubmit { confirmSelection() }
            List(filtered, selection: $selection) { action in
                HStack {
                    Text(action.title).font(FileRadarFont.body())
                    Spacer()
                    Text(action.shortcutHint).font(FileRadarFont.caption()).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { choose(action) }
            }
            .frame(minHeight: 220)
            Text("Use the arrow keys to move, Return to run, Escape to close. Every action here is also reachable from the menus and toolbar.")
                .font(FileRadarFont.caption()).foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 520)
        .onAppear { selection = filtered.first }
        .onChange(of: query) { _, _ in selection = filtered.first }
        .onKeyPress(.return) { confirmSelection(); return .handled }
        .onKeyPress(.escape) { dismiss(); return .handled }
    }

    private func confirmSelection() {
        if let action = selection ?? filtered.first { choose(action) }
    }

    private func choose(_ action: PaletteAction) {
        onSelect(action)
        dismiss()
    }
}

// MARK: - Folder size label (list rows; background, on-demand)

struct FolderSizeText: View {
    var folder: URL
    @State private var size: Int64?

    var body: some View {
        Group {
            if let size {
                Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                    .foregroundStyle(.secondary)
            } else {
                Text("Sizing…").foregroundStyle(.secondary)
            }
        }
        .font(FileRadarFont.caption())
        .task(id: folder) {
            size = await FolderSizeService.shared.sizeAsync(for: folder)
        }
    }
}
