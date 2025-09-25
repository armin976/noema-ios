import Foundation

public struct ZipWriter {
    struct Entry {
        let path: String
        let data: Data
        let crc32: UInt32
    }

    public static func writeZip(at destination: URL, files: [(relativePath: String, url: URL)], fileManager: FileManager = .default) throws {
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        var entries: [Entry] = []
        for file in files {
            let data = try Data(contentsOf: file.url)
            let normalizedPath = file.relativePath.replacingOccurrences(of: "\\", with: "/")
            entries.append(Entry(path: normalizedPath, data: data, crc32: CRC32.checksum(for: data)))
        }

        var archive = Data()
        var localHeaderOffsets: [UInt32] = []
        for entry in entries {
            let nameData = Data(entry.path.utf8)
            localHeaderOffsets.append(UInt32(archive.count))
            archive.appendUInt32LE(0x04034B50)
            archive.appendUInt16LE(20)
            archive.appendUInt16LE(0)
            archive.appendUInt16LE(0)
            archive.appendUInt16LE(0)
            archive.appendUInt16LE(0)
            archive.appendUInt32LE(entry.crc32)
            archive.appendUInt32LE(UInt32(entry.data.count))
            archive.appendUInt32LE(UInt32(entry.data.count))
            archive.appendUInt16LE(UInt16(nameData.count))
            archive.appendUInt16LE(0)
            archive.append(nameData)
            archive.append(entry.data)
        }

        let centralDirectoryOffset = UInt32(archive.count)
        var centralDirectory = Data()
        for (index, entry) in entries.enumerated() {
            let nameData = Data(entry.path.utf8)
            centralDirectory.appendUInt32LE(0x02014B50)
            centralDirectory.appendUInt16LE(20)
            centralDirectory.appendUInt16LE(20)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt32LE(entry.crc32)
            centralDirectory.appendUInt32LE(UInt32(entry.data.count))
            centralDirectory.appendUInt32LE(UInt32(entry.data.count))
            centralDirectory.appendUInt16LE(UInt16(nameData.count))
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt32LE(0)
            centralDirectory.appendUInt32LE(localHeaderOffsets[index])
            centralDirectory.append(nameData)
        }

        archive.append(centralDirectory)
        archive.appendUInt32LE(0x06054B50)
        archive.appendUInt16LE(0)
        archive.appendUInt16LE(0)
        archive.appendUInt16LE(UInt16(entries.count))
        archive.appendUInt16LE(UInt16(entries.count))
        archive.appendUInt32LE(UInt32(centralDirectory.count))
        archive.appendUInt32LE(centralDirectoryOffset)
        archive.appendUInt16LE(0)

        try archive.write(to: destination)
    }
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { ptr in append(contentsOf: ptr) }
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { ptr in append(contentsOf: ptr) }
    }
}
