import AppKit
import DataKit
import LeagueKit
import OverlayKit
import StatsKit

/// Shows sample in-game overlays on demand in Settings so positioning and appearance can be checked
/// out of game. Automatically dismisses after 5 seconds or when a real game begins.
@MainActor
final class OverlayPreviewController {
    private var skillPanel: OverlayPanel?
    private var augmentPanel: OverlayPanel?
    private var dismissTask: Task<Void, Never>?

    var isShowing: Bool {
        skillPanel?.isVisible == true || augmentPanel?.isVisible == true
    }

    func toggle(settings: AppSettings, icons: IconCache) {
        if isShowing {
            dismiss()
            return
        }
        let screen = NSScreen.main
        let skillView = SkillOverlayView(advice: SkillAdvice(next: .q, then: [.w, .e], unspentPoints: 1))
        let skill = skillPanel ?? OverlayPanel(rootView: skillView)
        skill.update(rootView: skillView)
        skillPanel = skill
        skill.present(on: screen, anchor: .bottomFraction(settings.skillOverlayOffset))

        let augmentView = AugmentOverlayView(
            board: Self.sampleBoard,
            prompt: AugmentPickPrompt(pick: 1, available: 1, total: 4),
            icons: icons,
            shortcutLabel: settings.toggleShortcutLabel
        )
        let augment = augmentPanel ?? OverlayPanel(rootView: augmentView)
        augment.update(rootView: augmentView)
        augmentPanel = augment
        augment.present(on: screen, anchor: InGameCoordinator.augmentAnchor)

        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func updateSkillOffset(_ offset: Double) {
        guard isShowing else { return }
        skillPanel?.present(on: NSScreen.main, anchor: .bottomFraction(offset))
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        skillPanel?.dismiss()
        augmentPanel?.dismiss()
    }

    private static let sampleBoard = AugmentBoard(
        championId: 0,
        columns: [
            AugmentBoard.Column(
                rarity: .prismatic,
                entries: [
                    AugmentBoard.Entry(
                        stat: AugmentStat(
                            id: 1,
                            name: "Jewelled Gauntlet",
                            tier: 0,
                            popularity: 0.25,
                            rarity: .prismatic,
                            iconURL: nil
                        ),
                        name: "Jewelled Gauntlet",
                        iconURL: nil
                    )
                ]
            ),
            AugmentBoard.Column(
                rarity: .gold,
                entries: [
                    AugmentBoard.Entry(
                        stat: AugmentStat(
                            id: 2,
                            name: "Witchful Thinking",
                            tier: 1,
                            popularity: 0.20,
                            rarity: .gold,
                            iconURL: nil
                        ),
                        name: "Witchful Thinking",
                        iconURL: nil
                    )
                ]
            ),
            AugmentBoard.Column(
                rarity: .silver,
                entries: [
                    AugmentBoard.Entry(
                        stat: AugmentStat(
                            id: 3,
                            name: "Mind to Matter",
                            tier: 1,
                            popularity: 0.15,
                            rarity: .silver,
                            iconURL: nil
                        ),
                        name: "Mind to Matter",
                        iconURL: nil
                    )
                ]
            )
        ]
    )
}

extension InGameCoordinator {
    func updateHotkeySettings() {
        hotkey?.toggleKeyCode = settings.augmentToggleKeyCode
        refreshAugmentOverlay()
    }

    func previewOverlays() {
        guard !isRunning else {
            preview.dismiss()
            return
        }
        preview.toggle(settings: settings, icons: champSelect.icons)
    }

    func updatePreviewOffset() {
        guard !isRunning else { return }
        preview.updateSkillOffset(settings.skillOverlayOffset)
    }

    func queryRanksIfNeeded(for snapshot: LiveGameSnapshot) {
        let currentRegion = settings.effectiveRegion
        if currentRegion != rankRegion {
            rankRegion = currentRegion
            ranks = [:]
            rankLookup.reset()
        }
        guard isRunning, settings.ranksEnabled, let region = currentRegion else { return }
        rankLookup.lookUp(
            snapshot.players,
            region: region,
            preferredQueue: queue?.isFlex == true ? .flex : .solo
        ) { [weak self] key, rank in
            self?.ranks[key] = rank
        }
    }

    func refreshRanksForCurrentRegion() {
        guard settings.effectiveRegion != rankRegion else { return }
        rankRegion = settings.effectiveRegion
        ranks = [:]
        rankLookup.reset()
        if let snapshot {
            queryRanksIfNeeded(for: snapshot)
        }
    }

    func applyEndOfGameStats(_ stats: EndOfGameStats) {
        if let gameId = stats.gameId,
           let existing = settings.recentGames.first(where: { $0.gameId == gameId }) {
            guard existing.won == nil else { return }
            let enriched = existing.enriched(with: stats)
            if lastGame?.id == existing.id {
                lastGame = enriched
            }
            settings.updateLatestGame(enriched)
            return
        }
        let championName = stats.championId.flatMap { champSelect.staticData?.champion($0)?.name }
            ?? lastGame?.championName
            ?? String(localized: "Unknown")
        if let latest = lastGame, latest.gameId == nil, latest.won == nil,
           Date().timeIntervalSince(latest.playedAt) < 600 {
            let enriched = latest.enriched(with: stats)
            lastGame = enriched
            settings.updateLatestGame(enriched)
        } else if let summary = GameSummary(endOfGame: stats, championName: championName) {
            lastGame = summary
            settings.recordGame(summary)
        }
    }

    /// Screen of the game window (largest window of the game process), else the primary screen.
    func gameScreen() -> NSScreen? {
        let screens = NSScreen.screens
        guard let game = NSRunningApplication.runningApplications(withBundleIdentifier: LeagueBundleID.game).first,
              let primary = screens.first
        else { return screens.first }
        let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let windows = raw.compactMap(WindowInfo.init(dictionary:))
        guard let window = DockGeometry.largestWindow(in: windows, pid: game.processIdentifier) else {
            return primary
        }
        let rect = DockGeometry.appKitRect(fromCG: window.bounds, primaryScreenHeight: primary.frame.height)
        let index = DockGeometry.bestScreenIndex(for: rect, in: screens.map(\.frame)) ?? 0
        return screens[index]
    }
}
