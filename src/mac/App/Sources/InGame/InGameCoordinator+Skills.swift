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
                if isGame {
                    if let snapshot = self.snapshot {
                        self.updateSkillOverlay(snapshot)
                    }
                    self.refreshAugmentOverlay()
                } else {
                    self.dismissGameOverlaysOnDeactivate()
                }
            }
        }
    }

    func updateSkillOverlay(_ snapshot: LiveGameSnapshot) {
        guard settings.skillOverlayEnabled, augmentPanel?.isVisible != true, let active = snapshot.activePlayer,
              let me = snapshot.me,
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

    func hideSkills() {
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
        if let planned = champSelect.plannedBuild,
           planned.championKey?.caseInsensitiveCompare(me.championKey) == .orderedSame,
           planned.queue != nil, planned.queue == buildQueue, !planned.skillOrder.isEmpty {
            skillOrder = planned.skillOrder
            return planned.skillOrder
        }
        if skillOrderTask == nil, let queue {
            loadSkillOrder(for: me, queue: queue)
        }
        return nil
    }

    /// One request per game – unless OP.GG cannot be reached: then it is repeated every 30 s instead of
    /// leaving the game without hints. Without a lane from the Live Client (`NONE` in blind pick and
    /// custom games) the champion's main lane on OP.GG decides, as in champ select.
    private func loadSkillOrder(for me: LivePlayer, queue: GameQueue) {
        let data = champSelect.staticData?.champion(key: me.championKey)
        let champion = ChampionRef(id: data.flatMap { Int($0.key) } ?? 0, key: me.championKey)
        let name = data?.name ?? me.championName
        let needsRates = queue.mode.hasLanes && Role(lcuPosition: me.position) == nil
        skillOrderTask = Task { [weak self, champSelect] in
            let role = await BuildLoader.resolveRole(
                assigned: me.position,
                championName: name,
                mode: queue.mode,
                rates: needsRates ? champSelect.loadRoleRates() : nil
            )
            let order = await BuildLoader().skillOrder(champion: champion, role: role, queue: queue)
            if order == nil {
                try? await Task.sleep(for: .seconds(30))
            }
            guard !Task.isCancelled, let self else { return }
            if let order {
                skillOrder = order
                if let snapshot {
                    updateSkillOverlay(snapshot)
                }
            } else {
                skillOrderTask = nil
            }
        }
    }

    /// Item plan of the build from champ select – nil when that build is for another champion or mode.
    func itemPlan(for player: LivePlayer) -> ItemPlan? {
        let buildQueue = queue.flatMap(BuildQueue.init(queue:))
        guard let build = champSelect.plannedBuild,
              build.championKey?.caseInsensitiveCompare(player.championKey) == .orderedSame,
              build.queue != nil, build.queue == buildQueue
        else { return nil }
        let plan = ItemPlan(required: build.requiredItemIds, alternatives: build.alternativeItemIds)
        return plan.isEmpty ? nil : plan
    }
}
