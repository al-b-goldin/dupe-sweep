import Foundation

/// One file found while scanning.
public struct FileItem: Identifiable, Hashable, Sendable {
    public let id: Int
    public let path: String
    public let size: Int64
    public let modified: Date
    public let created: Date
    public let device: Int32
    public let inode: UInt64
    public let isICloudSynced: Bool
    public init(id: Int, path: String, size: Int64, modified: Date, created: Date, device: Int32 = 0, inode: UInt64 = 0, isICloudSynced: Bool = false) {
        self.id = id; self.path = path; self.size = size; self.modified = modified; self.created = created
        self.device = device; self.inode = inode; self.isICloudSynced = isICloudSynced
    }
    public var url: URL { URL(fileURLWithPath: path) }
    public var name: String { (path as NSString).lastPathComponent }
    public var folder: String { (path as NSString).deletingLastPathComponent }
}

/// Two or more files with exactly the same contents (same size and same SHA-256).
public struct DuplicateSet: Identifiable, Hashable, Sendable {
    public let id: String
    public let size: Int64
    public let copies: [FileItem]
    public init(id: String, size: Int64, copies: [FileItem]) { self.id = id; self.size = size; self.copies = copies }
}

public struct ScanOptions: Sendable {
    /// Files smaller than this are ignored.
    public var minSize: Int64 = 10_240
    /// Ignore files and folders whose names start with a dot.
    public var skipHidden = true
    /// Do not look inside apps, photo libraries and similar packages.
    public var skipPackages = true
    /// Files read at once. nil picks a sensible number for the drive.
    public var workers: Int? = nil
    /// For tests and the developer tool only. The app never sets this: system folders and ~/Library stay off limits.
    public var allowProtectedFolders = false
    public init() {}
}

public struct ScanProgress: Sendable {
    public enum Phase: Int, Sendable { case finding, comparing, reading, finishing, done }
    public var phase: Phase = .finding
    public var filesFound = 0
    public var bytesFound: Int64 = 0
    public var candidateFiles = 0
    public var candidateBytes: Int64 = 0
    public var readFiles = 0
    public var readBytes: Int64 = 0
    public var readTotal: Int64 = 0
    public var bytesPerSecond: Double = 0
    public var etaSeconds: Double? = nil
    public var currentName = ""
    public init() {}
}

public struct ScanResult: Sendable {
    public var sets: [DuplicateSet]
    public var filesScanned: Int
    public var bytesScanned: Int64
    public var iCloudOnlySkipped: Int
    public var unreadable: Int
    public var refusedFolders: [String]
    public var folderFileCount: [String: Int]
    public var folderModified: [String: Date]
    /// Where on disk a file's blocks live; equal values mean the files share space (an APFS clone).
    public var blockSignature: [Int: [Int64]]
    public var seconds: Double
    public var bytesRead: Int64
    public init(sets: [DuplicateSet], filesScanned: Int, bytesScanned: Int64, iCloudOnlySkipped: Int = 0, unreadable: Int = 0, refusedFolders: [String] = [],
                folderFileCount: [String: Int] = [:], folderModified: [String: Date] = [:], blockSignature: [Int: [Int64]] = [:], seconds: Double = 0, bytesRead: Int64 = 0) {
        self.sets = sets; self.filesScanned = filesScanned; self.bytesScanned = bytesScanned; self.iCloudOnlySkipped = iCloudOnlySkipped; self.unreadable = unreadable
        self.refusedFolders = refusedFolders; self.folderFileCount = folderFileCount; self.folderModified = folderModified
        self.blockSignature = blockSignature; self.seconds = seconds; self.bytesRead = bytesRead
    }
    public var extraCopies: Int { sets.reduce(0) { $0 + $1.copies.count - 1 } }
    public var extraBytes: Int64 { sets.reduce(0) { $0 + $1.size * Int64($1.copies.count - 1) } }
}

public enum Format {
    public static func bytes(_ n: Int64) -> String {
        let v = Double(n)
        if v >= 1e12 { return String(format: "%.2f TB", v / 1e12) }
        if v >= 1e9 { return String(format: "%.1f GB", v / 1e9) }
        if v >= 1e6 { return String(format: "%.1f MB", v / 1e6) }
        if v >= 1e3 { return String(format: "%.0f KB", v / 1e3) }
        return "\(n) bytes"
    }
    public static func duration(_ s: Double) -> String {
        let t = Int(s.rounded())
        if t < 60 { return "\(t) sec" }
        if t < 3600 { return "\(t / 60) min \(t % 60) sec" }
        return "\(t / 3600) h \((t % 3600) / 60) min"
    }
}
