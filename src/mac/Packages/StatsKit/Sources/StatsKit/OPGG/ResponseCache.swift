import CryptoKit
import Foundation

/// Small disk cache with a time-to-live, in `~/Library/Caches/Riftglass/<name>/`.
/// Keeps OP.GG traffic low: one request per champion/role per TTL.
public actor ResponseCache {
    private let directory: URL
    private let timeToLive: TimeInterval
    private let now: @Sendable () -> Date

    public init(
        name: String,
        timeToLive: TimeInterval = 6 * 3600,
        directory: URL? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.directory = directory
            ?? URL.cachesDirectory.appending(path: "Riftglass/\(name)", directoryHint: .isDirectory)
        self.timeToLive = timeToLive
        self.now = now
    }

    public func value(for key: String) -> String? {
        let url = fileURL(for: key)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attributes[.modificationDate] as? Date,
              now().timeIntervalSince(modified) < timeToLive
        else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    public func store(_ value: String, for key: String) {
        let url = fileURL(for: key)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? Data(value.utf8).write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.modificationDate: now()], ofItemAtPath: url.path)
    }

    private func fileURL(for key: String) -> URL {
        let hash = SHA256.hash(data: Data(key.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: "\(hash).txt")
    }
}
