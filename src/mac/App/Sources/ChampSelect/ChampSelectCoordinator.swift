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
    /// Lane matchup, team comp and counter picks (`ChampSelectCoordinator+Briefing`).
    var briefing = ChampSelectBriefing()
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
    @ObservationIgnored let briefingSources = BriefingSources()
    /// OP.GG lane shares, loaded once per app run (the disk cache keeps them for 6 h).
    @ObservationIgnored var roleRates: RoleRates?
    /// Pending lane-share request, shared so concurrent updates send it only once.
    @ObservationIgnored var roleRatesTask: Task<RoleRates?, Never>?
    @ObservationIgnored let settings: AppSettings
    /// `gameId-championId` of the last automatic import, so it runs once per pick.
    @ObservationIgnored var autoImportedKey: String?
    /// Tail of the import queue. Imports read and replace shared state (rune pages, the whole
    /// item-set document), so they run strictly one after another.
    @ObservationIgnored var importChain: Task<Void, Never>?
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
        effectiveQueue.mode
    }

    /// Queue builds are loaded for; Summoner's Rift until the client reports one.
    var effectiveQueue: GameQueue {
        queue ?? GameQueue(id: nil, mode: .summonersRift, mapId: GameMode.Map.summonersRift)
    }

    /// Reloads builds when the mode or the statistics queue (Solo vs. Flex) changes while a champion
    /// is selected, so no builds of the previous queue are shown or auto-imported.
    func setQueue(_ newQueue: GameQueue?) {
        guard let newQueue, newQueue != queue else { return }
        let old = effectiveQueue
        queue = newQueue
        if Self.buildKey(newQueue) != Self.buildKey(old), let championId {
            builds = []
            augments = []
            Task { await loadBuilds(for: championId, session: session) }
        }
    }

    /// What decides which builds apply: the mode plus the statistics queue (Solo vs. Flex). Other
    /// queue changes (e.g. a richer name for the same queue) keep the loaded builds.
    static func buildKey(_ queue: GameQueue) -> String {
        "\(queue.mode.rawValue)-\(BuildQueue(queue: queue)?.rawValue ?? "none")"
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
        briefing = ChampSelectBriefing()
        actionState = .idle
    }

    func update(session: ChampSelectSession?) {
        self.session = session
        defer { updateBriefing() }
        let newChampion = session?.localChampionId
        if let queueId = session?.queueId, queueId > 0, queue?.id != queueId {
            // Fallback when the gameflow session was missed. A new champion loads with it anyway.
            if newChampion == championId {
                setQueue(GameQueue(queueId: queueId))
            } else {
                queue = GameQueue(queueId: queueId)
            }
        }
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
        let queue = effectiveQueue
        let role = await loader.resolveRole(session: session, championId: championId, mode: queue.mode, lcu: lcu)
        loadAugments(championId: championId, queue: queue)
        let loaded = await loader.load(
            champion: ChampionRef(id: championId, key: key),
            role: role,
            queue: queue,
            patch: staticData?.version,
            lcu: lcu
        )
        // Champion or queue (incl. Solo vs. Flex) changed meanwhile; the newer load owns the flag.
        guard championId == self.championId, Self.buildKey(queue) == Self.buildKey(effectiveQueue) else { return }
        self.role = role
        updateBriefing() // the matchup needs the resolved role
        builds = loaded
        isLoadingBuilds = false
        if plannedBuild?.championKey != key || plannedBuild?.queue != loaded.first?.queue {
            plannedBuild = loaded.first
        }
        prefetchIcons(for: loaded)
        autoImportIfNeeded()
    }

    /// Optional card, loaded independently so a slow OP.GG answer never delays builds or auto import.
    private func loadAugments(championId: Int, queue: GameQueue) {
        guard queue.mode == .aramMayhem else { return }
        Task { [augmentProvider] in
            do {
                let loaded = try await augmentProvider.augments(championId: championId, limit: 6)
                guard championId == self.championId, queue.mode == mode else { return }
                augments = loaded
            } catch {
                logger.notice("OP.GG augments unavailable: \(String(describing: error), privacy: .public)")
            }
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
