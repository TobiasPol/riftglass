import Foundation
import LeagueKit
@testable import Riftglass
import StatsKit
import Testing

struct GameSummaryTests {
    private func sampleSummary() -> GameSummary {
        GameSummary(
            championName: "Ahri",
            kills: 6,
            deaths: 2,
            assists: 9,
            csPerMinute: 7.4,
            minutes: 28,
            buildDone: 3,
            buildTotal: 4
        )
    }

    private func sampleEOG() -> EndOfGameStats {
        EndOfGameStats(
            gameId: 99,
            gameLength: 1680,
            localPlayer: .init(
                championId: 103,
                teamId: 100,
                stats: [
                    "CHAMPIONS_KILLED": 7, "NUM_DEATHS": 2, "ASSISTS": 10,
                    "VISION_SCORE": 22, "TOTAL_DAMAGE_DEALT_TO_CHAMPIONS": 20000
                ]
            ),
            teams: [
                .init(teamId: 100, isWinningTeam: true, players: [
                    .init(championId: 103, teamId: 100, isLocalPlayer: true, stats: [
                        "CHAMPIONS_KILLED": 7, "TOTAL_DAMAGE_DEALT_TO_CHAMPIONS": 20000
                    ]),
                    .init(championId: 64, teamId: 100, isLocalPlayer: false, stats: [
                        "CHAMPIONS_KILLED": 13, "TOTAL_DAMAGE_DEALT_TO_CHAMPIONS": 20000
                    ])
                ])
            ]
        )
    }

    @Test func codableRoundTrip() throws {
        let initial = sampleSummary()
        let data = try JSONEncoder().encode(initial)
        let decoded = try JSONDecoder().decode(GameSummary.self, from: data)
        #expect(decoded == initial)
    }

    @Test func enrichesWithEndOfGameStats() {
        let initial = sampleSummary()
        let enriched = initial.enriched(with: sampleEOG())
        #expect(enriched.id == initial.id)
        #expect(enriched.won == true)
        #expect(enriched.kills == 7 && enriched.assists == 10)
        #expect(enriched.csPerMinute == 7.4 && enriched.buildDone == 3)
        #expect(enriched.visionScore == 22)
        #expect(abs((enriched.killParticipation ?? 0) - 0.85) < 0.001)
        #expect(abs((enriched.damageShare ?? 0) - 0.5) < 0.001)
    }

    @MainActor
    @Test func recentGamesCapsAtTenEntries() throws {
        let suite = "de.polleydigital.riftglass.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        for idx in 1 ... 12 {
            settings.recordGame(GameSummary(
                championName: "Champ\(idx)",
                kills: idx,
                deaths: 1,
                assists: 2,
                csPerMinute: nil,
                minutes: 20,
                buildDone: 0,
                buildTotal: 0
            ))
        }
        #expect(settings.recentGames.count == 10)
        #expect(settings.recentGames.first?.championName == "Champ12")
        #expect(settings.recentGames.last?.championName == "Champ3")
    }

    @MainActor
    @Test func applyEndOfGameStatsDeduplicatesByGameIdAcrossRestarts() throws {
        let suite = "de.polleydigital.riftglass.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let firstSettings = AppSettings(defaults: defaults)
        let firstCoord = InGameCoordinator(
            champSelect: ChampSelectCoordinator(settings: firstSettings),
            settings: firstSettings
        )
        firstCoord.applyEndOfGameStats(sampleEOG())
        #expect(firstSettings.recentGames.count == 1)
        #expect(firstSettings.recentGames.first?.gameId == 99)

        // Simulates app restart while client is still in EndOfGame.
        let restartedSettings = AppSettings(defaults: defaults)
        let restartedCoord = InGameCoordinator(
            champSelect: ChampSelectCoordinator(settings: restartedSettings),
            settings: restartedSettings
        )
        restartedCoord.applyEndOfGameStats(sampleEOG())
        #expect(restartedSettings.recentGames.count == 1)
    }

    @MainActor
    @Test func refreshRanksForCurrentRegionClearsCachedRanksOnChange() throws {
        let suite = "de.polleydigital.riftglass.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        settings.region = "EUW"
        let coordinator = InGameCoordinator(
            champSelect: ChampSelectCoordinator(settings: settings),
            settings: settings
        )
        coordinator.rankRegion = "EUW"
        coordinator.ranks["Player0#EUW"] = PlayerRank(tier: "GOLD", division: 2, leaguePoints: 50, wins: 10, losses: 5)
        settings.manualRegion = "NA"
        coordinator.refreshRanksForCurrentRegion()
        #expect(coordinator.ranks.isEmpty)
        #expect(coordinator.rankRegion == "NA")
    }
}
