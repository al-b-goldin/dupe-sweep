import Foundation
import Darwin

final class ProgressState: @unchecked Sendable {
    private let lock = NSLock()
    private var p = ScanProgress()
    private var samples: [(Double, Int64)] = []

    func update(_ f: (inout ScanProgress) -> Void) { lock.lock(); f(&p); lock.unlock() }
    func addRead(_ n: Int64) { lock.lock(); p.readBytes += n; lock.unlock() }
    func fileDone() { lock.lock(); p.readFiles += 1; lock.unlock() }

    func snapshot() -> ScanProgress {
        lock.lock(); defer { lock.unlock() }
        let now = Date().timeIntervalSinceReferenceDate
        samples.append((now, p.readBytes))
        samples.removeAll { now - $0.0 > 4 }
        if let first = samples.first, now - first.0 > 0.4, p.phase == .reading {
            p.bytesPerSecond = Double(p.readBytes - first.1) / (now - first.0)
            let left = Double(p.readTotal - p.readBytes)
            p.etaSeconds = p.bytesPerSecond > 1e6 ? left / p.bytesPerSecond : nil
        }
        return p
    }
}

public final class DuplicateScanner: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    public init() {}

    public func cancel() { lock.lock(); stopped = true; lock.unlock() }
    private var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }

    /// Finds files with identical contents. Reads only; nothing is changed.
    public func scan(roots: [URL], options: ScanOptions = ScanOptions(), progress: @escaping @Sendable (ScanProgress) -> Void) async throws -> ScanResult {
        try await withTaskCancellationHandler {
            try await run(roots: roots, options: options, progress: progress)
        } onCancel: { self.cancel() }
    }

    private func run(roots: [URL], options: ScanOptions, progress: @escaping @Sendable (ScanProgress) -> Void) async throws -> ScanResult {
        let t0 = Date()
        let state = ProgressState()
        let publisher = Task.detached(priority: .utility) {
            while !Task.isCancelled { progress(state.snapshot()); try? await Task.sleep(nanoseconds: 250_000_000) }
        }
        defer { publisher.cancel() }

        // 1. Find the files.
        state.update { $0.phase = .finding }
        let walked = await Task.detached(priority: .utility) { [self] in
            walkTree(roots: roots, options: options, shouldStop: { self.isStopped }) { n, b, name in
                state.update { $0.filesFound = n; $0.bytesFound = b; $0.currentName = name }
            }
        }.value
        if isStopped { throw CancellationError() }
        state.update { $0.filesFound = walked.files.count; $0.bytesFound = walked.files.reduce(0) { $0 + $1.size } }

        // 2. Hard links are one file, not two. Only files that share a size can be duplicates.
        state.update { $0.phase = .comparing }
        var firstOfInode: [String: FileItem] = [:]
        var files: [FileItem] = []
        for f in walked.files {
            let key = "\(f.device):\(f.inode)"
            if firstOfInode[key] == nil { firstOfInode[key] = f; files.append(f) }
        }
        var bySize: [Int64: [FileItem]] = [:]
        for f in files { bySize[f.size, default: []].append(f) }
        let sameSize = bySize.values.filter { $0.count > 1 }.flatMap { $0 }
        state.update { $0.candidateFiles = sameSize.count; $0.candidateBytes = sameSize.reduce(0) { $0 + $1.size } }

        let workers = options.workers ?? DuplicateScanner.defaultWorkers(for: sameSize)

        // 3. A quick look at the start, middle and end of the bigger ones separates most same-size files that differ.
        let needFingerprint = sameSize.filter { $0.size > Int64(fingerprintThreshold) }
        let fingerprints = try await limited(needFingerprint, workers: workers) { f in
            try quickFingerprint(path: f.path, size: f.size) { _ in }
        }
        var groups: [String: [FileItem]] = [:]
        for f in sameSize { groups["\(f.size)|\(fingerprints[f.id] ?? "")", default: []].append(f) }
        let survivors = groups.values.filter { $0.count > 1 }.flatMap { $0 }

        // 4. Read what is left in full.
        let readTotal = survivors.reduce(Int64(0)) { $0 + $1.size }
        state.update { $0.phase = .reading; $0.readTotal = readTotal; $0.readBytes = 0; $0.readFiles = 0 }
        let sorted = survivors.sorted { $0.size > $1.size }
        let hashes = try await limited(sorted, workers: workers) { [self] f -> String in
            state.update { $0.currentName = f.name }
            let (h, _) = try fullHash(path: f.path, bump: { state.addRead($0) }, shouldStop: { self.isStopped })
            state.fileDone()
            return h
        }
        if isStopped { throw CancellationError() }

        // 5. Group by contents and measure which copies really take up space.
        state.update { $0.phase = .finishing }
        var byContent: [String: [FileItem]] = [:]
        for f in survivors { if let h = hashes[f.id] { byContent["\(f.size)|\(h)", default: []].append(f) } }
        var sets: [DuplicateSet] = []
        for (k, v) in byContent where v.count > 1 {
            sets.append(DuplicateSet(id: k, size: v[0].size, copies: v.sorted { $0.path < $1.path }))
        }
        sets.sort { $0.size * Int64($0.copies.count - 1) > $1.size * Int64($1.copies.count - 1) }
        var signatures: [Int: [Int64]] = [:]
        for s in sets where s.size >= Int64(sliceSize) {
            for c in s.copies { if let sig = blockSignature(path: c.path, size: c.size) { signatures[c.id] = sig } }
        }
        state.update { $0.phase = .done }
        progress(state.snapshot())
        return ScanResult(sets: sets, filesScanned: walked.files.count + walked.iCloudOnly, bytesScanned: walked.files.reduce(0) { $0 + $1.size },
                          iCloudOnlySkipped: walked.iCloudOnly, unreadable: walked.unreadable, refusedFolders: walked.refused,
                          folderFileCount: walked.folderFileCount, folderModified: walked.folderModified, blockSignature: signatures,
                          seconds: Date().timeIntervalSince(t0), bytesRead: state.snapshot().readBytes)
    }

    /// Two files at a time. That is the setting measured to keep a Mac as responsive as when nothing is running
    /// (small reads stay at 0.5 ms), while still reading about 3 GB/s from a fast internal drive.
    static func defaultWorkers(for files: [FileItem]) -> Int { 2 }

    /// Runs `work` for every item with at most `workers` running at once, at low priority so the Mac stays responsive.
    private func limited<R: Sendable>(_ items: [FileItem], workers: Int, work: @escaping @Sendable (FileItem) throws -> R) async throws -> [Int: R] {
        var results: [Int: R] = [:]
        try await withThrowingTaskGroup(of: (Int, R?).self) { group in
            var next = 0
            func add() {
                guard next < items.count, !isStopped else { return }
                let f = items[next]; next += 1
                group.addTask(priority: .utility) {
                    do { return (f.id, try work(f)) } catch is Cancelled { return (f.id, nil) } catch { return (f.id, nil) }
                }
            }
            for _ in 0..<max(1, workers) { add() }
            while let (id, r) = try await group.next() {
                if let r { results[id] = r }
                add()
            }
        }
        return results
    }
}
