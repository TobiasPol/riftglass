import AppKit
import LeagueKit
import OverlayKit

/// ARAM: Mayhem augment overlay: the champion's strong augments per rarity, shown at the top of the
/// screen while an augment choice is likely open. The offered cards are never read (no screen
/// capture); timing comes from the player's own level and death state (`AugmentPickTracker`).
extension InGameCoordinator {
    static let augmentTopInset: CGFloat = 28

    func resetAugments() {
        augmentTask?.cancel()
        augmentTask = nil
        augmentBoard = nil
        augmentTracker = AugmentPickTracker()
        augmentPrompt = nil
        hideAugments()
    }

    func updateAugmentOverlay(_ snapshot: LiveGameSnapshot) {
        guard queue?.mode == .aramMayhem, let active = snapshot.activePlayer, let me = snapshot.me else {
            augmentPrompt = nil
            return hideAugments()
        }
        loadAugmentBoardIfNeeded(championKey: me.championKey)
        // The tracker sees every snapshot, also while the overlay is off or another app is in front.
        augmentPrompt = augmentTracker.update(
            level: active.level,
            isDead: me.isDead ?? false,
            gameTime: snapshot.stats.gameTime
        )
        refreshAugmentOverlay()
    }

    /// Shows or hides the panel for the current prompt without advancing the tracker (app switches,
    /// Tab); the prompt itself survives while the panel is hidden.
    func refreshAugmentOverlay() {
        let gameInFront = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == LeagueBundleID.game
        guard settings.augmentOverlayEnabled, gameInFront, !isTabHeld, let prompt = augmentPrompt,
              let board = augmentBoard, !board.isEmpty
        else { return hideAugments() }
        guard prompt != shownAugmentPrompt || augmentPanel?.isVisible != true else { return }
        shownAugmentPrompt = prompt
        let view = AugmentOverlayView(board: board, prompt: prompt, icons: champSelect.icons)
        if let augmentPanel {
            augmentPanel.update(rootView: view)
        } else {
            augmentPanel = OverlayPanel(rootView: view)
        }
        augmentPanel?.present(on: gameScreen(), anchor: .top(Self.augmentTopInset))
        repositionBanner()
    }

    func hideAugments() {
        shownAugmentPrompt = nil
        guard augmentPanel?.isVisible == true else { return }
        augmentPanel?.dismiss()
        repositionBanner()
    }

    /// Once per game. Needs Data Dragon for the numeric champion ID; retried on the next snapshot
    /// until static data is there.
    private func loadAugmentBoardIfNeeded(championKey: String) {
        guard augmentBoard == nil, augmentTask == nil,
              let championId = champSelect.staticData?.champion(key: championKey).flatMap({ Int($0.key) })
        else { return }
        if let board = champSelect.augmentBoard, board.championId == championId {
            augmentBoard = board
            return
        }
        augmentTask = Task { [weak self, loader = champSelect.augmentLoader] in
            let board = try? await loader.board(championId: championId)
            if board == nil {
                try? await Task.sleep(for: .seconds(30)) // OP.GG failed: retry later, not every second
            }
            guard !Task.isCancelled, let self else { return }
            augmentBoard = board
            if let board {
                champSelect.icons.prefetch(board.iconURLs)
            } else {
                augmentTask = nil
            }
        }
    }
}
