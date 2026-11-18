import Foundation
import Testing
@testable import DupeEngine

/// Engine tests. They use Swift Testing, which ships with the Command Line Tools and with Xcode 16 or later,
/// so `swift test` runs on a Mac without Xcode. Serialized, because the stand-in Trash is one shared setting.
@Suite(.serialized)
final class EngineTests {
    let tmp: URL
    let mib = 1 << 20
    init() throws {
        tmp = URL(fileURLWithPath: (NSTemporaryDirectory() as NSString).appendingPathComponent("dupesweep-" + UUID().uuidString)).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    deinit {
        try? FileManager.default.removeItem(at: tmp)
        try? FileManager.default.removeItem(atPath: tmp.path + ".trash")
    }

    @discardableResult
    func write(_ rel: String, _ data: Data) throws -> String {
        let url = tmp.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        return url.path
    }
    func random(_ n: Int) -> Data { Data((0..<n).map { _ in UInt8.random(in: 0...255) }) }

    func scan(_ rels: [String] = [""], _ tweak: (inout ScanOptions) -> Void = { _ in }) async throws -> ScanResult {
        var o = ScanOptions(); o.minSize = 1; o.workers = 2; tweak(&o)
        return try await DuplicateScanner().scan(roots: rels.map { tmp.appendingPathComponent($0) }, options: o) { _ in }
    }
    func names(_ r: ScanResult) -> [[String]] { r.sets.map { $0.copies.map { ($0.path as NSString).lastPathComponent }.sorted() }.sorted { $0.joined() < $1.joined() } }

    @Test func testFindsTrueCopiesAndIgnoresSameSizeDecoys() async throws {
        let big = random(6 * mib)
        try write("a/orig.bin", big); try write("b/copy.bin", big); try write("b/decoy.bin", random(6 * mib)); try write("b/alone.bin", random(3 * mib))
        let r = try await scan()
        #expect(names(r) == [["copy.bin", "orig.bin"]])
        #expect(r.extraBytes == Int64(6 * mib))
    }

    @Test func testSmallFilesAreComparedInFull() async throws {
        let a = random(20_000)
        var b = a; b[19_999] ^= 0xFF
        try write("x/one.dat", a); try write("y/two.dat", a); try write("y/three.dat", b)
        let r = try await scan()
        #expect(names(r) == [["one.dat", "two.dat"]])
    }

    @Test func testFilesThatDifferOnlyInTheMiddleAreNotDuplicates() async throws {
        var a = random(9 * mib); let b = a
        a[4 * mib + 123] ^= 0x01       // between the fingerprint slices
        try write("p/a.bin", a); try write("q/b.bin", b)
        let r = try await scan()
        #expect(r.sets.count == 0)
    }

    @Test func testHardLinkIsOneFileNotTwo() async throws {
        let p = try write("a/file.bin", random(3 * mib))
        try FileManager.default.linkItem(atPath: p, toPath: tmp.appendingPathComponent("b-link.bin").path)
        let r = try await scan()
        #expect(r.sets.count == 0)
    }

    @Test func testSmallAndHiddenFilesAreSkippedWhenAsked() async throws {
        let d = random(50_000), h = random(50_000)
        try write("a/tiny.dat", Data("hi".utf8)); try write("b/tiny.dat", Data("hi".utf8))
        try write("a/.secret.dat", h); try write("b/.secret.dat", h); try write("a/shown.dat", d); try write("b/shown.dat", d)
        let r = try await scan([""]) { $0.minSize = 10_240; $0.skipHidden = true }
        #expect(names(r) == [["shown.dat", "shown.dat"]])
        let all = try await scan([""]) { $0.skipHidden = false }
        #expect(all.sets.count == 3)
    }

    @Test func testCloneCountsAsFreeButARealCopyDoesNot() async throws {
        let big = random(5 * mib)
        let a = try write("keep/orig.bin", big)
        try write("real/copy.bin", big)
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/cp"); p.arguments = ["-c", a, tmp.appendingPathComponent("clone/copy.bin").path]
        try FileManager.default.createDirectory(at: tmp.appendingPathComponent("clone"), withIntermediateDirectories: true)
        try p.run(); p.waitUntilExit()
        if p.terminationStatus != 0 { return }      // this volume cannot clone
        let r = try await scan()
        let plans = Planner(result: r).plan(rule: .smart, pinnedFolders: [tmp.appendingPathComponent("keep").path])
        #expect(plans.count == 1)
        #expect(plans[0].removed.count == 2)
        #expect(plans[0].freed == Int64(5 * mib))      // the clone frees nothing, the real copy frees its size
    }

    @Test func testRefusesSystemFolders() async throws {
        var o = ScanOptions(); o.minSize = 1
        let r = try await DuplicateScanner().scan(roots: [URL(fileURLWithPath: "/System")], options: o) { _ in }
        #expect(r.refusedFolders == ["/System"]); #expect(r.filesScanned == 0)
    }

    @Test func testCancelledScanThrows() async throws {
        try write("a/x.bin", random(1000))
        let s = DuplicateScanner(); s.cancel()
        do { _ = try await s.scan(roots: [tmp], options: ScanOptions()) { _ in }; Issue.record("a cancelled scan should throw") } catch is CancellationError {}
    }

    // MARK: choosing which copy to keep

    func plan(_ rule: KeepRule, pinned: [String] = [], _ r: ScanResult) -> [SetPlan] { Planner(result: r).plan(rule: rule, pinnedFolders: pinned) }
    func keptPaths(_ p: SetPlan) -> [String] { p.kept.map { $0.path.replacingOccurrences(of: tmp.path + "/", with: "") } }

    @Test func testSmartKeepsTheOriginalNotTheCopyNamed() async throws {
        let d = random(40_000)
        try write("t/photo.jpg", d); try write("t/photo copy.jpg", d); try write("t/photo (1).jpg", d)
        let r = try await scan()
        #expect(keptPaths(plan(.smart, r)[0]) == ["t/photo.jpg"])
    }

    @Test func testLargerFolderRuleKeepsTheFullFolder() async throws {
        let d = random(40_000)
        for i in 0..<5 { try write("full/f\(i).dat", random(30_000 + i)) }
        try write("full/shared.dat", d); try write("stray/shared.dat", d)
        let r = try await scan()
        #expect(keptPaths(plan(.largerFolder, r)[0]) == ["full/shared.dat"])
    }

    @Test func testRecentAndOlderFolderRules() async throws {
        let d = random(40_000)
        try write("new/x.dat", d); try write("old/x.dat", d)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000_000_000)], ofItemAtPath: tmp.appendingPathComponent("old").path)
        let r = try await scan()
        #expect(keptPaths(plan(.recentFolder, r)[0]) == ["new/x.dat"])
        #expect(keptPaths(plan(.olderFolder, r)[0]) == ["old/x.dat"])
    }

    @Test func testNewestOldestShortest() async throws {
        let d = random(40_000)
        try write("a/deep/er/x.dat", d); try write("b/x.dat", d)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000_000_000)], ofItemAtPath: tmp.appendingPathComponent("a/deep/er/x.dat").path)
        let r = try await scan()
        #expect(keptPaths(plan(.newestFile, r)[0]) == ["b/x.dat"])
        #expect(keptPaths(plan(.oldestFile, r)[0]) == ["a/deep/er/x.dat"])
        #expect(keptPaths(plan(.shortestPath, r)[0]) == ["b/x.dat"])
    }

    @Test func testPinnedFolderAndOverrideAndNeverRemovesEverything() async throws {
        let d = random(40_000)
        try write("a/x.dat", d); try write("b/x.dat", d); try write("c/x.dat", d)
        let r = try await scan()
        let pinned = plan(.smart, pinned: [tmp.appendingPathComponent("c").path], r)[0]
        #expect(keptPaths(pinned) == ["c/x.dat"]); #expect(pinned.removed.count == 2)
        let pick = r.sets[0].copies.first { $0.path.hasSuffix("b/x.dat") }!
        let over = Planner(result: r).plan(rule: .smart, overrides: [r.sets[0].id: pick.id])[0]
        #expect(keptPaths(over) == ["b/x.dat"])
        for rule in KeepRule.allCases { #expect(plan(rule, r)[0].kept.count >= 1, "\(rule)") }
    }

    // MARK: the Trash step

    /// A stand-in Trash, so a test never touches the real one: a file under `dupesweep-X/` moves to `dupesweep-X.trash/`.
    /// The setting is shared by every test in the process, so the stand-in holds no state of its own.
    func useFakeTrash() throws {
        Trasher.trashItem = { url in
            let parts = url.pathComponents
            guard let i = parts.firstIndex(where: { $0.hasPrefix("dupesweep-") }) else { throw CocoaError(.fileWriteNoPermission) }
            let trash = URL(fileURLWithPath: NSString.path(withComponents: Array(parts[...i])) + ".trash")
            try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
            let dest = trash.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: dest)
            return dest
        }
    }

    @Test func testMovesOnlyUnchangedFilesAndLeavesTheKeeper() async throws {
        try useFakeTrash()
        let d = random(40_000)
        try write("keep/x.dat", d); try write("dup1/y.dat", d); try write("dup2/z.dat", d)
        let r = try await scan()
        let plans = Planner(result: r).plan(rule: .smart, pinnedFolders: [tmp.appendingPathComponent("keep").path])
        try "changed".write(toFile: tmp.appendingPathComponent("dup2/z.dat").path, atomically: false, encoding: .utf8)      // edited after the scan
        let report = Trasher.move(plans)
        #expect(report.moved.count == 1); #expect(report.skipped.count == 1)
        #expect(FileManager.default.fileExists(atPath: tmp.appendingPathComponent("keep/x.dat").path))
        #expect(FileManager.default.fileExists(atPath: tmp.appendingPathComponent("dup2/z.dat").path))
        #expect(!FileManager.default.fileExists(atPath: tmp.appendingPathComponent("dup1/y.dat").path))
    }

    @Test func testNothingMovesIfTheKeptCopyHasGone() async throws {
        try useFakeTrash()
        let d = random(40_000)
        try write("keep/x.dat", d); try write("dup/y.dat", d)
        let plans = Planner(result: try await scan()).plan(rule: .smart, pinnedFolders: [tmp.appendingPathComponent("keep").path])
        try FileManager.default.removeItem(at: tmp.appendingPathComponent("keep/x.dat"))
        let report = Trasher.move(plans)
        #expect(report.moved.count == 0)
        #expect(FileManager.default.fileExists(atPath: tmp.appendingPathComponent("dup/y.dat").path))
    }

    @Test func testUndoPutsFilesBack() async throws {
        try useFakeTrash()
        let d = random(40_000)
        try write("keep/x.dat", d); try write("dup/y.dat", d)
        let plans = Planner(result: try await scan()).plan(rule: .smart, pinnedFolders: [tmp.appendingPathComponent("keep").path])
        let report = Trasher.move(plans)
        #expect(!FileManager.default.fileExists(atPath: tmp.appendingPathComponent("dup/y.dat").path))
        let u = Trasher.undo(report.moved)
        #expect(u.restored == 1)
        #expect(FileManager.default.fileExists(atPath: tmp.appendingPathComponent("dup/y.dat").path))
    }

    @Test func testSkippedSetsAreLeftAlone() async throws {
        try useFakeTrash()
        let d = random(40_000)
        try write("a/x.dat", d); try write("b/x.dat", d)
        let r = try await scan()
        let plans = Planner(result: r).plan(rule: .smart, skippedSets: [r.sets[0].id])
        #expect(Trasher.move(plans).moved.count == 0)
    }
}
