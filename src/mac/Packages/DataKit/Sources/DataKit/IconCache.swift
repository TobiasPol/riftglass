import AppKit
import CryptoKit
import os

/// Two-level icon cache: `NSCache` in memory, files on disk.
/// Icons are prefetched in champ select / loading screen – nothing is downloaded in game.
@MainActor
public final class IconCache {
    private let memory = NSCache<NSURL, NSImage>()
    private let fetcher: any HTTPFetching
    private let directory: URL
    /// Pending loads carry `Data` (Sendable); `NSImage` is only created on the main actor –
    /// it is not `Sendable` on older SDKs (Xcode 16).
    private var inFlight: [URL: Task<Data?, Never>] = [:]
    private let logger = Logger(subsystem: "de.polleydigital.riftglass", category: "IconCache")

    public init(
        fetcher: any HTTPFetching = URLSessionFetcher(),
        directory: URL = URL.cachesDirectory.appending(path: "Riftglass/icons", directoryHint: .isDirectory)
    ) {
        self.fetcher = fetcher
        self.directory = directory
        memory.countLimit = 400
    }

    /// Synchronous lookup (memory only) – safe to call from SwiftUI `body`.
    public func cachedImage(for url: URL) -> NSImage? {
        memory.object(forKey: url as NSURL)
    }

    public func image(for url: URL) async -> NSImage? {
        if let image = cachedImage(for: url) {
            return image
        }
        let task = inFlight[url] ?? Task { [fetcher, directory, file = diskURL(for: url)] in
            await Self.loadData(url, file: file, directory: directory, fetcher: fetcher)
        }
        inFlight[url] = task
        let data = await task.value
        inFlight[url] = nil
        if let image = cachedImage(for: url) {
            return image
        }
        guard let data, let image = NSImage(data: data) else {
            logger.debug("Icon unavailable: \(url.lastPathComponent, privacy: .public)")
            return nil
        }
        memory.setObject(image, forKey: url as NSURL)
        return image
    }

    public func prefetch(_ urls: some Sequence<URL>) {
        for url in urls where cachedImage(for: url) == nil && inFlight[url] == nil {
            Task { _ = await image(for: url) }
        }
    }

    /// Disk cache first, then download (and store). Runs off the main actor.
    private nonisolated static func loadData(
        _ url: URL,
        file: URL,
        directory: URL,
        fetcher: any HTTPFetching
    ) async -> Data? {
        if let cached = try? Data(contentsOf: file) {
            return cached
        }
        guard let data = try? await fetcher.data(from: url) else { return nil }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
        return data
    }

    nonisolated func diskURL(for url: URL) -> URL {
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: hash + "." + (url.pathExtension.isEmpty ? "img" : url.pathExtension))
    }
}
