import LeagueKit
import StatsKit

extension ChampSelectCoordinator {
    /// Imports the first option automatically once the champion is locked in (not on hover) –
    /// the item set for the detected mode's map, and runes/spells only if the player opted in.
    /// Runs once per game and champion; ARAM rerolls and bench swaps count as a new pick.
    func autoImportIfNeeded() {
        guard let plan = autoImportPlan() else { return }
        autoImportedKey = plan.key
        let mode = mode.rawValue
        logger.info("Auto import: items=\(plan.items) runes=\(plan.runes) mode=\(mode, privacy: .public)")
        runSteps(
            String(localized: "Automatic: \(plan.label)"),
            build: plan.build,
            runes: plan.runes,
            spells: plan.runes,
            items: plan.items
        )
    }

    private struct AutoImportPlan {
        let key: String
        let build: BuildOption
        let runes: Bool
        let items: Bool

        var label: String {
            [items ? String(localized: "Item set") : nil, runes ? String(localized: "Runes & spells") : nil]
                .compactMap(\.self).joined(separator: ", ")
        }
    }

    private func autoImportPlan() -> AutoImportPlan? {
        guard let session, let championId, !isLoadingBuilds,
              session.localPlayer?.championId == championId, // locked in, not just hovered
              let first = builds.first
        else { return nil }
        let key = "\(session.gameId ?? 0)-\(championId)"
        guard autoImportedKey != key else { return nil }
        let itemBuild = builds.first { !$0.itemBlocks.isEmpty }
        let items = settings.autoImportItemSet && mode.itemSetMapId != nil && itemBuild != nil
        let runes = settings.autoImportRunes && mode.usesRunePages
        guard items || runes else { return nil }
        // Item set from the first option with items; runes/spells from the first option. When both
        // are wanted and differ, the first option wins (OP.GG's build carries both).
        let build = runes ? first : (itemBuild ?? first)
        let importItems = items && !build.itemBlocks.isEmpty
        guard importItems || runes else { return nil }
        return AutoImportPlan(key: key, build: build, runes: runes, items: importItems)
    }
}
