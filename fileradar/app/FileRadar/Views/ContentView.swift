import SwiftUI
import AppKit

/// Main window. Principle 2: one job per destination.
enum Destination: Hashable {
    case home, search, cleanup, duplicates, timeline, diskMap, extras, muse
    case kind(FileKind)
    case source(String)
    case smartFolder(String)
    case pinned(URL)
    case favorite(URL)
    case workspaces, syncCompare
    case archive(URL)
    case savedSearch(UUID)

    var title: String {
        switch self {
        case .home: return "Home"
        case .search: return "Search"
        case .cleanup: return "Clean Up"
        case .duplicates: return "Duplicates"
        case .timeline: return "Timeline"
        case .diskMap: return "Disk Map"
        case .extras: return "Extras"
        case .muse: return "Muse"
        case .kind(let k): return k.displayName
        case .source(let s): return s
        case .smartFolder(let s): return s
        case .pinned(let u), .favorite(let u): return u.lastPathComponent
        case .workspaces: return "Workspaces"
        case .syncCompare: return "Compare Folders"
        case .archive(let u): return u.lastPathComponent
        case .savedSearch: return "Saved Search"
        }
    }
}

@MainActor
struct ContentView: View {
    @EnvironmentObject var store: FileStore
    @EnvironmentObject var license: LicenseManager
    @EnvironmentObject var theme: ThemeSettings
    @EnvironmentObject var playback: MusicPlaybackService
    @EnvironmentObject var museAuth: MuseAuthService
    @EnvironmentObject var museVoice: VoiceService
    @EnvironmentObject var favorites: FavoritesStore
    @EnvironmentObject var savedSearches: SavedSearchStore
    let museClient: MuseClient

    init(museClient: MuseClient) {
        self.museClient = museClient
    }
    @State private var museChatViewModel: ChatViewModel?
    @State private var museTokenProviderSet = false
    @State private var destination: Destination = .home
    @State private var searchText = ""
    @State private var showLicense = false
    @State private var showInspector = false
    @State private var showPalette = false
    @StateObject private var tabState = TabState()
    @AppStorage("dualPaneEnabled") private var dualPaneEnabled = false
    @AppStorage("previewStripEnabled") private var previewStripEnabled = true
    @State private var activeIsRight = false
    @State private var showBatchRename = false
    @State private var showTransfers = false
    @StateObject private var trash = TrashService()
    @ObservedObject private var transferQueue = TransferQueue.shared

    var body: some View {
        splitChrome
            .tint(theme.look.accent)
            .preferredColorScheme(theme.colorScheme)
            .fileRadarAtmosphere(theme.look)
            .modifier(ContentSheetsModifier(
                showLicense: $showLicense,
                showPalette: $showPalette,
                showBatchRename: $showBatchRename,
                selectedFiles: selectedFiles,
                onPalette: performPalette,
                onRenameApplied: { plan in
                    for (old, newURL) in plan {
                        store.updateFileURL(from: old.url, to: newURL)
                    }
                }
            ))
            .modifier(ContentNotificationsModifier(
                destination: $destination,
                searchText: $searchText,
                showBatchRename: $showBatchRename,
                showPalette: $showPalette,
                showLicense: $showLicense,
                dualPaneEnabled: $dualPaneEnabled,
                previewStripEnabled: $previewStripEnabled,
                store: store,
                favorites: favorites,
                trash: trash,
                license: license,
                onSelectAll: selectAllVisible,
                onTrashSelection: trashSelected
            ))
            .onAppear(perform: bootstrap)
            .onChange(of: destination) { _, new in
                museChatViewModel?.updateContext(title: new.title,
                                                 fileNames: museContextFileNames(for: new))
                if case .savedSearch(let id) = new,
                   let item = savedSearches.items.first(where: { $0.id == id }) {
                    searchText = item.query
                    destination = .search
                }
            }
            .onKeyPress(.space) {
                let selected = selectedFiles
                guard !selected.isEmpty else { return .ignored }
                QuickLookHelper.shared.show(files: selected)
                return .handled
            }
    }

    /// Sidebar row that sets `destination` directly. Avoids both
    /// `NavigationLink(value:)` (swallows clicks with `List(selection:)`)
    /// and tag-selection (also failed to update on this OS) — Buttons fire.
    @ViewBuilder
    private func sidebarItem(_ title: String, systemImage: String, _ dest: Destination) -> some View {
        Button {
            destination = dest
        } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(destination == dest ? theme.look.accent.opacity(0.14) : Color.clear)
        .accessibilityAddTraits(destination == dest ? .isSelected : [])
        .accessibilityLabel(title)
    }

    private var splitChrome: some View {
        NavigationSplitView {
            List {
                // Four sidebar sections — Library, Collections, Tools, Places.
                Section("Library") {
                    sidebarItem("Home", systemImage: "house", .home)
                    sidebarItem("Search", systemImage: "magnifyingglass", .search)
                    sidebarItem("Timeline", systemImage: "calendar", .timeline)
                    sidebarItem("Disk Map", systemImage: "square.grid.3x3", .diskMap)
                    sidebarItem("Muse", systemImage: "sparkles", .muse)
                }
                Section("Collections") {
                    ForEach([FileKind.image, .video, .audio, .document, .archive, .app], id: \.self) { kind in
                        sidebarItem(kind.displayName, systemImage: kind.systemImage, .kind(kind))
                    }
                    sidebarItem("Large Files", systemImage: "doc.fill", .smartFolder("Large Files"))
                    sidebarItem("Screenshots", systemImage: "camera", .smartFolder("Screenshots"))
                    sidebarItem("Receipts & invoices", systemImage: "receipt", .smartFolder("Receipts & invoices"))
                    sidebarItem("Unfinished drafts", systemImage: "pencil", .smartFolder("Unfinished drafts"))
                    if !favorites.paths.isEmpty {
                        ForEach(favorites.paths, id: \.self) { path in
                            let url = URL(fileURLWithPath: path)
                            sidebarItem(url.lastPathComponent, systemImage: "star.fill", .favorite(url))
                        }
                    }
                    if license.isAllowed(.savedSearches) {
                        ForEach(savedSearches.items) { item in
                            sidebarItem(item.name, systemImage: "bookmark", .savedSearch(item.id))
                                .contextMenu {
                                    Button("Delete", role: .destructive) { savedSearches.remove(item.id) }
                                }
                        }
                    }
                }
                Section("Tools") {
                    sidebarItem("Clean Up", systemImage: "trash", .cleanup)
                    sidebarItem("Duplicates", systemImage: "doc.on.doc", .duplicates)
                    sidebarItem("Workspaces", systemImage: "square.grid.2x2", .workspaces)
                    sidebarItem("Compare Folders", systemImage: "arrow.left.arrow.right", .syncCompare)
                    sidebarItem("Extras", systemImage: "wand.and.stars", .extras)
                }
                Section("Places") {
                    if store.pinnedFolderURLs.isEmpty {
                        Text("Pin folders from a file’s context menu.")
                            .font(FileRadarFont.caption())
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.pinnedFolderURLs, id: \.self) { url in
                            sidebarItem(url.lastPathComponent, systemImage: "pin", .pinned(url))
                        }
                    }
                }
                // Keep Drop Stack / disk bar inside the list — NOT safeAreaInset.
                // On this OS, sidebar safeAreaInset was an invisible hit plate over
                // the outline (rows received AX hits but never activated).
                Section {
                    DropStackView()
                    DiskFreeBar()
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("FileRadar")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if let current = playback.current {
                        Button(action: { playback.toggle(current) }) {
                            Label(playback.isPlaying ? "Pause" : "Play",
                                  systemImage: playback.isPlaying ? "pause.fill" : "play.fill")
                        }
                        .help("Play or pause \(current.name)")
                        .accessibilityLabel(playback.isPlaying ? "Pause \(current.name)" : "Play \(current.name)")
                    }
                }
            }
        } detail: {
            VStack(spacing: 0) {
                if let message = license.statusMessage, license.source == .trial {
                    HStack(spacing: 8) {
                        Image(systemName: "clock")
                        Text(message).font(FileRadarFont.caption())
                        Spacer()
                        Button("Unlock") { showLicense = true }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .accessibilityLabel("Unlock")
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.bar)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                if showTabBar {
                    TabBarView(tabState: tabState) { folder in
                        destination = .pinned(folder)
                    }
                }
                ZStack(alignment: .bottom) {
                    VStack(spacing: 0) {
                        if dualPaneEnabled, isFolderDestination {
                            DualPaneView(leftTitle: destination.title,
                                         leftFiles: folderFiles(for: destination),
                                         rightFolder: tabState.secondFolder,
                                         rightFiles: store.files.filter { $0.url.path.hasPrefix(tabState.secondFolder.path) },
                                         activeIsRight: $activeIsRight,
                                         onChooseRightFolder: chooseRightPaneFolder)
                        } else {
                            detailView
                        }
                        if previewStripEnabled {
                            SelectionPreviewStrip(file: selectedFile)
                        }
                    }
                    // HUD is conditional inside; keep the ZStack layer from
                    // eating clicks when no transfer is active.
                    TransferHUDView()
                        .allowsHitTesting(transferQueue.activeCount > 0
                                          || transferQueue.items.contains { $0.status == .failed })
                }
            }
            .inspector(isPresented: $showInspector) {
                if let first = store.files.first(where: { store.selectedIDs.contains($0.id) }) {
                    if store.viewMode == .showcase {
                        ShowcaseInspectorView(file: first)
                    } else {
                        InspectorView(file: first)
                    }
                } else {
                    Text("Select a file to inspect it.").padding()
                }
            }
            .onChange(of: store.viewMode) { _, mode in
                if mode == .showcase, destination == .home {
                    showInspector = true
                }
            }
            .searchable(text: $searchText, placement: .toolbar, prompt: "Search files…")
            .onSubmit(of: .search) {
                if !searchText.isEmpty { destination = .search }
            }
            .onChange(of: searchText) { _, new in
                if !new.isEmpty, destination != .search {
                    destination = .search
                }
            }
            .toolbar { detailToolbar }
        }
        .navigationSplitViewStyle(.balanced)
    }

    /// Tab strip only when tabs exist or the current destination is folder-scoped.
    private var showTabBar: Bool {
        !tabState.tabs.isEmpty || isFolderDestination || dualPaneEnabled
    }

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                theme.cycleAppearance()
            } label: {
                Image(systemName: theme.appearance.systemImage)
            }
            .help("Appearance: \(theme.appearance.rawValue). Click to cycle System / Light / Dark.")
            .accessibilityLabel("Appearance \(theme.appearance.rawValue)")

            Button {
                dualPaneEnabled.toggle()
            } label: {
                Image(systemName: dualPaneEnabled ? "rectangle.split.2x1.fill" : "rectangle.split.2x1")
            }
            .help("Dual-pane mode is optional and off by default.")
            .accessibilityLabel(dualPaneEnabled ? "Single pane" : "Dual pane")

            Menu {
                Picker("View", selection: $store.viewMode) {
                    Label("Grid", systemImage: "square.grid.2x2").tag(FileStore.ViewMode.grid)
                    Label("List", systemImage: "list.bullet").tag(FileStore.ViewMode.list)
                    Label("Columns", systemImage: "rectangle.split.3x1").tag(FileStore.ViewMode.columns)
                    Label("Showcase", systemImage: "rectangle.portrait.on.rectangle.portrait").tag(FileStore.ViewMode.showcase)
                }
            } label: {
                Image(systemName: "square.grid.2x2")
            }
            .help("View mode")
            .accessibilityLabel("View mode")

            Menu {
                Picker("Sort", selection: $store.sort) {
                    ForEach(FileStore.SortOrder.allCases, id: \.self) {
                        Text($0.rawValue.capitalized).tag($0)
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .help("Sort files")
            .accessibilityLabel("Sort files")

            Button {
                showInspector.toggle()
            } label: {
                Image(systemName: showInspector ? "sidebar.trailing" : "sidebar.right")
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .help("Toggle inspector")
            .accessibilityLabel("Inspector")

            Button {
                showTransfers.toggle()
            } label: {
                Image(systemName: transferQueue.activeCount > 0
                      ? "arrow.left.arrow.right.circle.fill"
                      : "arrow.left.arrow.right.circle")
            }
            .help("Transfer queue")
            .popover(isPresented: $showTransfers, arrowEdge: .bottom) {
                TransferQueueView()
                    .frame(width: 320, height: 280)
                    .padding(8)
            }

            Menu {
                Button("Command Palette…") { showPalette = true }
                    .keyboardShortcut("k", modifiers: .command)
                Button("Jump Panes") { activeIsRight.toggle() }
                    .keyboardShortcut(.tab, modifiers: .control)
                    .disabled(!dualPaneEnabled)
                Button(previewStripEnabled ? "Hide Preview Strip" : "Show Preview Strip") {
                    previewStripEnabled.toggle()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Add Folder…") { store.addFolderInteractive() }
                Button("Rename…") { showBatchRename = true }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(store.selectedIDs.isEmpty)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .help("More actions")
        }
    }

    private func bootstrap() {
        // Defer heavy work so the first frame paints and clicks respond.
        if store.files.isEmpty {
            Task { @MainActor in
                await Task.yield()
                store.refreshIndex()
            }
        }
        if !museTokenProviderSet {
            museClient.tokenProvider = { [museAuth] in try await museAuth.validAccessToken() }
            museTokenProviderSet = true
        }
        if museChatViewModel == nil {
            Task { @MainActor in
                await Task.yield()
                guard museChatViewModel == nil else { return }
                museChatViewModel = ChatViewModel(
                    store: store,
                    trash: trash,
                    auth: museAuth,
                    client: museClient,
                    voice: museVoice,
                    isLicensed: { [license] in license.isUnlocked },
                    destination: $destination,
                    contextTitle: destination.title,
                    contextFileNames: museContextFileNames(for: destination))
                museChatViewModel?.updateContext(title: destination.title,
                                                 fileNames: museContextFileNames(for: destination))
            }
        } else {
            museChatViewModel?.updateContext(title: destination.title,
                                             fileNames: museContextFileNames(for: destination))
        }
        Task { @MainActor in
            await Task.yield()
            license.refreshEntitlements()
        }
    }

    private var selectedFiles: [FileItem] {
        store.files.filter { store.selectedIDs.contains($0.id) }
    }

    private var selectedFile: FileItem? { selectedFiles.first }

    private func chooseRightPaneFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Use as right pane"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        tabState.setSecondFolder(folder)
        activeIsRight = true
    }

    private func trashSelected() {
        let items = selectedFiles
        guard !items.isEmpty else { return }
        let moved = trash.trash(items)
        store.removeFiles(matching: Set(moved.map { $0.originalURL.path }))
    }

    private func selectAllVisible() {
        let visible = folderFiles(for: destination)
        let ids: [String] = visible.isEmpty ? store.files.map(\.id) : visible.map(\.id)
        store.selectedIDs = Set(ids)
    }

    @ViewBuilder
    private var detailView: some View {
        switch destination {
        case .home: HomeView(destination: $destination)
        case .search, .savedSearch: SearchView(searchText: $searchText)
        case .cleanup: CleanupView(trash: trash)
        case .duplicates: DuplicatesView(trash: trash)
        case .timeline: TimelineView()
        case .diskMap: DiskMapView(destination: $destination)
        case .extras: ExtrasView()
        case .kind(let kind): FileCollectionView(title: kind.displayName, files: store.files.filter { $0.kind == kind })
        case .source(let name): FileCollectionView(title: name, files: store.files.filter { $0.downloadSource.displayName == name })
        case .smartFolder(let name):
            FileCollectionView(title: name, files: smartFolderFiles(named: name))
        case .pinned(let url), .favorite(let url):
            FileCollectionView(title: url.lastPathComponent,
                               files: store.files.filter { $0.url.path.hasPrefix(url.path) || $0.url.path == url.path },
                               dropTargetFolder: url.hasDirectoryPath ? url : url.deletingLastPathComponent())
        case .workspaces: WorkspacesView(tabState: tabState, dualPaneEnabled: $dualPaneEnabled)
        case .syncCompare: SyncCompareView()
        case .archive(let url): ArchiveBrowserView(archive: url)
        case .muse:
            if let museChatViewModel {
                ChatView(viewModel: museChatViewModel)
            } else {
                Text("Preparing Muse chat…").padding()
            }
        }
    }

    private var isFolderDestination: Bool {
        switch destination {
        case .kind, .pinned, .favorite: return true
        default: return false
        }
    }

    private func folderFiles(for dest: Destination) -> [FileItem] {
        switch dest {
        case .kind(let kind): return store.files.filter { $0.kind == kind }
        case .pinned(let url), .favorite(let url):
            return store.files.filter { $0.url.path.hasPrefix(url.path) || $0.url.path == url.path }
        default: return []
        }
    }

    private func performPalette(_ action: PaletteAction) {
        switch action {
        case .goHome: destination = .home
        case .goSearch: destination = .search
        case .goTimeline: destination = .timeline
        case .goDiskMap: destination = .diskMap
        case .goWorkspaces: destination = .workspaces
        case .goSyncCompare: destination = .syncCompare
        case .toggleDualPane: dualPaneEnabled.toggle()
        case .toggleInspector: showInspector.toggle()
        case .newTab:
            if case .pinned(let url) = destination {
                tabState.addTab(folder: url)
            } else if let folder = tabState.selectedTab?.folder {
                tabState.addTab(folder: folder)
            }
        case .toggleViewMode:
            switch store.viewMode {
            case .grid: store.viewMode = .list
            case .list: store.viewMode = .columns
            case .columns: store.viewMode = .showcase
            case .showcase: store.viewMode = .grid
            }
        case .batchRename:
            showBatchRename = true
        case .quickLookSelection:
            let selected = selectedFiles
            if !selected.isEmpty { QuickLookHelper.shared.show(files: selected) }
        case .togglePreviewStrip:
            previewStripEnabled.toggle()
        }
    }

    private func museContextFileNames(for dest: Destination) -> [String] {
        Array(museContextFiles(for: dest).prefix(50).map(\.name))
    }

    private func museContextFiles(for dest: Destination) -> [FileItem] {
        switch dest {
        case .kind(let kind): return store.files.filter { $0.kind == kind }
        case .source(let name): return store.files.filter { $0.downloadSource.displayName == name }
        case .smartFolder(let name): return smartFolderFiles(named: name)
        case .pinned(let url), .favorite(let url):
            return store.files.filter { $0.url.path.hasPrefix(url.path) || $0.url.path == url.path }
        default: return store.files
        }
    }

    private func smartFolderFiles(named name: String) -> [FileItem] {
        switch name {
        case "Large Files": return store.files.filter { $0.size > 100 * 1_024 * 1_024 }.sorted { $0.size > $1.size }
        case "Screenshots": return store.files.filter { $0.name.lowercased().hasPrefix("screenshot") }
        default:
            return TagService.smartCollections(in: store.files).first { $0.title == name }?.files ?? []
        }
    }
}

// MARK: - Body factoring (keeps the type-checker happy)

private struct ContentSheetsModifier: ViewModifier {
    @Binding var showLicense: Bool
    @Binding var showPalette: Bool
    @Binding var showBatchRename: Bool
    var selectedFiles: [FileItem]
    var onPalette: (PaletteAction) -> Void
    var onRenameApplied: ([(FileItem, URL)]) -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showLicense) { LicenseEntryView() }
            .sheet(isPresented: $showPalette) { CommandPaletteView(onSelect: onPalette) }
            .sheet(isPresented: $showBatchRename) {
                BatchRenameSheet(files: selectedFiles) { plan in onRenameApplied(plan) }
            }
    }
}

private struct ContentNotificationsModifier: ViewModifier {
    @Binding var destination: Destination
    @Binding var searchText: String
    @Binding var showBatchRename: Bool
    @Binding var showPalette: Bool
    @Binding var showLicense: Bool
    @Binding var dualPaneEnabled: Bool
    @Binding var previewStripEnabled: Bool
    var store: FileStore
    var favorites: FavoritesStore
    var trash: TrashService
    var license: LicenseManager
    var onSelectAll: () -> Void
    var onTrashSelection: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .browseArchive)) { note in
                if let url = note.object as? URL { destination = .archive(url) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .showBatchRename)) { _ in
                showBatchRename = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .togglePreviewStrip)) { _ in
                previewStripEnabled.toggle()
            }
            .onReceive(NotificationCenter.default.publisher(for: .showCommandPalette)) { _ in
                showPalette = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleDualPane)) { _ in
                dualPaneEnabled.toggle()
            }
            .onReceive(NotificationCenter.default.publisher(for: .showLicenseSheet)) { _ in
                showLicense = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .pinToSidebar)) { note in
                if let url = note.object as? URL, !store.pinnedFolderURLs.contains(url) {
                    store.pinnedFolderURLs.append(url)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleFavorite)) { note in
                if let url = note.object as? URL { favorites.toggle(url) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .exportParcel)) { note in
                let files: [FileItem]
                if let batch = note.object as? [FileItem] {
                    files = batch
                } else {
                    files = store.files.filter { store.selectedIDs.contains($0.id) }
                }
                guard !files.isEmpty else { return }
                ParcelExportUI.export(files: files, license: license)
            }
            .onReceive(NotificationCenter.default.publisher(for: .moveToTrash)) { note in
                if let file = note.object as? FileItem {
                    let moved = trash.trash([file])
                    store.removeFiles(matching: Set(moved.map { $0.originalURL.path }))
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .applySavedSearch)) { note in
                if let query = note.object as? String {
                    searchText = query
                    destination = .search
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .selectAllVisible)) { _ in
                onSelectAll()
            }
            .onReceive(NotificationCenter.default.publisher(for: .trashSelection)) { _ in
                onTrashSelection()
            }
            .onReceive(NotificationCenter.default.publisher(for: .fileURLDidChange)) { note in
                if let old = note.userInfo?["old"] as? URL,
                   let newURL = note.userInfo?["new"] as? URL {
                    store.updateFileURL(from: old, to: newURL)
                }
            }
    }
}
