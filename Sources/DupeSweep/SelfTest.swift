import Foundation
import DupeEngine

/// `DupeSweep --selftest` drives the whole flow (add folders, scan, choose, move, put back) on a scratch folder, with a stand-in Trash.
@MainActor
enum SelfTest {
    static func run(model m: AppModel) async {
        var failures: [String] = []
        func check(_ ok: Bool, _ what: String) { print((ok ? "PASS  " : "FAIL  ") + what); if !ok { failures.append(what) } }
        let fm = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("dupesweep-selftest-\(UUID().uuidString)").resolvingSymlinksInPath()
        let trash = root.appendingPathComponent("_trash")
        try? fm.createDirectory(at: trash, withIntermediateDirectories: true)
        Trasher.trashItem = { url in let d = trash.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent); try fm.moveItem(at: url, to: d); return d }
        func put(_ rel: String, _ data: Data) { let u = root.appendingPathComponent(rel); try? fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true); try? data.write(to: u) }
        func rnd(_ n: Int) -> Data { Data((0..<n).map { _ in UInt8.random(in: 0...255) }) }
        let video = rnd(30_000_000), doc = rnd(200_000)
        for i in 0..<6 { put("Library/Photos/p\(i).dat", rnd(60_000 + i)) }
        put("Library/Photos/trip.mov", video); put("Downloads/trip copy.mov", video); put("Backup/trip.mov", video)
        put("Library/Docs/report.pdf", doc); put("Downloads/report (1).pdf", doc)
        put("Library/Docs/unique.pdf", rnd(200_000))

        m.add([root])
        m.startScan()
        for _ in 0..<600 where m.stage == .scanning { try? await Task.sleep(nanoseconds: 100_000_000) }
        check(m.stage == .results, "scan finishes and shows results")
        check(m.plans.count == 2, "finds 2 sets of duplicates (found \(m.plans.count))")
        check(m.removeCount == 3, "3 extra copies are proposed for the Trash (got \(m.removeCount))")
        let kept = m.plans.flatMap { $0.kept.map { ($0.path as NSString).lastPathComponent } }.sorted()
        check(kept == ["report.pdf", "trip.mov"], "smart rule keeps the originals, not 'copy' or '(1)' (kept \(kept))")
        let big = m.plans.first { $0.set.size == 30_000_000 }!
        let other = big.set.copies.first { !big.keepIDs.contains($0.id) }!
        m.keep(other, in: big.set)
        check(m.plans.first { $0.set.size == 30_000_000 }!.keepIDs == [other.id], "clicking a copy makes it the one that stays")
        m.rule = .largerFolder
        check(m.plans.allSatisfy { !$0.kept.isEmpty }, "every rule leaves at least one copy")
        m.resetChoices(); m.rule = .smart

        m.moveToTrash()
        for _ in 0..<300 where m.stage != .done { try? await Task.sleep(nanoseconds: 100_000_000) }
        check(m.stage == .done && m.report?.moved.count == 3, "3 files moved to the Trash (moved \(m.report?.moved.count ?? -1))")
        check(fm.fileExists(atPath: root.appendingPathComponent("Library/Photos/trip.mov").path) && fm.fileExists(atPath: root.appendingPathComponent("Library/Docs/report.pdf").path), "the kept originals are untouched")
        check(!fm.fileExists(atPath: root.appendingPathComponent("Downloads/trip copy.mov").path), "the extra copy is gone from its folder")
        m.undo()
        for _ in 0..<100 where m.restored == nil { try? await Task.sleep(nanoseconds: 100_000_000) }
        check(m.restored == 3 && fm.fileExists(atPath: root.appendingPathComponent("Downloads/trip copy.mov").path), "Put Everything Back restores all 3")
        try? fm.removeItem(at: root)
        print(failures.isEmpty ? "ALL PASSED" : "FAILED: \(failures.count)")
        exit(failures.isEmpty ? 0 : 1)
    }
}
