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
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Drop Stack", systemImage: "tray.and.arrow.down")
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
                        Image(systemName: "doc").font(FileRadarFont.caption())
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
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(isTargeted ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08)))
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            DropUtilities.loadURLs(from: providers) { stack.add($0) }
            return true
        }
        .accessibilityLabel("Drop Stack: a temporary tray for files you are moving.")
    }

    private func placeStack() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Place stack here"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        queue.enqueueMove(stack.urls, to: folder)
        stack.clear()
    }
}

// MARK: - Transfer queue (sidebar strip + progress; principle 10)

struct TransferQueueView: View {
    @ObservedObject var queue = TransferQueue.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Transfers", systemImage: "arrow.left.arrow.right")
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
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
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
                Image(systemName: queue.isPaused ? "pause.circle.fill" : "doc.on.doc.fill")
                    .foregroundStyle(theme.look.accent)
                    .imageScale(.large)
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
                Button("Cancel") { queue.cancelAll() }
                    .controlSize(.small)
                if queue.activeCount == 0 {
                    Button("Dismiss") { queue.clearFinished() }
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
            .frame(maxWidth: 440)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
            .padding(.horizontal, 16).padding(.bottom, 14)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(FileRadarMotion.panel, value: queue.activeCount)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Transfer progress")
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
                    Image(systemName: "folder")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(tabState.selectedID == tab.id ? theme.look.accent : .secondary)
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

// MARK: - Dual pane (OPTIONAL, off by default; principle 2: default stays shelves + search)
//
// Two file collections side by side. Drag a file from one pane to the
// other: the drop enqueues a move through the transfer queue (never a
// silent overwrite — an existing name is skipped and reported). The
// active pane is the highlighted one; the Jump Panes button (Ctrl-Tab)
// moves the highlight. Focus here is the active-pane marker, not AppKit
// first-responder focus — see README UNTESTED.

struct DualPaneView: View {
    var leftTitle: String
    var leftFiles: [FileItem]
    var rightFolder: URL
    var rightFiles: [FileItem]
    @Binding var activeIsRight: Bool
    var onChooseRightFolder: () -> Void
    @EnvironmentObject var theme: ThemeSettings
    @State private var preferCopy = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label(activeIsRight ? "Right pane active" : "Left pane active",
                      systemImage: "rectangle.split.2x1")
                    .font(FileRadarFont.caption())
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("Drop copies (Option)", isOn: $preferCopy)
                    .toggleStyle(.checkbox)
                    .font(FileRadarFont.caption())
                    .help("When on, drops onto the right pane copy instead of move. Name clashes are still skipped, never overwritten.")
                Button("Choose right folder…") { onChooseRightFolder() }
                    .font(FileRadarFont.caption())
                    .controlSize(.small)
                Text(rightFolder.path)
                    .font(FileRadarFont.caption())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 220, alignment: .trailing)
                    .help(rightFolder.path)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color.primary.opacity(0.03))

            HStack(alignment: .top, spacing: 0) {
                pane(title: leftTitle, files: leftFiles, isActive: !activeIsRight,
                     dropFolder: nil, copyOnDrop: false, onActivate: { activeIsRight = false })
                Divider()
                pane(title: rightFolder.lastPathComponent, files: rightFiles, isActive: activeIsRight,
                     dropFolder: rightFolder, copyOnDrop: preferCopy, onActivate: { activeIsRight = true })
            }
        }
    }

    private func pane(title: String, files: [FileItem], isActive: Bool,
                      dropFolder: URL?, copyOnDrop: Bool, onActivate: @escaping () -> Void) -> some View {
        // Activate on the title chrome only — a full-pane onTapGesture sat
        // above FileCollectionView and stole clicks from cards/buttons.
        VStack(spacing: 0) {
            HStack {
                Text(title).font(FileRadarFont.caption()).foregroundStyle(isActive ? theme.look.accent : .secondary)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture(perform: onActivate)
            .accessibilityAddTraits(isActive ? .isSelected : [])
            .accessibilityLabel("\(title) pane")
            .accessibilityHint("Click to make this pane active")

            FileCollectionView(title: title, files: files,
                               dropTargetFolder: dropFolder, preferCopyOnDrop: copyOnDrop)
                .overlay(
                    RoundedRectangle(cornerRadius: theme.look.cardCorner, style: .continuous)
                        .strokeBorder(isActive ? theme.look.accent.opacity(0.55) : Color.clear, lineWidth: 1.5)
                        .padding(2)
                        .allowsHitTesting(false)
                )
                .background(isActive ? theme.look.accent.opacity(0.03) : Color.clear)
        }
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
                Button("Extract archive to a folder…") { extract() }
                    .padding(.horizontal)
                if let message = extractMessage {
                    Text(message).font(FileRadarFont.body()).padding(.horizontal)
                }
                if entries.isEmpty {
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
        .onAppear {
            entries = ArchiveBrowser.listEntries(of: archive)
        }
    }

    private func extract() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Extract here"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        if let error = ArchiveBrowser.extract(archive, to: folder) {
            extractMessage = error
        } else {
            extractMessage = "Extracted to \(folder.lastPathComponent). The archive itself was not changed."
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
