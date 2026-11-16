import Foundation
@testable import StatsKit
import Testing

struct DraftProviderTests {
    private func cache() -> ResponseCache {
        ResponseCache(name: "t", directory: FileManager.default.temporaryDirectory.appending(path: "rg-\(UUID())"))
    }

    @Test func parsesRecordedFullLaneMeta() async throws {
        let poster = try FakePoster(response: Fixture.data("opgg/lane-meta-full.json"))
        let meta = try await OPGGLaneMetaProvider(client: OPGGClient(poster: poster), cache: cache()).laneMeta()
        let zed = try #require(meta.champion(named: "Zed", in: .middle))
        #expect(zed == MetaChampion(
            name: "Zed", role: .middle, roleRate: 0.69, tier: 2, winRate: 0.5,
            pickRate: 0.08, banRate: 0.25, games: 182_148, isRip: false
        ))
        #expect(meta.champion(named: "Wukong", in: .jungle)?.tier == 1)
        #expect(meta.roleRates.rate(of: "Zed", in: .jungle) == 0.23)
        #expect(meta.roleRates.rate(of: "Nunu & Willump", in: .jungle) == 0.82)
        #expect(meta.lanes.values.allSatisfy { $0.count > 30 })
        let body = try #require(await poster.bodies.first.flatMap { String(data: $0, encoding: .utf8) })
        #expect(body.contains("ban_rate") && body.contains(#""position":"all""#))
    }

    /// Older lane-meta answers only have `{champion,role_rate}`; they still give lane shares.
    @Test func partialLaneMetaStillParses() async throws {
        let poster = try FakePoster(response: Fixture.data("opgg/lane-meta.json"))
        let meta = try await OPGGLaneMetaProvider(client: OPGGClient(poster: poster), cache: cache()).laneMeta()
        #expect(meta.champion(named: "Jinx", in: .bottom)?.roleRate == 1)
        #expect(meta.champion(named: "Jinx", in: .bottom)?.winRate == nil)
    }

    @Test func parsesRecordedSynergiesAndDropsSmallSamples() async throws {
        let poster = try FakePoster(response: Fixture.data("opgg/leesin-jungle-mid-synergies.json"))
        let provider = OPGGSynergyProvider(client: OPGGClient(poster: poster), cache: cache())
        let synergies = try await provider.synergies(of: "Lee Sin", in: .jungle, with: .middle)
        #expect(synergies.count == 10)
        #expect(synergies[1] == Synergy(id: 4, name: "Twisted Fate", winRate: 0.52, games: 6144, tier: 1))
        let body = try #require(await poster.bodies.first.flatMap { String(data: $0, encoding: .utf8) })
        #expect(body.contains(#""champion":"LEE_SIN""#) && body.contains(#""synergy_position":"mid""#))
        let small = try OPGGNotation.parse("""
        class R: data
        class D: synergies
        class S: synergy_champion_id,synergy_champion_name,play,win_rate

        R(D([S(1,"Annie",120,0.7),S(2,"Olaf",900,0.5)]))
        """)
        #expect(OPGGSynergyProvider.synergies(from: small).map(\.id) == [2])
    }

    @Test func synergyArgumentsUseOPGGsSpelling() {
        let names = ["Lee Sin", "Dr. Mundo", "Kog'Maw", "Nunu & Willump", "Jarvan IV", "Wukong"]
        #expect(names.map(OPGGSynergyProvider.argument(forName:)) == [
            "LEE_SIN", "DR_MUNDO", "KOGMAW", "NUNU_WILLUMP", "JARVAN_IV", "WUKONG"
        ])
    }

    @Test func parsesBothCounterDirections() async throws {
        let poster = try FakePoster(response: Fixture.data("opgg/zed-mid-lane-counters.json"))
        let provider = OPGGCounterProvider(client: OPGGClient(poster: poster), cache: cache())
        let counters = try await provider.laneCounters(
            of: ChampionRef(id: 238, key: "Zed"),
            role: .middle,
            queue: .ranked
        )
        #expect(counters.beatenBy.map(\.name) == ["Katarina", "Malphite", "Nasus"])
        #expect(counters.beatenBy.first == CounterPick(id: 55, name: "Katarina", winRate: 0.54, games: 4863))
        // Smolder (194 games) is below the sample minimum.
        #expect(counters.beats.map(\.name) == ["Cassiopeia", "Tristana"])
        #expect(counters.winRate(of: 18)?.winRate == 0.43)
    }

    @Test func directoryMatchesLocalizedNamesAndKeys() {
        let directory = ChampionDirectory([
            .init(id: 20, name: "Nunu und Willump", key: "Nunu"),
            .init(id: 62, name: "Wukong", key: "MonkeyKing"),
            .init(id: 96, name: "Kog'Maw", key: "KogMaw"),
            .init(id: 254, name: "Vi", key: "Vi"),
            .init(id: 234, name: "Viego", key: "Viego")
        ])
        #expect(directory.id(forName: "Nunu & Willump") == 20)
        #expect(directory.id(forName: "Wukong") == 62)
        #expect(directory.id(forName: "Kog'Maw") == 96)
        #expect(directory.id(forName: "Viego") == 234)
        // A short key must not swallow an unknown champion.
        #expect(directory.id(forName: "Vilemaw") == nil)
    }
}
