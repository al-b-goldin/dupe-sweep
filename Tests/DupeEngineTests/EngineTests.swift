import XCTest
@testable import DupeEngine

final class EngineTests: XCTestCase {
    var tmp: URL!
    let mib = 1 << 20

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: (NSTemporaryDirectory() as NSString).appendingPathComponent("dupesweep-" + UUID().uuidString)).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

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

    func testFindsTrueCopiesAndIgnoresSameSizeDecoys() async throws {
        let big = random(6 * mib)
        try write("a/orig.bin", big); try write("b/copy.bin", big); try write("b/decoy.bin", random(6 * mib)); try write("b/alone.bin", random(3 * mib))
        let r = try await scan()
        XCTAssertEqual(names(r), [["copy.bin", "orig.bin"]])
        XCTAssertEqual(r.extraBytes, Int64(6 * mib))
    }

    func testSmallFilesAreComparedInFull() async throws {
        let a = random(20_000)
        var b = a; b[19_999] ^= 0xFF
        try write("x/one.dat", a); try write("y/two.dat", a); try write("y/three.dat", b)
        let r = try await scan()
        XCTAssertEqual(names(r), [["one.dat", "two.dat"]])
    }

    func testFilesThatDifferOnlyInTheMiddleAreNotDuplicates() async throws {
        var a = random(9 * mib); let b = a
        a[4 * mib + 123] ^= 0x01       // between the fingerprint slices
        try write("p/a.bin", a); try write("q/b.bin", b)
        let r = try await scan()
        XCTAssertEqual(r.sets.count, 0)
    }

    func testHardLinkIsOneFileNotTwo() async throws {
        let p = try write("a/file.bin", random(3 * mib))
        try FileManager.default.linkItem(atPath: p, toPath: tmp.appendingPathComponent("b-link.bin").path)
        let r = try await scan()
        XCTAssertEqual(r.sets.count, 0)
    }

    func testSmallAndHiddenFilesAreSkippedWhenAsked() async throws {
        let d = random(50_000), h = random(50_000)
        try write("a/tiny.dat", Data("hi".utf8)); try write("b/tiny.dat", Data("hi".utf8))
        try write("a/.secret.dat", h); try write("b/.secret.dat", h); try write("a/shown.dat", d); try write("b/shown.dat", d)
        let r = try await scan([""]) { $0.minSize = 10_240; $0.skipHidden = true }
        XCTAssertEqual(names(r), [["shown.dat", "shown.dat"]])
        let all = try await scan([""]) { $0.skipHidden = false }
        XCTAssertEqual(all.sets.count, 3)
    }

    func testCloneCountsAsFreeButARealCopyDoesNot() async throws {
        let big = random(5 * mib)
        let a = try write("keep/orig.bin", big)
        try write("real/copy.bin", big)
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/cp"); p.arguments = ["-c", a, tmp.appendingPathComponent("clone/copy.bin").path]
        try FileManager.default.createDirectory(at: tmp.appendingPathComponent("clone"), withIntermediateDirectories: true)
        try p.run(); p.waitUntilExit()
        try XCTSkipIf(p.terminationStatus != 0, "this volume cannot clone")
        let r = try await scan()
        let plans = Planner(result: r).plan(rule: .smart, pinnedFolders: [tmp.appendingPathComponent("keep").path])
        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(plans[0].removed.count, 2)
        XCTAssertEqual(plans[0].freed, Int64(5 * mib))      // the clone frees nothing, the real copy frees its size
    }

    func testRefusesSystemFolders() async throws {
        var o = ScanOptions(); o.minSize = 1
        let r = try await DuplicateScanner().scan(roots: [URL(fileURLWithPath: "/System")], options: o) { _ in }
        XCTAssertEqual(r.refusedFolders, ["/System"]); XCTAssertEqual(r.filesScanned, 0)
    }

    func testCancelledScanThrows() async throws {
        try write("a/x.bin", random(1000))
        let s = DuplicateScanner(); s.cancel()
        do { _ = try await s.scan(roots: [tmp], options: ScanOptions()) { _ in }; XCTFail("should throw") } catch is CancellationError {}
    }

    // MARK: choosing which copy to keep

    func plan(_ rule: KeepRule, pinned: [String] = [], _ r: ScanResult) -> [SetPlan] { Planner(result: r).plan(rule: rule, pinnedFolders: pinned) }
    func keptPaths(_ p: SetPlan) -> [String] { p.kept.map { $0.path.replacingOccurrences(of: tmp.path + "/", with: "") } }

    func testSmartKeepsTheOriginalNotTheCopyNamed() async throws {
        let d = random(40_000)
        try write("t/photo.jpg", d); try write("t/photo copy.jpg", d); try write("t/photo (1).jpg", d)
        let r = try await scan()
        XCTAssertEqual(keptPaths(plan(.smart, r)[0]), ["t/photo.jpg"])
    }

    func testLargerFolderRuleKeepsTheFullFolder() async throws {
        let d = random(40_000)
        for i in 0..<5 { try write("full/f\(i).dat", random(30_000 + i)) }
        try write("full/shared.dat", d); try write("stray/shared.dat", d)
        let r = try await scan()
        XCTAssertEqual(keptPaths(plan(.largerFolder, r)[0]), ["full/shared.dat"])
    }

    func testRecentAndOlderFolderRules() async throws {
        let d = random(40_000)
        try write("new/x.dat", d); try write("old/x.dat", d)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000_000_000)], ofItemAtPath: tmp.appendingPathComponent("old").path)
        let r = try await scan()
        XCTAssertEqual(keptPaths(plan(.recentFolder, r)[0]), ["new/x.dat"])
        XCTAssertEqual(keptPaths(plan(.olderFolder, r)[0]), ["old/x.dat"])
    }

    func testNewestOldestShortest() async throws {
        let d = random(40_000)
        try write("a/deep/er/x.dat", d); try write("b/x.dat", d)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000_000_000)], ofItemAtPath: tmp.appendingPathComponent("a/deep/er/x.dat").path)
        let r = try await scan()
        XCTAssertEqual(keptPaths(plan(.newestFile, r)[0]), ["b/x.dat"])
        XCTAssertEqual(keptPaths(plan(.oldestFile, r)[0]), ["a/deep/er/x.dat"])
        XCTAssertEqual(keptPaths(plan(.shortestPath, r)[0]), ["b/x.dat"])
    }

    func testPinnedFolderAndOverrideAndNeverRemovesEverything() async throws {
        let d = random(40_000)
        try write("a/x.dat", d); try write("b/x.dat", d); try write("c/x.dat", d)
        let r = try await scan()
        let pinned = plan(.smart, pinned: [tmp.appendingPathComponent("c").path], r)[0]
        XCTAssertEqual(keptPaths(pinned), ["c/x.dat"]); XCTAssertEqual(pinned.removed.count, 2)
        let pick = r.sets[0].copies.first { $0.path.hasSuffix("b/x.dat") }!
        let over = Planner(result: r).plan(rule: .smart, overrides: [r.sets[0].id: pick.id])[0]
        XCTAssertEqual(keptPaths(over), ["b/x.dat"])
        for rule in KeepRule.allCases { XCTAssertGreaterThanOrEqual(plan(rule, r)[0].kept.count, 1, "\(rule)") }
    }

    // MARK: the Trash step

    var fakeTrash: URL!
    func useFakeTrash() throws {
        fakeTrash = tmp.deletingLastPathComponent().appendingPathComponent("fake-trash-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: fakeTrash, withIntermediateDirectories: true)
        let t = fakeTrash!
        Trasher.trashItem = { url in let dest = t.appendingPathComponent(url.lastPathComponent); try FileManager.default.moveItem(at: url, to: dest); return dest }
        addTeardownBlock { try? FileManager.default.removeItem(at: t) }
    }

    func testMovesOnlyUnchangedFilesAndLeavesTheKeeper() async throws {
        try useFakeTrash()
        let d = random(40_000)
        try write("keep/x.dat", d); try write("dup1/y.dat", d); try write("dup2/z.dat", d)
        let r = try await scan()
        let plans = Planner(result: r).plan(rule: .smart, pinnedFolders: [tmp.appendingPathComponent("keep").path])
        try "changed".write(toFile: tmp.appendingPathComponent("dup2/z.dat").path, atomically: false, encoding: .utf8)      // edited after the scan
        let report = Trasher.move(plans)
        XCTAssertEqual(report.moved.count, 1); XCTAssertEqual(report.skipped.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.appendingPathComponent("keep/x.dat").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.appendingPathComponent("dup2/z.dat").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.appendingPathComponent("dup1/y.dat").path))
    }

    func testNothingMovesIfTheKeptCopyHasGone() async throws {
        try useFakeTrash()
        let d = random(40_000)
        try write("keep/x.dat", d); try write("dup/y.dat", d)
        let plans = Planner(result: try await scan()).plan(rule: .smart, pinnedFolders: [tmp.appendingPathComponent("keep").path])
        try FileManager.default.removeItem(at: tmp.appendingPathComponent("keep/x.dat"))
        let report = Trasher.move(plans)
        XCTAssertEqual(report.moved.count, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.appendingPathComponent("dup/y.dat").path))
    }

    func testUndoPutsFilesBack() async throws {
        try useFakeTrash()
        let d = random(40_000)
        try write("keep/x.dat", d); try write("dup/y.dat", d)
        let plans = Planner(result: try await scan()).plan(rule: .smart, pinnedFolders: [tmp.appendingPathComponent("keep").path])
        let report = Trasher.move(plans)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.appendingPathComponent("dup/y.dat").path))
        let u = Trasher.undo(report.moved)
        XCTAssertEqual(u.restored, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.appendingPathComponent("dup/y.dat").path))
    }

    func testSkippedSetsAreLeftAlone() async throws {
        try useFakeTrash()
        let d = random(40_000)
        try write("a/x.dat", d); try write("b/x.dat", d)
        let r = try await scan()
        let plans = Planner(result: r).plan(rule: .smart, skippedSets: [r.sets[0].id])
        XCTAssertEqual(Trasher.move(plans).moved.count, 0)
    }
}
