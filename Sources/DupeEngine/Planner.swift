import Foundation

/// How to choose which copy of a file to keep.
public enum KeepRule: String, CaseIterable, Identifiable, Sendable {
    case smart, largerFolder, recentFolder, olderFolder, newestFile, oldestFile, shortestPath

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .smart: return "Smart (recommended)"
        case .largerFolder: return "Keep the copy in the larger folder"
        case .recentFolder: return "Keep the copy in the most recent folder"
        case .olderFolder: return "Keep the copy in the oldest folder"
        case .newestFile: return "Keep the newest file"
        case .oldestFile: return "Keep the oldest file"
        case .shortestPath: return "Keep the copy closest to the top"
        }
    }

    public var explanation: String {
        switch self {
        case .smart: return "Keeps the copy that looks like the original: not sitting in Downloads or Desktop, without “copy” or “(1)” in its name, in the fuller folder, and then the oldest."
        case .largerFolder: return "Keeps the copy in the folder that holds the most files. A big folder is usually the real collection, and the stray copy is the one in a small folder."
        case .recentFolder: return "Keeps the copy in the folder that changed most recently."
        case .olderFolder: return "Keeps the copy in the folder that has gone longest without a change."
        case .newestFile: return "Keeps the copy that was modified last."
        case .oldestFile: return "Keeps the copy that was modified first."
        case .shortestPath: return "Keeps the copy with the fewest folders above it."
        }
    }
}

/// What will happen to one set of identical files.
public struct SetPlan: Identifiable, Sendable {
    public let set: DuplicateSet
    public var keepIDs: Set<Int>
    /// The user chose to leave this whole set alone.
    public var skipped = false
    /// Space that would really come back, counting copies that share disk space (clones) as free of cost.
    public var freed: Int64
    public var id: String { self.set.id }
    public var removed: [FileItem] { skipped ? [] : self.set.copies.filter { !keepIDs.contains($0.id) } }
    public var kept: [FileItem] { self.set.copies.filter { skipped || keepIDs.contains($0.id) } }
    public var removedBytes: Int64 { Int64(removed.count) * self.set.size }
}

public struct Planner: Sendable {
    public let result: ScanResult
    public init(result: ScanResult) { self.result = result }

    static let holding: [String] = [NSHomeDirectory() + "/Downloads", NSHomeDirectory() + "/Desktop", NSHomeDirectory() + "/.Trash", "/tmp", "/private/tmp"]
    static let copyLike = try! NSRegularExpression(pattern: #"( copy( \d+)?| \(\d+\)| - copy( \d+)?)$"#, options: [.caseInsensitive])

    func inHolding(_ f: FileItem) -> Bool { Planner.holding.contains { f.path == $0 || f.path.hasPrefix($0 + "/") } || f.path.contains("/.Trashes/") }

    func copyLikeName(_ f: FileItem) -> Bool {
        let base = ((f.name as NSString).deletingPathExtension) as NSString
        return Planner.copyLike.firstMatch(in: base as String, range: NSRange(location: 0, length: base.length)) != nil
    }

    /// Lower is better. Compared left to right.
    func score(_ f: FileItem, _ rule: KeepRule) -> [Double] {
        let count = Double(result.folderFileCount[f.folder] ?? 0)
        let folderDate = (result.folderModified[f.folder] ?? f.modified).timeIntervalSince1970
        let depth = Double(f.path.split(separator: "/").count)
        let tail = [Double(f.path.utf8.count)]
        switch rule {
        case .smart: return [inHolding(f) ? 1 : 0, copyLikeName(f) ? 1 : 0, -count, f.created.timeIntervalSince1970] + tail
        case .largerFolder: return [-count, f.created.timeIntervalSince1970] + tail
        case .recentFolder: return [-folderDate, -count] + tail
        case .olderFolder: return [folderDate, -count] + tail
        case .newestFile: return [-f.modified.timeIntervalSince1970] + tail
        case .oldestFile: return [f.modified.timeIntervalSince1970] + tail
        case .shortestPath: return [depth] + tail
        }
    }

    func better(_ a: FileItem, _ b: FileItem, _ rule: KeepRule) -> Bool {
        let x = score(a, rule), y = score(b, rule)
        for (p, q) in zip(x, y) where p != q { return p < q }
        return a.path < b.path
    }

    /// - pinnedFolders: copies inside these folders always stay.
    /// - overrides: set id to the file the user picked to keep.
    /// - skippedSets: sets the user chose to leave alone.
    public func plan(rule: KeepRule, pinnedFolders: [String] = [], overrides: [String: Int] = [:], skippedSets: Set<String> = []) -> [SetPlan] {
        result.sets.map { set in
            var keep: Set<Int>
            if let pick = overrides[set.id], set.copies.contains(where: { $0.id == pick }) {
                keep = [pick]
            } else {
                let pinned = set.copies.filter { c in pinnedFolders.contains { c.path.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") } }
                keep = Set(pinned.map(\.id))
                if keep.isEmpty, let best = set.copies.min(by: { better($0, $1, rule) }) { keep = [best.id] }
            }
            var p = SetPlan(set: set, keepIDs: keep, skipped: skippedSets.contains(set.id), freed: 0)
            p.freed = freedBytes(p)
            return p
        }
    }

    /// Recomputes the space that would come back after the user changes a choice.
    public func freedBytes(_ p: SetPlan) -> Int64 {
        var total: Int64 = 0
        for r in p.removed {
            var shared = 0.0
            if let sig = result.blockSignature[r.id] {
                for k in p.kept where k.device == r.device {
                    if let ks = result.blockSignature[k.id], ks.count == sig.count {
                        shared = max(shared, Double(zip(sig, ks).filter { $0 == $1 }.count) / Double(sig.count))
                    }
                }
            }
            total += Int64(Double(r.size) * (1 - shared))
        }
        return total
    }
}
