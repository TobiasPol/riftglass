import Foundation
@testable import LeagueKit
import Testing

private let desired = NewRunePage(
    name: RunePagePlanner.pageName(for: "Ahri"),
    primaryStyleId: 8100,
    subStyleId: 8200,
    selectedPerkIds: [
        8112,
        8139,
        8138,
        8135,
        8226,
        8210,
        5008,
        5008,
        5001
    ]
)

struct RunePagePlannerTests {
    private let freeSlot = PerkInventory(canAddCustomPage: true)
    private let full = PerkInventory(canAddCustomPage: false)

    @Test func recordedAccountWithFullStorageIsLeftAlone() throws {
        // Recorded: 2/2 pages, both from other tools → must not delete anything.
        let pages: [RunePage] = try Fixture.decode("lcu/perks-pages.json")
        let inventory: PerkInventory = try Fixture.decode("lcu/perks-inventory.json")
        #expect(throws: RuneImportError.noFreeSlot) {
            try RunePagePlanner.plan(desired: desired, existing: pages, inventory: inventory)
        }
    }

    @Test func createsWhenSlotIsFree() throws {
        let pages = [RunePage(id: 1, name: "My page")]
        #expect(try RunePagePlanner.plan(desired: desired, existing: pages, inventory: freeSlot) == .create(desired))
    }

    @Test func replacesOnlyOwnPage() throws {
        let pages = [
            RunePage(id: 1, name: "OP.GG Ahri", current: true),
            RunePage(id: 2, name: "Riftglass: Lux"),
            RunePage(id: 3, name: "Mine")
        ]
        #expect(try RunePagePlanner.plan(desired: desired, existing: pages, inventory: full)
            == .replace(ownPageId: 2, with: desired))
    }

    @Test func skipsUndeletableOrTemporaryLookalikes() throws {
        let pages = [
            RunePage(id: 7, name: "Riftglass preset", isDeletable: false),
            RunePage(id: 8, name: "Riftglass temp", isTemporary: true)
        ]
        #expect(throws: RuneImportError.noFreeSlot) {
            try RunePagePlanner.plan(desired: desired, existing: pages, inventory: full)
        }
    }

    @Test func rejectsInvalidPages() {
        let short = NewRunePage(name: "Riftglass: X", primaryStyleId: 8100, subStyleId: 8200, selectedPerkIds: [1])
        let foreignName = NewRunePage(
            name: "Other",
            primaryStyleId: 8100,
            subStyleId: 8200,
            selectedPerkIds: desired.selectedPerkIds
        )
        for page in [short, foreignName] {
            #expect(throws: RuneImportError.invalidPage) {
                try RunePagePlanner.plan(desired: page, existing: [], inventory: freeSlot)
            }
        }
    }
}

struct ItemSetMergerTests {
    private let draft = ItemSetDraft(
        championId: 103,
        title: "Riftglass: Ahri",
        blocks: [.init(title: "Start", itemIds: [1056, 2003])]
    )

    private func recorded() throws -> JSONValue {
        try Fixture.decode("lcu/item-sets.json")
    }

    private func sets(_ document: JSONValue) -> [JSONValue] {
        if case let .array(sets)? = document["itemSets"] {
            return sets
        }
        return []
    }

    @Test func keepsForeignSetsUntouched() throws {
        let original = try recorded()
        let merged = try ItemSetMerger.merge(draft, into: original)
        #expect(sets(merged).count == sets(original).count + 1)
        #expect(Array(sets(merged).prefix(3)) == sets(original)) // byte-for-byte equal JSON values
        #expect(merged["accountId"] == original["accountId"])
        #expect(merged["timestamp"] == original["timestamp"])
    }

    @Test func replacesOwnSetOnReimport() throws {
        let once = try ItemSetMerger.merge(draft, into: recorded())
        let twice = try ItemSetMerger.merge(draft, into: once)
        #expect(sets(twice).count == sets(once).count)
        #expect(ItemSetMerger.ownSetCount(in: twice) == 1)
    }

    @Test func uidIsDeterministicUUIDShape() {
        #expect(draft.uid == "52494654-474c-4153-5300-000000000067")
        #expect(UUID(uuidString: draft.uid) != nil)
    }

    @Test func handlesEmptyAndBrokenDocuments() throws {
        let empty = try ItemSetMerger.merge(draft, into: .object(["itemSets": .null]))
        #expect(sets(empty).count == 1)
        #expect(throws: ItemSetMergeError.unexpectedDocument) { try ItemSetMerger.merge(draft, into: .array([])) }
    }
}
