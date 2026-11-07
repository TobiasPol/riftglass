import AppKit
import LeagueKit
import os
import OverlayKit

/// What ⌥A last did to the augment overlay (reset every game).
enum AugmentOverride: String, Equatable {
    /// Shown while a choice is likely open (`AugmentPickTracker`).
    case auto
    /// Hidden by the player for the rest of the game, until ⌥A again.
    case hidden
    /// Shown by the player without a pending choice, until ⌥A again.
    case pinned
}

/// ARAM: Mayhem augment overlay: the champion's strong augments per rarity, shown left of League's
/// selection cards while an augment choice is likely open. The offered cards are never read (no screen capture);
/// timing comes from the player's own level and death state (`AugmentPickTracker`). ⌥A toggles it.
extension InGameCoordinator {
    /// Left of the selection cards: on the live 21:9 screenshots they span ±0.49 × height around the
    /// middle, centred 42 % below the top edge. The top centre is no option – the cards start at 18 %.
    static let augmentAnchor = cardSide(.left)

    /// Beside League's selection cards (augments, stat anvils).
    static func cardSide(_ side: OverlaySide) -> OverlayPanel.Anchor {
        .besideCentre(side, clearHalfWidth: 0.5, gap: 24, centreY: 0.42)
    }

    static let augmentLog = Logger(subsystem: "de.polleydigital.riftglass", category: "Augments")

    func resetAugments() {
        augmentTask?.cancel()
        augmentTask = nil
        augmentBoard = nil
        augmentTracker = AugmentPickTracker()
        augmentPrompt = nil
        augmentOverride = .auto
        hideAugments()
    }

    func updateAugmentOverlay(_ snapshot: LiveGameSnapshot) {
        guard queue?.mode == .aramMayhem, let active = snapshot.activePlayer, let me = snapshot.me else {
            augmentPrompt = nil
            return hideAugments()
        }
        loadAugmentBoardIfNeeded(championKey: me.championKey)
        // The tracker sees every snapshot, also while the overlay is off or another app is in front.
        let prompt = augmentTracker.update(
            level: active.level,
            isDead: me.isDead ?? false,
            gameTime: snapshot.stats.gameTime
        )
        // ⌥A hides the list until the next choice – also one reached while the window stays open.
        if let prompt, augmentOverride == .hidden, prompt.available > augmentPrompt?.available ?? 0 {
            augmentOverride = .auto
        }
        if prompt != augmentPrompt {
            let time = Int(snapshot.stats.gameTime), dead = me.isDead ?? false
            Self.augmentLog.notice(
                "Prompt \(Self.describe(prompt), privacy: .public) at t=\(time)s level=\(active.level) dead=\(dead)"
            )
        }
        augmentPrompt = prompt
        refreshAugmentOverlay()
    }

    /// ⌥A: hides a visible overlay until the next choice, shows a hidden one (also without a pending
    /// choice) until ⌥A again.
    func toggleAugmentOverlay() {
        guard queue?.mode == .aramMayhem else { return }
        augmentOverride = augmentPanel?.isVisible == true ? .hidden : .pinned
        let state = augmentOverride.rawValue
        Self.augmentLog.notice("⌥A → \(state, privacy: .public)")
        refreshAugmentOverlay()
    }

    /// Shows or hides the panel for the current prompt without advancing the tracker (app switches,
    /// Tab); the prompt itself survives while the panel is hidden.
    func refreshAugmentOverlay() {
        let gameInFront = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == LeagueBundleID.game
        let wanted = switch augmentOverride {
        case .auto: augmentPrompt != nil
        case .hidden: false
        case .pinned: true
        }
        guard settings.augmentOverlayEnabled, wanted, gameInFront, !isTabHeld,
              let board = augmentBoard, !board.isEmpty
        else { return hideAugments() }
        let content = AugmentPanelContent(prompt: augmentPrompt, pinned: augmentOverride == .pinned)
        guard content != shownAugmentContent || augmentPanel?.isVisible != true else { return }
        shownAugmentContent = content
        let view = AugmentOverlayView(board: board, prompt: content.prompt, icons: champSelect.icons)
        if let augmentPanel {
            augmentPanel.update(rootView: view)
        } else {
            augmentPanel = OverlayPanel(rootView: view)
        }
        let screen = gameScreen()
        augmentPanel?.present(on: screen, anchor: Self.augmentAnchor)
        if let augmentPanel {
            let frame = NSStringFromRect(augmentPanel.frame), screenFrame = NSStringFromRect(screen?.frame ?? .zero)
            Self.augmentLog.notice("""
            Panel shown \(Self.describe(content.prompt), privacy: .public) \
            frame=\(frame, privacy: .public) screen=\(screenFrame, privacy: .public)
            """)
        }
        hideSkills() // the pill would sit on League's card tooltip
    }

    func hideAugments() {
        shownAugmentContent = nil
        guard augmentPanel?.isVisible == true else { return }
        augmentPanel?.dismiss()
        let state = augmentOverride.rawValue, tab = isTabHeld
        Self.augmentLog.notice("Panel hidden (override=\(state, privacy: .public), tab=\(tab))")
        if let snapshot {
            updateSkillOverlay(snapshot)
        }
    }

    private static func describe(_ prompt: AugmentPickPrompt?) -> String {
        prompt.map { "pick \($0.pick)/\($0.total) available=\($0.available)" } ?? "none"
    }

    /// Once per game. Needs Data Dragon for the numeric champion ID; retried on the next snapshot
    /// until static data is there.
    private func loadAugmentBoardIfNeeded(championKey: String) {
        guard augmentBoard == nil, augmentTask == nil,
              let championId = champSelect.staticData?.champion(key: championKey).flatMap({ Int($0.key) })
        else { return }
        if let board = champSelect.augmentBoard, board.championId == championId {
            Self.augmentLog.notice("Board from champ select: \(board.columns.map(\.entries.count), privacy: .public)")
            augmentBoard = board
            return
        }
        augmentTask = Task { [weak self, loader = champSelect.augmentLoader] in
            let board: AugmentBoard?
            do {
                board = try await loader.board(championId: championId)
            } catch {
                Self.augmentLog.error("Board load failed: \(String(describing: error), privacy: .public)")
                board = nil
            }
            if let board {
                Self.augmentLog
                    .notice("Board loaded for \(championId): \(board.columns.map(\.entries.count), privacy: .public)")
            } else {
                try? await Task.sleep(for: .seconds(30)) // OP.GG failed: retry later, not every second
            }
            guard !Task.isCancelled, let self else { return }
            augmentBoard = board
            if let board {
                champSelect.icons.prefetch(board.iconURLs)
                refreshAugmentOverlay()
            } else {
                augmentTask = nil
            }
        }
    }
}

/// What the augment panel shows; the panel is only rebuilt when this changes.
struct AugmentPanelContent: Equatable {
    let prompt: AugmentPickPrompt?
    let pinned: Bool
}
