import Foundation
@testable import LeagueKit
import Testing

struct ObjectiveAndEOGTests {
    @Test func objectiveTimersTrackDragonElderBaronAndInhibitors() throws {
        let json = """
        {
          "Events": [
            {"EventID": 1, "EventName": "DragonKill", "EventTime": 320.0, "DragonType": "Fire"},
            {"EventID": 2, "EventName": "BaronKill", "EventTime": 1200.0},
            {"EventID": 3, "EventName": "InhibKilled", "EventTime": 1300.0, "InhibKilled": "Barracks_T2_C1"},
            {"EventID": 4, "EventName": "InhibKilled", "EventTime": 900.0, "InhibKilled": "Barracks_T1_L1"},
            {"EventID": 5, "EventName": "InhibRespawned", "EventTime": 1200.0, "InhibRespawned": "Barracks_T1_L1"}
          ]
        }
        """
        let decoded = try JSONDecoder().decode(LiveEventsResponse.self, from: Data(json.utf8))
        let at1350 = ObjectiveTimerTracker.activeTimers(from: decoded.events, at: 1350)
        // Dragon died at 320 -> respawns at 620 (already expired at 1350).
        // Barracks_T1_L1 died at 900 & respawned at 1200 -> cleared.
        // Remaining: Baron (1560) and Red Mid Inhib (1600).
        #expect(at1350.map(\.id) == ["baron", "inhib-Barracks_T2_C1"])
        #expect(at1350[0].kind == .baron)
        #expect(at1350[0].formattedRemaining(at: 1350) == "3:30")
        #expect(at1350[1].label == "Red Mid Inhib")
        #expect(at1350[1].formattedRemaining(at: 1350) == "4:10")

        let elderEvent = LiveGameEvent(eventID: 6, eventName: "DragonKill", eventTime: 1800, dragonType: "Elder")
        let elderTimers = ObjectiveTimerTracker.activeTimers(from: [elderEvent], at: 1900)
        #expect(elderTimers.first?.kind == .elder)
        #expect(elderTimers.first?.label == "Elder")
        #expect(elderTimers.first?.remainingSeconds(at: 1900) == 260)
    }

    @Test func soulTakingElementalDrakeEmitsElderTimer() throws {
        let players = try JSONDecoder().decode([LivePlayer].self, from: Data(Self.twoTeamPlayersJSON.utf8))
        let splitEvents = [
            LiveGameEvent(
                eventID: 1,
                eventName: "DragonKill",
                eventTime: 300,
                killerName: "Jungler",
                dragonType: "Fire"
            ),
            LiveGameEvent(
                eventID: 2,
                eventName: "DragonKill",
                eventTime: 650,
                killerName: "EnemyJg",
                dragonType: "Air"
            ),
            LiveGameEvent(
                eventID: 3, eventName: "DragonKill", eventTime: 1000, killerName: "Jungler", dragonType: "Earth"
            ),
            LiveGameEvent(
                eventID: 4, eventName: "DragonKill", eventTime: 1350, killerName: "Jungler#EUW", dragonType: "Water"
            ),
            LiveGameEvent(
                eventID: 5, eventName: "DragonKill", eventTime: 1700, killerName: "Jungler", dragonType: "Water"
            )
        ]
        // 3rd ORDER drake -> still Dragon (300s).
        let afterThree = ObjectiveTimerTracker.activeTimers(
            from: Array(splitEvents.prefix(4)), players: players, at: 1400
        )
        #expect(afterThree.first?.kind == .dragon && afterThree.first?.remainingSeconds(at: 1400) == 250)
        // 4th ORDER drake claims Soul -> next spawn is Elder (360s).
        let afterSoul = ObjectiveTimerTracker.activeTimers(from: splitEvents, players: players, at: 1750)
        #expect(afterSoul.first?.kind == .elder && afterSoul.first?.label == "Elder")
        #expect(afterSoul.first?.remainingSeconds(at: 1750) == 310)
        // Fallback without players emits Elder on the 7th elemental drake.
        let anonymous = (1 ... 7).map { idx in
            LiveGameEvent(eventID: idx, eventName: "DragonKill", eventTime: Double(idx * 300), dragonType: "Fire")
        }
        let seventh = ObjectiveTimerTracker.activeTimers(from: anonymous, at: 2150)
        #expect(seventh.first?.kind == .elder && seventh.first?.remainingSeconds(at: 2150) == 310)
    }

    private static let twoTeamPlayersJSON = """
    [
      {
        "championName": "Lee Sin", "riotId": "Jungler#EUW", "riotIdGameName": "Jungler",
        "team": "ORDER", "level": 11, "items": [],
        "scores": {"kills": 0, "deaths": 0, "assists": 0, "creepScore": 0}
      },
      {
        "championName": "Vi", "riotId": "EnemyJg#EUW", "riotIdGameName": "EnemyJg",
        "team": "CHAOS", "level": 11, "items": [],
        "scores": {"kills": 0, "deaths": 0, "assists": 0, "creepScore": 0}
      }
    ]
    """

    @Test func goldNeededSubtractsNestedComponentsAndDuplicates() throws {
        // 3118 (2700) = 3802 (1200) + 3108 (900)
        // 3802 (1200) = 1052 (400) + 1027 (300) + 2022 (250)
        // 3108 (900) = 1052 (400) + 2022 (250)
        let prices = [3118: 2700, 3802: 1200, 3108: 900, 1052: 400, 1027: 300, 2022: 250]
        let recipes = [3118: [3802, 3108], 3802: [1052, 1027, 2022], 3108: [1052, 2022]]
        let itemJSON = #"[{"itemID":3802,"slot":0},{"itemID":1052,"slot":1},{"itemID":1052,"slot":2}]"#
        let owned = try JSONDecoder().decode([LivePlayer.Item].self, from: Data(itemJSON.utf8))
        // Owning 3802 (1200) satisfies the 3802 branch completely (doesn't double-count), leaving 3108 branch to
        // consume ONE 1052 (400). Second 1052 is spare. Missing = 2700 - 1200 - 400 = 1100.
        #expect(
            InGameAnalysis.goldNeeded(for: 3118, currentGold: 350, owned: owned, prices: prices, recipes: recipes)
                == 750
        )
        #expect(
            InGameAnalysis.goldNeeded(for: 3118, currentGold: 1200, owned: owned, prices: prices, recipes: recipes) == 0
        )
        let alreadyOwned = try JSONDecoder().decode(
            [LivePlayer.Item].self,
            from: Data(#"[{"itemID":3118,"slot":0}]"#.utf8)
        )
        #expect(
            InGameAnalysis.goldNeeded(for: 3118, currentGold: 0, owned: alreadyOwned, prices: prices, recipes: recipes)
                == 0
        )
        #expect(
            InGameAnalysis.goldNeeded(for: 9999, currentGold: 0, owned: [], prices: prices, recipes: recipes) == nil
        )
    }

    @Test func decodesEndOfGameStatsAndComputesShares() async throws {
        let lcu = FakeLCU(responses: ["/lol-end-of-game/v1/eog-stats-block": Data(Self.sampleEOGPayload.utf8)])
        let stats = try await lcu.endOfGameStats()
        #expect(stats.championId == 103)
        #expect(stats.won == true)
        #expect(stats.kills == 8 && stats.deaths == 3 && stats.assists == 10)
        #expect(stats.visionScore == 24)
        #expect(abs((stats.killParticipation ?? 0) - 0.9) < 0.001)
        #expect(abs((stats.damageShare ?? 0) - 0.5) < 0.001)
    }

    private static let sampleEOGPayload = """
    {
      "gameId": 123456,
      "gameLength": 1820,
      "localPlayer": {
        "championId": 103,
        "teamId": 100,
        "stats": {
          "CHAMPIONS_KILLED": 8,
          "NUM_DEATHS": 3,
          "ASSISTS": 10,
          "VISION_SCORE": 24,
          "TOTAL_DAMAGE_DEALT_TO_CHAMPIONS": 25000,
          "WIN": 1
        }
      },
      "teams": [
        {
          "teamId": 100,
          "isWinningTeam": true,
          "players": [
            {
              "championId": 103,
              "teamId": 100,
              "isLocalPlayer": true,
              "stats": { "CHAMPIONS_KILLED": 8, "TOTAL_DAMAGE_DEALT_TO_CHAMPIONS": 25000 }
            },
            {
              "championId": 64,
              "teamId": 100,
              "isLocalPlayer": false,
              "stats": { "CHAMPIONS_KILLED": 12, "TOTAL_DAMAGE_DEALT_TO_CHAMPIONS": 25000 }
            }
          ]
        }
      ]
    }
    """
}
