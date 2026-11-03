import LeagueKit
import StatsKit

/// Translates a `BuildOption` (StatsKit) into LCU payloads (LeagueKit).
struct BuildMapping {
    let runePage: NewRunePage
    let spells: SpellSelection
    let itemSet: ItemSetDraft

    init(build: BuildOption, championId: Int, championName: String) {
        runePage = NewRunePage(
            name: RunePagePlanner.pageName(for: championName),
            primaryStyleId: build.runes.primaryStyleId,
            subStyleId: build.runes.subStyleId,
            selectedPerkIds: build.runes.perkIds
        )
        let first = build.summonerSpells.first ?? 4
        let second = build.summonerSpells.dropFirst().first ?? 14
        spells = SpellSelection(spell1Id: first, spell2Id: second)
        itemSet = ItemSetDraft(
            championId: championId,
            title: "Riftglass: \(championName) – \(build.title)",
            blocks: build.itemBlocks.map { .init(title: $0.title, itemIds: $0.itemIds) }
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
        case let LCUError.http(status, _):
            "Der Client hat die Aktion abgelehnt (HTTP \(status))."
        default:
            "Aktion fehlgeschlagen: \(error.localizedDescription)"
        }
    }
}
