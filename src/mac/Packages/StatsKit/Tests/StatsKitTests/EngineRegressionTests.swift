import Foundation
@testable import StatsKit
import Testing

/// Answers with one canned response after the other (the last one repeats).
actor SequencePoster: HTTPPosting {
    private(set) var calls = 0
    private var responses: [Data]

    init(_ responses: [Data]) {
        self.responses = responses
    }

    func post(_: URL, body _: Data, headers _: [String: String]) async throws -> Data {
        calls += 1
        return responses.count > 1 ? responses.removeFirst() : responses[0]
    }
}

struct EngineRegressionTests {
    private let ahri = ChampionRef(id: 103, key: "Ahri")
    /// A well-formed MCP answer whose text is not OP.GG's notation (maintenance, rate limit).
    private let notice = Data(
        #"{"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":"Too many requests"}]}}"#.utf8
    )

    private func cache() -> ResponseCache {
        ResponseCache(name: "t", directory: FileManager.default.temporaryDirectory.appending(path: "rg-\(UUID())"))
    }

    @Test func unusableBuildAnswerIsNotCached() async throws {
        let poster = try SequencePoster([notice, Fixture.data("opgg/ahri-mid.json")])
        let provider = OPGGBuildProvider(client: OPGGClient(poster: poster), cache: cache())
        await #expect(throws: (any Error).self) {
            try await provider.builds(for: ahri, role: .middle, queue: .ranked, patch: "1")
        }
        // The next call asks OP.GG again instead of re-reading the notice for six hours.
        #expect(try await provider.builds(for: ahri, role: .middle, queue: .ranked, patch: "1").count == 1)
        #expect(try await provider.builds(for: ahri, role: .middle, queue: .ranked, patch: "1").count == 1)
        #expect(await poster.calls == 2)
    }

    @Test func unusableLaneMetaAndCounterAnswersAreNotCached() async throws {
        let lanePoster = try SequencePoster([notice, Fixture.data("opgg/lane-meta.json")])
        let lanes = OPGGLaneMetaProvider(client: OPGGClient(poster: lanePoster), cache: cache())
        await #expect(throws: (any Error).self) { try await lanes.roleRates() }
        #expect(try await lanes.roleRates().mainRole(of: "Zed") == .middle)
        _ = try await lanes.roleRates()
        #expect(await lanePoster.calls == 2)

        let counterPoster = try SequencePoster([notice, Fixture.data("opgg/zed-mid-counters.json")])
        let counters = OPGGCounterProvider(client: OPGGClient(poster: counterPoster), cache: cache())
        let zed = ChampionRef(id: 238, key: "Zed")
        await #expect(throws: (any Error).self) {
            try await counters.counters(against: zed, role: .middle, queue: .ranked)
        }
        #expect(try await counters.counters(against: zed, role: .middle, queue: .ranked).count == 3)
        #expect(await counterPoster.calls == 2)
    }

    @Test func mainRoleIsTheMostPlayedLane() {
        let rates = RoleRates(rates: [
            "talon": [.jungle: 0.75, .middle: 0.24],
            "nunuwillump": [.jungle: 0.82],
            "nobody": [.top: 0]
        ])
        #expect(rates.mainRole(of: "Talon") == .jungle)
        #expect(rates.mainRole(of: "Nunu & Willump") == .jungle)
        #expect(rates.mainRole(of: "Nobody") == nil)
        #expect(rates.mainRole(of: "Unknown") == nil)
    }

    /// Two bot laners: the exhaustive search has to put one somewhere – but not on screen.
    @Test func noLaneGuessFromAZeroShare() {
        let rates = RoleRates(rates: ["jinx": [.bottom: 1], "caitlyn": [.bottom: 1], "zed": [.middle: 0.69]])
        let picks = [
            LaneAssigner.Pick(championId: 222, name: "Jinx"),
            LaneAssigner.Pick(championId: 51, name: "Caitlyn"),
            LaneAssigner.Pick(championId: 238, name: "Zed")
        ]
        let lanes = LaneAssigner.assign(picks, rates: rates)
        // One of the two takes bottom (a tie); the other is left out instead of shown at 0 %.
        #expect(lanes.count == 2 && lanes[.middle]?.championId == 238)
        #expect([222, 51].contains(lanes[.bottom]?.championId ?? 0))
        #expect(lanes.values.allSatisfy { $0.confidence >= LaneAssigner.minimumShare })
    }

    @Test func itemPlanSeparatesCoreFromStartersAndAlternatives() throws {
        let text = try OPGGClient.text(fromResponse: Fixture.data("opgg/ahri-mid.json"))
        let build = try #require(OPGGBuildProvider.buildOption(
            from: OPGGNotation.parse(text),
            champion: ahri,
            role: .middle
        ))
        #expect(build.requiredItemIds == [3118, 4645, 3157, 3020])
        // 3157 is a fourth-item option too, but already part of the core.
        #expect(build.alternativeItemIds == [3089, 3135])
        #expect(!build.requiredItemIds.contains(1056) && build.allItemIds.contains(1056))
    }

    @Test func incompleteCounterEntryKeepsTheMatchupBrief() throws {
        let json = #"{"my_champion":"Ahri","opponent_champion":"Zed","data":{"opponent_champion_tip":"Tip","#
            + #""lane_advantage_champion":"Ahri","counters":[{"champion_id":1,"play":900},"#
            + #"{"champion_id":238,"play":500,"win":260}]}}"#
        let brief = try OPGGMatchupProvider.brief(from: Data(json.utf8), opponentId: 238)
        #expect(brief.tip == "Tip" && brief.laneAdvantage == .me)
        #expect(abs((brief.winRate ?? 0) - 0.52) < 0.0001)
    }
}
