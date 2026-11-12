import Foundation
import Darwin

/// Walks folders with readdir and lstat: fast, never follows links, never opens a file.
struct WalkResult {
    var files: [FileItem] = []
    var iCloudOnly = 0
    var unreadable = 0
    var refused: [String] = []
    var folderFileCount: [String: Int] = [:]
    var folderModified: [String: Date] = [:]
}

enum Protected {
    /// Folders nobody should clean duplicates out of.
    static let roots = ["/", "/System", "/Library", "/usr", "/bin", "/sbin", "/private", "/etc", "/var", "/Applications", "/cores", "/opt"]
    static let skipNames: Set<String> = [".DS_Store", ".localized", "node_modules", ".Trashes", ".Spotlight-V100", ".fseventsd", ".TemporaryItems", ".DocumentRevisions-V100", ".MobileBackups"]
    static let packageSuffixes = [".app", ".framework", ".photoslibrary", ".musiclibrary", ".tvlibrary", ".imovielibrary", ".fcpbundle", ".lrlibrary", ".bundle", ".plugin", ".kext", ".xcodeproj", ".xcworkspace"]

    static func isProtectedRoot(_ path: String) -> Bool {
        let p = (path as NSString).standardizingPath
        if roots.contains(p) { return true }
        let home = NSHomeDirectory()
        return p == home + "/Library" || p.hasPrefix(home + "/Library/") || p.hasPrefix("/System/") || p.hasPrefix("/Library/") || p.hasPrefix("/usr/") || p.hasPrefix("/private/") || p.hasPrefix("/Applications/")
    }
}

func walkTree(roots: [URL], options: ScanOptions, shouldStop: () -> Bool, tick: (Int, Int64, String) -> Void) -> WalkResult {
    var out = WalkResult()
    var seen = Set<String>()
    var nextID = 0
    var stack: [String] = []
    for r in roots {
        let p = (r.path as NSString).standardizingPath
        if !options.allowProtectedFolders && Protected.isProtectedRoot(p) { out.refused.append(p); continue }
        stack.append(p)
    }
    var bytes: Int64 = 0

    func consider(_ path: String, _ st: stat) {
        let size = Int64(st.st_size)
        if size < options.minSize || size == 0 { return }
        if !seen.insert(path).inserted { return }
        let dataless = (UInt32(st.st_flags) & 0x4000_0000) != 0
        if dataless { out.iCloudOnly += 1; return }
        let item = FileItem(
            id: nextID, path: path, size: size,
            modified: Date(timeIntervalSince1970: Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1e9),
            created: Date(timeIntervalSince1970: Double(st.st_birthtimespec.tv_sec) + Double(st.st_birthtimespec.tv_nsec) / 1e9),
            device: st.st_dev, inode: UInt64(st.st_ino), isICloudSynced: false)
        nextID += 1
        out.files.append(item)
        bytes += size
        out.folderFileCount[(path as NSString).deletingLastPathComponent, default: 0] += 1
    }

    while let dir = stack.popLast() {
        if shouldStop() { break }
        var rootStat = stat()
        if lstat(dir, &rootStat) != 0 { out.unreadable += 1; continue }
        let mode = rootStat.st_mode & S_IFMT
        if mode == S_IFREG { consider(dir, rootStat); continue }
        if mode != S_IFDIR { continue }
        out.folderModified[dir] = Date(timeIntervalSince1970: Double(rootStat.st_mtimespec.tv_sec))
        guard let d = opendir(dir) else { out.unreadable += 1; continue }
        tick(out.files.count, bytes, (dir as NSString).lastPathComponent)
        while let ent = readdir(d) {
            let name = withUnsafePointer(to: &ent.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
            }
            if name == "." || name == ".." { continue }
            if options.skipHidden && name.hasPrefix(".") { continue }
            if Protected.skipNames.contains(name) { continue }
            let path = dir == "/" ? "/" + name : dir + "/" + name
            var st = stat()
            if lstat(path, &st) != 0 { out.unreadable += 1; continue }
            let m = st.st_mode & S_IFMT
            if m == S_IFDIR {
                if options.skipPackages && Protected.packageSuffixes.contains(where: { name.lowercased().hasSuffix($0) }) { continue }
                stack.append(path)
            } else if m == S_IFREG {
                consider(path, st)
            }
        }
        closedir(d)
    }
    return out
}
