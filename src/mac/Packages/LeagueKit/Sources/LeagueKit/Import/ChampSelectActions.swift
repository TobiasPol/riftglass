import Foundation
import os

/// The three champ-select actions: import runes, set summoner spells, merge an item set.
/// Each action reads the current state first and only modifies what Riftglass owns.
public struct ChampSelectActions: Sendable {
    private let lcu: any LCURequesting
    private let logger = Logger(subsystem: "de.polleydigital.riftglass", category: "ChampSelectActions")

    public init(lcu: any LCURequesting) {
        self.lcu = lcu
    }

    public func importRunes(_ page: NewRunePage) async throws {
        async let pages: [RunePage] = lcu.get("/lol-perks/v1/pages")
        async let inventory: PerkInventory = lcu.get("/lol-perks/v1/inventory")
        let plan = try await RunePagePlanner.plan(desired: page, existing: pages, inventory: inventory)
        switch plan {
        case let .create(newPage):
            try await lcu.send(.post, "/lol-perks/v1/pages", json: newPage)
        case let .replace(ownPageId, newPage):
            // Always with an ID – DELETE /lol-perks/v1/pages without one deletes *all* pages.
            try await lcu.send(.delete, "/lol-perks/v1/pages/\(ownPageId)")
            try await lcu.send(.post, "/lol-perks/v1/pages", json: newPage)
        }
        logger.info("Imported rune page")
    }

    public func setSpells(_ selection: SpellSelection) async throws {
        try await lcu.send(.patch, "/lol-champ-select/v1/session/my-selection", json: selection)
    }

    public func mergeItemSet(_ draft: ItemSetDraft) async throws {
        let summoner: CurrentSummoner = try await lcu.get("/lol-summoner/v1/current-summoner")
        let path = "/lol-item-sets/v1/item-sets/\(summoner.summonerId)/sets"
        let document: JSONValue = try await lcu.get(path)
        let merged = try ItemSetMerger.merge(draft, into: document)
        try await lcu.send(.put, path, json: merged)
        logger.info("Merged item set")
    }
}
