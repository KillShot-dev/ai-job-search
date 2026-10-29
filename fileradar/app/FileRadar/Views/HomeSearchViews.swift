import SwiftUI
import AppKit

// MARK: - Home (principle 2: shelves + recents, one job)

/// Home is always the mockup Showcase layout (shelves album cards + Recents +
/// inspector elsewhere). Grid / List / Columns still apply to other destinations.
struct HomeView: View {
    @Binding var destination: Destination

    var body: some View {
        ShowcaseHomeView(destination: $destination)
    }
}

// MARK: - Showcase Home (Cmd-4): mockup-style shelves + recents, real data

private enum ShowcaseRecentsLayout: String, CaseIterable {
    case grid, list
}

struct ShowcaseHomeView: View {
    @Binding var destination: Destination
    @EnvironmentObject var store: FileStore
    @EnvironmentObject var theme: ThemeSettings
    @EnvironmentObject var favorites: FavoritesStore
    @EnvironmentObject var license: LicenseManager
    @State private var recentsLayout: ShowcaseRecentsLayout = .grid
    @State private var showLicense = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FileRadarChrome.spaceSection) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("> Home")
                        .font(FileRadarFont.caption())
                        .foregroundStyle(.secondary)
                    Text("Home").font(FileRadarFont.title())
                    if store.isIndexing {
                        Label("Indexing your files in the background…", systemImage: "arrow.triangle.2.circlepath")
                            .font(FileRadarFont.caption()).foregroundStyle(.secondary)
                    }
                    homeLookAppearancePills
                }

                shelvesSection
                smartCollectionsBento
                recentsSection

                if !license.isUnlocked {
                    Button(DistributionChannel.current == .macAppStore
                           ? "Unlock the full version"
                           : "Enter serial number to unlock the full version") {
                        showLicense = true
                    }
                        .buttonStyle(.bordered)
                }
            }
            .padding(FileRadarChrome.spacePage)
        }
        .sheet(isPresented: $showLicense) { LicenseEntryView() }
    }

    private var homeLookAppearancePills: some View {
        HStack(spacing: 8) {
            ForEach(AppLook.allCases) { look in
                Button {
                    theme.look = look
                } label: {
                    Text(look.rawValue)
                        .font(FileRadarFont.caption())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(theme.look == look
                                           ? theme.look.accent.opacity(0.18)
                                           : Color.primary.opacity(0.06))
                        )
                        .overlay(
                            Capsule().strokeBorder(
                                theme.look == look ? theme.look.accent.opacity(0.55) : Color.clear,
                                lineWidth: 1
                            )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Look \(look.rawValue)")
                .accessibilityAddTraits(theme.look == look ? .isSelected : [])
            }
            Divider().frame(height: 16)
            ForEach(AppearanceMode.allCases) { mode in
                Button {
                    theme.appearance = mode
                } label: {
                    Image(systemName: mode.systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .padding(6)
                        .background(
                            Circle().fill(theme.appearance == mode
                                          ? theme.look.accent.opacity(0.18)
                                          : Color.primary.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
                .help(mode.rawValue)
                .accessibilityLabel("Appearance \(mode.rawValue)")
                .accessibilityAddTraits(theme.appearance == mode ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 6)
    }

    private var shelvesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Shelves").font(FileRadarFont.heading())
                    Text("Curated groups of your files")
                        .font(FileRadarFont.caption())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Edit Shelves") {
                    // Shelves are kind-derived; open Kinds via Images.
                    destination = .kind(.image)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Shelves map to kinds. Open a kind shelf to browse.")
            }

            if kindShelves.isEmpty {
                EmptyStateView(title: "No shelves yet",
                               message: "Once FileRadar indexes your folders, kind shelves appear here as album cards.")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: FileRadarChrome.spaceCardGap) {
                        ForEach(kindShelves) { album in
                            ShelfAlbumCard(album: album)
                                .onTapGesture {
                                    withAnimation(FileRadarMotion.panel) {
                                        destination = album.destination
                                    }
                                }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var smartCollectionsBento: some View {
        let cols = TagService.smartCollections(in: store.files).filter { !$0.files.isEmpty }
        return Group {
            if !cols.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Smart Collections").font(FileRadarFont.heading())
                        Text("On-device groups from tags and OCR")
                            .font(FileRadarFont.caption())
                            .foregroundStyle(.secondary)
                    }
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 160), spacing: FileRadarChrome.spaceCardGap)],
                        spacing: FileRadarChrome.spaceCardGap
                    ) {
                        ForEach(Array(cols.enumerated()), id: \.offset) { _, col in
                            Button {
                                withAnimation(FileRadarMotion.panel) {
                                    destination = .smartFolder(col.title)
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: theme.look.cardCorner, style: .continuous)
                                            .fill(theme.look.accent.opacity(0.12))
                                        if let cover = col.files.first(where: { $0.kind == .image && !$0.isICloudOnly })
                                            ?? col.files.first {
                                            AsyncFileThumbnailView(file: cover, size: CGSize(width: 160, height: 100))
                                        } else {
                                            Image(systemName: "sparkles.rectangle.stack")
                                                .font(.system(size: 28, weight: .medium))
                                                .foregroundStyle(theme.look.accent)
                                        }
                                    }
                                    .frame(height: 100)
                                    .clipShape(RoundedRectangle(cornerRadius: theme.look.cardCorner, style: .continuous))
                                    Text(col.title).font(FileRadarFont.body()).lineLimit(1)
                                    Text("\(col.files.count) file\(col.files.count == 1 ? "" : "s")")
                                        .font(FileRadarFont.caption())
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recents").font(FileRadarFont.heading())
                    Text("Recently accessed files")
                        .font(FileRadarFont.caption())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Recents layout", selection: $recentsLayout) {
                    Image(systemName: "square.grid.2x2").tag(ShowcaseRecentsLayout.grid)
                    Image(systemName: "list.bullet").tag(ShowcaseRecentsLayout.list)
                }
                .pickerStyle(.segmented)
                .frame(width: 88)
                .accessibilityLabel("Recents grid or list")

                Picker("Sort", selection: $store.sort) {
                    ForEach(FileStore.SortOrder.allCases, id: \.self) {
                        Text($0.rawValue.capitalized).tag($0)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 110)
            }

            let recentFiles = store.sorted(Array(store.recents.prefix(24)))
            if recentFiles.isEmpty {
                EmptyStateView(title: "No recent files yet",
                               message: "Once FileRadar finishes its first background index, your newest files will live here.")
            } else if recentsLayout == .grid {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 168), spacing: FileRadarChrome.spaceCardGap)],
                    spacing: FileRadarChrome.spaceCardGap
                ) {
                    ForEach(recentFiles) { file in
                        ShowcaseRecentCard(file: file)
                            .onTapGesture {
                                withAnimation(FileRadarMotion.selection) {
                                    store.selectedIDs = [file.id]
                                }
                            }
                            .onTapGesture(count: 2) { NSWorkspace.shared.open(file.url) }
                    }
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(recentFiles) { file in
                        ShowcaseRecentRow(file: file)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(FileRadarMotion.selection) {
                                    store.selectedIDs = [file.id]
                                }
                            }
                            .onTapGesture(count: 2) { NSWorkspace.shared.open(file.url) }
                        Divider().opacity(0.35)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: theme.look.cardCorner, style: .continuous)
                        .fill(FileRadarChrome.chromeBarFill)
                )
            }
        }
    }

    /// Kind shelves + favorites as album cards. Smart Collections use the
    /// separate bento grid below.
    private var kindShelves: [ShelfAlbum] {
        var albums: [ShelfAlbum] = []
        for (kind, files) in store.shelves {
            let count = store.files.filter { $0.kind == kind }.count
            let cover = files.first(where: { $0.kind == .image && !$0.isICloudOnly }) ?? files.first
            albums.append(ShelfAlbum(
                id: "kind-\(kind.rawValue)",
                title: kind.displayName,
                subtitle: count == 0
                    ? "Empty shelf"
                    : "\(count) file\(count == 1 ? "" : "s")",
                cover: cover,
                systemImage: kind.systemImage,
                destination: .kind(kind)
            ))
        }
        if !favorites.paths.isEmpty {
            let favFiles = store.files.filter { favorites.paths.contains($0.url.path) }
            if !favFiles.isEmpty {
                albums.append(ShelfAlbum(
                    id: "favorites",
                    title: "Favorites",
                    subtitle: "\(favFiles.count) file\(favFiles.count == 1 ? "" : "s")",
                    cover: favFiles.first(where: { $0.kind == .image && !$0.isICloudOnly }) ?? favFiles.first,
                    systemImage: "star.fill",
                    destination: .favorite(URL(fileURLWithPath: favorites.paths[0]))
                ))
            }
        }
        return albums
    }
}

struct ShelfAlbum: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let cover: FileItem?
    let systemImage: String
    let destination: Destination
}

struct ShelfAlbumCard: View {
    var album: ShelfAlbum
    @EnvironmentObject var theme: ThemeSettings
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: theme.look.cardCorner, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                if let cover = album.cover {
                    AsyncFileThumbnail(file: cover, size: CGSize(width: 200, height: 140))
                } else {
                    Image(systemName: album.systemImage)
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 200, height: 140)
            .clipShape(RoundedRectangle(cornerRadius: theme.look.cardCorner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: theme.look.cardCorner, style: .continuous)
                    .strokeBorder(FileRadarChrome.hairline.opacity(hovering ? 1.6 : 0.6), lineWidth: 1)
            )
            .shadow(color: FileRadarChrome.hudShadow.opacity(hovering ? 0.7 : 0.35), radius: hovering ? 8 : 4, y: 3)

            Text(album.title).font(FileRadarFont.body()).lineLimit(1)
            Text(album.subtitle).font(FileRadarFont.caption()).foregroundStyle(.secondary)
        }
        .frame(width: 200, alignment: .leading)
        .scaleEffect(hovering ? 1.015 : 1)
        .animation(FileRadarMotion.selection, value: hovering)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(album.title), \(album.subtitle)")
        .accessibilityHint("Opens this shelf.")
    }
}

struct ShowcaseRecentCard: View {
    var file: FileItem
    @EnvironmentObject var store: FileStore
    @EnvironmentObject var theme: ThemeSettings
    @State private var hovering = false

    private var selected: Bool { store.selectedIDs.contains(file.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncFileThumbnail(file: file, size: CGSize(width: 200, height: 140))
                .frame(maxWidth: .infinity)
                .frame(height: 140)
                .clipShape(RoundedRectangle(cornerRadius: theme.look.cardCorner, style: .continuous))
            Text(file.name).font(FileRadarFont.body()).lineLimit(2)
            Text(file.modifiedDate.formatted(date: .abbreviated, time: .shortened))
                .font(FileRadarFont.caption())
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: theme.look.cardCorner, style: .continuous)
                .fill(selected || hovering
                      ? FileRadarChrome.selectionWash(theme.look.accent)
                      : FileRadarChrome.chromeBarFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: theme.look.cardCorner, style: .continuous)
                .strokeBorder(
                    selected ? theme.look.accent : Color.clear,
                    lineWidth: FileRadarChrome.selectionStroke
                )
        )
        .animation(FileRadarMotion.selection, value: hovering)
        .animation(FileRadarMotion.selection, value: selected)
        .onHover { hovering = $0 }
        .contextMenu { fileContextMenu(for: file) }
        .onDrag { NSItemProvider(object: file.url as NSURL) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(file.name), \(file.modifiedDate.formatted())")
    }
}

struct ShowcaseRecentRow: View {
    var file: FileItem
    @EnvironmentObject var store: FileStore
    @EnvironmentObject var theme: ThemeSettings

    private var selected: Bool { store.selectedIDs.contains(file.id) }

    var body: some View {
        HStack(spacing: 12) {
            AsyncFileThumbnail(file: file, size: CGSize(width: 44, height: 44))
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name).font(FileRadarFont.body()).lineLimit(1)
                Text(file.modifiedDate.formatted(date: .abbreviated, time: .shortened))
                    .font(FileRadarFont.caption()).foregroundStyle(.secondary)
            }
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                .font(FileRadarFont.caption()).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(selected ? FileRadarChrome.selectionWash(theme.look.accent) : Color.clear)
        .contextMenu { fileContextMenu(for: file) }
    }
}

/// Rich inspector used in Showcase mode — preview-first, calm EXIF/tags, Finder.
/// Secondary depth uses Path Finder–style disclosure modules so the first
/// screenful stays mockup-calm (unified look §2.7).
struct ShowcaseInspectorView: View {
    var file: FileItem
    @EnvironmentObject var license: LicenseManager
    @EnvironmentObject var theme: ThemeSettings
    @EnvironmentObject var tags: ManualTagStore
    @AppStorage("gitBadgesEnabled") private var gitBadgesEnabled = false
    @State private var showLicense = false
    @State private var detailsExpanded = true
    @State private var tagsExpanded = true
    @State private var moreExpanded = false
    @State private var gitBadge: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FileRadarChrome.spaceCardGap) {
                HStack {
                    Spacer()
                    ShareLink(item: file.url) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .help("Share")
                    .accessibilityLabel("Share")
                    Menu {
                        Button("Copy Path") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(file.url.path, forType: .string)
                        }
                        Button("Quick Look") {
                            QuickLookHelper.shared.show(files: [file])
                        }
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([file.url])
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .help("More")
                    .accessibilityLabel("More actions")
                }

                AsyncFileThumbnail(file: file, size: CGSize(width: 320, height: 220))
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: theme.look.cardCorner, style: .continuous))
                    .background(theme.look.chromeMaterial,
                                in: RoundedRectangle(cornerRadius: theme.look.cardCorner, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(file.name).font(FileRadarFont.heading()).textSelection(.enabled)
                    Text(file.modifiedDate.formatted(date: .abbreviated, time: .shortened))
                        .font(FileRadarFont.caption())
                        .foregroundStyle(.secondary)
                }

                DisclosureGroup("Info", isExpanded: $detailsExpanded) {
                    VStack(spacing: 8) {
                        showcaseRow("Dimensions", dimensionsText)
                        showcaseRow("File Size", ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                        if let cam = file.cameraModel { showcaseRow("Camera", cam) }
                        showcaseRow("Kind", file.kind.displayName)
                        showcaseRow("Downloaded from", file.downloadSource.displayName)
                    }
                    .padding(.top, 6)
                }
                .font(FileRadarFont.heading())

                DisclosureGroup("Tags", isExpanded: $tagsExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        let allTags = file.tags.map(\.name) + tags.tags(for: file.url.path).map(\.name)
                        if allTags.isEmpty {
                            Text("No tags yet.")
                                .font(FileRadarFont.caption())
                                .foregroundStyle(.secondary)
                        } else {
                            FlowTagRow(names: allTags)
                        }
                        ManualTagEditor(file: file)
                    }
                    .padding(.top, 6)
                }
                .font(FileRadarFont.heading())

                DisclosureGroup("More", isExpanded: $moreExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        if let permissions = permissionText {
                            Text(permissions).font(FileRadarFont.caption()).foregroundStyle(.secondary)
                        }
                        if let ocr = file.ocrText, !ocr.isEmpty {
                            Text(ocr).font(FileRadarFont.caption()).lineLimit(6)
                        }
                        if gitBadgesEnabled {
                            Text(gitBadge.map { "Git: \($0) (read-only)" } ?? "No Git status for this file.")
                                .font(FileRadarFont.caption())
                                .foregroundStyle(.secondary)
                        }
                        if file.isICloudOnly {
                            Label("iCloud only — FileRadar will not download this file.", systemImage: "icloud")
                                .font(FileRadarFont.caption())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 6)
                }
                .font(FileRadarFont.heading())

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([file.url])
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.look.accent)
                .controlSize(.large)
            }
            .padding(FileRadarChrome.spaceCardGap)
        }
        .background(theme.look.chromeMaterial)
        .sheet(isPresented: $showLicense) { LicenseEntryView() }
        .task(id: file.url) {
            guard gitBadgesEnabled else { gitBadge = nil; return }
            gitBadge = await GitStatusService.badge(for: file.url)
        }
    }

    private var permissionText: String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.url.path) else { return nil }
        var parts: [String] = []
        if let perms = attributes[.posixPermissions] as? NSNumber {
            parts.append("Permissions: \(String(perms.intValue, radix: 8))")
        }
        if let owner = attributes[.ownerAccountName] as? String {
            parts.append("Owner: \(owner)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var dimensionsText: String {
        if let w = file.width, let h = file.height { return "\(w) × \(h)" }
        return "—"
    }

    private func showcaseRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(FileRadarFont.body()).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(FileRadarFont.body()).multilineTextAlignment(.trailing)
        }
    }
}

private struct FlowTagRow: View {
    var names: [String]

    var body: some View {
        // Simple wrapping via LazyVGrid keeps dependencies light.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(names, id: \.self) { name in
                Text(name)
                    .font(FileRadarFont.caption())
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Color.accentColor.opacity(0.14)))
            }
        }
    }
}

/// Sidebar disk free indicator (mockup Macintosh HD bar).
struct DiskFreeBar: View {
    @EnvironmentObject var theme: ThemeSettings
    @State private var free: Int64 = 0
    @State private var total: Int64 = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ZStack {
                    FRIconTile(size: 22,
                               top: Color(red: 0.55, green: 0.72, blue: 0.95),
                               bottom: Color(red: 0.22, green: 0.35, blue: 0.62),
                               corner: 6)
                    Image(systemName: "internaldrive.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Text(volumeName).font(FileRadarFont.caption())
                Spacer()
            }
            Text(capacityLabel)
                .font(FileRadarFont.caption())
                .foregroundStyle(.secondary)
            ProgressView(value: usedFraction)
                .tint(theme.look.accent)
                .accessibilityLabel("Disk used")
                .accessibilityValue("\(Int(usedFraction * 100)) percent")
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: theme.look.cardCorner, style: .continuous)
                .fill(FileRadarChrome.cardFill)
        )
        .onAppear(perform: refresh)
    }

    private var volumeName: String {
        FileManager.default.displayName(atPath: "/")
    }

    private var capacityLabel: String {
        guard total > 0 else { return "Disk capacity unavailable" }
        let freeText = ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
        let totalText = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
        return "\(freeText) free of \(totalText)"
    }

    private var usedFraction: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(total - free) / Double(total)))
    }

    private func refresh() {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        if let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]) {
            free = Int64(values.volumeAvailableCapacityForImportantUsage ?? 0)
            total = Int64(values.volumeTotalCapacity ?? 0)
        }
    }
}

// MARK: - Search (principle 5 + 6: chips animate in, read like sentences)

struct SearchView: View {
    @Binding var searchText: String
    @EnvironmentObject var store: FileStore
    @EnvironmentObject var license: LicenseManager
    @State private var parsed = ParsedQuery(chips: [], freeText: "")
    @State private var showSave = false
    @State private var showLicense = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                TextField("Search in plain words — try “images from last week over 100 MB”", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .font(FileRadarFont.body())
                    .accessibilityLabel("Search files")
                    .onChange(of: searchText) { _, new in
                        withAnimation(FileRadarMotion.chip) { parsed = SearchQueryParser.parse(new) }
                    }
                if !searchText.isEmpty {
                    Button("Save") {
                        if license.isAllowed(.savedSearches) { showSave = true }
                        else { showLicense = true }
                    }
                    .help(license.isUnlocked ? "Save this search" : "Saved searches are a full-version feature.")
                }
            }
            .padding(.horizontal)
            if !parsed.chips.isEmpty {
                HStack(spacing: 8) {
                    ForEach(parsed.chips) { chip in
                        Text(chip.sentence)
                            .font(FileRadarFont.caption())
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                            .transition(.move(edge: .leading).combined(with: .opacity))
                            .accessibilityLabel("Filter: \(chip.sentence)")
                    }
                    Spacer()
                }.padding(.horizontal)
                if !parsed.sentence.isEmpty {
                    Text(parsed.sentence).font(FileRadarFont.caption()).foregroundStyle(.secondary).padding(.horizontal)
                }
            }
            let results = store.search(parsed)
            if searchText.isEmpty {
                EmptyStateView(title: "Search everything, in plain words",
                               message: "Type a kind, a time, a size, or a source. FileRadar turns it into filters you can see — and searches file names, tags, and text inside files.")
            } else if results.isEmpty {
                EmptyStateView(title: "No files match",
                               message: "Try fewer words, or a different time or size. Nothing was changed or deleted.")
            } else {
                FileCollectionView(title: "\(results.count) result\(results.count == 1 ? "" : "s")", files: results)
            }
        }
        .sheet(isPresented: $showSave) { SaveSearchSheet(query: searchText) }
        .sheet(isPresented: $showLicense) { LicenseEntryView() }
    }
}

// MARK: - Shared empty state (principle 8: kind empty states)

struct EmptyStateView: View {
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                FRIconTile(size: 64,
                           top: Color(red: 0.55, green: 0.78, blue: 1.0),
                           bottom: Color(red: 0.18, green: 0.42, blue: 0.88),
                           corner: 18)
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                Image(systemName: "sparkle")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.yellow)
                    .offset(x: 18, y: -18)
            }
            Text(title).font(FileRadarFont.heading())
            Text(message).font(FileRadarFont.body()).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Inspector (principle 3: hover inspector + full detail pane)
//
// Iteration 1: modular inspector — Preview, Info, Tags, and Permissions
// as collapsible modules in one inspector, replacing the previous flat
// section list. All previous detail content is kept (dimensions,
// duration, camera, download source, tags with explanations, recognised
// text with its paid-gated copy-all). Permissions is read-only display
// in this build; editing permissions is not built. The optional Git
// module appears only when Git badges are opted in (Settings, off by
// default) and is read-only.

struct InspectorView: View {
    var file: FileItem
    @EnvironmentObject var license: LicenseManager
    @AppStorage("gitBadgesEnabled") private var gitBadgesEnabled = false
    @State private var showLicense = false
    @State private var copied = false
    @State private var gitBadge: String?
    @State private var previewExpanded = true
    @State private var infoExpanded = true
    @State private var tagsExpanded = true
    @State private var permissionsExpanded = false
    @State private var gitExpanded = false

    var body: some View {
        Form {
            DisclosureGroup("Preview", isExpanded: $previewExpanded) {
                AsyncFileThumbnail(file: file, size: CGSize(width: 280, height: 180))
                    .frame(maxHeight: 220)
                if file.isICloudOnly {
                    Label("iCloud only — FileRadar will not download this file.", systemImage: "icloud")
                        .font(FileRadarFont.caption())
                }
            }
            DisclosureGroup("Info", isExpanded: $infoExpanded) {
                LabeledContent("Name", value: file.name)
                LabeledContent("Kind", value: file.kind.displayName)
                LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                LabeledContent("Modified", value: file.modifiedDate.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Added", value: file.createdDate.formatted(date: .abbreviated, time: .shortened))
                if let w = file.width, let h = file.height { LabeledContent("Dimensions", value: "\(w) × \(h)") }
                if let d = file.duration { LabeledContent("Duration", value: "\(Int(d / 60)):\(String(format: "%02d", Int(d) % 60))") }
                if let cam = file.cameraModel { LabeledContent("Camera", value: cam) }
                LabeledContent("Downloaded from", value: file.downloadSource.displayName)
            }
            DisclosureGroup("Tags", isExpanded: $tagsExpanded) {
                if file.tags.isEmpty {
                    Text("No automatic tags yet.").foregroundStyle(.secondary)
                }
                ForEach(file.tags) { tag in
                    VStack(alignment: .leading) {
                        Text(tag.name)
                        if let explanation = tag.explanation {
                            Text(explanation).font(FileRadarFont.caption()).foregroundStyle(.secondary)
                        }
                    }
                }
                Divider()
                Text("Your tags").font(FileRadarFont.caption()).foregroundStyle(.secondary)
                ManualTagEditor(file: file)
            }
            DisclosureGroup("Permissions", isExpanded: $permissionsExpanded) {
                if let permissions = permissionText {
                    Text(permissions).font(FileRadarFont.body())
                } else {
                    Text("Permissions could not be read for this file.").foregroundStyle(.secondary)
                }
                Text("Shown read-only in this build; changing permissions is not offered here.")
                    .font(FileRadarFont.caption()).foregroundStyle(.secondary)
            }
            if gitBadgesEnabled {
                DisclosureGroup("Git status", isExpanded: $gitExpanded) {
                    if let badge = gitBadge {
                        Text("Status: \(badge) — read-only; FileRadar never stages, commits, or resets.")
                            .font(FileRadarFont.body())
                    } else {
                        Text("Not in a Git working copy, or no changes for this file.")
                            .font(FileRadarFont.caption()).foregroundStyle(.secondary)
                    }
                }
                .task(id: file.url) { gitBadge = await GitStatusService.badge(for: file.url) }
            }
            if let ocr = file.ocrText, !ocr.isEmpty {
                Section("Text in this file") {
                    Text(ocr).font(FileRadarFont.body()).lineLimit(10)
                    Button(copied ? "Copied" : "Copy all recognised text") {
                        if license.isAllowed(.ocrCopyAll) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(ocr, forType: .string)
                            copied = true
                        } else { showLicense = true }
                    }
                    .help(license.isUnlocked ? "Copy the recognised text" : "Copy all recognised text is a full-version feature.")
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showLicense) { LicenseEntryView() }
    }

    private var permissionText: String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.url.path) else { return nil }
        var parts: [String] = []
        if let perms = attributes[.posixPermissions] as? NSNumber {
            parts.append("Permissions: \(String(perms.intValue, radix: 8))")
        }
        if let owner = attributes[.ownerAccountName] as? String {
            parts.append("Owner: \(owner)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
