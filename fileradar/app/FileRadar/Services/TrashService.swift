import Foundation
import AppKit

/// Trash-only destructive actions + undo (principle 10).
///
/// Nothing in FileRadar ever calls FileManager.removeItem on a user file.
/// Moves go through NSWorkspace recycle, which puts files in Trash where
/// Finder can restore them. Undo restores from Trash by moving back to the
/// recorded original location — best effort, reported honestly if it fails.
@MainActor
final class TrashService: ObservableObject {
    struct TrashedEntry: Identifiable {
        let id = UUID()
        var trashURL: URL
        var originalURL: URL
        var date: Date
    }

    @Published private(set) var recentTrashed: [TrashedEntry] = []
    @Published var lastError: String?

    /// Move files to Trash. Returns the entries that actually moved.
    /// Every entry in one call shares one batch date: `undoLastBatch`
    /// groups by exact date, so per-file `Date()` calls (microseconds
    /// apart) previously made it undo only the single newest file.
    @discardableResult
    func trash(_ files: [FileItem]) -> [TrashedEntry] {
        var moved: [TrashedEntry] = []
        let batchDate = Date()
        for file in files {
            var resultingURL: NSURL?
            do {
                try FileManager.default.trashItem(at: file.url, resultingItemURL: &resultingURL)
                if let trashURL = resultingURL as URL? {
                    moved.append(TrashedEntry(trashURL: trashURL, originalURL: file.url, date: batchDate))
                }
            } catch {
                lastError = "Could not move \(file.name) to Trash: \(error.localizedDescription)"
            }
        }
        recentTrashed.append(contentsOf: moved)
        return moved
    }

    /// Undo: move trashed files back to their original locations.
    func undo(_ entries: [TrashedEntry]) {
        for entry in entries {
            do {
                try FileManager.default.moveItem(at: entry.trashURL, to: entry.originalURL)
                recentTrashed.removeAll { $0.id == entry.id }
            } catch {
                lastError = "Could not restore \(entry.originalURL.lastPathComponent): \(error.localizedDescription)"
            }
        }
    }

    func undoLastBatch() {
        guard let latest = recentTrashed.map(\.date).max() else { return }
        undo(recentTrashed.filter { $0.date == latest })
    }
}
