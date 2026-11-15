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

struct RegionTests {
    @Test func regionViaLCU() async throws {
        let lcu = FakeLCU(responses: [
            "/riotclient/region-locale": Data(#"{"region":"EUW","locale":"en_US"}"#.utf8)
        ])
        #expect(try await lcu.region() == "EUW")
    }
}
