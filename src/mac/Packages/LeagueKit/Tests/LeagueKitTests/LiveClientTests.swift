import Foundation
@testable import LeagueKit
import Testing

struct LiveClientTests {
    @Test func decodesRecordedPracticeToolGame() throws {
        let stats: LiveGameStats = try Fixture.decode("liveclient/gamestats.json")
        #expect(stats.gameMode == "PRACTICETOOL")
        #expect(stats.gameTime > 30)
        let active: LiveActivePlayer = try Fixture.decode("liveclient/activeplayer.json")
        #expect(active.currentGold == 500)
        let players: [LivePlayer] = try Fixture.decode("liveclient/playerlist.json")
        #expect(players.count == 1)
        #expect(players[0].championKey == "Lux")
        let snapshot = LiveGameSnapshot(stats: stats, activePlayer: active, players: players)
        #expect(snapshot.me?.championName == "Lux")
    }

    @Test func teamsLanesAndRiotIDs() throws {
        let players: [LivePlayer] = try Fixture.decode("liveclient/playerlist-10.json")
        let snapshot = LiveGameSnapshot(
            stats: LiveGameStats(gameMode: "CLASSIC", gameTime: 600, mapNumber: 11),
            activePlayer: nil,
            players: players
        )
        let jinx = try #require(players.first { $0.championKey == "Jinx" })
        #expect(snapshot.laneOpponent(of: jinx)?.championKey == "Caitlyn")
        #expect(jinx.items.map(\.itemID) == [1055, 3006, 3031])
        #expect(players.first { $0.championName == "Lee Sin" }?.championKey == "LeeSin")
        #expect(jinx.riotIDParts?.gameName == "Player3")
        #expect(jinx.riotIDParts?.tagLine == "EUW")
        #expect(snapshot.me == nil)
    }

    @Test func riotIDFallsBackToCombinedField() throws {
        let json = #"{"championName":"Lux","riotId":"Some Name#TAG1","team":"ORDER","level":1,"items":[],"#
            + #""scores":{"kills":0,"deaths":0,"assists":0,"creepScore":0}}"#
        let player = try JSONDecoder().decode(LivePlayer.self, from: Data(json.utf8))
        #expect(player.riotIDParts?.gameName == "Some Name")
        #expect(player.riotIDParts?.tagLine == "TAG1")
        #expect(player.championKey == "Lux")
    }
}

struct RecommendationTests {
    @Test func decodesRecordedRecommendedPages() throws {
        let pages: [RecommendedRunePage] = try Fixture.decode("lcu/recommended-pages.json")
        #expect(pages.count >= 2)
        #expect(pages.allSatisfy { $0.perkIds.count == 9 })
        #expect(pages[1].keystone?.name == "Electrocute")
        #expect(pages[1].summonerSpellIds == [4, 14])
    }

    @Test func positionsAndRegionViaLCU() async throws {
        let lcu = try FakeLCU(responses: [
            "/lol-perks/v1/recommended-champion-positions": Fixture.data("lcu/recommended-champion-positions.json"),
            "/riotclient/region-locale": Data(#"{"region":"EUW","locale":"en_US"}"#.utf8)
        ])
        #expect(try await lcu.recommendedPositions(championId: 99) == ["MIDDLE", "UTILITY"])
        #expect(try await lcu.recommendedPositions(championId: 1) == [])
        #expect(try await lcu.region() == "EUW")
    }
}

struct InGameAnalysisTests {
    private func players() throws -> [LivePlayer] {
        try Fixture.decode("liveclient/playerlist-10.json")
    }

    @Test func csPerMinuteAndBenchmark() throws {
        let jinx = try #require(try players().first { $0.championKey == "Jinx" })
        #expect(InGameAnalysis.csPerMinute(jinx, gameTime: 30) == nil)
        #expect(InGameAnalysis.csPerMinute(jinx, gameTime: 600) == 6.1) // 61 CS in 10 min
        #expect(InGameAnalysis.csBenchmark(for: jinx) == 8.0)
        #expect(InGameAnalysis.kda(jinx) == 6.0) // (3 + 3) / max(1, 1)
    }

    @Test func buildProgressIgnoresDuplicates() throws {
        let jinx = try #require(try players().first { $0.championKey == "Jinx" })
        let progress = InGameAnalysis.buildProgress(owned: jinx.items, planned: [1055, 2003, 2003, 3006, 3031, 6672])
        #expect(progress.done == 3 && progress.total == 5)
        #expect(InGameAnalysis.nextItem(owned: jinx.items, planned: [1055, 2003, 3031]) == 2003)
    }

    @Test func laneGoldDifferenceUsesVisibleItems() throws {
        let all = try players()
        let snapshot = LiveGameSnapshot(
            stats: LiveGameStats(gameMode: nil, gameTime: 600, mapNumber: 11),
            activePlayer: nil,
            players: all
        )
        let jinx = try #require(all.first { $0.championKey == "Jinx" })
        let prices = [1055: 450, 3006: 1000, 3031: 3500, 1054: 450]
        // Jinx: 450 + 1000 + 3500; Caitlyn (index 8, even) has no items.
        #expect(InGameAnalysis.laneGoldDifference(for: jinx, in: snapshot, prices: prices) == 4950)
        let solo = LiveGameSnapshot(stats: snapshot.stats, activePlayer: nil, players: [jinx])
        #expect(InGameAnalysis.laneGoldDifference(for: jinx, in: solo, prices: prices) == nil)
    }
}
