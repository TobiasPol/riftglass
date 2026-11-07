import LeagueKit
import StatsKit

/// Translates a `BuildOption` (StatsKit) into LCU payloads (LeagueKit).
struct BuildMapping {
    let runePage: NewRunePage
    /// Nil when the source has no spell recommendation.
    let spells: SpellSelection?
    let itemSet: ItemSetDraft

    /// `itemSetMapId` binds the item set to the detected mode's map, so an ARAM set does not
    /// replace the Summoner's Rift set of the same champion.
    init(build: BuildOption, championId: Int, championName: String, itemSetMapId: Int) {
        runePage = NewRunePage(
            name: RunePagePlanner.pageName(for: championName),
            primaryStyleId: build.runes.primaryStyleId,
            subStyleId: build.runes.subStyleId,
            selectedPerkIds: build.runes.perkIds
        )
        spells = build.summonerSpells.count >= 2
            ? SpellSelection(spell1Id: build.summonerSpells[0], spell2Id: build.summonerSpells[1]) : nil
        itemSet = ItemSetDraft(
            championId: championId,
            title: "Riftglass: \(championName) – \(build.title)",
            blocks: build.itemBlocks.map { .init(title: BuildText.blockTitle($0.title), itemIds: $0.itemIds) },
            mapId: itemSetMapId
        )
    }
}

/// Build texts from StatsKit are English identifiers; shown and written to the client localized.
enum BuildText {
    static func blockTitle(_ title: String) -> String {
        String(localized: String.LocalizationValue(title))
    }
}

struct PartialImportError: Error {
    let failures: [String]
}

enum ActionErrorText {
    static func describe(_ error: Error) -> String {
        switch error {
        case let partial as PartialImportError:
            partial.failures.joined(separator: "\n")
        case RuneImportError.noFreeSlot:
            String(localized: """
            No free rune page slot. Delete a page in the client – Riftglass only replaces its own pages.
            """)
        case RuneImportError.invalidPage:
            String(localized: "This rune page is invalid (outdated placeholder data?).")
        case let MissingDataError.unsupportedInMode(what, mode):
            String(localized: "\(what) don’t exist in \(mode.displayName).")
        case let LCUError.http(status, _):
            String(localized: "The client rejected the action (HTTP \(status)).")
        default:
            String(localized: "Action failed: \(error.localizedDescription)")
        }
    }
}
