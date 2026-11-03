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
    private(set) var role: Role?
    private(set) var builds: [BuildOption] = []
    private(set) var isLoadingBuilds = false
    private(set) var staticData: StaticData?
    var actionState: ActionState = .idle
    /// Build the player imported (or the first option) – used for build progress in game.
    var plannedBuild: BuildOption? {
        get { settings.plannedBuild }
        set { settings.plannedBuild = newValue }
    }

    @ObservationIgnored let icons = IconCache()
    @ObservationIgnored let dataDragon = DataDragon()
    @ObservationIgnored private let loader: BuildLoader
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private(set) var lcu: LCUClient?
    @ObservationIgnored private(set) var actions: ChampSelectActions?
    @ObservationIgnored private var panel: ChampSelectPanel?
    @ObservationIgnored private var dock: ClientDockController?
    @ObservationIgnored private var staticDataTask: Task<Void, Never>?
    @ObservationIgnored let logger = Logger(subsystem: "de.polleydigital.riftglass", category: "ChampSelect")

    init(settings: AppSettings, loader: BuildLoader = BuildLoader()) {
        self.settings = settings
        self.loader = loader
    }

    var championName: String? {
        championId.flatMap { staticData?.champion($0)?.name }
    }

    func setClient(_ client: LCUClient?) {
        lcu = client
        actions = client.map { ChampSelectActions(lcu: $0) }
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
        plannedBuild = nil
        dock?.start(clientPID: clientPID)
    }

    /// Hides the panel. `plannedBuild` survives for the in-game build progress.
    func deactivate() {
        dock?.stop()
        session = nil
        championId = nil
        role = nil
        builds = []
        actionState = .idle
    }

    func update(session: ChampSelectSession?) {
        self.session = session
        let newChampion = session?.localChampionId
        guard newChampion != championId else { return }
        championId = newChampion
        actionState = .idle
        builds = []
        Task { await loadBuilds(for: newChampion, session: session) }
    }

    private func loadBuilds(for championId: Int?, session: ChampSelectSession?) async {
        guard let championId else { return }
        isLoadingBuilds = true
        await staticDataTask?.value
        guard let key = staticData?.champion(championId)?.id else {
            logger.error("Unknown champion \(championId)")
            isLoadingBuilds = false
            return
        }
        let role = await loader.resolveRole(session: session, championId: championId, lcu: lcu)
        let loaded = await loader.load(
            champion: ChampionRef(id: championId, key: key),
            role: role,
            patch: staticData?.version,
            lcu: lcu
        )
        guard championId == self.championId else { return } // champion changed; newer load owns the flag
        self.role = role
        builds = loaded
        isLoadingBuilds = false
        if plannedBuild?.id.contains("-\(championId)-") != true {
            plannedBuild = loaded.first
        }
        prefetchIcons(for: loaded)
    }

    private func prefetchIcons(for builds: [BuildOption]) {
        guard let data = staticData else { return }
        var urls: [URL] = []
        for build in builds {
            urls += build.allItemIds.map { dataDragon.itemIconURL($0, version: data.version) }
            urls += build.summonerSpells.compactMap { data.spellsById[$0] }
                .map { dataDragon.spellIconURL($0, version: data.version) }
            urls += build.runes.perkIds.compactMap { data.runesById[$0] }.map { dataDragon.runeIconURL($0.icon) }
        }
        if let championId, let champion = data.champion(championId) {
            urls.append(dataDragon.championIconURL(champion, version: data.version))
        }
        icons.prefetch(urls)
    }
}
