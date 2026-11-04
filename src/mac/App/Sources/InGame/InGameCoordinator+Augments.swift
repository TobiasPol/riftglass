import AppKit
import LeagueKit
import OverlayKit

/// ARAM: Mayhem augment overlay: the champion's strong augments per rarity, shown at the top of the
/// screen while an augment choice is likely open. The offered cards are never read (no screen
/// capture); timing comes from the player's own level and death state (`AugmentPickTracker`).
extension InGameCoordinator {
    func resetAugments() {
        augmentTask?.cancel()
        augmentTask = nil
        augmentBoard = nil
        augmentTracker = AugmentPickTracker()
        hideAugments()
    }

    func updateAugmentOverlay(_ snapshot: LiveGameSnapshot) {
        guard queue?.mode == .aramMayhem, let active = snapshot.activePlayer, let me = snapshot.me else {
            return hideAugments()
        }
        loadAugmentBoardIfNeeded(championKey: me.championKey)
        // The tracker sees every snapshot, also while the overlay is off or another app is in front.
        let prompt = augmentTracker.update(
            level: active.level,
            isDead: me.isDead ?? false,
            gameTime: snapshot.stats.gameTime
        )
        showAugments(prompt)
    }

    /// Re-evaluates visibility without advancing the tracker (app switches).
    func refreshAugmentOverlay() {
        showAugments(augmentPrompt)
    }

    func hideAugments() {
        augmentPrompt = nil
        augmentPanel?.dismiss()
    }

    private func showAugments(_ prompt: AugmentPickPrompt?) {
        let gameInFront = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == LeagueBundleID.game
        guard settings.augmentOverlayEnabled, gameInFront, let prompt, let board = augmentBoard, !board.isEmpty
        else { return hideAugments() }
        guard prompt != augmentPrompt || augmentPanel?.isVisible != true else { return }
        augmentPrompt = prompt
        let view = AugmentOverlayView(board: board, prompt: prompt, icons: champSelect.icons)
        if let augmentPanel {
            augmentPanel.update(rootView: view)
        } else {
            augmentPanel = OverlayPanel(rootView: view)
        }
        augmentPanel?.present(on: gameScreen(), anchor: .top(28))
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
