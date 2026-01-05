import Foundation

enum Weights {
    struct Installed {
        let url: URL
        var path: UnsafePointer<CChar> { (url.path as NSString).utf8String! }
    }

    enum InstallError: Error { case notFound, copyFailed }

    // Copy a large file from bundle to Library/Caches on first use.
    static func installFromBundle(named name: String, ext: String) throws -> Installed {
        let fm = FileManager.default
        guard let src = Bundle.main.url(forResource: name, withExtension: ext) else {
            throw InstallError.notFound
        }
        let caches = try fm.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dst = caches.appendingPathComponent("Weights_\(name).\(ext)")

        if !fm.fileExists(atPath: dst.path) {
            try copyStreaming(from: src, to: dst)
        }
        return Installed(url: dst)
    }

    private static func copyStreaming(from src: URL, to dst: URL) throws {
        let fm = FileManager.default
        fm.createFile(atPath: dst.path, contents: nil)
        guard let inHandle = try? FileHandle(forReadingFrom: src),
              let outHandle = try? FileHandle(forWritingTo: dst) else {
            throw InstallError.copyFailed
        }
        defer {
            try? inHandle.close()
            try? outHandle.close()
        }
        let chunkSize = 4 * 1024 * 1024
        while autoreleasepool(invoking: {
            let data = try? inHandle.read(upToCount: chunkSize)
            if let data, !data.isEmpty {
                try? outHandle.write(contentsOf: data)
                return true
            }
            return false
        }) {}
    }

    // Try to find and install any resource in the bundle matching extension `ext`.
    // Returns nil if none found.
    static func installAny(withExtension ext: String) throws -> Installed? {
        let fm = FileManager.default
        guard let root = Bundle.main.resourceURL else { return nil }
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return nil }
        for case let url as URL in enumerator {
            if url.pathExtension.lowercased() == ext.lowercased() {
                let caches = try fm.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                let dst = caches.appendingPathComponent(url.lastPathComponent)
                if !fm.fileExists(atPath: dst.path) {
                    try copyStreaming(from: url, to: dst)
                }
                return Installed(url: dst)
            }
        }
        return nil
    }
}
