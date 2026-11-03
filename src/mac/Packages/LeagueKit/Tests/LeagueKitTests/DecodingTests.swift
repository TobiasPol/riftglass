import Foundation
@testable import LeagueKit
import Testing

/// Decoding of anonymized recordings from a real client (docs/SPIKE.md).
struct DecodingTests {
    @Test func champSelectSession() throws {
        let session: ChampSelectSession = try Fixture.decode("lcu/champ-select-session.json")
        #expect(session.localPlayerCellId == 0)
        #expect(session.queueId == 3140)
        #expect(session.localPlayer?.spell1Id == 6)
        #expect(session.localPlayer?.spell2Id == 7)
        #expect(session.localChampionId == nil) // nothing hovered yet (championId 0)
        #expect(session.localPosition == nil) // practice tool: no assigned position
        #expect(session.timer?.phase == "BAN_PICK")
        #expect(session.enemyPicks.isEmpty)
        #expect(session.isLocalPickInProgress) // practice tool: own pick action is open
    }

    /// Synthetic normal draft: three enemies locked, local player (mid) hovering during their turn.
    @Test func draftSessionTeams() throws {
        let session: ChampSelectSession = try Fixture.decode("lcu/champ-select-session-draft.json")
        #expect(session.localChampionId == 103)
        #expect(session.localPosition == "middle")
        #expect(session.allyChampionIds == [86, 254, 103])
        #expect(session.enemyPicks.map(\.championId) == [238, 64, 222])
        #expect(session.enemyPicks.allSatisfy { $0.position == nil })
        #expect(session.isLocalPickInProgress)
    }

    @Test func runePagesAndInventory() throws {
        let pages: [RunePage] = try Fixture.decode("lcu/perks-pages.json")
        #expect(!pages.isEmpty)
        #expect(pages.allSatisfy { $0.selectedPerkIds?.count == 9 || $0.selectedPerkIds == nil })
        let inventory: PerkInventory = try Fixture.decode("lcu/perks-inventory.json")
        #expect(inventory.canAddCustomPage == false)
        #expect(inventory.ownedPageCount == 2)
    }

    @Test func currentSummonerIsAnonymized() throws {
        let summoner: CurrentSummoner = try Fixture.decode("lcu/current-summoner.json")
        #expect(summoner.summonerId == 1000)
        #expect(summoner.puuid == "anon")
    }

    @Test func gameflowPhase() throws {
        #expect(try Fixture.decode("lcu/gameflow-phase.json", as: GameflowPhase.self) == .champSelect)
        #expect(GameflowPhase(rawValue: "None") == .idle)
        #expect(GameflowPhase(rawValue: "SomethingNew") == .unknown("SomethingNew"))
    }

    @Test func itemSetDocumentRoundTripsLosslessly() throws {
        let original = try Fixture.data("lcu/item-sets.json")
        let value = try JSONDecoder().decode(JSONValue.self, from: original)
        let reencoded = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
        #expect(value == reencoded)
        guard case let .array(sets)? = value["itemSets"] else { Issue.record("no itemSets"); return }
        #expect(sets.count == 3)
    }

    @Test func jsonValueKeepsIntegers() throws {
        let encoded = try JSONEncoder().encode(JSONValue.array([.number(3), .number(2.5)]))
        #expect(String(data: encoded, encoding: .utf8) == "[3,2.5]")
    }
}

struct WAMPMessageTests {
    private let uris = LCUEventStream.defaultURIs

    @Test func welcome() {
        let message = WAMPMessage.parse(Data(#"[0,"bb3cda84",1,"WAMP-1.0-RiotRemoting"]"#.utf8), keeping: uris)
        #expect(message == .welcome(session: "bb3cda84"))
    }

    @Test func champSelectEvent() throws {
        let data = try Fixture.data("lcu/ws-champ-select-event.json")
        guard case let .event(event)? = WAMPMessage.parse(data, keeping: uris) else {
            Issue.record("expected event"); return
        }
        #expect(event.uri == "/lol-champ-select/v1/session")
        #expect(event.eventType == .update)
        #expect(try event.decode(ChampSelectSession.self).localPlayerCellId == 0)
    }

    @Test func dropsUnrelatedEventsBeforeDecoding() {
        let frame = #"[8,"OnJsonApiEvent",{"data":{},"eventType":"Update","uri":"/lol-chat/v1/me"}]"#
        #expect(WAMPMessage.parse(Data(frame.utf8), keeping: uris) == nil)
    }

    @Test func gameflowPhaseEvent() throws {
        let frame = #"[8,"OnJsonApiEvent","#
            + #"{"data":"ChampSelect","eventType":"Update","uri":"/lol-gameflow/v1/gameflow-phase"}]"#
        guard case let .event(event)? = WAMPMessage.parse(Data(frame.utf8), keeping: uris) else {
            Issue.record("expected event"); return
        }
        #expect(try event.decode(GameflowPhase.self) == .champSelect)
    }

    @Test func ignoresGarbage() {
        #expect(WAMPMessage.parse(Data(), keeping: uris) == nil)
        #expect(WAMPMessage.parse(Data("[8,\"x\"".utf8), keeping: uris) == nil)
        #expect(WAMPMessage.subscribe() == #"[5,"OnJsonApiEvent"]"#)
    }
}
