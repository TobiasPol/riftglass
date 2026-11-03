@testable import DataKit
import Foundation
import Testing

/// Serves `tests/fixtures/ddragon/<file>` for any URL ending in that file name and counts requests.
actor FixtureFetcher: HTTPFetching {
    static let root: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 7 {
            url.deleteLastPathComponent()
        }
        return url.appending(path: "tests/fixtures/ddragon")
    }()

    private(set) var requested: [URL] = []
    var offline = false

    func setOffline(_ value: Bool) {
        offline = value
    }

    func data(from url: URL) async throws -> Data {
        requested.append(url)
        if offline {
            throw URLError(.notConnectedToInternet)
        }
        return try Data(contentsOf: Self.root.appending(path: url.lastPathComponent))
    }
}

struct DataDragonTests {
    private let cache = FileManager.default.temporaryDirectory.appending(path: "riftglass-tests-\(UUID().uuidString)")

    @Test func latestVersionAndIndexedStaticData() async throws {
        let dragon = DataDragon(fetcher: FixtureFetcher(), cacheDirectory: cache)
        let version = try await dragon.latestVersion()
        #expect(version == "15.22.1")
        let data = try await dragon.staticData(version: version)
        #expect(data.champion(62)?.name == "Wukong")
        #expect(data.champion(62)?.id == "MonkeyKing")
        #expect(data.spellsById[4]?.name == "Blitz")
        #expect(data.itemsById[1056]?.name == "Dorans Ring")
        #expect(data.runesById[8112]?.key == "Electrocute")
        #expect(data.runeStylesById[8200]?.name == "Zauberei")
    }

    @Test func secondLoadComesFromDiskCache() async throws {
        let fetcher = FixtureFetcher()
        _ = try await DataDragon(fetcher: fetcher, cacheDirectory: cache).staticData(version: "15.22.1")
        let firstCount = await fetcher.requested.count
        #expect(firstCount == 4)
        await fetcher.setOffline(true)
        let fresh = DataDragon(fetcher: fetcher, cacheDirectory: cache)
        let data = try await fresh.staticData(version: "15.22.1")
        #expect(data.champion(103)?.name == "Ahri")
        #expect(await fetcher.requested.count == firstCount)
        #expect(try await fresh.latestVersion() == "15.22.1") // offline → newest cached version
    }

    @Test func offlineWithoutCacheThrows() async {
        let fetcher = FixtureFetcher()
        await fetcher.setOffline(true)
        await #expect(throws: URLError.self) {
            try await DataDragon(fetcher: fetcher, cacheDirectory: cache).latestVersion()
        }
    }

    @Test func assetURLs() async throws {
        let dragon = DataDragon(fetcher: FixtureFetcher(), cacheDirectory: cache)
        let ahri = try #require(try await dragon.staticData(version: "15.22.1").champion(103))
        #expect(dragon.championIconURL(ahri, version: "15.22.1").absoluteString
            == "https://ddragon.leagueoflegends.com/cdn/15.22.1/img/champion/Ahri.png")
        #expect(dragon.itemIconURL(1056, version: "15.22.1").lastPathComponent == "1056.png")
        #expect(dragon.runeIconURL("perk-images/x.png").absoluteString
            == "https://ddragon.leagueoflegends.com/cdn/img/perk-images/x.png")
    }
}
