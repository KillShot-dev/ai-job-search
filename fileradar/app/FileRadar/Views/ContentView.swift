import SwiftUI
import AppKit

/// Main window. Principle 2: one job per destination.
/// Default launch is dual-pane Browser (ForkLift-primary), not Shelves Home.
enum Destination: Hashable {
    case browser, home, search, cleanup, duplicates, timeline, diskMap, extras, muse
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
        case .browser: return "Browser"
        case .home: return "Shelves"
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
    @State private var destination: Destination = .browser
    @State private var searchText = ""
    @State private var showLicense = false
    /// Inspector optional — dual-pane Browser is the primary composition.
    @State private var showInspector = false
    @State private var showPalette = false
    @StateObject private var tabState = TabState()
    /// New key so Showcase-era `false` defaults do not stick after ForkLift flip.
    @AppStorage("dualPaneEnabled.v3") private var dualPaneEnabled = true
    @AppStorage("previewStripEnabled") private var previewStripEnabled = false
    /// Persisted chrome layout ID (shared with Windows): radarGlass | previewTheater | commandRail | workspaceTabs.
    @AppStorage(ChromeView.storageKey) private var chromeViewRaw = ChromeView.default.rawValue
    @State private var activeIsRight = false
    @State private var showBatchRename = false
    @State private var showTransfers = false
    @State private var inspectorMode: InspectorMode = .activities
    @State private var workspaceChromeTab = "Work"
    @State private var showQueueDrawer = true
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showFolderAccess = false
    @StateObject private var trash = TrashService()
    @ObservedObject private var transferQueue = TransferQueue.shared

    private enum InspectorMode: String, CaseIterable {
        case info = "Info"
        case activities = "Activities"
    }

    private var chromeView: ChromeView {
        ChromeView(rawValue: chromeViewRaw) ?? .radarGlass
    }

    private var chromeAccent: Color { chromeView.accent }

    var body: some View {
        ZStack {
            splitChrome
                .tint(chromeAccent)
                .preferredColorScheme(theme.colorScheme)
                .fileRadarAtmosphere(theme.look)
                // While the consent card is up, chrome must not receive hits
                // (Drop Stack / transfer dock previously sat above the card).
                .allowsHitTesting(!showFolderAccess)
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
                chromeViewRaw: $chromeViewRaw,
                store: store,
                favorites: favorites,
                trash: trash,
                license: license,
                onSelectAll: selectAllVisible,
                onTrashSelection: trashSelected
            ))
            .onAppear(perform: bootstrap)
            .onChange(of: chromeViewRaw) { _, _ in
                applyChromeDefaults()
            }
            .onReceive(NotificationCenter.default.publisher(for: .pinDemoFoldersForSnapshot)) { note in
                guard let urls = note.object as? [URL], urls.count >= 2 else { return }
                tabState.tabs = [TabState.TabItem(folder: urls[0]), TabState.TabItem(folder: urls[1])]
                tabState.selectedID = tabState.tabs.first?.id
                dualPaneEnabled = true
                destination = .browser
                columnVisibility = .all
            }
            .onChange(of: destination) { _, new in
                if new == .home {
                    showInspector = true
                    inspectorMode = .info
                } else if new == .browser {
                    dualPaneEnabled = true
                } else if case .pinned(let url) = new {
                    // Standard-place / pin tags drive folder browse without a Button wrapper.
                    if standardPlaces.contains(where: { $0.path == url.path }) {
                        openStandardPlace(url)
                    } else if FolderAccessConsent.canBrowse(url) {
                        tabState.setFirstFolder(url)
                        dualPaneEnabled = true
                    }
                } else if case .favorite(let url) = new {
                    if FolderAccessConsent.canBrowse(url) {
                        tabState.setFirstFolder(url)
                        dualPaneEnabled = true
                    }
                }
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

            if showFolderAccess {
                // Dimmer is behind the card only — never a transparent plate above buttons.
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .accessibilityHidden(true)

                FolderAccessOnboardingView(
                    onChooseFolders: handleOnboardingChooseFolders,
                    onStartDownloads: handleOnboardingStartDownloads,
                    onSkip: handleOnboardingSkip
                )
                .zIndex(1)
            }
        }
    }

    /// NSOpenPanel over the root overlay (not a SwiftUI sheet). Card stays
    /// until grant succeeds so cancel never leaves the user without an escape.
    private func handleOnboardingChooseFolders() {
        DispatchQueue.main.async {
            if let urls = SecurityBookmarkStore.pickAndStoreFolders(allowsMultiple: true), !urls.isEmpty {
                FolderAccessConsent.completeWithBookmarks(urls)
                showFolderAccess = false
                tabState.seedDefaultsAfterConsent()
                store.refreshIndex()
            }
            // Cancel → card remains; Continue without indexing still available.
        }
    }

    private func handleOnboardingStartDownloads() {
        FolderAccessConsent.completeWithDownloadsOnly()
        showFolderAccess = false
        tabState.seedDefaultsAfterConsent()
        store.refreshIndex()
    }

    private func handleOnboardingSkip() {
        FolderAccessConsent.completeSkipped()
        showFolderAccess = false
    }

    /// Sidebar row via `Label` + `.tag` for `List(selection:)` — no Button /
    /// NavigationLink wrapper (those competed with selection hit-testing).
    @ViewBuilder
    private func sidebarItem(_ title: String, systemImage: String, _ dest: Destination,
                             nav: FRNavGlyph? = nil, place: FRPlaceKind? = nil, kind: FileKind? = nil) -> some View {
        Label {
            Text(title)
        } icon: {
            if let kind {
                FRKindIcon(kind: kind, size: .sidebar)
            } else if let place {
                FRPlaceIcon(place: place, size: .sidebar)
            } else if let nav {
                FRNavIcon(glyph: nav, size: .sidebar, selected: destination == dest, accent: chromeAccent)
            } else {
                Image(systemName: systemImage)
            }
        }
        .tag(dest)
        .contentShape(Rectangle())
        .listRowBackground(destination == dest ? FileRadarChrome.sidebarSelectionWash(chromeAccent) : Color.clear)
        .accessibilityAddTraits(destination == dest ? .isSelected : [])
        .accessibilityLabel(title)
    }

    private var splitChrome: some View {
        Group {
            switch chromeView {
            case .commandRail:
                commandRailChrome
            default:
                navigationSplitChrome
            }
        }
    }

    /// Radar Glass / Preview Theater / Workspace Tabs share NavigationSplitView.
    private var navigationSplitChrome: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ZStack {
                if chromeView == .radarGlass {
                    RadarGlassWatermark(accent: chromeAccent)
                }
                sidebarList
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: chromeView == .previewTheater ? 72 : 200,
                                            ideal: chromeView == .previewTheater ? 88 : 220,
                                            max: chromeView == .previewTheater ? 120 : 280)
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
            detailColumn
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var commandRailChrome: some View {
        HStack(spacing: 0) {
            CommandRailView(
                destination: $destination,
                accent: chromeAccent,
                onBrowser: {
                    destination = .browser
                    dualPaneEnabled = true
                },
                onSearch: { destination = .search },
                onTransfers: { showTransfers = true },
                onSettings: {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
            )
            detailColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var sidebarList: some View {
        List(selection: $destination) {
            if chromeView == .previewTheater {
                Section {
                    sidebarItem("Home", systemImage: "house", .browser, nav: .home)
                    let downloads = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
                    sidebarItem("Downloads", systemImage: "arrow.down.circle", .pinned(downloads), place: .downloads)
                    ForEach([FileKind.image, .audio, .video], id: \.self) { kind in
                        sidebarItem(kind.displayName, systemImage: kind.systemImage, .kind(kind), kind: kind)
                    }
                }
            } else {
                Section("Library") {
                    sidebarItem("Browser", systemImage: "rectangle.split.2x1", .browser, nav: .browser)
                    sidebarItem("Search", systemImage: "magnifyingglass", .search, nav: .search)
                    ForEach(standardPlaces, id: \.path) { place in
                        Label {
                            Text(place.lastPathComponent)
                        } icon: {
                            FRPlaceIcon(place: FRPlaceKind.from(url: place), size: .sidebar)
                        }
                        .tag(Destination.pinned(place))
                        .contentShape(Rectangle())
                        .listRowBackground(
                            (destination == .browser && tabState.firstFolder.path == place.path)
                                || destination == .pinned(place)
                            ? FileRadarChrome.sidebarSelectionWash(chromeAccent) : Color.clear
                        )
                        .accessibilityLabel(place.lastPathComponent)
                    }
                    if !favorites.paths.isEmpty {
                        ForEach(favorites.paths, id: \.self) { path in
                            let url = URL(fileURLWithPath: path)
                            sidebarItem(url.lastPathComponent, systemImage: "star.fill", .favorite(url), place: .favorite)
                        }
                    }
                }
                if chromeView != .workspaceTabs {
                    Section("Shelves") {
                        sidebarItem("Shelves", systemImage: "square.stack", .home, nav: .shelves)
                        sidebarItem("Workspaces", systemImage: "square.grid.2x2", .workspaces, nav: .workspaces)
                    }
                    Section("Smart Views") {
                        sidebarItem("Clean Up", systemImage: "trash", .cleanup, nav: .cleanup)
                        sidebarItem("Duplicates", systemImage: "doc.on.doc", .duplicates, nav: .duplicates)
                        sidebarItem("Compare Folders", systemImage: "arrow.left.arrow.right", .syncCompare, nav: .sync)
                        sidebarItem("Timeline", systemImage: "calendar", .timeline, nav: .timeline)
                        sidebarItem("Disk Map", systemImage: "square.grid.3x3", .diskMap, nav: .diskMap)
                        sidebarItem("Muse", systemImage: "sparkles", .muse, nav: .muse)
                        sidebarItem("Extras", systemImage: "wand.and.stars", .extras, nav: .extras)
                        ForEach([FileKind.image, .video, .audio, .document], id: \.self) { kind in
                            sidebarItem(kind.displayName, systemImage: kind.systemImage, .kind(kind), kind: kind)
                        }
                        if license.isAllowed(.savedSearches) {
                            ForEach(savedSearches.items) { item in
                                sidebarItem(item.name, systemImage: "bookmark", .savedSearch(item.id), nav: .bookmark)
                                    .contextMenu {
                                        Button("Delete", role: .destructive) { savedSearches.remove(item.id) }
                                    }
                            }
                        }
                    }
                    Section("Locations") {
                        if store.pinnedFolderURLs.isEmpty {
                            Text("Pin folders from a file’s context menu.")
                                .font(FileRadarFont.caption())
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(store.pinnedFolderURLs, id: \.self) { url in
                                sidebarItem(url.lastPathComponent, systemImage: "pin", .pinned(url), place: .pin)
                            }
                        }
                        DiskFreeBar()
                    }
                } else {
                    Section("Locations") {
                        ForEach(["Pictures", "Music", "Movies"], id: \.self) { name in
                            let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(name)
                            Label {
                                Text(name)
                            } icon: {
                                FRPlaceIcon(place: FRPlaceKind.from(url: url), size: .sidebar)
                            }
                            .tag(Destination.pinned(url))
                            .contentShape(Rectangle())
                            .accessibilityLabel(name)
                        }
                    }
                    Section("Shelves") {
                        sidebarItem("Shelves", systemImage: "square.stack", .home, nav: .shelves)
                    }
                }
            }
        }
        // Drop Stack / Add Folder sit in a bottom inset with intrinsic height
        // only — never a max-height plate that would swallow sidebar hits.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                if chromeView != .previewTheater {
                    DropStackView()
                        .padding(.horizontal, 10)
                }
                Button {
                    store.addFolderInteractive()
                } label: {
                    Label("Add Folder…", systemImage: "folder.badge.plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .accessibilityLabel("Add Folder")
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.look.chromeMaterial)
        }
    }

    private var detailColumn: some View {
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
            if chromeView == .workspaceTabs {
                WorkspaceChromeTabBar(selected: $workspaceChromeTab, accent: chromeAccent)
            }
            if showTabBar, chromeView != .workspaceTabs {
                TabBarView(tabState: tabState) { folder in
                    tabState.setFirstFolder(folder)
                    destination = .browser
                    dualPaneEnabled = true
                }
            }
            if chromeView == .previewTheater {
                TransferTopStrip(accent: chromeAccent) { showTransfers = true }
            }
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    if showsDualPane {
                        DualPaneView(leftFolder: tabState.firstFolder,
                                     leftFiles: FolderBrowser.children(of: tabState.firstFolder, indexed: store.files),
                                     rightFolder: tabState.secondFolder,
                                     rightFiles: FolderBrowser.children(of: tabState.secondFolder, indexed: store.files),
                                     activeIsRight: $activeIsRight,
                                     onNavigateLeft: { tabState.setFirstFolder($0) },
                                     onNavigateRight: { tabState.setSecondFolder($0) },
                                     onChooseLeftFolder: chooseLeftPaneFolder,
                                     onChooseRightFolder: chooseRightPaneFolder,
                                     onSyncCompare: { destination = .syncCompare },
                                     chromeView: chromeView,
                                     accent: chromeAccent)
                    } else {
                        detailView
                    }
                    if previewStripEnabled, destination != .home, !showsDualPane {
                        SelectionPreviewStrip(file: selectedFile)
                    }
                    if chromeView == .radarGlass {
                        TransferDockedDrawer(accent: chromeAccent) { showTransfers = true }
                    } else if chromeView == .commandRail {
                        CommandKeyboardLegend()
                    } else if chromeView != .previewTheater, chromeView != .workspaceTabs {
                        ActivitiesStripView { showTransfers = true }
                    }
                }
                // Transfer chrome via bottom inset (intrinsic height) — never a
                // full-frame ZStack overlay that can eat detail clicks when idle.
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Group {
                        if chromeView == .commandRail {
                            TransferFloatingPill(accent: chromeAccent)
                        } else if chromeView != .radarGlass,
                                  chromeView != .previewTheater,
                                  chromeView != .workspaceTabs {
                            TransferHUDView()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .allowsHitTesting(transferQueue.activeCount > 0
                                      || transferQueue.items.contains { $0.status == .failed })
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if chromeView == .previewTheater {
                    PreviewTheaterPanel(file: selectedFile, accent: chromeAccent)
                }
                if chromeView == .workspaceTabs, showQueueDrawer {
                    QueueDrawerView(accent: chromeAccent) { showQueueDrawer = false }
                }
            }
        }
        .inspector(isPresented: $showInspector) {
            VStack(spacing: 0) {
                Picker("Inspector", selection: $inspectorMode) {
                    ForEach(InspectorMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(10)
                if inspectorMode == .activities {
                    TransferQueueView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                } else if let first = store.files.first(where: { store.selectedIDs.contains($0.id) }) {
                    if destination == .home || store.viewMode == .showcase {
                        ShowcaseInspectorView(file: first)
                    } else {
                        InspectorView(file: first)
                    }
                } else {
                    Text("Select a file to inspect it.")
                        .font(FileRadarFont.body())
                        .foregroundStyle(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onChange(of: store.viewMode) { _, mode in
            if mode == .showcase, destination == .home {
                showInspector = true
                inspectorMode = .info
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
        .popover(isPresented: $showTransfers, arrowEdge: .bottom) {
            TransferQueueView()
                .frame(width: 320, height: 280)
                .padding(8)
        }
    }

    private var standardPlaces: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return ["Documents", "Downloads", "Desktop"].map { home.appendingPathComponent($0) }
    }

    private func placeIcon(_ url: URL) -> String {
        switch url.lastPathComponent {
        case "Downloads": return "arrow.down.circle"
        case "Desktop": return "desktopcomputer"
        default: return "folder"
        }
    }

    private var showsDualPane: Bool {
        dualPaneEnabled && (destination == .browser || isFolderDestination)
    }

    /// Tab strip when dual-pane Browser or folder destinations are active.
    private var showTabBar: Bool {
        destination == .browser || isFolderDestination || dualPaneEnabled || !tabState.tabs.isEmpty
    }

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                theme.cycleAppearance()
            } label: {
                FRToolbarGlyph(kind: .appearance(theme.appearance), accent: chromeAccent)
            }
            .help("Appearance: \(theme.appearance.rawValue). Click to cycle System / Light / Dark. ⇧⌘L toggles Light/Dark.")
            .accessibilityLabel("Appearance \(theme.appearance.rawValue)")

            Menu {
                Picker("Look", selection: Binding(
                    get: { theme.look },
                    set: { theme.look = $0 }
                )) {
                    ForEach(AppLook.allCases) { look in
                        Label(look.rawValue, systemImage: look.systemImage).tag(look)
                    }
                }
            } label: {
                FRToolbarGlyph(kind: .look(theme.look), accent: chromeAccent)
            }
            .help("Look: \(theme.look.rawValue)")
            .accessibilityLabel("Look \(theme.look.rawValue)")

            Menu {
                Picker("Chrome", selection: $chromeViewRaw) {
                    ForEach(ChromeView.allCases) { chrome in
                        Text("\(chrome.optionLetter) · \(chrome.displayName)").tag(chrome.rawValue)
                    }
                }
            } label: {
                FRChromeGlyph(chrome: chromeView, accent: chromeAccent)
            }
            .help("Chrome layout: \(chromeView.displayName)")
            .accessibilityLabel("Chrome \(chromeView.displayName)")

            Button {
                if dualPaneEnabled {
                    dualPaneEnabled = false
                } else {
                    dualPaneEnabled = true
                    destination = .browser
                }
            } label: {
                FRToolbarGlyph(kind: .dualPane(dualPaneEnabled), accent: chromeAccent)
            }
            .help("Dual-pane Browser is the default. Toggle for single-pane destinations.")
            .accessibilityLabel(dualPaneEnabled ? "Single pane" : "Dual pane")

            Menu {
                Picker("View", selection: $store.viewMode) {
                    Label("List", systemImage: "list.bullet").tag(FileStore.ViewMode.list)
                    Label("Columns", systemImage: "rectangle.split.3x1").tag(FileStore.ViewMode.columns)
                    Label("Grid", systemImage: "square.grid.2x2").tag(FileStore.ViewMode.grid)
                    Label("Showcase", systemImage: "rectangle.portrait.on.rectangle.portrait").tag(FileStore.ViewMode.showcase)
                }
            } label: {
                FRToolbarGlyph(kind: .viewMode(store.viewMode), accent: chromeAccent)
            }
            .help("View mode — list and columns are first-class")
            .accessibilityLabel("View mode")

            Menu {
                Picker("Sort", selection: $store.sort) {
                    ForEach(FileStore.SortOrder.allCases, id: \.self) {
                        Text($0.rawValue.capitalized).tag($0)
                    }
                }
            } label: {
                FRToolbarGlyph(kind: .sort, accent: chromeAccent)
            }
            .help("Sort files")
            .accessibilityLabel("Sort files")

            Button {
                if chromeView == .workspaceTabs {
                    showQueueDrawer.toggle()
                } else {
                    showInspector.toggle()
                    if showInspector { inspectorMode = .activities }
                }
            } label: {
                FRToolbarGlyph(kind: .inspector(showInspector || showQueueDrawer), accent: chromeAccent)
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .help(chromeView == .workspaceTabs ? "Toggle Queue drawer" : "Toggle inspector / Activities")
            .accessibilityLabel(chromeView == .workspaceTabs ? "Queue" : "Inspector")

            Button {
                showTransfers.toggle()
            } label: {
                FRTransferIcon(active: transferQueue.activeCount > 0, accent: chromeAccent)
            }
            .help("Activities / transfer queue")

            Menu {
                Button("Command Palette…") { showPalette = true }
                    .keyboardShortcut("k", modifiers: .command)
                Button("Jump Panes") { activeIsRight.toggle() }
                    .keyboardShortcut(.tab, modifiers: .control)
                    .disabled(!dualPaneEnabled)
                Button("Go to Shelves") { destination = .home }
                Button(previewStripEnabled ? "Hide Preview Strip" : "Show Preview Strip") {
                    previewStripEnabled.toggle()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Add Folder…") { store.addFolderInteractive() }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Add Folder")
                Button("Rename…") { showBatchRename = true }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(store.selectedIDs.isEmpty)
            } label: {
                FRToolbarGlyph(kind: .more, accent: chromeAccent)
            }
            .help("More actions")
        }
    }

    private func applyChromeDefaults() {
        dualPaneEnabled = true
        destination = .browser
        showInspector = false
        showQueueDrawer = chromeView == .workspaceTabs
        if chromeView == .previewTheater {
            // Keep user appearance; theater is light-capable but not forced.
        }
    }

    private func bootstrap() {
        applyChromeDefaults()
        // ForkLift-primary: list density for dual-pane (Showcase stays on Shelves).
        if store.viewMode == .showcase {
            store.viewMode = .list
        }
        // One consent sheet — never fire indexing / open panels in parallel.
        // Prior installs that already have bookmarks skip the sheet once.
        if !FolderAccessConsent.isCompleted, SecurityBookmarkStore.hasStoredFolders() {
            FolderAccessConsent.useDownloadsEntitlement = true
            FolderAccessConsent.isCompleted = true
            tabState.seedDefaultsAfterConsent()
        }
        if !FolderAccessConsent.isCompleted {
            showFolderAccess = true
        } else if store.files.isEmpty {
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

    /// Navigate to a standard place only when already granted; otherwise open
    /// the single consent sheet (never a second stacked open panel at launch).
    private func openStandardPlace(_ place: URL) {
        if FolderAccessConsent.canBrowse(place) {
            tabState.setFirstFolder(place)
            destination = .browser
            dualPaneEnabled = true
            return
        }
        if !FolderAccessConsent.isCompleted {
            showFolderAccess = true
            return
        }
        // User previously consented but this root was not among bookmarks —
        // add it through the shared multi-select panel (one dialog).
        if let folders = SecurityBookmarkStore.pickAndStoreFolders(), !folders.isEmpty {
            tabState.setFirstFolder(folders[0])
            destination = .browser
            dualPaneEnabled = true
            store.refreshIndex()
        }
    }

    private func chooseLeftPaneFolder() {
        // Reuse bookmark-aware picker so grants persist and do not stack with
        // a bare NSOpenPanel that never stores scope.
        guard let folder = SecurityBookmarkStore.pickAndStoreFolder() else { return }
        tabState.setFirstFolder(folder)
        activeIsRight = false
        destination = .browser
        store.refreshIndex()
    }

    private func chooseRightPaneFolder() {
        guard let folder = SecurityBookmarkStore.pickAndStoreFolder() else { return }
        tabState.setSecondFolder(folder)
        activeIsRight = true
        destination = .browser
        store.refreshIndex()
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
        case .browser:
            // Dual-pane owns Browser; fallback if dual-pane was toggled off.
            FileCollectionView(title: tabState.firstFolder.lastPathComponent,
                               files: FolderBrowser.children(of: tabState.firstFolder, indexed: store.files),
                               dropTargetFolder: tabState.firstFolder,
                               onOpenFolder: { tabState.setFirstFolder($0) })
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
                               files: FolderBrowser.children(of: url, indexed: store.files),
                               dropTargetFolder: url.hasDirectoryPath ? url : url.deletingLastPathComponent(),
                               onOpenFolder: { tabState.setFirstFolder($0); destination = .browser; dualPaneEnabled = true })
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
        case .browser, .pinned, .favorite: return true
        default: return false
        }
    }

    private func folderFiles(for dest: Destination) -> [FileItem] {
        switch dest {
        case .browser:
            return FolderBrowser.children(of: tabState.firstFolder, indexed: store.files)
        case .kind(let kind): return store.files.filter { $0.kind == kind }
        case .pinned(let url), .favorite(let url):
            return FolderBrowser.children(of: url, indexed: store.files)
        default: return []
        }
    }

    private func performPalette(_ action: PaletteAction) {
        switch action {
        case .goHome:
            destination = .browser
            dualPaneEnabled = true
        case .goSearch: destination = .search
        case .goTimeline: destination = .timeline
        case .goDiskMap: destination = .diskMap
        case .goWorkspaces: destination = .workspaces
        case .goSyncCompare: destination = .syncCompare
        case .toggleDualPane:
            dualPaneEnabled.toggle()
            if dualPaneEnabled { destination = .browser }
        case .toggleInspector: showInspector.toggle()
        case .newTab:
            if case .pinned(let url) = destination {
                tabState.addTab(folder: url)
            } else if let folder = tabState.selectedTab?.folder {
                tabState.addTab(folder: folder)
            }
        case .toggleViewMode:
            switch store.viewMode {
            case .list: store.viewMode = .columns
            case .columns: store.viewMode = .grid
            case .grid: store.viewMode = .showcase
            case .showcase: store.viewMode = .list
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
    @Binding var chromeViewRaw: String
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
            .onReceive(NotificationCenter.default.publisher(for: .setChromeView)) { note in
                if let raw = note.object as? String, ChromeView(rawValue: raw) != nil {
                    chromeViewRaw = raw
                } else {
                    let all = ChromeView.allCases
                    let current = ChromeView(rawValue: chromeViewRaw) ?? .radarGlass
                    let idx = all.firstIndex(of: current) ?? 0
                    chromeViewRaw = all[(idx + 1) % all.count].rawValue
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleDualPane)) { _ in
                dualPaneEnabled.toggle()
                if dualPaneEnabled { destination = .browser }
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
