import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Shared file grid / list + card + context menu (principles 3, 4, 9)

/// One file, shown big: thumbnail first, chrome second (principle 3).
/// Selection ring, hover dims overlay (opacity only — no layout jitter),
/// and aspect framing by kind.
struct FileCardView: View {
    var file: FileItem
    var size: CGFloat
    @EnvironmentObject var store: FileStore
    @EnvironmentObject var theme: ThemeSettings
    @EnvironmentObject var favorites: FavoritesStore
    @State private var hovering = false

    private var selected: Bool { store.selectedIDs.contains(file.id) }
    private var thumbHeight: CGFloat { size * file.kind.cardAspect }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                AsyncFileThumbnail(file: file, size: CGSize(width: size, height: thumbHeight))
                    .frame(width: size, height: thumbHeight)
                    .clipped()

                // Hover dims overlay — opacity-only so layout never jitters.
                RoundedRectangle(cornerRadius: theme.look.cardCorner, style: .continuous)
                    .fill(Color.black.opacity(hovering && !selected ? 0.22 : 0))
                    .allowsHitTesting(false)

                if hovering, let dims = dimensionsText {
                    Text(dims)
                        .font(FileRadarFont.caption())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(.ultraThinMaterial, in: Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(6)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                if favorites.contains(file.url) {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                        .padding(6)
                }
                if file.isICloudOnly {
                    Label("iCloud only — not downloaded", systemImage: "icloud")
                        .font(FileRadarFont.caption()).padding(4)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(6)
                }
            }
            .frame(width: size, height: thumbHeight)
            .clipShape(RoundedRectangle(cornerRadius: theme.look.cardCorner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: theme.look.cardCorner, style: .continuous)
                    .strokeBorder(selected ? theme.look.accent : Color.clear, lineWidth: FileRadarChrome.selectionStroke)
            )

            Text(file.name).font(FileRadarFont.body()).lineLimit(2)
                .accessibilityLabel(file.name)
            Text("\(file.kind.displayName) · \(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))")
                .font(FileRadarFont.caption()).foregroundStyle(.secondary)
        }
        .frame(width: size, alignment: .leading)
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: theme.look.cardCorner, style: .continuous)
                .fill(selected ? FileRadarChrome.selectionWash(theme.look.accent) : Color.clear)
        )
        .contentShape(Rectangle())
        .animation(FileRadarMotion.selection, value: hovering)
        .animation(FileRadarMotion.selection, value: selected)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint("Double-click to open. Press Space for Quick Look. Right-click for more actions.")
        .contextMenu { fileContextMenu(for: file) }
        .onDrag { NSItemProvider(object: file.url as NSURL) }
    }

    private var dimensionsText: String? {
        var parts: [String] = []
        if let w = file.width, let h = file.height { parts.append("\(w) × \(h)") }
        if let d = file.duration { parts.append("\(Int(d / 60)):\(String(format: "%02d", Int(d) % 60))") }
        if let cam = file.cameraModel { parts.append(cam) }
        parts.append("From \(file.downloadSource.displayName)")
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Full right-click actions. Pin, Favorite, Copy Path, Parcel, Trash.
@ViewBuilder
func fileContextMenu(for file: FileItem) -> some View {
    Button("Quick Look") { QuickLookHelper.shared.show(files: [file]) }
    Button("Open") { NSWorkspace.shared.open(file.url) }
    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
    if ArchiveBrowser.isArchive(file.url) {
        Button("Browse Archive") {
            NotificationCenter.default.post(name: .browseArchive, object: file.url)
        }
    }
    Divider()
    Button("Add to Drop Stack") {
        DropStack.shared.add([file.url])
    }
    Button("Pin to Sidebar") {
        NotificationCenter.default.post(name: .pinToSidebar, object: file.url)
    }
    Button("Toggle Favorite") {
        NotificationCenter.default.post(name: .toggleFavorite, object: file.url)
    }
    Button("Copy") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([file.url as NSURL])
    }
    Button("Copy Path") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(file.url.path, forType: .string)
    }
    Button("Batch Rename Selection…") {
        NotificationCenter.default.post(name: .showBatchRename, object: nil)
    }
    Button("Export Parcel…") {
        NotificationCenter.default.post(name: .exportParcel, object: [file] as [FileItem])
    }
    Divider()
    Button("Move to Trash") {
        NotificationCenter.default.post(name: .moveToTrash, object: file)
    }
}

extension Notification.Name {
    static let pinToSidebar = Notification.Name("FileRadarPinToSidebar")
    static let moveToTrash = Notification.Name("FileRadarMoveToTrash")
    static let browseArchive = Notification.Name("FileRadarBrowseArchive")
    static let showCommandPalette = Notification.Name("FileRadarShowCommandPalette")
    static let toggleDualPane = Notification.Name("FileRadarToggleDualPane")
    static let toggleFavorite = Notification.Name("FileRadarToggleFavorite")
    static let showBatchRename = Notification.Name("FileRadarShowBatchRename")
    static let togglePreviewStrip = Notification.Name("FileRadarTogglePreviewStrip")
    static let selectAllVisible = Notification.Name("FileRadarSelectAllVisible")
    static let trashSelection = Notification.Name("FileRadarTrashSelection")
    static let fileURLDidChange = Notification.Name("FileRadarFileURLDidChange")
    /// Object is optional ChromeView.rawValue String; nil cycles to the next chrome.
    static let setChromeView = Notification.Name("FileRadarSetChromeView")
    /// Snapshot helper: object is `[URL]` left/right pane folders.
    static let pinDemoFoldersForSnapshot = Notification.Name("FileRadarPinDemoFoldersForSnapshot")
}

struct FileCollectionView: View {
    var title: String
    var files: [FileItem]
    var dropTargetFolder: URL?
    /// When true, drops enqueue a copy instead of a move (dual-pane Option mode).
    var preferCopyOnDrop: Bool = false
    /// Dual-pane path bars own the chrome; hide the large collection title.
    var showsHeader: Bool = true
    /// When set, double-clicking a folder navigates in-pane (ForkLift browse).
    var onOpenFolder: ((URL) -> Void)? = nil
    @EnvironmentObject var store: FileStore
    @EnvironmentObject var playback: MusicPlaybackService
    @EnvironmentObject var theme: ThemeSettings
    @State private var dropTargeted = false

    private var sortedFiles: [FileItem] { store.sorted(files) }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.compactDensity ? 6 : 10) {
            if showsHeader {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(FileRadarFont.title())
                    Spacer()
                    if dropTargetFolder != nil {
                        Text(preferCopyOnDrop ? "Drop to copy" : "Drop to move")
                            .font(FileRadarFont.caption())
                            .foregroundStyle(dropTargeted ? AnyShapeStyle(theme.look.accent) : AnyShapeStyle(.secondary))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(
                                Capsule().fill(dropTargeted ? theme.look.accent.opacity(0.14) : Color.clear)
                            )
                    }
                }
                .padding(.horizontal)
            }

            ZStack {
                content
                if dropTargeted, dropTargetFolder != nil {
                    RoundedRectangle(cornerRadius: theme.look.cardCorner, style: .continuous)
                        .strokeBorder(theme.look.accent, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                        .background(
                            RoundedRectangle(cornerRadius: theme.look.cardCorner, style: .continuous)
                                .fill(theme.look.accent.opacity(0.08))
                        )
                        .padding(8)
                        .allowsHitTesting(false)
                        .overlay {
                            Text(preferCopyOnDrop ? "Release to copy" : "Release to move")
                                .font(FileRadarFont.heading())
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        .transition(.opacity)
                }
            }
            .animation(FileRadarMotion.selection, value: dropTargeted)
            .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
                guard let folder = dropTargetFolder else { return false }
                DropUtilities.loadURLs(from: providers) { urls in
                    if preferCopyOnDrop {
                        TransferQueue.shared.enqueueCopy(urls, to: folder)
                    } else {
                        TransferQueue.shared.enqueueMove(urls, to: folder)
                    }
                }
                return true
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if files.isEmpty {
            EmptyStateView(title: "Nothing here yet",
                           message: "Files of this kind will appear here once they are indexed. Nothing has been moved or deleted.")
        } else if store.viewMode == .columns {
            ColumnBrowserView(rootFiles: files)
        } else if store.viewMode == .grid || store.viewMode == .showcase {
            // Showcase is a Home-first layout; elsewhere it keeps a larger grid.
            let minSize = store.viewMode == .showcase ? max(store.cardSize, 180) : store.cardSize
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: minSize), spacing: theme.compactDensity ? 10 : 16)],
                          spacing: theme.compactDensity ? 10 : 16) {
                    ForEach(sortedFiles) { file in
                        FileCardView(file: file, size: minSize)
                            .onTapGesture(count: 2) { handleOpen(file) }
                            .onTapGesture {
                                withAnimation(FileRadarMotion.selection) {
                                    store.selectedIDs = [file.id]
                                }
                            }
                    }
                }.padding()
            }
        } else {
            List(sortedFiles, selection: $store.selectedIDs) { file in
                HStack(spacing: 10) {
                    if file.kind == .image, !file.isICloudOnly {
                        AsyncFileThumbnail(file: file, size: CGSize(width: 28, height: 28))
                    } else {
                        FRKindIcon(kind: file.kind, size: .list)
                    }
                    Text(file.name)
                    Spacer()
                    if file.kind == .folder {
                        FolderSizeText(folder: file.url)
                    } else {
                        Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                            .foregroundStyle(.secondary)
                    }
                    Text(file.modifiedDate, style: .date).foregroundStyle(.secondary)
                }
                .contextMenu { fileContextMenu(for: file) }
                .onTapGesture(count: 2) { handleOpen(file) }
            }
        }
    }

    private func handleOpen(_ file: FileItem) {
        if file.kind == .folder, let onOpenFolder {
            onOpenFolder(file.url)
        } else if file.kind == .audio {
            playback.toggle(file)
        } else {
            NSWorkspace.shared.open(file.url)
        }
    }
}
