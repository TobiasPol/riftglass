import Foundation
import LeagueKit
import StatsKit

extension ChampSelectCoordinator {
    var displayedBuilds: [BuildOption] {
        guard let championId, let champion = staticData?.champion(championId),
              let matchupBuild = briefing.matchup?.build,
              matchupBuild.championKey == champion.id,
              matchupBuild.role == (manualRole ?? role)
        else { return builds }
        let sameCore = builds.contains { existing in
            existing.runes == matchupBuild.runes
                && existing.itemBlocks == matchupBuild.itemBlocks
                && existing.summonerSpells == matchupBuild.summonerSpells
        }
        return sameCore ? builds : builds + [matchupBuild]
    }

    func selectRole(_ newRole: Role) {
        guard mode.hasLanes, newRole != (manualRole ?? role) else { return }
        manualRole = newRole
        role = newRole
        actionState = .idle
        updateBriefing()
        guard let championId else { return }
        builds = []
        Task { await loadBuilds(for: championId, session: session) }
    }

    func loadBuilds(for championId: Int, session: ChampSelectSession?) async {
        isLoadingBuilds = true
        await staticDataTask?.value
        guard championId == self.championId else { return }
        guard let champion = staticData?.champion(championId) else {
            logger.error("Unknown champion \(championId)")
            isLoadingBuilds = false
            return
        }
        let key = champion.id, queue = effectiveQueue, chosenManualRole = manualRole
        loadAugments(championId: championId, queue: queue)
        let assigned = session?.localPosition
        let role = await resolvedLoadRole(
            assigned: assigned,
            manual: chosenManualRole,
            championName: champion.name,
            mode: queue.mode
        )
        let loaded = await loader.load(
            champion: ChampionRef(id: championId, key: key),
            role: role,
            queue: queue,
            patch: staticData?.version
        )
        guard championId == self.championId, Role(lcuPosition: assigned) == assignedRole,
              chosenManualRole == manualRole, Self.buildKey(queue) == Self.buildKey(effectiveQueue)
        else { return }
        applyLoadedBuilds(loaded, championKey: key, role: role)
    }

    private func resolvedLoadRole(
        assigned: String?,
        manual: Role?,
        championName: String,
        mode: GameMode
    ) async -> Role? {
        if mode.hasLanes, let manual {
            return manual
        }
        let needsRates = mode.hasLanes && Role(lcuPosition: assigned) == nil
        let rates = needsRates ? await loadRoleRates() : nil
        return BuildLoader.resolveRole(assigned: assigned, championName: championName, mode: mode, rates: rates)
    }

    private func applyLoadedBuilds(_ loaded: [BuildOption], championKey key: String, role: Role?) {
        self.role = role
        updateBriefing() // the matchup needs the resolved role
        builds = loaded
        isLoadingBuilds = false
        // The remembered build follows champion, queue and lane (a swap keeps the first two).
        if plannedBuild?.championKey != key || plannedBuild?.queue != loaded.first?.queue
            || plannedBuild?.role != loaded.first?.role {
            plannedBuild = loaded.first
        }
        prefetchIcons(for: loaded)
        autoImportIfNeeded()
    }

    func applyAugmentBoard(_ board: AugmentBoard) {
        augmentBoard = board
        lastAugmentBoard = board
    }
}
