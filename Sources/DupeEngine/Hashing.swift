import Foundation
import CryptoKit
import Darwin

let chunkSize = 8 << 20
let sliceSize = 1 << 20
/// Files up to this size are simply read in full; bigger ones get a quick three-slice fingerprint first.
let fingerprintThreshold = 4 << 20

struct Cancelled: Error {}

private let hexDigits = Array("0123456789abcdef".utf8)

func hex(_ digest: SHA256.Digest) -> String {
    var bytes = [UInt8](); bytes.reserveCapacity(64)
    for b in digest { bytes.append(hexDigits[Int(b >> 4)]); bytes.append(hexDigits[Int(b & 15)]) }
    return String(decoding: bytes, as: UTF8.self)
}

/// SHA-256 of the start, middle and end of a file. Same-size files that differ are told apart here for almost no reading.
func quickFingerprint(path: String, size: Int64, bump: (Int64) -> Void) throws -> String {
    let fd = open(path, O_RDONLY)
    if fd < 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    defer { close(fd) }
    _ = fcntl(fd, F_NOCACHE, 1)
    var hasher = SHA256()
    let buf = UnsafeMutableRawPointer.allocate(byteCount: sliceSize, alignment: 4096)
    defer { buf.deallocate() }
    for off in [Int64(0), max(0, size / 2 - Int64(sliceSize / 2)), max(0, size - Int64(sliceSize))] {
        var got = 0
        while got < sliceSize {
            let n = pread(fd, buf + got, sliceSize - got, off + Int64(got))
            if n <= 0 { break }
            got += n
        }
        hasher.update(bufferPointer: UnsafeRawBufferPointer(start: buf, count: got))
        bump(Int64(got))
    }
    return hex(hasher.finalize())
}

/// SHA-256 of a whole file. Reads in 8 MB pieces, leaves the system cache alone, stops quickly when cancelled.
func fullHash(path: String, bump: (Int64) -> Void, shouldStop: () -> Bool) throws -> (String, Int64) {
    let fd = open(path, O_RDONLY)
    if fd < 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    defer { close(fd) }
    _ = fcntl(fd, F_NOCACHE, 1)
    var hasher = SHA256()
    let buf = UnsafeMutableRawPointer.allocate(byteCount: chunkSize, alignment: 4096)
    defer { buf.deallocate() }
    var off: Int64 = 0
    while true {
        if shouldStop() { throw Cancelled() }
        let n = pread(fd, buf, chunkSize, off)
        if n < 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        if n == 0 { break }
        hasher.update(bufferPointer: UnsafeRawBufferPointer(start: buf, count: n))
        off += Int64(n)
        bump(Int64(n))
    }
    return (hex(hasher.finalize()), off)
}

/// Where eight evenly spaced blocks of the file physically live. Two files with equal signatures share disk space
/// (an APFS clone), so deleting one frees nothing. struct log2phys is packed to 4 bytes: 20 bytes in all.
func blockSignature(path: String, size: Int64) -> [Int64]? {
    if size < Int64(sliceSize) { return nil }
    let fd = open(path, O_RDONLY)
    if fd < 0 { return nil }
    defer { close(fd) }
    var sig: [Int64] = []
    let n = 8
    for i in 0..<n {
        let off = (Int64(i) * (size - 4096) / Int64(n - 1)) / 4096 * 4096
        var raw = [UInt8](repeating: 0, count: 20)
        raw.withUnsafeMutableBytes { p in
            p.storeBytes(of: UInt32(0), toByteOffset: 0, as: UInt32.self)
            p.storeBytes(of: Int64(4096), toByteOffset: 4, as: Int64.self)
            p.storeBytes(of: off, toByteOffset: 12, as: Int64.self)
        }
        let rc = raw.withUnsafeMutableBytes { fcntl(fd, 65 /* F_LOG2PHYS_EXT */, $0.baseAddress!) }
        if rc == -1 { return nil }
        sig.append(raw.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 12, as: Int64.self) })
    }
    return sig
}
