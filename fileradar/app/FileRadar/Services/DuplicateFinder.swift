import Foundation
import CryptoKit
import Vision
import AppKit

/// Duplicates — paid feature (gated by callers via LicenseManager).
///
/// - Exact duplicates: SHA-256 over file bytes, grouped by hash. Files of
///   different sizes can never match, so hashing is skipped for unique sizes.
/// - Look-alike photos: Vision `VNGenerateImageFeaturePrintRequest`
///   feature prints, grouped by cosine distance below a threshold.
/// - iCloud-only files are skipped entirely: hashing or feature-printing
///   them would trigger a download, which FileRadar never does.
/// - The keeper is the newest file by default; the user picks otherwise.
///   Non-keepers go to Trash via TrashService, never outright deleted.
enum DuplicateFinder {
    static func exactGroups(in files: [FileItem]) -> [DuplicateGroup] {
        var bySize: [Int64: [FileItem]] = [:]
        for f in files where !f.isICloudOnly && f.kind != .folder { bySize[f.size, default: []].append(f) }
        var groups: [DuplicateGroup] = []
        for (_, candidates) in bySize where candidates.count > 1 {
            var byHash: [String: [FileItem]] = [:]
            for f in candidates {
                if let hash = sha256(of: f.url) { byHash[hash, default: []].append(f) }
            }
            for (_, dupes) in byHash where dupes.count > 1 {
                let sorted = dupes.sorted { $0.modifiedDate > $1.modifiedDate }
                groups.append(DuplicateGroup(kind: .exact, files: sorted, keeper: sorted.first))
            }
        }
        return groups
    }

    static func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Look-alike photos. Feature prints are compared pairwise within the
    /// image set; distance < 0.25 counts as "looks alike". Threshold is a
    /// named constant so it can be tuned from real-world testing.
    static let lookAlikeThreshold: Float = 0.25

    static func lookAlikeGroups(in files: [FileItem]) async -> [DuplicateGroup] {
        let images = files.filter { $0.kind == .image && !$0.isICloudOnly }
        var prints: [(FileItem, VNFeaturePrintObservation)] = []
        for file in images {
            if let print = await featurePrint(for: file) { prints.append((file, print)) }
        }
        var used = Set<String>()
        var groups: [DuplicateGroup] = []
        for (i, (file, print)) in prints.enumerated() where !used.contains(file.id) {
            var group = [file]
            for (otherFile, otherPrint) in prints.dropFirst(i + 1) where !used.contains(otherFile.id) {
                var distance: Float = 0
                do {
                    try print.computeDistance(&distance, to: otherPrint)
                } catch { continue }
                if distance < lookAlikeThreshold {
                    group.append(otherFile)
                    used.insert(otherFile.id)
                }
            }
            if group.count > 1 {
                used.insert(file.id)
                let sorted = group.sorted { $0.modifiedDate > $1.modifiedDate }
                groups.append(DuplicateGroup(kind: .lookAlike, files: sorted, keeper: sorted.first))
            }
        }
        return groups
    }

    private static func featurePrint(for file: FileItem) async -> VNFeaturePrintObservation? {
        guard let image = NSImage(contentsOf: file.url),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return await withCheckedContinuation { continuation in
            let request = VNGenerateImageFeaturePrintRequest { request, _ in
                continuation.resume(returning: request.results?.first as? VNFeaturePrintObservation)
            }
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do { try handler.perform([request]) } catch {
                    // Completion may not fire if perform throws; resume nil.
                    // (Double-resume is guarded by the continuation contract
                    // in practice because a failed perform produces no result
                    // callback; see README UNTESTED section.)
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
