import SwiftUI
import AppKit

// MARK: - Chrome helpers (docs/fileradar-chrome-views.md)
//
// Four persisted layouts share dual-pane browsing; only chrome around the
// panes changes. IDs match Windows: radarGlass | previewTheater | commandRail | workspaceTabs.

/// Concentric radar rings behind the Radar Glass sidebar.
struct RadarGlassWatermark: View {
    var accent: Color

    var body: some View {
        // GeometryReader fills the sidebar ZStack — disable hit-testing on the
        // reader itself, not only its circles, or gaps in the List fall through
        // to a hit-absorbing empty GeometryReader.
        GeometryReader { geo in
            let side = max(geo.size.width, geo.size.height) * 1.6
            ZStack {
                ForEach(0..<5, id: \.self) { i in
                    Circle()
                        .strokeBorder(accent.opacity(0.07 - Double(i) * 0.01), lineWidth: 1)
                        .frame(width: side * (0.25 + Double(i) * 0.18),
                               height: side * (0.25 + Double(i) * 0.18))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
            .offset(x: -geo.size.width * 0.55)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Pill-style path crumbs used by Radar Glass.
struct PillPathBarView: View {
    var folder: URL
    var isActive: Bool
    var itemCount: Int
    var onNavigate: (URL) -> Void
    var onChooseFolder: () -> Void
    var accent: Color
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
        return urls.reversed().suffix(3).map { url in
            if url.path == home.path { return ("Home", url) }
            let name = url.lastPathComponent
            return (name.isEmpty ? url.path : name, url)
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onChooseFolder) {
                Image(systemName: "house")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(isActive ? accent : .secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(crumbs.enumerated()), id: \.offset) { _, crumb in
                        Button(crumb.0) { onNavigate(crumb.1) }
                            .buttonStyle(.plain)
                            .font(FileRadarFont.caption())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(isActive ? accent.opacity(0.14) : Color.primary.opacity(0.05))
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(isActive ? accent.opacity(0.45) : FileRadarChrome.hairline,
                                                  lineWidth: 1)
                            )
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 4)
            Text("\(itemCount)")
                .font(FileRadarFont.caption())
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }
}

/// Docked bottom transfer drawer (Radar Glass) — always anchored, not floating.
struct TransferDockedDrawer: View {
    @ObservedObject var queue = TransferQueue.shared
    var accent: Color
    var onOpenQueue: () -> Void

    private var headline: String {
        let n = max(queue.activeCount, 1)
        if queue.isPaused { return "Paused · \(n) item\(n == 1 ? "" : "s")" }
        let verb = queue.items.contains(where: { $0.title.lowercased().contains("copy") }) ? "Copying" : "Moving"
        if queue.activeCount == 0 { return "Transfers · Idle" }
        return "\(verb) \(n) item\(n == 1 ? "" : "s")"
    }

    private var progress: Double {
        let active = queue.items.filter { $0.status == .working || $0.status == .queued }
        guard !active.isEmpty else { return 0 }
        return active.map(\.progress).reduce(0, +) / Double(active.count)
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(headline)
                .font(FileRadarFont.heading())
                .lineLimit(1)
            if queue.activeCount > 0 {
                Text("\(Int((progress * 100).rounded()))%")
                    .font(FileRadarFont.caption())
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                ProgressView(value: progress)
                    .tint(accent)
                Button(queue.isPaused ? "Resume" : "Pause") { queue.isPaused.toggle() }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                Button("Cancel") { queue.cancelAll() }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
            } else {
                Spacer(minLength: 0)
                Button("Queue") { onOpenQueue() }
                    .controlSize(.small)
                    .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(FileRadarChrome.hairline).frame(height: 1)
        }
        .accessibilityLabel("Transfer drawer")
    }
}

/// Top transfer strip (Preview Theater).
struct TransferTopStrip: View {
    @ObservedObject var queue = TransferQueue.shared
    var accent: Color
    var onOpenQueue: () -> Void

    private var progress: Double {
        let active = queue.items.filter { $0.status == .working || $0.status == .queued }
        guard !active.isEmpty else { return 0 }
        return active.map(\.progress).reduce(0, +) / Double(active.count)
    }

    var body: some View {
        HStack(spacing: 10) {
            FRTransferIcon(active: queue.activeCount > 0, size: .toolbar, accent: accent)
            if queue.activeCount > 0 {
                Text(queue.isPaused ? "Paused" : "Copying \(queue.activeCount) item\(queue.activeCount == 1 ? "" : "s")")
                    .font(FileRadarFont.caption())
                ProgressView(value: progress)
                    .tint(accent)
                    .frame(maxWidth: 220)
                Button(queue.isPaused ? "Resume" : "Pause") { queue.isPaused.toggle() }
                    .controlSize(.mini)
                    .buttonStyle(.bordered)
                Button("Cancel") { queue.cancelAll() }
                    .controlSize(.mini)
                    .buttonStyle(.bordered)
            } else {
                Text("Transfers idle")
                    .font(FileRadarFont.caption())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            Button("Queue") { onOpenQueue() }
                .controlSize(.mini)
                .buttonStyle(.borderless)
                .font(FileRadarFont.caption())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.03))
        .overlay(alignment: .bottom) {
            Rectangle().fill(FileRadarChrome.hairline).frame(height: 1)
        }
        .accessibilityLabel("Transfer strip")
    }
}

/// Large Quick Look theater panel (Preview Theater).
struct PreviewTheaterPanel: View {
    var file: FileItem?
    var accent: Color
    @EnvironmentObject var theme: ThemeSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preview")
                .font(FileRadarFont.caption())
                .foregroundStyle(.secondary)
            if let file {
                AsyncFileThumbnail(file: file, size: CGSize(width: 280, height: 180))
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: FileRadarChrome.radiusCard, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: FileRadarChrome.radiusCard, style: .continuous)
                            .strokeBorder(FileRadarChrome.hairline, lineWidth: 1)
                    )
                Text(file.name)
                    .font(FileRadarFont.heading())
                    .lineLimit(2)
                metaRow("Type", file.kind.displayName)
                metaRow("Size", ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                if let w = file.width, let h = file.height {
                    metaRow("Dimensions", "\(w) × \(h)")
                }
                metaRow("Modified", file.modifiedDate.formatted(date: .abbreviated, time: .omitted))
                Spacer(minLength: 0)
                HStack {
                    Button("Quick Look") { QuickLookHelper.shared.show(files: [file]) }
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                        .controlSize(.small)
                    Button("Open") { NSWorkspace.shared.open(file.url) }
                        .controlSize(.small)
                }
            } else {
                RoundedRectangle(cornerRadius: FileRadarChrome.radiusCard, style: .continuous)
                    .fill(FileRadarChrome.cardFill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .overlay {
                        Text("Select a file")
                            .font(FileRadarFont.caption())
                            .foregroundStyle(.secondary)
                    }
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(minWidth: 240, idealWidth: 280, maxWidth: 320)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.ultraThinMaterial)
        .overlay(alignment: .leading) {
            Rectangle().fill(FileRadarChrome.hairline).frame(width: 1)
        }
        .accessibilityLabel(file.map { "Preview of \($0.name)" } ?? "Empty preview theater")
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(FileRadarFont.caption()).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(FileRadarFont.caption()).lineLimit(1)
        }
    }
}

/// Narrow vertical command rail (Command Rail chrome).
struct CommandRailView: View {
    @Binding var destination: Destination
    var accent: Color
    var onBrowser: () -> Void
    var onSearch: () -> Void
    var onTransfers: () -> Void
    var onSettings: () -> Void

    var body: some View {
        let items: [(id: String, title: String, glyph: FRNavGlyph, action: () -> Void, selected: Bool)] = [
            ("home", "Home", .home, onBrowser, destination == .browser),
            ("search", "Search", .search, onSearch, destination == .search),
            ("sync", "Sync", .sync, { destination = .syncCompare }, destination == .syncCompare),
            ("xfer", "Transfer", .transfer, onTransfers, false),
            ("settings", "Settings", .settings, onSettings, false)
        ]
        VStack(spacing: 14) {
            ForEach(items, id: \.id) { item in
                Button(action: item.action) {
                    VStack(spacing: 6) {
                        FRNavIcon(glyph: item.glyph, size: .list, selected: item.selected, accent: accent)
                        Text(item.title)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(item.selected ? accent : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(item.selected ? accent.opacity(0.14) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(item.selected ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .frame(width: 72)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.85))
        .overlay(alignment: .trailing) {
            Rectangle().fill(FileRadarChrome.hairline).frame(width: 1)
        }
    }
}

/// Sync pill between dual panes (Command Rail).
struct PaneSyncPill: View {
    var accent: Color
    var onCopyRight: () -> Void
    var onCopyLeft: () -> Void
    var onSync: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            syncButton(systemImage: "arrow.right", help: "Copy selection to right pane", action: onCopyRight)
            syncButton(systemImage: "arrow.left.arrow.right", help: "Compare / sync panes", action: onSync)
            syncButton(systemImage: "arrow.left", help: "Copy selection to left pane", action: onCopyLeft)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .frame(width: 52)
    }

    private func syncButton(systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                FRIconTile(size: 28, top: accent.opacity(0.95), bottom: accent.opacity(0.7), corner: 8)
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Keyboard legend footer (Command Rail).
struct CommandKeyboardLegend: View {
    var body: some View {
        HStack(spacing: 18) {
            legend("F5", "Refresh")
            legend("F8", "Delete")
            legend("F9", "New Folder")
            legend("⌘,", "Preferences")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04))
        .overlay(alignment: .top) {
            Rectangle().fill(FileRadarChrome.hairline).frame(height: 1)
        }
        .accessibilityLabel("Keyboard shortcuts")
    }

    private func legend(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08)))
            Text(label)
                .font(FileRadarFont.caption())
                .foregroundStyle(.secondary)
        }
    }
}

/// Browser-style workspace tabs (Workspace Tabs chrome).
struct WorkspaceChromeTabBar: View {
    @Binding var selected: String
    var accent: Color
    var names: [String] = ["Work", "Photos", "Archive"]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(names, id: \.self) { name in
                Button {
                    withAnimation(FileRadarMotion.chip) { selected = name }
                } label: {
                    Text(name)
                        .font(FileRadarFont.caption())
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .foregroundStyle(selected == name ? .primary : .secondary)
                        .overlay(alignment: .top) {
                            Rectangle()
                                .fill(selected == name ? accent : Color.clear)
                                .frame(height: 2)
                        }
                        .background(selected == name ? Color.primary.opacity(0.04) : Color.clear)
                }
                .buttonStyle(.plain)
            }
            Button {
                // Visual affordance only — tabs are chrome labels for now.
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(10)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New workspace tab")
            Spacer(minLength: 0)
        }
        .background(Color.primary.opacity(0.02))
        .overlay(alignment: .bottom) {
            Rectangle().fill(FileRadarChrome.hairline).frame(height: 1)
        }
    }
}

/// Right Queue drawer for Workspace Tabs.
struct QueueDrawerView: View {
    @ObservedObject var queue = TransferQueue.shared
    var accent: Color
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Queue").font(FileRadarFont.heading())
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close queue")
            }
            if queue.activeCount > 0 {
                Text(queue.isPaused ? "Paused" : "Copying \(queue.activeCount) item\(queue.activeCount == 1 ? "" : "s")")
                    .font(FileRadarFont.caption())
                ProgressView(value: aggregate)
                    .tint(accent)
                HStack {
                    Button(queue.isPaused ? "Resume" : "Pause") { queue.isPaused.toggle() }
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                        .controlSize(.small)
                    Button("Cancel") { queue.cancelAll() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            } else {
                Text("Nothing in the queue.")
                    .font(FileRadarFont.caption())
                    .foregroundStyle(.secondary)
            }
            TransferQueueView()
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 260)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.regularMaterial)
        .overlay(alignment: .leading) {
            Rectangle().fill(FileRadarChrome.hairline).frame(width: 1)
        }
        .accessibilityLabel("Transfer queue drawer")
    }

    private var aggregate: Double {
        let active = queue.items.filter { $0.status == .working || $0.status == .queued }
        guard !active.isEmpty else { return 0 }
        return active.map(\.progress).reduce(0, +) / Double(active.count)
    }
}

/// Floating transfer pill used by Command Rail (teal).
struct TransferFloatingPill: View {
    @ObservedObject var queue = TransferQueue.shared
    var accent: Color

    private var progress: Double {
        let active = queue.items.filter { $0.status == .working || $0.status == .queued }
        guard !active.isEmpty else { return 0 }
        return active.map(\.progress).reduce(0, +) / Double(active.count)
    }

    var body: some View {
        if queue.activeCount > 0 || queue.items.contains(where: { $0.status == .failed }) {
            HStack(spacing: 10) {
                Text(queue.isPaused ? "Paused" : "Copying \(max(queue.activeCount, 1)) item")
                    .font(FileRadarFont.heading())
                ProgressView(value: progress)
                    .tint(accent)
                    .frame(width: 120)
                Text("\(Int((progress * 100).rounded()))%")
                    .font(FileRadarFont.caption())
                    .monospacedDigit()
                Button(queue.isPaused ? "Resume" : "Pause") { queue.isPaused.toggle() }
                    .controlSize(.mini)
                Button("Cancel") { queue.cancelAll() }
                    .controlSize(.mini)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(.ultraThinMaterial))
            .overlay(Capsule().strokeBorder(accent.opacity(0.35), lineWidth: 1))
            .shadow(color: FileRadarChrome.hudShadow, radius: 12, y: 4)
            .padding(.bottom, 18)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityLabel("Transfer progress")
        }
    }
}
