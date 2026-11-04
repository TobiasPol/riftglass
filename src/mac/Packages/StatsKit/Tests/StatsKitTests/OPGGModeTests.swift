import Foundation
@testable import StatsKit
import Testing

struct OPGGModeTests {
    private let ahri = ChampionRef(id: 103, key: "Ahri")

    private func provider(_ fixture: String) throws -> (OPGGBuildProvider, FakePoster) {
        let poster = try FakePoster(response: Fixture.data(fixture))
        let directory = FileManager.default.temporaryDirectory.appending(path: "rg-\(UUID().uuidString)")
        let provider = OPGGBuildProvider(
            client: OPGGClient(poster: poster),
            cache: ResponseCache(name: "t", directory: directory)
        )
        return (provider, poster)
    }

    private func arguments(_ poster: FakePoster) async throws -> [String: Any] {
        let body = try #require(await poster.bodies.first)
        let request = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        return try #require((request?["params"] as? [String: Any])?["arguments"] as? [String: Any])
    }

    @Test func aramBuildFromRecordedResponse() async throws {
        let (provider, poster) = try provider("opgg/ahri-aram.json")
        // In ARAM the player's role is irrelevant; OP.GG requires *a* position and ignores it.
        let build = try #require(try await provider.builds(for: ahri, role: .utility, queue: .aram, patch: nil).first)
        #expect(build.title == "OP.GG ARAM-Build · Tier 2")
        #expect(build.queue == .aram)
        #expect(build.championKey == "Ahri")
        #expect(build.runes.perkIds == [8128, 8126, 8140, 8106, 8009, 8014, 5008, 5008, 5001])
        #expect(build.summonerSpells == [4, 32])
        #expect(build.itemBlocks.map(\.title) == ["Start", "Kern", "Stiefel", "Danach"])
        #expect(build.itemBlocks[3].itemIds == [3089, 3135, 3157])
        #expect(build.skillOrder.prefix(3) == ["Q", "W", "E"])
        let arguments = try await arguments(poster)
        #expect(arguments["game_mode"] as? String == "aram")
        #expect(arguments["position"] as? String == "mid")
    }

    @Test func cacheIsSeparatedPerQueue() async throws {
        let (provider, poster) = try provider("opgg/ahri-mid.json")
        _ = try await provider.builds(for: ahri, role: .middle, queue: .ranked, patch: "1")
        _ = try await provider.builds(for: ahri, role: .middle, queue: .flex, patch: "1")
        _ = try await provider.builds(for: ahri, role: .middle, queue: .ranked, patch: "1")
        #expect(await poster.bodies.count == 2)
    }

    @Test func augmentsSortedByPickRate() async throws {
        let poster = try FakePoster(response: Fixture.data("opgg/ahri-aram-augments.json"))
        let directory = FileManager.default.temporaryDirectory.appending(path: "rg-\(UUID().uuidString)")
        let provider = OPGGAugmentProvider(
            client: OPGGClient(poster: poster),
            cache: ResponseCache(name: "t", directory: directory)
        )
        let augments = try await provider.augments(championId: 103, limit: 3)
        // Goldrend and Searing Dawn tie at 17 %: lower ID first, deterministic.
        #expect(augments.map(\.name) == ["Cruelty", "Searing Dawn", "Goldrend"])
        #expect(abs(augments[0].pickRate - 0.19) < 0.0001)
        #expect(augments[0].performance.map { abs($0 - 80.74) < 0.0001 } == true)
        let all = try await provider.augments(championId: 103)
        #expect(all.count > 40 && !all.contains { $0.name.isEmpty })
        #expect(await poster.bodies.count == 1) // second call served from cache
        let body = try #require(await poster.bodies.first)
        let request = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let arguments = (request?["params"] as? [String: Any])?["arguments"] as? [String: Any]
        #expect(arguments?["champion_id"] as? Int == 103)
    }
}
