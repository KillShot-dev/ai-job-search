import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Shared file grid / list + card + context menu (principles 3, 4, 9)

/// One file, shown big: thumbnail first, chrome second (principle 3).
/// Thumbnails load through `ThumbnailCache` (async) so big libraries do
/// not stutter on the main thread.
struct FileCardView: View {
    var file: FileItem
    var size: CGFloat
    @EnvironmentObject var store: FileStore
    @EnvironmentObject var theme: ThemeSettings
    @EnvironmentObject var favorites: FavoritesStore
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                AsyncFileThumbnail(file: file, size: CGSize(width: size, height: size * 0.75))
                if favorites.contains(file.url) {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                        .padding(6)
                        .transition(.scale.combined(with: .opacity))
                }
                if file.isICloudOnly {
                    Label("iCloud only — not downloaded", systemImage: "icloud")
                        .font(FileRadarFont.caption()).padding(4)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(6)
                }
            }
            Text(file.name).font(FileRadarFont.body()).lineLimit(2)
                .accessibilityLabel(file.name)
            Text("\(file.kind.displayName) · \(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))")
                .font(FileRadarFont.caption()).foregroundStyle(.secondary)
            if hovering, let dims = dimensionsText {
                Text(dims).font(FileRadarFont.caption()).foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: theme.look.cardCorner, style: .continuous)
                .fill(hovering ? Color.accentColor.opacity(0.06) : Color.clear)
        )
        .animation(FileRadarMotion.selection, value: hovering)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
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
}

struct FileCollectionView: View {
    var title: String
    var files: [FileItem]
    var dropTargetFolder: URL?
    @EnvironmentObject var store: FileStore
    @EnvironmentObject var playback: MusicPlaybackService
    @EnvironmentObject var theme: ThemeSettings

    private var sortedFiles: [FileItem] { store.sorted(files) }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.compactDensity ? 6 : 10) {
            Text(title).font(FileRadarFont.title()).padding(.horizontal)
            if files.isEmpty {
                EmptyStateView(title: "Nothing here yet",
                               message: "Files of this kind will appear here once they are indexed. Nothing has been moved or deleted.")
            } else if store.viewMode == .columns {
                ColumnBrowserView(rootFiles: files)
            } else if store.viewMode == .grid {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: store.cardSize), spacing: theme.compactDensity ? 10 : 16)],
                              spacing: theme.compactDensity ? 10 : 16) {
                        ForEach(sortedFiles) { file in
                            FileCardView(file: file, size: store.cardSize)
                                .onTapGesture(count: 2) { handleOpen(file) }
                                .onTapGesture {
                                    withAnimation(FileRadarMotion.selection) {
                                        store.selectedIDs = [file.id]
                                    }
                                }
                        }
                    }.padding()
                }
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    guard let folder = dropTargetFolder else { return true }
                    DropUtilities.loadURLs(from: providers) { urls in
                        TransferQueue.shared.enqueueMove(urls, to: folder)
                    }
                    return true
                }
            } else {
                List(sortedFiles, selection: $store.selectedIDs) { file in
                    HStack(spacing: 10) {
                        AsyncFileThumbnail(file: file, size: CGSize(width: 28, height: 28))
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
    }

    private func handleOpen(_ file: FileItem) {
        if file.kind == .audio { playback.toggle(file) } else { NSWorkspace.shared.open(file.url) }
    }
}
