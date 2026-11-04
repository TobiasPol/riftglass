@testable import DataKit
import Foundation
import Testing

/// Serves the recorded German `cherry-augments.json` (trimmed) for every request.
private actor CatalogFetcher: HTTPFetching {
    private(set) var requests = 0
    var offline = false

    func setOffline(_ value: Bool) {
        offline = value
    }

    func data(from url: URL) async throws -> Data {
        requests += 1
        if offline {
            throw URLError(.notConnectedToInternet)
        }
        #expect(url.absoluteString.hasSuffix("/global/de_de/v1/cherry-augments.json"))
        let fixtures = FixtureFetcher.root.deletingLastPathComponent()
        return try Data(contentsOf: fixtures.appending(path: "cdragon/cherry-augments-de.json"))
    }
}

struct AugmentCatalogTests {
    private let cache = FileManager.default.temporaryDirectory.appending(path: "rg-cdragon-\(UUID().uuidString)")

    @Test func parsesLocalizedNamesRaritiesAndIcons() async throws {
        let catalog = AugmentCatalog(fetcher: CatalogFetcher(), cacheDirectory: cache)
        let augments = try await catalog.augments()
        let baron = try #require(augments[1389])
        #expect(baron.name == "Hand des Barons" && baron.rarity == .prismatic)
        #expect(baron.iconURL?.absoluteString == "https://raw.communitydragon.org/latest/plugins/"
            + "rcp-be-lol-game-data/global/default/assets/ux/kiwi/augments/icons/handofbaron_small.png")
        #expect(augments[1026]?.rarity == .silver)
        #expect(augments[341] == nil) // kEventChoice has no rarity
        #expect(augments.count == 8)
    }

    @Test func usesCacheAndFallsBackWhenOffline() async throws {
        let fetcher = CatalogFetcher()
        _ = try await AugmentCatalog(fetcher: fetcher, cacheDirectory: cache).augments()
        _ = try await AugmentCatalog(fetcher: fetcher, cacheDirectory: cache).augments()
        #expect(await fetcher.requests == 1) // fresh disk cache

        let file = cache.appending(path: "cherry-augments-de_de.json")
        try FileManager.default.setAttributes([.modificationDate: Date.distantPast], ofItemAtPath: file.path)
        await fetcher.setOffline(true)
        let stale = try await AugmentCatalog(fetcher: fetcher, cacheDirectory: cache).augments()
        #expect(stale[1323]?.name == "Grausamkeit")
        #expect(await fetcher.requests == 2)
    }

    @Test func inMemoryCopyRefreshesAfterExpiry() async throws {
        let fetcher = CatalogFetcher()
        let clock = Clock()
        let catalog = AugmentCatalog(fetcher: fetcher, cacheDirectory: cache, now: { clock.date })
        _ = try await catalog.augments()
        _ = try await catalog.augments()
        #expect(await fetcher.requests == 1)
        clock.date = clock.date.addingTimeInterval(AugmentCatalog.timeToLive + 1)
        _ = try await catalog.augments()
        #expect(await fetcher.requests == 2) // expired in memory and on disk → fetched again
    }
}

/// Settable time source for expiry tests.
private final class Clock: @unchecked Sendable {
    var date = Date()
}
