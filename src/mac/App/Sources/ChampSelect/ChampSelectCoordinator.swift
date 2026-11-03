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
    /// Detected queue; from the gameflow session, else from champ select's `queueId`.
    private(set) var queue: GameQueue?
    private(set) var championId: Int?
    private(set) var role: Role?
    private(set) var builds: [BuildOption] = []
    /// ARAM: Mayhem only – most picked augments for the champion (OP.GG).
    private(set) var augments: [AugmentStat] = []
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
    @ObservationIgnored private let augmentProvider = OPGGAugmentProvider()
    @ObservationIgnored let settings: AppSettings
    /// `gameId-championId` of the last automatic import, so it runs once per pick.
    @ObservationIgnored var autoImportedKey: String?
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

    var mode: GameMode {
        queue?.mode ?? .summonersRift
    }

    /// From the gameflow session. Reloads builds if the mode changes while a champion is selected.
    func setQueue(_ newQueue: GameQueue?) {
        guard let newQueue, newQueue != queue else { return }
        let reload = BuildQueue(queue: newQueue) != queue.flatMap(BuildQueue.init(queue:))
            || newQueue.mode != queue?.mode
        queue = newQueue
        if reload, let championId {
            builds = []
            Task { await loadBuilds(for: championId, session: session) }
        }
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
        augments = []
        actionState = .idle
    }

    func update(session: ChampSelectSession?) {
        self.session = session
        if let queueId = session?.queueId, queueId > 0, queue?.id != queueId {
            queue = GameQueue(queueId: queueId)
        }
        let newChampion = session?.localChampionId
        guard newChampion != championId else {
            autoImportIfNeeded() // lock-in of the hovered champion
            return
        }
        championId = newChampion
        actionState = .idle
        builds = []
        augments = []
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
        let queue = queue ?? GameQueue(id: nil, mode: .summonersRift, mapId: GameMode.Map.summonersRift)
        let role = await loader.resolveRole(session: session, championId: championId, mode: queue.mode, lcu: lcu)
        async let loadedAugments = loadAugments(championId: championId, mode: queue.mode)
        let loaded = await loader.load(
            champion: ChampionRef(id: championId, key: key),
            role: role,
            queue: queue,
            patch: staticData?.version,
            lcu: lcu
        )
        let augments = await loadedAugments
        // Champion or queue changed meanwhile; the newer load owns the flag.
        guard championId == self.championId, queue.mode == mode else { return }
        self.role = role
        builds = loaded
        self.augments = augments
        isLoadingBuilds = false
        if plannedBuild?.championKey != key || plannedBuild?.queue != loaded.first?.queue {
            plannedBuild = loaded.first
        }
        prefetchIcons(for: loaded)
        autoImportIfNeeded()
    }

    private func loadAugments(championId: Int, mode: GameMode) async -> [AugmentStat] {
        guard mode == .aramMayhem else { return [] }
        do {
            return try await augmentProvider.augments(championId: championId, limit: 6)
        } catch {
            logger.notice("OP.GG augments unavailable: \(String(describing: error), privacy: .public)")
            return []
        }
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
