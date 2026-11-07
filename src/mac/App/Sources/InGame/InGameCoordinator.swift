import AppKit
import LeagueKit
import Observation
import os
import OverlayKit
import StatsKit
import SwiftUI

/// Everything that runs while the game process is alive: Live Client polling (1 Hz), the Tab
/// hotkey, the click-through overlays and the rank lookup. Nothing of this runs outside a game.
@MainActor
@Observable
final class InGameCoordinator {
    private(set) var snapshot: LiveGameSnapshot?
    private(set) var ranks: [String: PlayerRank] = [:]
    private(set) var isTabHeld = false
    private(set) var lastGame: GameSummary?
    /// Detected mode of the running game (lobby queue if plausible, else Live Client).
    private(set) var queue: GameQueue?

    @ObservationIgnored let champSelect: ChampSelectCoordinator
    @ObservationIgnored let settings: AppSettings
    @ObservationIgnored private let rankLookup = RankLookup()
    @ObservationIgnored private var liveClient: LiveClient?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var hotkey: HotkeyMonitor?
    @ObservationIgnored private var tabPanel: OverlayPanel?
    @ObservationIgnored private var bannerPanel: OverlayPanel?
    @ObservationIgnored private var bannerShown = false
    @ObservationIgnored private var rememberedQueue: GameQueue?
    /// What the skill-point overlay currently shows (nil = hidden).
    @ObservationIgnored var skillAdvice: SkillAdvice?
    @ObservationIgnored var skillPanel: OverlayPanel?
    /// Skill order for the current champion; nil until resolved (champ select or OP.GG).
    @ObservationIgnored var skillOrder: [String]?
    @ObservationIgnored var skillOrderTask: Task<Void, Never>?
    /// ARAM: Mayhem augment list for the player's champion (`InGameCoordinator+Augments`).
    var augmentBoard: AugmentBoard?
    @ObservationIgnored var augmentTracker = AugmentPickTracker()
    /// The tracker's current prompt, kept while the panel is hidden (app switch, Tab held).
    @ObservationIgnored var augmentPrompt: AugmentPickPrompt?
    /// What the augment panel currently shows (nil = hidden).
    @ObservationIgnored var shownAugmentContent: AugmentPanelContent?
    /// ⌥A state for the augment overlay, reset every game.
    @ObservationIgnored var augmentOverride = AugmentOverride.auto
    @ObservationIgnored var augmentPanel: OverlayPanel?
    @ObservationIgnored var augmentTask: Task<Void, Never>?
    /// Hides the skill pill the moment another app comes to the front (snapshots may pause).
    @ObservationIgnored var activationObserver: (any NSObjectProtocol)?
    @ObservationIgnored private let logger = Logger(subsystem: "de.polleydigital.riftglass", category: "InGame")

    init(champSelect: ChampSelectCoordinator, settings: AppSettings) {
        self.champSelect = champSelect
        self.settings = settings
    }

    var isRunning: Bool {
        pollTask != nil
    }

    func start(evaluator: LocalTrustEvaluator, rememberedQueue: GameQueue?) {
        guard pollTask == nil else { return }
        logger.info("Game detected – starting Live Client polling")
        snapshot = nil
        queue = nil
        self.rememberedQueue = rememberedQueue
        resetSkills()
        resetAugments()
        ranks = [:]
        rankLookup.reset()
        bannerShown = false
        let client = LiveClient(evaluator: evaluator)
        liveClient = client
        pollTask = Task { [weak self] in
            for await snapshot in await client.snapshots() {
                self?.handle(snapshot)
            }
        }
        startHotkey()
        observeActivation()
    }

    func stop() {
        guard pollTask != nil else { return }
        let planned = champSelect.plannedBuild?.allItemIds ?? []
        if let snapshot, let summary = GameSummary(snapshot: snapshot, plannedItems: planned) {
            lastGame = summary
        }
        pollTask?.cancel()
        pollTask = nil
        let client = liveClient
        liveClient = nil
        Task { await client?.stop() }
        hotkey?.stop()
        hotkey = nil
        tabPanel?.dismiss()
        bannerPanel?.dismiss()
        resetSkills()
        resetAugments()
        isTabHeld = false
        snapshot = nil
        logger.info("Game ended")
    }

    // MARK: - Snapshots

    private func handle(_ snapshot: LiveGameSnapshot) {
        if self.snapshot == nil {
            let region = settings.region ?? "nil"
            logger.notice("""
            First snapshot: \(snapshot.players.count) players, me=\(snapshot.me != nil), \
            region=\(region, privacy: .public), mode=\(snapshot.stats.gameMode ?? "nil", privacy: .public), \
            map=\(snapshot.stats.mapNumber ?? -1)
            """)
            queue = GameQueue.resolvedInGame(
                remembered: rememberedQueue,
                liveGameMode: snapshot.stats.gameMode,
                mapNumber: snapshot.stats.mapNumber
            )
            let resolved = String(describing: queue)
            logger.notice("Queue resolved: \(resolved, privacy: .public)")
        }
        self.snapshot = snapshot
        logTick(snapshot)
        updateSkillOverlay(snapshot)
        updateAugmentOverlay(snapshot)
        if settings.ranksEnabled, let region = settings.region {
            rankLookup.lookUp(snapshot.players, region: region) { [weak self] key, rank in
                self?.ranks[key] = rank
            }
        }
        // Game time stays 0 on the loading screen (98 s live) – the banner would expire unseen.
        if !bannerShown, settings.ranksEnabled, snapshot.players.count > 1, snapshot.stats.gameTime > 0 {
            bannerShown = true
            showBanner()
        }
        if isTabHeld {
            tabPanel?.present(on: gameScreen())
        }
    }

    /// Debug trace, one line per snapshot (`info` is not persisted; `log stream --level info`).
    private func logTick(_ snapshot: LiveGameSnapshot) {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == LeagueBundleID.game
        let tab = isTabHeld, aug = augmentPanel?.isVisible ?? false, skill = skillPanel?.isVisible ?? false
        logger.info("""
        tick t=\(Int(snapshot.stats.gameTime)) mode=\(snapshot.stats.gameMode ?? "nil", privacy: .public) \
        lvl=\(snapshot.activePlayer?.level ?? -1) dead=\(snapshot.me?.isDead ?? false) front=\(front) \
        tab=\(tab) augPanel=\(aug) skillPanel=\(skill)
        """)
    }

    // MARK: - Overlays

    /// Tab (held overlay) and ⌥A (augment toggle) share one listen-only tap.
    private func startHotkey() {
        guard HotkeyMonitor.hasPermission else {
            logger.notice("Hotkeys off – Input Monitoring not granted")
            return
        }
        let monitor = HotkeyMonitor()
        monitor.isActive = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier == LeagueBundleID.game }
        monitor.onTabChange = { [weak self] down in
            guard let self, settings.tabOverlayEnabled || !down else { return }
            setTabHeld(down)
        }
        monitor.onToggle = { [weak self] in self?.toggleAugmentOverlay() }
        if monitor.start() {
            hotkey = monitor
        }
        logger.notice("Hotkeys started: \(monitor.isRunning)")
    }

    private func setTabHeld(_ held: Bool) {
        isTabHeld = held
        refreshAugmentOverlay() // the Tab panel lists the augments itself and would overlap
        guard held, snapshot != nil else {
            tabPanel?.dismiss()
            return
        }
        if tabPanel == nil {
            tabPanel = OverlayPanel(rootView: TabOverlayView(coordinator: self))
        }
        tabPanel?.present(on: gameScreen())
    }

    /// Mayhem opens the augment cards at match start and announces the mode at the top centre, so the
    /// banner goes right of the cards there (the augment list is on the left).
    private var bannerAnchor: OverlayPanel.Anchor {
        queue?.mode == .aramMayhem ? Self.cardSide(.right) : .top(120)
    }

    /// Shows the ranks of all players for a few seconds at the start of the game.
    private func showBanner() {
        if bannerPanel == nil {
            bannerPanel = OverlayPanel(rootView: RanksBannerView(coordinator: self))
        }
        bannerPanel?.present(on: gameScreen(), anchor: bannerAnchor)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            self?.bannerPanel?.dismiss()
        }
    }

    /// Screen of the game window (largest window of the game process), else the primary screen.
    func gameScreen() -> NSScreen? {
        guard let game = NSRunningApplication.runningApplications(withBundleIdentifier: LeagueBundleID.game).first
        else { return NSScreen.screens.first }
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let bounds = info.first { ($0[kCGWindowOwnerPID as String] as? Int) == Int(game.processIdentifier) }
            .flatMap {
                ($0[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0) }
            }
        guard let bounds, let primary = NSScreen.screens.first else { return NSScreen.screens.first }
        let rect = DockGeometry.appKitRect(fromCG: bounds, primaryScreenHeight: primary.frame.height)
        return NSScreen.screens.first { $0.frame.intersects(rect) } ?? primary
    }
}
