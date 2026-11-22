import Foundation

/// Inspects and clears Riftglass's on-disk caches (OP.GG responses, Data Dragon JSONs, CommunityDragon augments,
/// icons).
enum CacheManager {
    static var directories: [URL] {
        [
            URL.cachesDirectory.appending(path: "Riftglass", directoryHint: .isDirectory),
            URL.applicationSupportDirectory.appending(path: "Riftglass", directoryHint: .isDirectory)
        ]
    }

    static func totalBytes() -> Int64 {
        directories.reduce(0) { $0 + directoryBytes($1) }
    }

    static func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func clearAll() {
        let fileManager = FileManager.default
        for directory in directories {
            guard let children = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            else { continue }
            for child in children {
                try? fileManager.removeItem(at: child)
            }
        }
    }

    private static func directoryBytes(_ directory: URL) -> Int64 {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: keys)
        else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let size = values.fileSize
            else { continue }
            total += Int64(size)
        }
        return total
    }
}
