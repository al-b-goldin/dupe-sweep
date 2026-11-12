import Foundation
import Darwin

public struct TrashRecord: Sendable, Hashable, Identifiable {
    public var id: String { original }
    public let original: String
    public let trashed: String?
    public let size: Int64
    public init(original: String, trashed: String?, size: Int64) { self.original = original; self.trashed = trashed; self.size = size }
}

public struct TrashReport: Sendable {
    public var moved: [TrashRecord] = []
    public var skipped: [(path: String, reason: String)] = []
    public init() {}
    public var bytesMoved: Int64 { moved.reduce(0) { $0 + $1.size } }
}

/// Moves files to the Trash after checking them again. Never deletes anything for good.
public enum Trasher {
    /// How a file reaches the Trash. Tests replace this so they never touch the real Trash.
    nonisolated(unsafe) public static var trashItem: (URL) throws -> URL? = { url in
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        return result as URL?
    }

    static func unchanged(_ f: FileItem) -> Bool {
        var st = stat()
        guard lstat(f.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG, Int64(st.st_size) == f.size else { return false }
        let t = Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1e9
        return abs(t - f.modified.timeIntervalSince1970) < 0.002
    }

    public static func move(_ plans: [SetPlan], progress: ((Int, Int) -> Void)? = nil) -> TrashReport {
        var report = TrashReport()
        let total = plans.reduce(0) { $0 + $1.removed.count }
        var done = 0
        for p in plans where !p.removed.isEmpty {
            // At least one kept copy must still be there and unchanged, or nothing in this set is touched.
            guard p.kept.contains(where: unchanged) else {
                for r in p.removed { report.skipped.append((r.path, "the copy that was going to stay has changed or is gone")) }
                done += p.removed.count; progress?(done, total); continue
            }
            for r in p.removed {
                defer { done += 1; progress?(done, total) }
                guard unchanged(r) else { report.skipped.append((r.path, "changed since the scan")); continue }
                do {
                    let result = try trashItem(r.url)
                    report.moved.append(TrashRecord(original: r.path, trashed: result?.path, size: r.size))
                } catch {
                    report.skipped.append((r.path, error.localizedDescription))
                }
            }
        }
        return report
    }

    /// Puts files back where they came from, unless something else is there now.
    public static func undo(_ records: [TrashRecord]) -> (restored: Int, failed: [String]) {
        var restored = 0
        var failed: [String] = []
        for r in records {
            guard let t = r.trashed, FileManager.default.fileExists(atPath: t), !FileManager.default.fileExists(atPath: r.original) else { failed.append(r.original); continue }
            do {
                try FileManager.default.createDirectory(atPath: (r.original as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
                try FileManager.default.moveItem(atPath: t, toPath: r.original)
                restored += 1
            } catch { failed.append(r.original) }
        }
        return (restored, failed)
    }
}
