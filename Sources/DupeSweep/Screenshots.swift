import SwiftUI
import AppKit
import DupeEngine

/// Developer mode: `DupeSweep --screenshots DIR` renders the main screens with made-up data to PNG files and quits.
@MainActor
enum Screenshots {
    static func file(_ i: Int, _ path: String, _ size: Int64, daysAgo: Double) -> FileItem {
        FileItem(id: i, path: path, size: size, modified: Date().addingTimeInterval(-daysAgo * 86400), created: Date().addingTimeInterval(-daysAgo * 86400))
    }

    static func sample() -> ScanResult {
        let h = NSHomeDirectory()
        var id = 0
        func set(_ name: String, _ size: Int64, _ places: [(String, Double)]) -> DuplicateSet {
            let copies = places.map { p -> FileItem in id += 1; return file(id, h + "/" + p.0 + "/" + name, size, daysAgo: p.1) }
            return DuplicateSet(id: name, size: size, copies: copies)
        }
        let sets = [
            set("Wedding highlights.mov", 4_820_000_000, [("Movies/Wedding", 620), ("Downloads", 12), ("Desktop/Old stuff", 400)]),
            set("Tax return 2023.pdf", 3_400_000, [("Documents/Taxes", 700), ("Downloads", 30)]),
            set("IMG_4032.HEIC", 2_900_000, [("Pictures/Camera Roll", 300), ("Pictures/Camera Roll copy", 290), ("Downloads", 15)]),
            set("Project proposal v3.pptx", 18_700_000, [("Documents/Work", 90), ("Documents/Work/Archive", 80)]),
            set("Podcast episode 12.wav", 412_000_000, [("Music/Podcast", 200), ("Desktop", 180)]),
            set("Holiday card.indd", 96_000_000, [("Documents/Cards", 365), ("Downloads", 360)]),
        ]
        var folders: [String: Int] = [:]
        for s in sets { for c in s.copies { folders[c.folder] = [("Movies/Wedding", 214), ("Documents/Taxes", 38), ("Pictures/Camera Roll", 3_212), ("Documents/Work", 530)].first { c.folder.hasSuffix($0.0) }?.1 ?? 6 } }
        return ScanResult(sets: sets, filesScanned: 41_873, bytesScanned: 612_400_000_000, folderFileCount: folders, seconds: 214)
    }

    static func snapshot(_ win: NSWindow, name: String, dir: String, dark: Bool) {
        guard let v = win.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { print("snapshot failed: \(name)"); return }
        v.cacheDisplay(in: v.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + (dark ? "-dark" : "") + ".png"))
        print("wrote \(name)\(dark ? "-dark" : "")")
    }

    static func run(into dir: String, model m: AppModel) async {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        NSApp.activate(ignoringOtherApps: true)
        guard let win = NSApp.windows.first(where: { $0.contentView != nil }) else { print("no window"); exit(1) }
        win.setContentSize(NSSize(width: 880, height: 700))
        for dark in [false, true] {
            NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            func shot(_ name: String) async { try? await Task.sleep(nanoseconds: 900_000_000); snapshot(win, name: name, dir: dir, dark: dark) }

            m.stage = .start; m.folders = [URL(fileURLWithPath: NSHomeDirectory() + "/Pictures"), URL(fileURLWithPath: NSHomeDirectory() + "/Downloads"), URL(fileURLWithPath: "/Volumes/Backup/Photos")]
            await shot("1-start")

            var p = ScanProgress(); p.phase = .reading; p.filesFound = 41_873; p.bytesFound = 612_400_000_000; p.candidateFiles = 9_204
            p.readTotal = 188_000_000_000; p.readBytes = 114_000_000_000; p.bytesPerSecond = 2_900_000_000; p.etaSeconds = 26; p.currentName = "Wedding highlights.mov"
            m.progress = p; m.stage = .scanning
            await shot("2-scanning")

            m.result = sample(); m.replan(); m.expanded = [m.plans[0].id]; m.stage = .results
            await shot("3-results")

            m.rule = .largerFolder; m.expanded = [m.plans[2].id]
            await shot("3b-results-larger-folder")
            m.rule = .smart

            var rep = TrashReport(); rep.moved = (0..<14).map { TrashRecord(original: "/x/\($0)", trashed: nil, size: 560_000_000) }
            m.report = rep; m.stage = .done
            await shot("4-done")
        }
        exit(0)
    }
}
