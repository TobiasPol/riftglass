import AppKit
import LeagueKit
import OverlayKit
import StatsKit

/// Skill-point overlay: appears above the ability bar while a skill point is unspent and shows
/// which ability the recorded skill order levels next. Purely informational, no input is sent.
extension InGameCoordinator {
    func resetSkills() {
        skillOrderTask?.cancel()
        skillOrderTask = nil
        skillOrder = nil
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        hideSkills()
    }

    /// The pill sits on the shielding level, above every app, and Live Client snapshots stop while
    /// the game is paused or the API hiccups – so app switches are handled independently of polling.
    func observeActivation() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let isGame = app?.bundleIdentifier == LeagueBundleID.game
            MainActor.assumeIsolated {
                guard let self else { return }
                if isGame, let snapshot = self.snapshot {
                    self.updateSkillOverlay(snapshot)
                } else {
                    self.hideSkills()
                }
            }
        }
    }

    func updateSkillOverlay(_ snapshot: LiveGameSnapshot) {
        guard settings.skillOverlayEnabled, let active = snapshot.activePlayer, let me = snapshot.me,
              let order = resolveSkillOrder(for: me)
        else { return hideSkills() }
        let advice = SkillOrderAdvisor.advice(
            order: order,
            championLevel: active.level,
            ranks: active.abilityRanks,
            rules: SkillRules.forChampion(me.championKey)
        )
        // Shielding level floats above everything – only show it while the game is in front.
        let gameInFront = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == LeagueBundleID.game
        guard let advice, gameInFront else { return hideSkills() }
        guard advice != skillAdvice || skillPanel?.isVisible != true else { return }
        skillAdvice = advice
        let view = SkillOverlayView(advice: advice)
        if let skillPanel {
            skillPanel.update(rootView: view)
        } else {
            skillPanel = OverlayPanel(rootView: view)
        }
        skillPanel?.present(on: gameScreen(), anchor: .bottomFraction(0.2))
    }

    private func hideSkills() {
        skillAdvice = nil
        skillPanel?.dismiss()
    }

    /// The order from champ select if it matches champion and queue; otherwise fetched from OP.GG
    /// once (app started mid-game, champ select skipped). Nil while loading; empty = no data.
    private func resolveSkillOrder(for me: LivePlayer) -> [String]? {
        if let skillOrder {
            return skillOrder
        }
        // Builds persisted before v0.2 have no queue and are not trusted; they trigger a fetch.
        let buildQueue = queue.flatMap(BuildQueue.init(queue:))
        if let planned = champSelect.plannedBuild, planned.championKey == me.championKey,
           planned.queue != nil, planned.queue == buildQueue, !planned.skillOrder.isEmpty {
            skillOrder = planned.skillOrder
            return planned.skillOrder
        }
        guard skillOrderTask == nil, let queue else { return nil }
        let numericId = champSelect.staticData?.champion(key: me.championKey).flatMap { Int($0.key) }
        let champion = ChampionRef(id: numericId ?? 0, key: me.championKey)
        let role = Role(lcuPosition: me.position)
        skillOrderTask = Task { [weak self] in
            let order = await BuildLoader().skillOrder(champion: champion, role: role, queue: queue)
            guard !Task.isCancelled else { return }
            self?.skillOrder = order
        }
        return nil
    }
}
