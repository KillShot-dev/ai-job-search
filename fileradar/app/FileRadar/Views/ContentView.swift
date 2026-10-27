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
    @State private var activeIsRight = false
    @StateObject private var trash = TrashService()

    var body: some View {
        NavigationSplitView {
            List(selection: $destination) {
                Section("Library") {
                    NavigationLink(value: Destination.home) { Label("Home", systemImage: "house") }
                    NavigationLink(value: Destination.search) { Label("Search", systemImage: "magnifyingglass") }
                    NavigationLink(value: Destination.timeline) { Label("Timeline", systemImage: "calendar") }
                    NavigationLink(value: Destination.diskMap) { Label("Disk Map", systemImage: "square.grid.3x3") }
                    NavigationLink(value: Destination.extras) { Label("Extras", systemImage: "wand.and.stars") }
                    NavigationLink(value: Destination.muse) { Label("Muse", systemImage: "sparkles") }
                }
                Section("Kinds") {
                    ForEach([FileKind.image, .video, .audio, .document, .archive, .app], id: \.self) { kind in
                        NavigationLink(value: Destination.kind(kind)) {
                            Label(kind.displayName, systemImage: kind.systemImage)
                        }
                    }
                }
                if !favorites.paths.isEmpty {
                    Section("Favorites") {
                        ForEach(favorites.paths, id: \.self) { path in
                            let url = URL(fileURLWithPath: path)
                            NavigationLink(value: Destination.favorite(url)) {
                                Label(url.lastPathComponent, systemImage: "star.fill")
                            }
                        }
                    }
                }
                if license.isAllowed(.savedSearches), !savedSearches.items.isEmpty {
                    Section("Saved Searches") {
                        ForEach(savedSearches.items) { item in
                            NavigationLink(value: Destination.savedSearch(item.id)) {
                                Label(item.name, systemImage: "bookmark")
                            }
                            .contextMenu {
                                Button("Delete", role: .destructive) { savedSearches.remove(item.id) }
                            }
                        }
                    }
                }
                Section("Smart Folders") {
                    NavigationLink(value: Destination.smartFolder("Large Files")) { Label("Large Files", systemImage: "doc.fill") }
                    NavigationLink(value: Destination.smartFolder("Screenshots")) { Label("Screenshots", systemImage: "camera") }
                    NavigationLink(value: Destination.smartFolder("Receipts & invoices")) { Label("Receipts & invoices", systemImage: "receipt") }
                    NavigationLink(value: Destination.smartFolder("Unfinished drafts")) { Label("Unfinished drafts", systemImage: "pencil") }
                }
                Section("Clean Up") {
                    NavigationLink(value: Destination.cleanup) { Label("Clean Up", systemImage: "trash") }
                    NavigationLink(value: Destination.duplicates) { Label("Duplicates", systemImage: "doc.on.doc") }
                }
                Section("Workspaces & Compare") {
                    NavigationLink(value: Destination.workspaces) { Label("Workspaces", systemImage: "square.grid.2x2") }
                    NavigationLink(value: Destination.syncCompare) { Label("Compare Folders", systemImage: "arrow.left.arrow.right") }
                }
                Section("Holding & Transfers") {
                    DropStackView()
                    TransferQueueView()
                }
                if !store.pinnedFolderURLs.isEmpty {
                    Section("Pinned") {
                        ForEach(store.pinnedFolderURLs, id: \.self) { url in
                            NavigationLink(value: Destination.pinned(url)) { Label(url.lastPathComponent, systemImage: "pin") }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("FileRadar")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if let current = playback.current {
                        Button(action: { playback.toggle(current) }) {
                            Label(playback.isPlaying ? "Pause" : "Play", systemImage: playback.isPlaying ? "pause.fill" : "play.fill")
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
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.bar)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                TabBarView(tabState: tabState) { folder in
                    destination = .pinned(folder)
                }
                if dualPaneEnabled, isFolderDestination {
                    DualPaneView(leftTitle: destination.title,
                                 leftFiles: folderFiles(for: destination),
                                 rightFolder: tabState.secondFolder,
                                 rightFiles: store.files.filter { $0.url.path.hasPrefix(tabState.secondFolder.path) },
                                 activeIsRight: $activeIsRight)
                } else {
                    detailView
                }
            }
            .inspector(isPresented: $showInspector) {
                if let first = store.files.first(where: { store.selectedIDs.contains($0.id) }) {
                    InspectorView(file: first)
                } else {
                    Text("Select a file to inspect it.").padding()
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button("Inspector") { showInspector.toggle() }
                        .keyboardShortcut("i", modifiers: [.command, .option])
                }
                ToolbarItem(placement: .navigation) {
                    Button("Command Palette…") { showPalette = true }
                        .keyboardShortcut("k", modifiers: .command)
                        .help("Command palette: every action, by keyboard (Cmd-K).")
                }
                ToolbarItem(placement: .navigation) {
                    Button(dualPaneEnabled ? "Single Pane" : "Dual Pane") { dualPaneEnabled.toggle() }
                        .help("Dual-pane mode is optional and off by default.")
                }
                ToolbarItem(placement: .navigation) {
                    Button("Jump Panes") { activeIsRight.toggle() }
                        .keyboardShortcut(.tab, modifiers: .control)
                        .disabled(!dualPaneEnabled)
                }
                ToolbarItem(placement: .navigation) {
                    Picker("Sort", selection: $store.sort) {
                        ForEach(FileStore.SortOrder.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .accessibilityLabel("Sort files")
                }
                ToolbarItem(placement: .navigation) {
                    Picker("View", selection: $store.viewMode) {
                        Text("Grid").tag(FileStore.ViewMode.grid)
                        Text("List").tag(FileStore.ViewMode.list)
                        Text("Columns").tag(FileStore.ViewMode.columns)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Grid, list, or columns")
                }
            }
        }
        .tint(theme.look.accent)
        .sheet(isPresented: $showLicense) { LicenseEntryView() }
        .sheet(isPresented: $showPalette) { CommandPaletteView(onSelect: performPalette) }
        .onReceive(NotificationCenter.default.publisher(for: .browseArchive)) { note in
            if let url = note.object as? URL { destination = .archive(url) }
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
                _ = trash.trash([file])
                store.files.removeAll { $0.id == file.id }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .applySavedSearch)) { note in
            if let query = note.object as? String {
                searchText = query
                destination = .search
            }
        }
        .onAppear {
            if store.files.isEmpty {
                let home = FileManager.default.homeDirectoryForCurrentUser
                store.startIndexing(folders: [home.appendingPathComponent("Downloads"),
                                              home.appendingPathComponent("Documents"),
                                              home.appendingPathComponent("Desktop")])
            }
            if !museTokenProviderSet {
                museClient.tokenProvider = { [museAuth] in try await museAuth.validAccessToken() }
                museTokenProviderSet = true
            }
            if museChatViewModel == nil {
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
            }
            museChatViewModel?.updateContext(title: destination.title,
                                             fileNames: museContextFileNames(for: destination))
            license.refreshEntitlements()
        }
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
            if let first = store.files.first(where: { store.selectedIDs.contains($0.id) }) {
                QuickLookHelper.shared.show(files: [first])
                return .handled
            }
            return .ignored
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch destination {
        case .home: HomeView()
        case .search, .savedSearch: SearchView(searchText: $searchText)
        case .cleanup: CleanupView(trash: trash)
        case .duplicates: DuplicatesView(trash: trash)
        case .timeline: TimelineView()
        case .diskMap: DiskMapView()
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
            case .columns: store.viewMode = .grid
            }
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
