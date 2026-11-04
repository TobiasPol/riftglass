import Foundation
@testable import LeagueKit
import Testing

struct GameModeTests {
    @Test(arguments: [
        (420, GameMode.summonersRift), (440, .summonersRift), (480, .summonersRift), (490, .summonersRift),
        (450, .aram), (2400, .aramMayhem), (1700, .arena), (1710, .arena), (1750, .arena), (900, .urf), (1900, .urf),
        (1020, .oneForAll), (1400, .ultimateSpellbook), (1300, .nexusBlitz), (2300, .brawl), (1810, .swarm)
    ])
    func knownQueueIds(queueId: Int, expected: GameMode) {
        #expect(GameMode.classify(queueId: queueId, gameMode: nil, mapId: nil) == expected)
    }

    @Test func unknownQueueFallsBackToModeStringThenMap() {
        // Practice tool (queue 3140 in the spike) and a future mode on a known map.
        #expect(GameMode.classify(queueId: 3140, gameMode: "PRACTICETOOL", mapId: 11) == .summonersRift)
        #expect(GameMode.classify(queueId: 9999, gameMode: "NEWMODE", mapId: 12) == .aram)
        #expect(GameMode.classify(queueId: nil, gameMode: "kiwi", mapId: 12) == .aramMayhem)
        #expect(GameMode.classify(queueId: nil, gameMode: "CHERRY", mapId: nil) == .arena)
        #expect(GameMode.classify(queueId: nil, gameMode: nil, mapId: 99) == .unknown)
    }

    @Test func leagueClassicIsRecognisedByQueueName() {
        let mode = GameMode.classify(queueId: 9001, gameMode: "CLASSIC", mapId: 11, description: "League Classic")
        #expect(mode == .leagueClassic)
        #expect(!mode.usesRunePages && mode.itemSetMapId == nil)
    }

    @Test func capabilitiesPerMode() {
        #expect(GameMode.summonersRift.hasLanes && GameMode.summonersRift.itemSetMapId == 11)
        #expect(!GameMode.aram.hasLanes && GameMode.aram.itemSetMapId == 12)
        #expect(GameMode.aramMayhem.itemSetMapId == 12 && GameMode.aramMayhem.hasAugments)
        #expect(!GameMode.aramMayhem.usesRunePages && GameMode.aram.usesRunePages)
        #expect(!GameMode.arena.usesRunePages && GameMode.arena.itemSetMapId == nil)
    }

    @Test func decodesGameflowSessionQueue() throws {
        let json = #"{"phase":"ChampSelect","gameData":{"gameId":1,"queue":{"id":2400,"mapId":12,"#
            + #""gameMode":"KIWI","description":"ARAM: Mayhem","type":"KIWI","isRanked":false}}}"#
        let session = try JSONDecoder().decode(GameflowSession.self, from: Data(json.utf8))
        let queue = try #require(session.queue)
        #expect(queue.mode == .aramMayhem && queue.id == 2400 && queue.mapId == 12)
        #expect(queue.displayName == "ARAM: Mayhem")
        let idle = #"{"phase":"None","gameData":{"queue":{"id":-1,"mapId":0,"gameMode":""}}}"#
        #expect(try JSONDecoder().decode(GameflowSession.self, from: Data(idle.utf8)).queue == nil)
    }

    @Test func gameflowSessionEventPassesFilterAndYieldsQueue() throws {
        // Mode switch inside the lobby: only a gameflow-session event, no phase change.
        let frame = #"[8,"OnJsonApiEvent",{"data":{"phase":"Lobby","gameData":{"queue":{"id":450,"#
            + #""mapId":12,"gameMode":"ARAM","description":"ARAM"}}},"eventType":"Update","#
            + #""uri":"/lol-gameflow/v1/session"}]"#
        let message = WAMPMessage.parse(Data(frame.utf8), keeping: LCUEventStream.defaultURIs)
        guard case let .event(event)? = message else {
            Issue.record("event dropped")
            return
        }
        #expect(try event.decode(GameflowSession.self).queue?.mode == .aram)
        // Sub-resources of the session are not mistaken for it.
        let other = frame.replacingOccurrences(of: "/v1/session\"", with: "/v1/session/extra\"")
        #expect(WAMPMessage.parse(Data(other.utf8), keeping: LCUEventStream.defaultURIs) == nil)
    }

    @Test func inGameKeepsRememberedQueueOnlyOnSameMap() {
        let flex = GameQueue(id: 440, mode: .summonersRift, mapId: 11, isRanked: true, name: "Ranked Flex")
        #expect(GameQueue.resolvedInGame(remembered: flex, liveGameMode: "CLASSIC", mapNumber: 11) == flex)
        let aram = GameQueue.resolvedInGame(remembered: flex, liveGameMode: "ARAM", mapNumber: 12)
        #expect(aram.mode == .aram && aram.id == nil)
        #expect(GameQueue.resolvedInGame(remembered: nil, liveGameMode: "CHERRY", mapNumber: 30).mode == .arena)
        #expect(flex.isFlex && flex.displayName == "Ranked Flex")
    }

    @Test func itemSetUidIsPerMap() {
        let rift = ItemSetDraft(championId: 103, title: "A", blocks: [])
        let abyss = ItemSetDraft(championId: 103, title: "A", blocks: [], mapId: 12)
        #expect(rift.uid == "52494654-474c-4153-5300-000000000067")
        #expect(abyss.uid == "52494654-474c-4153-530c-000000000067")
        #expect(UUID(uuidString: abyss.uid) != nil)
        #expect(abyss.json["associatedMaps"] == .array([.number(12)]))
    }
}
