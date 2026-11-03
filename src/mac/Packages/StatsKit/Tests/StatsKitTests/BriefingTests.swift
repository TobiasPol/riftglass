import Foundation
@testable import StatsKit
import Testing

struct LaneAssignerTests {
    private let rates = RoleRates(rates: [
        "zed": [.middle: 0.69, .jungle: 0.22],
        "leesin": [.jungle: 0.96],
        "jinx": [.bottom: 1],
        "malphite": [.top: 0.78, .middle: 0.09, .jungle: 0.09],
        "thresh": [.utility: 1],
        "talon": [.jungle: 0.75, .middle: 0.24]
    ])

    private func pick(_ id: Int, _ name: String, _ fixed: Role? = nil) -> LaneAssigner.Pick {
        .init(championId: id, name: name, fixed: fixed)
    }

    @Test func assignsCompleteTeamToMainLanes() {
        let lanes = LaneAssigner.assign(
            [pick(238, "Zed"), pick(64, "Lee Sin"), pick(222, "Jinx"), pick(54, "Malphite"), pick(412, "Thresh")],
            rates: rates
        )
        #expect(lanes[.middle]?.championId == 238)
        #expect(lanes[.jungle]?.championId == 64)
        #expect(lanes[.bottom]?.championId == 222)
        #expect(lanes[.top]?.championId == 54)
        #expect(lanes[.utility]?.championId == 412)
        #expect(lanes[.middle]?.isLikely == true)
    }

    /// Talon is mostly a jungler, but Lee Sin takes the jungle → Talon goes mid, flagged as a guess.
    @Test func resolvesConflictsByJointLikelihood() {
        let lanes = LaneAssigner.assign([pick(91, "Talon"), pick(64, "Lee Sin")], rates: rates)
        #expect(lanes[.jungle]?.championId == 64)
        #expect(lanes[.middle]?.championId == 91)
        #expect(lanes[.middle]?.isLikely == false)
        #expect(lanes.count == 2)
    }

    @Test func keepsRevealedPositions() {
        let lanes = LaneAssigner.assign([pick(238, "Zed", .jungle), pick(91, "Talon")], rates: rates)
        #expect(lanes[.jungle] == .init(championId: 238, confidence: 1))
        #expect(lanes[.middle]?.championId == 91)
    }

    @Test func unknownChampionsStillGetALane() {
        let lanes = LaneAssigner.assign([pick(1, "Newchamp"), pick(222, "Jinx")], rates: rates)
        #expect(lanes[.bottom]?.championId == 222)
        #expect(lanes.values.contains { $0.championId == 1 && $0.confidence == 0 })
    }

    @Test func normalizesNames() {
        #expect(RoleRates.normalized("Kog'Maw") == "kogmaw")
        #expect(RoleRates.normalized("Nunu & Willump") == "nunuwillump")
        #expect(RoleRates.normalized("Dr. Mundo") == "drmundo")
    }
}

struct BriefingProviderTests {
    private func cache() -> ResponseCache {
        ResponseCache(name: "t", directory: FileManager.default.temporaryDirectory.appending(path: "rg-\(UUID())"))
    }

    @Test func parsesRecordedLaneMeta() async throws {
        let poster = try FakePoster(response: Fixture.data("opgg/lane-meta.json"))
        let provider = OPGGLaneMetaProvider(client: OPGGClient(poster: poster), cache: cache())
        let rates = try await provider.roleRates()
        #expect(rates.rate(of: "Jinx", in: .bottom) == 1)
        #expect(rates.rate(of: "Zed", in: .middle) == 0.69)
        #expect(rates.rate(of: "Zed", in: .jungle) == 0.22)
        #expect(rates.rate(of: "Nunu & Willump", in: .jungle) == 0.82)
        #expect(rates.rate(of: "Thresh", in: .top) == 0)
    }

    @Test func parsesRecordedMatchupGuide() async throws {
        let poster = try FakePoster(response: Fixture.data("opgg/ahri-zed-mid-guide.json"))
        let provider = OPGGMatchupProvider(client: OPGGClient(poster: poster), cache: cache())
        let brief = try await provider.matchup(
            my: ChampionRef(id: 103, key: "Ahri"),
            against: ChampionRef(id: 238, key: "Zed"),
            role: .middle
        )
        #expect(brief.games == 8004)
        #expect(abs((brief.winRate ?? 0) - 3966.0 / 8004.0) < 0.0001)
        #expect(brief.laneAdvantage == .opponent)
        #expect(brief.soloKillAdvantage == .opponent)
        #expect(brief.playStyle == "even")
        #expect(brief.tip?.hasPrefix("Do not use Charm") == true)
        let body = try #require(await poster.bodies.first.flatMap { String(data: $0, encoding: .utf8) })
        #expect(body.contains(#""opponent_champion":"ZED""#))
    }

    @Test func smallMatchupSampleHasNoWinRate() throws {
        let json = #"{"my_champion":"Ahri","opponent_champion":"Zed","#
            + #""data":{"counters":[{"champion_id":238,"play":12,"win":9}]}}"#
        let brief = try OPGGMatchupProvider.brief(from: Data(json.utf8), opponentId: 238)
        #expect(brief.winRate == nil)
        #expect(brief.games == 12)
        #expect(brief.laneAdvantage == nil && brief.tip == nil)
    }

    @Test func parsesRecordedCounters() async throws {
        let poster = try FakePoster(response: Fixture.data("opgg/zed-mid-counters.json"))
        let provider = OPGGCounterProvider(client: OPGGClient(poster: poster), cache: cache())
        let counters = try await provider.counters(
            against: ChampionRef(id: 238, key: "Zed"),
            role: .middle,
            queue: .ranked
        )
        #expect(counters.map(\.name) == ["Malphite", "Gwen", "Gragas"])
        #expect(counters.first == CounterPick(id: 54, name: "Malphite", winRate: 0.56, games: 2572))
    }

    @Test func dropsSmallCounterSamples() throws {
        let value = try OPGGNotation.parse("""
        class A: data
        class D: weak_counters
        class W: champion_id,champion_name,play,my_win_rate,counter_win_rate

        A(D([W(1,"Few",50,0.3,0.7),W(2,"Many",900,0.48,0.52)]))
        """)
        #expect(OPGGCounterProvider.counters(from: value).map(\.id) == [2])
    }
}
