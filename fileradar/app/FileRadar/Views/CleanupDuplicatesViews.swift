import SwiftUI

// MARK: - Clean Up (principle 2: decisions; principle 10: Trash only, confirm bulk)

struct CleanupView: View {
    var trash: TrashService
    @EnvironmentObject var store: FileStore
    @EnvironmentObject var license: LicenseManager
    @State private var showLicense = false
    @State private var confirmingCard: CleanupCard?
    @State private var completedMessage: String?

    var body: some View {
        VStack(alignment: .leading) {
            Text("Clean Up").font(FileRadarFont.title()).padding(.horizontal)
            if !license.isAllowed(.cleanup) {
                LockedFeatureView(feature: .cleanup) { showLicense = true }
            } else if let message = completedMessage {
                // Principle 8: satisfying completion, not a dry toast.
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(.green)
                    Text(message).font(FileRadarFont.heading())
                    Button("Undo") {
                        let before = trash.recentTrashed
                        trash.undoLastBatch()
                        let restored = before.filter { entry in !trash.recentTrashed.contains(where: { $0.id == entry.id }) }
                        store.restoreFiles(restored.compactMap { SyncCompareService.fileItem(for: $0.originalURL) })
                        completedMessage = nil
                    }
                        .keyboardShortcut("z", modifiers: .command)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let cards = CleanupEngine.cards(for: store.files)
                if cards.isEmpty {
                    EmptyStateView(title: "All clear",
                                   message: "No old installers, forgotten downloads, old screenshots, or big old videos were found. Nicely kept.")
                } else {
                    List(cards) { card in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(card.type.rawValue).font(FileRadarFont.heading())
                            Text(card.type.explanation).font(FileRadarFont.body()).foregroundStyle(.secondary)
                            Text("\(card.files.count) files · \(ByteCountFormatter.string(fromByteCount: card.totalSize, countStyle: .file))")
                                .font(FileRadarFont.caption()).foregroundStyle(.secondary)
                            Button("Move all to Trash") { confirmingCard = card }
                                .buttonStyle(.borderedProminent)
                                .accessibilityHint("Moves these files to Trash. Nothing is deleted outright.")
                        }.padding(.vertical, 4)
                    }
                }
            }
        }
        .sheet(isPresented: $showLicense) { LicenseEntryView() }
        .alert("Move these files to Trash?", isPresented: .init(
            get: { confirmingCard != nil },
            set: { if !$0 { confirmingCard = nil } }
        )) {
            Button("Move to Trash", role: .destructive) {
                guard let card = confirmingCard else { return }
                // Principle 5: the completion message names where files went.
                let moved = trash.trash(card.files)
                store.removeFiles(matching: Set(moved.map { $0.originalURL.path }))
                completedMessage = "\(moved.count) files moved to Trash. You can restore them from Finder, or undo here."
                confirmingCard = nil
            }
            Button("Cancel", role: .cancel) { confirmingCard = nil }
        } message: {
            Text("Files in Trash can be restored. This does not delete anything outright.")
        }
    }
}

// MARK: - Duplicates (paid feature; keeper picked, rest to Trash)

struct DuplicatesView: View {
    var trash: TrashService
    @EnvironmentObject var store: FileStore
    @EnvironmentObject var license: LicenseManager
    @State private var groups: [DuplicateGroup] = []
    @State private var scanning = false
    @State private var showLicense = false
    @State private var confirmingGroup: DuplicateGroup?

    var body: some View {
        VStack(alignment: .leading) {
            Text("Duplicates").font(FileRadarFont.title()).padding(.horizontal)
            if !license.isAllowed(.duplicates) {
                LockedFeatureView(feature: .duplicates) { showLicense = true }
            } else {
                Button(scanning ? "Scanning…" : "Scan for duplicates") {
                    scanning = true
                    let snapshot = store.files
                    Task {
                        let exact = await Task.detached(priority: .userInitiated) {
                            DuplicateFinder.exactGroups(in: snapshot)
                        }.value
                        let alike = await DuplicateFinder.lookAlikeGroups(in: snapshot)
                        groups = exact + alike
                        scanning = false
                    }
                }.padding(.horizontal).disabled(scanning)
                Text("iCloud-only files are skipped — scanning them would download them, and FileRadar never does that.")
                    .font(FileRadarFont.caption()).foregroundStyle(.secondary).padding(.horizontal)
                if groups.isEmpty && !scanning {
                    EmptyStateView(title: "No duplicates found",
                                   message: "Run a scan to check for identical files and photos that look alike.")
                } else {
                    List(groups) { group in
                        VStack(alignment: .leading) {
                            Text(group.title).font(FileRadarFont.heading())
                            ForEach(group.files) { file in
                                HStack {
                                    Text(file.name)
                                    if file.id == group.keeper?.id {
                                        Text("Keeper").font(FileRadarFont.caption())
                                            .padding(4).background(Capsule().fill(Color.green.opacity(0.2)))
                                    }
                                    Spacer()
                                    Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Button("Move the rest to Trash") { confirmingGroup = group }
                                .accessibilityHint("Keeps the newest file and moves the rest to Trash.")
                        }.padding(.vertical, 4)
                    }
                }
            }
        }
        .sheet(isPresented: $showLicense) { LicenseEntryView() }
        .alert("Move duplicates to Trash?", isPresented: .init(
            get: { confirmingGroup != nil }, set: { if !$0 { confirmingGroup = nil } }
        )) {
            Button("Move to Trash", role: .destructive) {
                guard let group = confirmingGroup, let keeper = group.keeper else { return }
                let rest = group.files.filter { $0.id != keeper.id }
                let moved = trash.trash(rest)
                store.removeFiles(matching: Set(moved.map { $0.originalURL.path }))
                groups.removeAll { $0.id == group.id }
                confirmingGroup = nil
            }
            Button("Cancel", role: .cancel) { confirmingGroup = nil }
        } message: {
            Text("The keeper stays where it is. The rest go to Trash and can be restored.")
        }
    }
}

// MARK: - Paid-feature lock screen (plain language, no dark patterns)

struct LockedFeatureView: View {
    var feature: PaidFeature
    var onUnlock: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock").font(.largeTitle).foregroundStyle(.secondary)
            Text(feature.rawValue).font(FileRadarFont.heading())
            Text(feature.lockedMessage).font(FileRadarFont.body()).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 420)
            Text("Browsing, searching, and previewing are free in demo mode.")
                .font(FileRadarFont.caption()).foregroundStyle(.secondary)
            Button("Enter serial number") { onUnlock() }.buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
