import Foundation
import CoreGraphics
import Darwin

/// Reads a framebuffer written by core/host_headless.py.
///
/// The host writes to a regular file in /tmp (memory-backed) with this
/// layout (little-endian):
///
///   bytes 0..3   frame_counter (u32; bumped after each full frame is written)
///   bytes 4..7   width (u32)
///   bytes 8..11  height (u32)
///   bytes 12..   pixels (W*H*2 bytes, RGB565 little-endian)
///
/// Swift mmaps the whole file read-only and polls the counter. When it
/// advances past the last-seen value, we convert the pixel region to a
/// CGImage and hand it back.
public final class SharedFramebuffer {
    private let fd: Int32
    private let base: UnsafeMutableRawPointer
    private let totalSize: Int
    private var lastSeenCounter: UInt32 = 0

    public let width: Int
    public let height: Int

    public init(path: String, width: Int, height: Int) throws {
        self.width = width
        self.height = height
        let header = 12
        self.totalSize = header + width * height * 2

        // Wait briefly for the host to create the file (it truncates on startup)
        var fdTmp: Int32 = -1
        for _ in 0..<100 {
            fdTmp = open(path, O_RDONLY)
            if fdTmp >= 0 { break }
            usleep(50_000) // 50ms
        }
        guard fdTmp >= 0 else {
            throw CLIError.generic("SharedFramebuffer: couldn't open \(path) after 5s")
        }
        self.fd = fdTmp

        // Wait for the host to size the file to at least totalSize
        var stats = stat()
        for _ in 0..<100 {
            fstat(fd, &stats)
            if stats.st_size >= totalSize { break }
            usleep(50_000)
        }
        guard stats.st_size >= totalSize else {
            close(fd)
            throw CLIError.generic("SharedFramebuffer: file never reached expected size")
        }

        guard let p = mmap(nil, totalSize, PROT_READ, MAP_SHARED, fd, 0),
              p != MAP_FAILED else {
            close(fd)
            throw CLIError.generic("SharedFramebuffer: mmap failed")
        }
        self.base = p
    }

    deinit {
        munmap(base, totalSize)
        close(fd)
    }

    /// Returns a freshly-rendered CGImage if a new frame has arrived since
    /// the last call, otherwise nil. Safe to call at display-link rate.
    public func pollForNewFrame() -> CGImage? {
        let counterPtr = base.assumingMemoryBound(to: UInt32.self)
        let counter = counterPtr[0]
        guard counter != lastSeenCounter else { return nil }

        // Convert RGB565 → RGBA8. Small loop; ~60K pixels for 100x310.
        let pixelBase = base.advanced(by: 12)
            .assumingMemoryBound(to: UInt16.self)
        let count = width * height
        var rgba = Data(count: count * 4)
        rgba.withUnsafeMutableBytes { raw in
            let dst = raw.bindMemory(to: UInt8.self).baseAddress!
            for i in 0..<count {
                let px = pixelBase[i]
                let r5 = UInt8((px >> 11) & 0x1F)
                let g6 = UInt8((px >> 5) & 0x3F)
                let b5 = UInt8(px & 0x1F)
                dst[i*4 + 0] = (r5 << 3) | (r5 >> 2)
                dst[i*4 + 1] = (g6 << 2) | (g6 >> 4)
                dst[i*4 + 2] = (b5 << 3) | (b5 >> 2)
                dst[i*4 + 3] = 255
            }
        }

        // Seqlock-lite: re-read counter; if it changed we got a partial frame,
        // skip this one and let the next poll catch up.
        let counterAfter = counterPtr[0]
        guard counter == counterAfter else { return nil }

        lastSeenCounter = counter

        // Build CGImage from RGBA8 data
        guard let provider = CGDataProvider(data: rgba as CFData) else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo: CGBitmapInfo = [
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            CGBitmapInfo.byteOrder32Big
        ]
        return CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace, bitmapInfo: bitmapInfo,
            provider: provider, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}
