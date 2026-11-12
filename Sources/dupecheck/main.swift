import Foundation
import DupeEngine

// Developer tool: scan the paths in a text file (one per line) and print what the engine finds.
// usage: dupecheck PATHS.txt [--min-size N] [--workers N] [--show-hidden] [--allow-library]
var args = Array(CommandLine.arguments.dropFirst())
guard let listPath = args.first else { print("usage: dupecheck PATHS.txt [--min-size N] [--workers N] [--show-hidden]"); exit(2) }
var options = ScanOptions()
if let i = args.firstIndex(of: "--min-size"), i + 1 < args.count { options.minSize = Int64(args[i + 1]) ?? options.minSize }
if let i = args.firstIndex(of: "--workers"), i + 1 < args.count { options.workers = Int(args[i + 1]) }
if args.contains("--show-hidden") { options.skipHidden = false }
if args.contains("--allow-library") { options.allowProtectedFolders = true }   // developer only
let roots = try String(contentsOfFile: listPath, encoding: .utf8).split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
let started = Date()
nonisolated(unsafe) var lastLine = Date.distantPast
let result = try await DuplicateScanner().scan(roots: roots, options: options) { p in
    if Date().timeIntervalSince(lastLine) > 5 {
        lastLine = Date()
        FileHandle.standardError.write(Data(String(format: "  phase %d  %d files  read %@ of %@  %.1f GB/s\n", p.phase.rawValue, p.filesFound, Format.bytes(p.readBytes), Format.bytes(p.readTotal), p.bytesPerSecond / 1e9).utf8))
    }
}
print("scanned \(result.filesScanned) files (\(result.iCloudOnlySkipped) iCloud-only counted, not read), \(Format.bytes(result.bytesScanned))")
print("\(result.sets.count) duplicate sets, \(result.sets.reduce(0) { $0 + $1.copies.count }) files in sets, \(result.extraCopies) extra copies, \(String(format: "%.2f", Double(result.extraBytes) / 1e9)) GB of extra copies")
print("read \(Format.bytes(result.bytesRead)) in \(String(format: "%.1f", result.seconds)) s = \(String(format: "%.2f", Double(result.bytesRead) / result.seconds / 1e9)) GB/s overall")
