import Foundation
import Testing
@testable import DupeSweep
@testable import DupeEngine

/// Workflow tests: each test moves through one user workflow of the app, step by step, the way the screens do.
/// The screens are thin: every button calls one `AppModel` function and every label reads one `AppModel` value.
/// So a test calls the function behind the button, then checks what the next screen shows and what is on disk.
///
/// Safety: every file is an invented file in a scratch folder under the temporary directory. The Trash is a stand-in
/// folder beside the scratch folder. No test touches a real folder of the user or the real Trash.
@Suite(.serialized) @MainActor
final class WorkflowTests {
    let root: URL
    let model = AppModel()
    let fm = FileManager.default

    init() throws {
        root = URL(fileURLWithPath: (NSTemporaryDirectory() as NSString).appendingPathComponent("dupesweep-flow-" + UUID().uuidString)).resolvingSymlinksInPath()
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
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
    deinit {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(atPath: root.path + ".trash")
    }

    // MARK: helpers

    func put(_ rel: String, _ data: Data) throws {
        let u = root.appendingPathComponent(rel)
        try fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: u)
    }
    func random(_ n: Int) -> Data { Data((0..<n).map { _ in UInt8.random(in: 0...255) }) }
    func exists(_ rel: String) -> Bool { fm.fileExists(atPath: root.appendingPathComponent(rel).path) }

    /// Waits, with a time limit, until the app reaches the screen the step leads to.
    func wait(_ what: String, seconds: Double = 30, until done: () -> Bool) async {
        let end = Date().addingTimeInterval(seconds)
        while !done(), Date() < end { try? await Task.sleep(nanoseconds: 20_000_000) }
        #expect(done(), "the app did not reach: \(what) within \(Int(seconds)) s")
    }

    /// An invented library: a video with two extra copies, a document with one extra copy, and files without copies.
    func makeLibrary() throws {
        let video = random(300_000), doc = random(60_000)
        for i in 0..<6 { try put("Library/Photos/p\(i).dat", random(20_000 + i)) }
        try put("Library/Photos/trip.mov", video); try put("Inbox/trip copy.mov", video); try put("Backup/trip.mov", video)
        try put("Library/Docs/report.pdf", doc); try put("Inbox/report (1).pdf", doc)
        try put("Library/Docs/unique.pdf", random(60_000))
    }

    /// Steps 1 and 2 of every workflow: add the folder, press Find Duplicates, wait for the next screen.
    func scan() async {
        #expect(model.stage == .start && model.folders.isEmpty, "step 1: the app opens on the start screen. Find Duplicates is off until a folder is added")
        model.add([root])
        #expect(model.folders == [root], "step 1: the dropped folder shows under “To check”, which turns Find Duplicates on")
        model.startScan()
        #expect(model.stage == .scanning, "step 2: Find Duplicates opens the progress screen (it has Cancel)")
        await wait("the results screen") { self.model.stage != .scanning }
    }

    // MARK: workflows

    @Test func scanReviewMoveToTrashAndPutEverythingBack() async throws {
        try makeLibrary()
        await scan()
        #expect(model.stage == .results, "step 3: the scan ends on the results screen")
        #expect(model.plans.count == 2 && model.removeCount == 3, "step 3: the screen shows 2 sets and 3 extra copies (got \(model.plans.count) sets, \(model.removeCount) copies)")
        #expect(model.removeCount > 0, "step 3: “Move to Trash…” is on, because there is something to move")
        #expect(model.scanNotes.isEmpty && !model.nothingChecked, "step 3: nothing was left out, so the screen shows no warning line")
        let kept = model.plans.flatMap { $0.kept.map(\.name) }.sorted()
        #expect(kept == ["report.pdf", "trip.mov"], "step 3: Smart keeps the originals, not “copy” or “(1)” (kept \(kept))")

        model.moveToTrash()                                   // the user confirmed “Move to Trash”
        await wait("the done screen") { self.model.stage == .done }
        #expect(model.report?.moved.count == 3 && !model.nothingMoved, "step 4: the done screen says 3 files moved")
        #expect(exists("Library/Photos/trip.mov") && exists("Library/Docs/report.pdf"), "step 4: the kept originals are untouched on disk")
        #expect(!exists("Inbox/trip copy.mov") && !exists("Backup/trip.mov") && !exists("Inbox/report (1).pdf"), "step 4: the extra copies left their folders")
        #expect(model.restored == nil, "step 4: “Put Everything Back” is offered, because files moved and nothing is put back yet")

        model.undo()                                          // Put Everything Back
        await wait("the “Put 3 files back” message") { self.model.restored != nil }
        #expect(model.restored == 3 && model.restoreFailed == 0, "step 5: all 3 files are put back")
        #expect(exists("Inbox/trip copy.mov") && exists("Backup/trip.mov") && exists("Inbox/report (1).pdf"), "step 5: the files are back in their folders on disk")

        model.startOver()                                     // Done
        #expect(model.stage == .start && model.folders == [root] && model.result == nil && model.report == nil,
                "step 6: Done returns to the start screen. The folder is still listed, so the next scan is one click")
    }

    @Test func chooseADifferentCopyLeaveASetAloneAndReset() async throws {
        try makeLibrary()
        await scan()
        let big = try #require(model.plans.first { $0.set.copies.count == 3 })
        let other = try #require(big.set.copies.first { !big.keepIDs.contains($0.id) })

        model.keep(other, in: big.set)                        // “Keep this one”
        #expect(model.plans.first { $0.id == big.id }?.keepIDs == [other.id], "“Keep this one” makes that copy the one that stays")
        #expect(!model.overrides.isEmpty, "after a choice the bar offers “Reset My Choices”")
        #expect(model.removeCount == 3, "a different keeper does not change how many copies go")

        model.toggleSkip(big.set)                             // “Leave this set alone”
        #expect(model.removeCount == 1 && model.activeSets == 1, "a set left alone moves nothing: the bar now counts 1 file (got \(model.removeCount))")
        model.toggleSkip(big.set)                             // “Include this set again”
        #expect(model.removeCount == 3, "“Include this set again” puts its copies back in the count")

        for rule in KeepRule.allCases {                       // “Which copy should stay?”
            model.rule = rule
            #expect(model.plans.allSatisfy { !$0.kept.isEmpty }, "rule \(rule.title): every set keeps at least one copy")
        }
        model.rule = .smart

        model.pin([root.appendingPathComponent("Backup")])    // “Always keep copies in:”
        #expect(model.plans.first { $0.id == big.id }?.keepIDs == [other.id], "a copy the user picked by hand wins over an always-keep folder")
        model.resetChoices()                                  // “Reset My Choices”
        #expect(model.overrides.isEmpty && model.skipped.isEmpty, "Reset My Choices clears the hand-made choices")
        #expect(model.plans.first { $0.id == big.id }?.kept.map(\.path) == [root.appendingPathComponent("Backup/trip.mov").path], "the always-keep folder now decides: the Backup copy stays")
        model.unpin(root.appendingPathComponent("Backup").path)
        #expect(model.plans.first { $0.id == big.id }?.kept.map(\.name) == ["trip.mov"] && model.removeCount == 3, "without the always-keep folder the rule decides again")

        model.toggleSkip(model.plans[0].set); model.toggleSkip(model.plans[1].set)
        #expect(model.removeCount == 0, "with every set left alone, nothing is counted, so “Move to Trash…” is off")
        #expect(!model.skipped.isEmpty, "…and “Reset My Choices” is the control that leads on")
    }

    @Test func aFolderWithoutDuplicatesSaysSoAndLeadsBack() async throws {
        for i in 0..<4 { try put("Notes/n\(i).txt", random(30_000 + i)) }
        await scan()
        #expect(model.stage == .results && model.plans.isEmpty, "the scan ends on the “No duplicates found” screen")
        #expect(!model.nothingChecked && model.result?.filesScanned == 4, "the screen says 4 files were checked")
        model.startOver()                                     // “Check Something Else”
        #expect(model.stage == .start, "“Check Something Else” returns to the start screen")
    }

    @Test func aProtectedFolderIsNamedOnTheResultsScreen() async throws {
        // Before the fix the results screen said “No duplicates found. Checked 0 files” and never named the folder.
        #expect(model.stage == .start)
        model.add([URL(fileURLWithPath: "/System")])          // refused before any file is read
        model.startScan()
        await wait("the results screen") { self.model.stage != .scanning }
        #expect(model.stage == .results && model.nothingChecked, "the screen must say “Nothing was checked”, not “No duplicates found”")
        #expect(model.scanNotes.count == 1 && model.scanNotes[0].contains("/System"), "the screen must name the folder that was not checked (notes: \(model.scanNotes))")
        model.startOver()                                     // “Choose Other Folders”
        #expect(model.stage == .start && model.message == nil, "“Choose Other Folders” returns to the start screen")
    }

    @Test func aProtectedFolderBesideARealOneIsStillNamed() async throws {
        try makeLibrary()
        model.add([URL(fileURLWithPath: "/System")])
        model.add([root])
        model.startScan()
        await wait("the results screen") { self.model.stage != .scanning }
        #expect(model.plans.count == 2 && !model.nothingChecked, "the real folder is scanned as usual")
        #expect(model.scanNotes.contains { $0.contains("/System") }, "the results screen names the folder that was left out")
    }

    @Test func filesSmallerThanTheLimitGiveAClearEmptyScreen() async throws {
        try put("Tiny/a.txt", Data("same".utf8)); try put("Tiny/b.txt", Data("same".utf8))
        await scan()                                          // the default limit is 10 KB
        #expect(model.stage == .results && model.nothingChecked && model.scanNotes.isEmpty, "no file reaches the size limit: the screen says “Nothing was checked” and points to Options")
        model.startOver(); model.floor = .any                 // Options > Ignore files smaller than > Any size
        model.startScan()
        await wait("the results screen") { self.model.stage != .scanning }
        #expect(model.plans.count == 1, "with “Any size” the two small copies are found")
    }

    @Test func cancelReturnsToTheStartScreen() async throws {
        try makeLibrary()
        model.add([root])
        model.startScan()
        model.cancelScan()                                    // Cancel
        await wait("the start screen") { self.model.stage == .start }
        #expect(model.result == nil && model.folders == [root], "after Cancel the start screen still lists the folder, so Find Duplicates is on")
    }

    @Test func aCopyThatChangedAfterTheScanStaysAndTheScreenSaysSo() async throws {
        let d = random(40_000)
        try put("Keep/x.dat", d); try put("Inbox/x copy.dat", d)
        await scan()
        #expect(model.removeCount == 1)
        try Data("edited after the scan".utf8).write(to: root.appendingPathComponent("Inbox/x copy.dat"))
        model.moveToTrash()
        await wait("the done screen") { self.model.stage == .done }
        #expect(model.nothingMoved && model.report?.skipped.count == 1, "the done screen must say “No files were moved”, not “Moved 0 files to the Trash”")
        #expect(exists("Inbox/x copy.dat") && exists("Keep/x.dat"), "the edited file and the kept file are both still there")
        model.scanAgain()                                     // “Scan Again”
        await wait("the results screen") { self.model.stage == .results }
        #expect(model.plans.isEmpty && model.result?.filesScanned == 1, "Scan Again shows the folders as they are now: the edited file is no longer a copy")
    }

    @Test func aFileThatCannotBePutBackIsCounted() async throws {
        // Before the fix the screen said “Put 2 files back. They are exactly where they were before.” and hid the third.
        try makeLibrary()
        await scan()
        model.moveToTrash()
        await wait("the done screen") { self.model.stage == .done }
        try put("Inbox/report (1).pdf", random(500))          // something else took the place of one moved file
        model.undo()
        await wait("the put-back message") { self.model.restored != nil }
        #expect(model.restored == 2 && model.restoreFailed == 1, "2 files go back and the screen counts the 1 that could not (restored \(model.restored ?? -1), failed \(model.restoreFailed))")
    }
}
