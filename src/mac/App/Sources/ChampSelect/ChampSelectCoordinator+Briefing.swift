import DataKit
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
    var counterPicks: [CounterPick] = []
    /// Nil when the client did not answer; then no counter is dimmed.
    var pickableIds: Set<Int>?

    var teamsKey: String?
    var matchupKey: String?
    var countersKey: String?
}

/// OP.GG sources of the briefing.
struct BriefingSources {
    let laneMeta = OPGGLaneMetaProvider()
    let matchups = OPGGMatchupProvider()
    let counters = OPGGCounterProvider()
}

extension ChampSelectCoordinator {
    /// Own role: resolved with the builds, else what the client assigned.
    var briefingRole: Role? {
        role ?? Role(lcuPosition: session?.localPosition)
    }

    /// Recomputes the briefing when the visible champions, the own role or the pick turn change.
    func updateBriefing() {
        guard settings.briefingEnabled, let session, let data = staticData else { return }
        let enemies = session.enemyPicks
        let key = [
            "\(session.allyChampionIds)", "\(enemies.map(\.championId))", "\(championId ?? 0)",
            briefingRole?.rawValue ?? "-", "\(session.isLocalPickInProgress)", mode.rawValue
        ].joined(separator: "|")
        guard key != briefing.teamsKey else { return }
        briefing.teamsKey = key
        briefing.ally = TeamProfile(champions: session.allyChampionIds.compactMap { data.champion($0) })
        briefing.enemy = TeamProfile(champions: enemies.compactMap { data.champion($0.championId) })
        briefing.hints = CompHint.hints(ally: briefing.ally, enemy: briefing.enemy)
        // Lanes, matchups and counters only exist on Summoner's Rift with OP.GG lane statistics.
        guard mode == .summonersRift, !enemies.isEmpty else {
            briefing.lanes = [:]
            briefing.opponent = nil
            loadMatchup()
            loadCounters(isPicking: false)
            return
        }
        Task { await assignLanes(enemies, key: key, isPicking: session.isLocalPickInProgress) }
    }

    private func assignLanes(_ enemies: [ChampSelectSession.EnemyPick], key: String, isPicking: Bool) async {
        let rates = await loadRoleRates()
        guard key == briefing.teamsKey, let data = staticData else { return }
        let picks = enemies.compactMap { pick -> LaneAssigner.Pick? in
            guard let champion = data.champion(pick.championId) else { return nil }
            return .init(championId: pick.championId, name: champion.name, fixed: Role(lcuPosition: pick.position))
        }
        briefing.lanes = LaneAssigner.assign(picks, rates: rates)
        briefing.opponent = briefingRole.flatMap { briefing.lanes[$0] }
        loadMatchup()
        loadCounters(isPicking: isPicking)
    }

    /// Without OP.GG only positions the client revealed are known.
    private func loadRoleRates() async -> RoleRates {
        if let roleRates {
            return roleRates
        }
        do {
            let rates = try await briefingSources.laneMeta.roleRates()
            roleRates = rates
            return rates
        } catch {
            logger.notice("OP.GG lane meta unavailable: \(String(describing: error), privacy: .public)")
            return RoleRates(rates: [:])
        }
    }

    private func championRef(_ id: Int?) -> ChampionRef? {
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
        let key = "\(mine.id)-\(theirs.id)-\(role.rawValue)"
        guard key != briefing.matchupKey else { return }
        briefing.matchupKey = key
        briefing.matchup = nil
        Task { [briefingSources] in
            do {
                let brief = try await briefingSources.matchups.matchup(my: mine, against: theirs, role: role)
                guard key == briefing.matchupKey else { return }
                briefing.matchup = brief
            } catch {
                logger.notice("OP.GG matchup unavailable: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Counter picks against the lane opponent – only during the player's own pick turn.
    private func loadCounters(isPicking: Bool) {
        guard isPicking, let role = briefingRole, let theirs = championRef(briefing.opponent?.championId),
              let queue = BuildQueue(queue: effectiveQueue)
        else {
            briefing.counterPicks = []
            briefing.countersKey = nil
            return
        }
        let key = "\(theirs.id)-\(role.rawValue)-\(queue.rawValue)"
        guard key != briefing.countersKey else { return }
        briefing.countersKey = key
        briefing.counterPicks = []
        Task { [briefingSources, lcu] in
            do {
                async let pickable = try? lcu?.pickableChampionIds()
                let counters = try await briefingSources.counters.counters(against: theirs, role: role, queue: queue)
                let pickableIds = await pickable
                guard key == briefing.countersKey else { return }
                briefing.counterPicks = counters
                briefing.pickableIds = pickableIds
            } catch {
                logger.notice("OP.GG counters unavailable: \(String(describing: error), privacy: .public)")
            }
        }
    }
}
