import Foundation
@testable import LeagueKit
import Testing

struct ChampSelectActionsTests {
    private let page = NewRunePage(
        name: "Riftglass: Ahri",
        primaryStyleId: 8100,
        subStyleId: 8200,
        selectedPerkIds: [8112, 8139, 8138, 8135, 8226, 8210, 5008, 5008, 5001]
    )

    @Test func replacingOwnPageDeletesByIdThenCreates() async throws {
        let pages = #"[{"id":5,"name":"OP.GG"},{"id":9,"name":"Riftglass: Lux","isDeletable":true}]"#
        let lcu = FakeLCU(responses: [
            "/lol-perks/v1/pages": Data(pages.utf8),
            "/lol-perks/v1/inventory": Data(#"{"canAddCustomPage":false}"#.utf8)
        ])
        try await ChampSelectActions(lcu: lcu).importRunes(page)
        let writes = await lcu.requests.filter { $0.method != .get }
        #expect(writes.map(\.method) == [.delete, .post])
        #expect(writes.first?.path == "/lol-perks/v1/pages/9")
        #expect(!writes.contains { $0.method == .delete && $0.path == "/lol-perks/v1/pages" })
    }

    @Test func fullStorageWritesNothing() async throws {
        let lcu = try FakeLCU(responses: [
            "/lol-perks/v1/pages": Fixture.data("lcu/perks-pages.json"),
            "/lol-perks/v1/inventory": Fixture.data("lcu/perks-inventory.json")
        ])
        await #expect(throws: RuneImportError.noFreeSlot) { try await ChampSelectActions(lcu: lcu).importRunes(page) }
        #expect(await lcu.requests.allSatisfy { $0.method == .get })
    }

    @Test func setSpellsPatchesMySelection() async throws {
        let lcu = FakeLCU(responses: [:])
        try await ChampSelectActions(lcu: lcu).setSpells(SpellSelection(spell1Id: 4, spell2Id: 14))
        let request = try #require(await lcu.requests.first)
        #expect(request.method == .patch)
        #expect(request.path == "/lol-champ-select/v1/session/my-selection")
        let body = try JSONDecoder().decode([String: Int].self, from: #require(request.body))
        #expect(body == ["spell1Id": 4, "spell2Id": 14])
    }

    @Test func itemSetIsMergedIntoRecordedDocument() async throws {
        let path = "/lol-item-sets/v1/item-sets/1000/sets"
        let lcu = try FakeLCU(responses: [
            "/lol-summoner/v1/current-summoner": Fixture.data("lcu/current-summoner.json"),
            path: Fixture.data("lcu/item-sets.json")
        ])
        let draft = ItemSetDraft(championId: 103, title: "Riftglass: Ahri", blocks: [.init(title: "S", itemIds: [1])])
        try await ChampSelectActions(lcu: lcu).mergeItemSet(draft)
        let put = try #require(await lcu.requests.last)
        #expect(put.method == .put && put.path == path)
        let body = try JSONDecoder().decode(JSONValue.self, from: #require(put.body))
        #expect(ItemSetMerger.ownSetCount(in: body) == 1)
        guard case let .array(sets)? = body["itemSets"] else { Issue.record("no sets"); return }
        #expect(sets.count == 4)
    }
}
