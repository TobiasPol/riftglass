import LeagueKit
import StatsKit

extension ChampSelectCoordinator {
    /// Runs all imports independently; one failing (e.g. full rune storage) does not block the others.
    func importAll(_ build: BuildOption) {
        runSteps(String(localized: "Build"), build: build, runes: true, spells: true, items: true)
    }

    func importRunes(_ build: BuildOption) {
        perform(String(localized: "Runes"), build: build) { [mode] actions, mapping in
            guard mode.usesRunePages else {
                throw MissingDataError.unsupportedInMode(String(localized: "Rune pages"), mode)
            }
            try await actions.importRunes(mapping.runePage)
        }
    }

    func setSpells(_ build: BuildOption) {
        perform(String(localized: "Spells"), build: build) { actions, mapping in
            guard let spells = mapping.spells else { throw MissingDataError.spells }
            try await actions.setSpells(spells)
        }
    }

    func importItemSet(_ build: BuildOption) {
        perform(String(localized: "Item set"), build: build) { [mode] actions, mapping in
            guard mode.itemSetMapId != nil else {
                throw MissingDataError.unsupportedInMode(String(localized: "Item sets"), mode)
            }
            try await actions.mergeItemSet(mapping.itemSet)
        }
    }

    /// Runs the selected imports that make sense in the current mode; collects failures instead of
    /// stopping at the first one.
    func runSteps(_ label: String, build: BuildOption, runes: Bool, spells: Bool, items: Bool) {
        let mode = mode
        perform(label, build: build) { actions, mapping in
            var steps: [(String, () async throws -> Void)] = []
            if runes, mode.usesRunePages {
                steps.append((String(localized: "Runes"), { try await actions.importRunes(mapping.runePage) }))
            }
            if spells, let selection = mapping.spells {
                steps.append((String(localized: "Spells"), { try await actions.setSpells(selection) }))
            }
            if items, mode.itemSetMapId != nil, !build.itemBlocks.isEmpty {
                steps.append((String(localized: "Item set"), { try await actions.mergeItemSet(mapping.itemSet) }))
            }
            var failures: [String] = []
            for (stepLabel, step) in steps {
                do { try await step() } catch { failures.append("\(stepLabel): \(ActionErrorText.describe(error))") }
            }
            if !failures.isEmpty {
                throw PartialImportError(failures: failures)
            }
        }
    }

    private func perform(
        _ label: String,
        build: BuildOption,
        _ work: @escaping (ChampSelectActions, BuildMapping) async throws -> Void
    ) {
        guard let championId else { return }
        guard let actions else {
            actionState = .failed(String(localized: "No connection to the League client."))
            return
        }
        let mapping = BuildMapping(
            build: build,
            championId: championId,
            championName: championName ?? "Champion",
            itemSetMapId: mode.itemSetMapId ?? GameMode.Map.summonersRift
        )
        actionState = .running(String(localized: "Importing \(label) …"))
        plannedBuild = build
        let previous = importChain
        importChain = Task {
            await previous?.value // never overlap: a reroll during an import waits for it
            do {
                try await work(actions, mapping)
                actionState = .done(String(localized: "\(label) imported."))
            } catch {
                actionState = .failed(ActionErrorText.describe(error))
                logger.error("\(label, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            }
            autoImportIfNeeded() // the pick may have changed while this import ran
        }
    }
}

enum MissingDataError: Error {
    case spells
    case unsupportedInMode(String, GameMode)
}
