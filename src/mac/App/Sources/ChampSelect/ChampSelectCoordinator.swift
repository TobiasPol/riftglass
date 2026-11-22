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
    var role: Role?
    /// Manual lane selection overriding LCU / OP.GG default in champ select.
    var manualRole: Role?
    /// Lane the client assigned when the current builds were requested (nil in blind pick).
    @ObservationIgnored var assignedRole: Role?
    var builds: [BuildOption] = []
    /// ARAM: Mayhem only – the champion's augments per rarity, in OP.GG's tier order.
    var augmentBoard: AugmentBoard?
    /// Last loaded board for this game – survives `deactivate()` so the in-game overlay reuses it.
    @ObservationIgnored var lastAugmentBoard: AugmentBoard?
    var isLoadingBuilds = false
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
    @ObservationIgnored let dataDragon = DataDragon(locale: GameDataLocale.dataDragon)
    @ObservationIgnored let loader: BuildLoader
    /// Shared with the in-game overlay (one in-memory augment catalog).
    @ObservationIgnored let augmentLoader = AugmentBoardLoader()
    @ObservationIgnored let briefingSources = BriefingSources()
    /// OP.GG tier list with lane shares, loaded once per app run (the disk cache keeps it for 6 h).
    @ObservationIgnored var laneMeta: LaneMeta?
    /// When `laneMeta` was loaded – the app runs for days, the tier list changes with every patch.
    @ObservationIgnored var laneMetaLoadedAt: Date?
    /// Pending tier-list request, shared so concurrent updates send it only once.
    @ObservationIgnored var laneMetaTask: Task<LaneMeta?, Never>?
    /// Pick and ban options (`ChampSelectCoordinator+Draft`).
    var draft = DraftAdvice()
    /// The player's mastery points, read once per champ select; nil when the client did not answer.
    @ObservationIgnored var mastery: [Int: Int]?
    @ObservationIgnored var masteryTask: Task<[Int: Int]?, Never>?
    @ObservationIgnored let settings: AppSettings
    /// `gameId-championId` of the last automatic import, so it runs once per pick.
    @ObservationIgnored var autoImportedKey: String?
    @ObservationIgnored var activeImportToken: UUID?
    /// Tail of the import queue. Imports read and replace shared state (rune pages, the whole
    /// item-set document), so they run strictly one after another.
    @ObservationIgnored var importChain: Task<Void, Never>?
    @ObservationIgnored private(set) var lcu: LCUClient?
    @ObservationIgnored private(set) var actions: ChampSelectActions?
    @ObservationIgnored private var panel: ChampSelectPanel?
    @ObservationIgnored private var dock: ClientDockController?
    @ObservationIgnored var staticDataTask: Task<Void, Never>?
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
            augmentBoard = nil
            Task { await loadBuilds(for: championId, session: session) }
        }
        updateBriefing()
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
                updateBriefing()
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
        lastAugmentBoard = nil
        dock?.start(clientPID: clientPID)
    }

    /// Hides the panel. `plannedBuild` and `lastAugmentBoard` survive for the game.
    func deactivate() {
        dock?.stop()
        session = nil
        championId = nil
        role = nil
        manualRole = nil
        assignedRole = nil
        builds = []
        augmentBoard = nil
        isLoadingBuilds = false
        autoImportedKey = nil
        activeImportToken = nil
        briefing = ChampSelectBriefing()
        draft = DraftAdvice()
        mastery = nil
        masteryTask?.cancel()
        masteryTask = nil
        actionState = .idle
    }

    func update(session: ChampSelectSession?) {
        self.session = session
        defer { updateBriefing() }
        let newChampion = session?.localChampionId
        if let queueId = session?.queueId, queueId > 0, queue?.id != queueId {
            let detected = GameQueue(queueId: queueId)
            if settings.lastQueue?.id != queueId {
                settings.lastQueue = detected
            }
            // Fallback when the gameflow session was missed. A new champion loads with it anyway.
            if newChampion == championId {
                setQueue(detected)
            } else {
                queue = detected
            }
        }
        // A lane swap with a teammate keeps the champion but needs the other lane's build.
        let newRole = Role(lcuPosition: session?.localPosition)
        guard newChampion != championId || newRole != assignedRole else {
            autoImportIfNeeded() // lock-in of the hovered champion
            return
        }
        if newChampion != championId {
            augmentBoard = nil
        }
        if newRole != assignedRole {
            manualRole = nil
        }
        championId = newChampion
        assignedRole = newRole
        actionState = .idle
        builds = []
        if let newChampion {
            Task { await loadBuilds(for: newChampion, session: session) }
        } else {
            isLoadingBuilds = false
            role = nil
        }
    }
}
