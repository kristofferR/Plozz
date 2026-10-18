import Foundation
import os
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Worker-written backing, immutable after publication; never an authoritative sync store.
final class LiveTVPortableRecordStorage: @unchecked Sendable {
    static let maximumResidentBytes = 4 * 1_024 * 1_024
    static let maximumStoredBytes = 128 * 1_024 * 1_024
    private static let logger = Logger(subsystem: "com.plozz.app", category: "live-tv-sync")
    private(set) var residentBytes = 0
    private(set) var storedBytes = 0
    private let temporaryDirectory: URL

    init(temporaryDirectory: URL = FileManager.default.temporaryDirectory) {
        self.temporaryDirectory = temporaryDirectory
    }

    func store(_ bytes: Data) throws -> Data {
        try Task.checkCancellation()
        guard bytes.count <= Self.maximumStoredBytes - storedBytes else {
            throw LiveTVPortableStateError.tooLarge
        }
        if bytes.count <= Self.maximumResidentBytes - residentBytes {
            storedBytes += bytes.count
            residentBytes += bytes.count
            return bytes
        }
        var name = Array(temporaryDirectory.appendingPathComponent(".plozz-record-XXXXXX").path.utf8CString)
        let descriptor = mkstemp(&name)
        guard descriptor >= 0 else { throw Self.posixError() }
        defer { close(descriptor) }
        // Unlink before writing: mappings own the bytes, and process exit reclaims
        // even an interrupted export without relying on Swift deinitialization.
        guard unlink(name) == 0 else {
            let error = Self.posixError()
            if unlink(name) != 0 {
                Self.logger.error("Unable to unlink Live TV staging file errno=\(errno)")
            }
            throw error
        }
        try bytes.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                try Task.checkCancellation()
                let count = write(descriptor, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw Self.posixError() }
                offset += count
            }
        }
        let mapping = mmap(nil, bytes.count, PROT_READ, MAP_PRIVATE, descriptor, 0)
        guard mapping != MAP_FAILED, let mapping else { throw Self.posixError() }
        storedBytes += bytes.count
        return Data(bytesNoCopy: mapping, count: bytes.count, deallocator: .unmap)
    }

    private static func posixError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }

    static func reclaimLegacyFiles(in root: URL) throws {
        let manager = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        for folder in try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: Array(keys)) {
            let prefix = "plozz-live-tv-records-"
            guard folder.lastPathComponent.hasPrefix(prefix),
                  UUID(uuidString: String(folder.lastPathComponent.dropFirst(prefix.count))) != nil else { continue }
            let attributes = try folder.resourceValues(forKeys: keys)
            guard attributes.isDirectory == true, attributes.isSymbolicLink != true else { continue }
            let files = try manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys))
            guard try files.allSatisfy({ file in
                let values = try file.resourceValues(forKeys: keys)
                return values.isRegularFile == true && values.isSymbolicLink != true
                    && file.pathExtension == "record"
                    && Int(file.deletingPathExtension().lastPathComponent).map { $0 >= 0 } == true
            }) else { continue }
            for file in files { try manager.removeItem(at: file) }
            try manager.removeItem(at: folder)
        }
    }

    static let reclaimLegacyFilesOnce: Void = {
        do { try reclaimLegacyFiles(in: FileManager.default.temporaryDirectory) }
        catch { logger.error("Unable to reclaim obsolete Live TV staging: \(error.localizedDescription, privacy: .private)") }
    }()
}
