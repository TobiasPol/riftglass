import DataKit
import Foundation
import LeagueKit
import StatsKit

/// What the briefing cards show. Keys remember what was loaded, so the many identical WAMP
/// session updates cause no work and late answers for an old pick are dropped.
struct ChampSelectBriefing {
    var ally = TeamProfile(champions: [])
    var enemy = TeamProfile(champions: [])
    var hints: [CompHint] = []
    /// Guessed (or revealed) enemy lanes.
    var lanes: [Role: LaneAssigner.Assignment] = [:]
    /// Enemy in the local player's lane.
    var opponent: LaneAssigner.Assignment?
    var matchup: MatchupBrief?

    var teamsKey: String?
    var matchupKey: String?
}

/// OP.GG sources of the briefing.
struct BriefingSources {
    let laneMeta = OPGGLaneMetaProvider()
    let matchups = OPGGMatchupProvider(language: GameDataLocale.dataDragon)
    let counters = OPGGCounterProvider()
    let synergies = OPGGSynergyProvider()
}

extension ChampSelectCoordinator {
    /// Own role: manual override first, else what the client assigns, else resolved with builds.
    var briefingRole: Role? {
        manualRole ?? Role(lcuPosition: session?.localPosition) ?? role
    }

    /// Recomputes the briefing when the visible champions, their revealed positions, the own role,
    /// the pick turn or the lock state change. Turning the briefing off drops everything, so pending
    /// answers are discarded and turning it on again starts fresh.
    func updateBriefing() {
        updateDraft()
        guard settings.briefingEnabled else {
            if briefing.teamsKey != nil {
                briefing = ChampSelectBriefing()
            }
            return
        }
        guard let session, let data = staticData else { return }
        let enemies = session.enemyPicks
        let key = [
            "\(session.allyChampionIds)",
            enemies.map { "\($0.championId):\($0.position ?? "-")" }.joined(separator: ","),
            "\(championId ?? 0)", briefingRole?.rawValue ?? "-", mode.rawValue
        ].joined(separator: "|")
        guard key != briefing.teamsKey else { return }
        briefing.teamsKey = key
        briefing.ally = TeamProfile(champions: session.allyChampionIds.compactMap { data.champion($0) })
        briefing.enemy = TeamProfile(champions: enemies.compactMap { data.champion($0.championId) })
        briefing.hints = CompHint.hints(ally: briefing.ally, enemy: briefing.enemy)
        // Lanes and matchups only exist on Summoner's Rift with OP.GG lane statistics.
        guard mode == .summonersRift, !enemies.isEmpty else {
            briefing.lanes = [:]
            briefing.opponent = nil
            loadMatchup()
            return
        }
        Task { await assignLanes(enemies, key: key) }
    }

    private func assignLanes(_ enemies: [ChampSelectSession.EnemyPick], key: String) async {
        let rates = await loadRoleRates()
        // Opted out while waiting (the key was reset) or a newer session took over.
        guard settings.briefingEnabled, key == briefing.teamsKey else { return }
        briefing.lanes = enemyLanes(enemies, rates: rates)
        briefing.opponent = briefingRole.flatMap { briefing.lanes[$0] }
        loadMatchup()
    }

    /// Revealed positions as they are, the rest guessed from OP.GG lane shares.
    func enemyLanes(_ enemies: [ChampSelectSession.EnemyPick], rates: RoleRates) -> [Role: LaneAssigner.Assignment] {
        guard let data = staticData else { return [:] }
        let picks = enemies.compactMap { pick -> LaneAssigner.Pick? in
            guard let champion = data.champion(pick.championId) else { return nil }
            return .init(championId: pick.championId, name: champion.name, fixed: Role(lcuPosition: pick.position))
        }
        return LaneAssigner.assign(picks, rates: rates)
    }

    /// Without OP.GG only positions the client revealed are known.
    func loadRoleRates() async -> RoleRates {
        await loadLaneMeta()?.roleRates ?? RoleRates(rates: [:])
    }

    /// OP.GG's tier list. Concurrent callers share one request; a failure clears it, so the next
    /// update retries, and keeps an older list.
    func loadLaneMeta() async -> LaneMeta? {
        if let laneMeta, let loadedAt = laneMetaLoadedAt, Date().timeIntervalSince(loadedAt) < 6 * 3600 {
            return laneMeta
        }
        let task = laneMetaTask ?? Task { [briefingSources, logger] () -> LaneMeta? in
            do {
                return try await briefingSources.laneMeta.laneMeta()
            } catch {
                logger.notice("OP.GG lane meta unavailable: \(String(describing: error), privacy: .public)")
                return nil
            }
        }
        laneMetaTask = task
        let meta = await task.value
        if laneMetaTask == task {
            laneMetaTask = nil
        }
        if let meta, !meta.isEmpty {
            laneMeta = meta
            laneMetaLoadedAt = Date()
        }
        return laneMeta
    }

    func championRef(_ id: Int?) -> ChampionRef? {
        guard let id, let champion = staticData?.champion(id) else { return nil }
        return ChampionRef(id: id, key: champion.id)
    }

    /// Matchup of the locked or hovered own champion against the lane opponent.
    private func loadMatchup() {
        guard let role = briefingRole, let mine = championRef(championId),
              let theirs = championRef(briefing.opponent?.championId)
        else {
            briefing.matchup = nil
            briefing.matchupKey = nil
            return
        }
        let buildQueue = BuildQueue(queue: effectiveQueue) ?? .ranked
        let key = "\(mine.id)-\(theirs.id)-\(role.rawValue)-\(buildQueue.rawValue)"
        guard key != briefing.matchupKey else { return }
        briefing.matchupKey = key
        briefing.matchup = nil
        Task { [briefingSources] in
            do {
                let brief = try await briefingSources.matchups.matchup(
                    my: mine,
                    against: theirs,
                    role: role,
                    queue: buildQueue
                )
                guard key == briefing.matchupKey else { return }
                briefing.matchup = brief
                if let build = brief.build {
                    prefetchIcons(for: [build])
                }
            } catch {
                logger.notice("OP.GG matchup unavailable: \(String(describing: error), privacy: .public)")
            }
        }
    }
}
