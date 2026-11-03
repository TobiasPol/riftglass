import LeagueKit
import StatsKit

extension ChampSelectCoordinator {
    /// Runs all imports independently; one failing (e.g. full rune storage) does not block the others.
    func importAll(_ build: BuildOption) {
        perform("Build", build: build) { actions, mapping in
            var failures: [String] = []
            for (label, step) in Self.steps(actions, mapping, includeItems: !build.itemBlocks.isEmpty) {
                do { try await step() } catch { failures.append("\(label): \(ActionErrorText.describe(error))") }
            }
            if !failures.isEmpty {
                throw PartialImportError(failures: failures)
            }
        }
    }

    func importRunes(_ build: BuildOption) {
        perform("Runen", build: build) { actions, mapping in try await actions.importRunes(mapping.runePage) }
    }

    func setSpells(_ build: BuildOption) {
        perform("Spells", build: build) { actions, mapping in
            guard let spells = mapping.spells else { throw MissingDataError.spells }
            try await actions.setSpells(spells)
        }
    }

    func importItemSet(_ build: BuildOption) {
        perform("Item-Set", build: build) { actions, mapping in try await actions.mergeItemSet(mapping.itemSet) }
    }

    private static func steps(
        _ actions: ChampSelectActions,
        _ mapping: BuildMapping,
        includeItems: Bool
    ) -> [(String, () async throws -> Void)] {
        var steps: [(String, () async throws -> Void)] = [
            ("Runen", { try await actions.importRunes(mapping.runePage) })
        ]
        if let spells = mapping.spells {
            steps.append(("Spells", { try await actions.setSpells(spells) }))
        }
        if includeItems {
            steps.append(("Item-Set", { try await actions.mergeItemSet(mapping.itemSet) }))
        }
        return steps
    }

    private func perform(
        _ label: String,
        build: BuildOption,
        _ work: @escaping (ChampSelectActions, BuildMapping) async throws -> Void
    ) {
        guard let championId else { return }
        guard let actions else {
            actionState = .failed("Keine Verbindung zum League-Client.")
            return
        }
        let mapping = BuildMapping(build: build, championId: championId, championName: championName ?? "Champion")
        actionState = .running("\(label) wird übernommen …")
        plannedBuild = build
        Task {
            do {
                try await work(actions, mapping)
                actionState = .done("\(label) übernommen.")
            } catch {
                actionState = .failed(ActionErrorText.describe(error))
                logger.error("\(label, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            }
        }
    }
}

enum MissingDataError: Error {
    case spells
}
