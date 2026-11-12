import SwiftUI
import AppKit
import Observation
import DupeEngine

enum Stage { case start, scanning, results, done }

enum SizeFloor: Int64, CaseIterable, Identifiable {
    case any = 1, kb10 = 10_240, kb100 = 102_400, mb1 = 1_048_576, mb10 = 10_485_760
    var id: Int64 { rawValue }
    var title: String {
        switch self { case .any: return "Any size"; case .kb10: return "10 KB"; case .kb100: return "100 KB"; case .mb1: return "1 MB"; case .mb10: return "10 MB" }
    }
}

@MainActor @Observable
final class AppModel {
    var stage: Stage = .start
    var folders: [URL] = []
    var floor: SizeFloor = .kb10
    var includeHidden = false
    var rule: KeepRule = .smart { didSet { replan() } }
    var pinned: [String] = [] { didSet { replan() } }
    var overrides: [String: Int] = [:]
    var skipped: Set<String> = []
    var progress = ScanProgress()
    var result: ScanResult?
    var plans: [SetPlan] = []
    var report: TrashReport?
    var trashProgress: (done: Int, total: Int)?
    var restored: Int?
    var message: String?
    var expanded: Set<String> = []
    private var scanner: DuplicateScanner?
    private var task: Task<Void, Never>?

    // MARK: choosing folders

    func add(_ urls: [URL]) {
        for u in urls where !folders.contains(u) { folders.append(u) }
    }
    func remove(_ u: URL) { folders.removeAll { $0 == u } }

    func choose() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = true; p.allowsMultipleSelection = true
        p.prompt = "Add"; p.message = "Choose the folders to check for duplicate files."
        if p.runModal() == .OK { add(p.urls) }
    }

    func pick(forPinned: Bool = true) {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = true
        p.prompt = "Always keep"; p.message = "Copies inside these folders will always stay."
        if p.runModal() == .OK { pin(p.urls) }
    }
    func pin(_ urls: [URL]) { for u in urls where !pinned.contains(u.path) { pinned.append(u.path) } }
    func unpin(_ path: String) { pinned.removeAll { $0 == path } }

    // MARK: scanning

    func startScan() {
        guard !folders.isEmpty else { return }
        var o = ScanOptions()
        o.minSize = floor.rawValue; o.skipHidden = !includeHidden
        progress = ScanProgress(); result = nil; plans = []; overrides = [:]; skipped = []; message = nil
        stage = .scanning
        let s = DuplicateScanner(); scanner = s
        let roots = folders
        task = Task { [weak self] in
            do {
                let r = try await s.scan(roots: roots, options: o) { p in Task { @MainActor in self?.progress = p } }
                self?.result = r
                self?.replan()
                if !r.refusedFolders.isEmpty { self?.message = "Skipped protected folders: " + r.refusedFolders.joined(separator: ", ") }
                self?.stage = .results
            } catch is CancellationError {
                self?.stage = .start
            } catch {
                self?.message = error.localizedDescription; self?.stage = .start
            }
        }
    }

    func cancelScan() { scanner?.cancel(); task?.cancel() }

    // MARK: choices

    func replan() {
        guard let r = result else { return }
        plans = Planner(result: r).plan(rule: rule, pinnedFolders: pinned, overrides: overrides, skippedSets: skipped)
    }
    func keep(_ file: FileItem, in set: DuplicateSet) { overrides[set.id] = file.id; skipped.remove(set.id); replan() }
    func toggleSkip(_ set: DuplicateSet) { if skipped.contains(set.id) { skipped.remove(set.id) } else { skipped.insert(set.id) }; replan() }
    func resetChoices() { overrides = [:]; skipped = []; replan() }

    var removeCount: Int { plans.reduce(0) { $0 + $1.removed.count } }
    var removeBytes: Int64 { plans.reduce(0) { $0 + $1.removedBytes } }
    var freedBytes: Int64 { plans.reduce(0) { $0 + ($1.skipped ? 0 : $1.freed) } }
    var activeSets: Int { plans.filter { !$0.removed.isEmpty }.count }

    // MARK: moving to the Trash

    func moveToTrash() {
        let work = plans.filter { !$0.removed.isEmpty }
        trashProgress = (0, work.reduce(0) { $0 + $1.removed.count })
        Task.detached(priority: .userInitiated) { [model = self] in
            let rep = Trasher.move(work) { done, total in Task { @MainActor in model.trashProgress = (done, total) } }
            await MainActor.run { model.report = rep; model.trashProgress = nil; model.stage = .done }
        }
    }

    func undo() {
        guard let moved = report?.moved else { return }
        Task.detached { [model = self] in
            let u = Trasher.undo(moved)
            await MainActor.run { model.restored = u.restored }
        }
    }

    func startOver() { cancelScan(); stage = .start; result = nil; plans = []; report = nil; restored = nil; overrides = [:]; skipped = []; message = nil }

    func reveal(_ f: FileItem) { NSWorkspace.shared.activateFileViewerSelecting([f.url]) }
    func openTrash() { NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory() + "/.Trash")) }
}
