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
            blocks: build.itemBlocks.map { .init(title: $0.title, itemIds: $0.itemIds) },
            mapId: itemSetMapId
        )
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
            "Kein freier Runenseiten-Platz. Lösche eine Seite im Client – Riftglass ersetzt nur eigene Seiten."
        case RuneImportError.invalidPage:
            "Diese Runenseite ist ungültig (Platzhalter-Daten veraltet?)."
        case let MissingDataError.unsupportedInMode(what, mode):
            "\(what) gibt es in \(mode.displayName) nicht."
        case let LCUError.http(status, _):
            "Der Client hat die Aktion abgelehnt (HTTP \(status))."
        default:
            "Aktion fehlgeschlagen: \(error.localizedDescription)"
        }
    }
}
