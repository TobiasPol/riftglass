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
    private var inFlight: [URL: Task<NSImage?, Never>] = [:]
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
        if let task = inFlight[url] {
            return await task.value
        }
        let task = Task { await load(url) }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        return image
    }

    public func prefetch(_ urls: some Sequence<URL>) {
        for url in urls where cachedImage(for: url) == nil && inFlight[url] == nil {
            Task { _ = await image(for: url) }
        }
    }

    private func load(_ url: URL) async -> NSImage? {
        let file = diskURL(for: url)
        let data: Data
        if let cached = try? Data(contentsOf: file) {
            data = cached
        } else {
            do {
                data = try await fetcher.data(from: url)
            } catch {
                logger.debug("Icon download failed: \(url.lastPathComponent, privacy: .public)")
                return nil
            }
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        }
        guard let image = NSImage(data: data) else { return nil }
        memory.setObject(image, forKey: url as NSURL)
        return image
    }

    nonisolated func diskURL(for url: URL) -> URL {
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: hash + "." + (url.pathExtension.isEmpty ? "img" : url.pathExtension))
    }
}
