import DataKit
import LeagueKit
import Observation
import os
import OverlayKit
import StatsKit
import SwiftUI

/// State + actions behind the docked champ-select panel.
@MainActor
@Observable
final class ChampSelectCoordinator {
    enum ActionState: Equatable {
        case idle
        case running(String)
        case done(String)
        case failed(String)
    }

    private(set) var session: ChampSelectSession?
    private(set) var championId: Int?
    private(set) var builds: [BuildOption] = []
    private(set) var staticData: StaticData?
    private(set) var actionState: ActionState = .idle

    @ObservationIgnored let icons = IconCache()
    @ObservationIgnored let dataDragon = DataDragon()
    @ObservationIgnored private let buildProvider: (any BuildProvider)?
    @ObservationIgnored private var actions: ChampSelectActions?
    @ObservationIgnored private var panel: ChampSelectPanel?
    @ObservationIgnored private var dock: ClientDockController?
    @ObservationIgnored private var staticDataTask: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: "de.polleydigital.riftglass", category: "ChampSelect")

    init(buildProvider: (any BuildProvider)? = try? BundledBuildProvider.bundled()) {
        self.buildProvider = buildProvider
    }

    var championName: String? {
        championId.flatMap { staticData?.champion($0)?.name }
    }

    func setActions(_ actions: ChampSelectActions?) {
        self.actions = actions
    }

    /// Loads Data Dragon as soon as the client is connected, so champ select opens instantly.
    func prepare() {
        guard staticData == nil, staticDataTask == nil else { return }
        staticDataTask = Task { [dataDragon] in
            defer { staticDataTask = nil }
            do {
                let version = try await dataDragon.latestVersion()
                staticData = try await dataDragon.staticData(version: version)
            } catch {
                logger.error("Data Dragon unavailable: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func activate(clientPID: pid_t) {
        prepare()
        if panel == nil {
            let panel = ChampSelectPanel(rootView: ChampSelectView(coordinator: self))
            self.panel = panel
            dock = ClientDockController(panel: panel)
        }
        dock?.start(clientPID: clientPID)
    }

    func deactivate() {
        dock?.stop()
        session = nil
        championId = nil
        builds = []
        actionState = .idle
    }

    func update(session: ChampSelectSession?) {
        self.session = session
        let newChampion = session?.localChampionId
        guard newChampion != championId else { return }
        championId = newChampion
        actionState = .idle
        Task { await loadBuilds(for: newChampion, role: Role(lcuPosition: session?.localPosition)) }
    }

    private func loadBuilds(for championId: Int?, role: Role?) async {
        guard let championId, let buildProvider else {
            builds = []
            return
        }
        let loaded = await (try? buildProvider.builds(
            championId: championId,
            role: role,
            patch: staticData?.version
        )) ?? []
        guard championId == self.championId else { return } // champion changed meanwhile
        builds = loaded
        prefetchIcons(for: loaded)
    }

    private func prefetchIcons(for builds: [BuildOption]) {
        guard let data = staticData else { return }
        var urls: [URL] = []
        for build in builds {
            urls += build.itemBlocks.flatMap(\.itemIds).map { dataDragon.itemIconURL($0, version: data.version) }
            urls += build.summonerSpells.compactMap { data.spellsById[$0] }
                .map { dataDragon.spellIconURL($0, version: data.version) }
            urls += build.runes.perkIds.compactMap { data.runesById[$0] }.map { dataDragon.runeIconURL($0.icon) }
        }
        if let championId, let champion = data.champion(championId) {
            urls.append(dataDragon.championIconURL(champion, version: data.version))
        }
        icons.prefetch(urls)
    }

    // MARK: - Actions

    /// Runs all three imports independently; one failing (e.g. full rune storage) does not block the others.
    func importAll(_ build: BuildOption) {
        perform("Build", build: build) { actions, mapping in
            var failures: [String] = []
            for (label, step) in Self.steps(actions, mapping) {
                do { try await step() } catch { failures.append("\(label): \(ActionErrorText.describe(error))") }
            }
            if !failures.isEmpty {
                throw PartialImportError(failures: failures)
            }
        }
    }

    private static func steps(
        _ actions: ChampSelectActions,
        _ mapping: BuildMapping
    ) -> [(String, () async throws -> Void)] {
        [
            ("Runen", { try await actions.importRunes(mapping.runePage) }),
            ("Spells", { try await actions.setSpells(mapping.spells) }),
            ("Item-Set", { try await actions.mergeItemSet(mapping.itemSet) })
        ]
    }

    func importRunes(_ build: BuildOption) {
        perform("Runen", build: build) { actions, mapping in try await actions.importRunes(mapping.runePage) }
    }

    func setSpells(_ build: BuildOption) {
        perform("Spells", build: build) { actions, mapping in try await actions.setSpells(mapping.spells) }
    }

    func importItemSet(_ build: BuildOption) {
        perform("Item-Set", build: build) { actions, mapping in try await actions.mergeItemSet(mapping.itemSet) }
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
