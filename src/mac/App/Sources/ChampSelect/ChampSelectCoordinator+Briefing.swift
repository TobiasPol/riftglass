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
    /// Counter key plus the lock count: pickability changes with every pick or ban.
    var pickableKey: String?
}

/// OP.GG sources of the briefing.
struct BriefingSources {
    let laneMeta = OPGGLaneMetaProvider()
    let matchups = OPGGMatchupProvider(language: GameDataLocale.dataDragon)
    let counters = OPGGCounterProvider()
}

extension ChampSelectCoordinator {
    /// Own role: resolved with the builds, else what the client assigned.
    var briefingRole: Role? {
        role ?? Role(lcuPosition: session?.localPosition)
    }

    /// Recomputes the briefing when the visible champions, their revealed positions, the own role,
    /// the pick turn or the lock state change. Turning the briefing off drops everything, so pending
    /// answers are discarded and turning it on again starts fresh.
    func updateBriefing() {
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
            "\(championId ?? 0)", briefingRole?.rawValue ?? "-", "\(session.isLocalPickInProgress)",
            "\(session.completedActionCount)", mode.rawValue
        ].joined(separator: "|")
        guard key != briefing.teamsKey else { return }
        briefing.teamsKey = key
        briefing.ally = TeamProfile(champions: session.allyChampionIds.compactMap { data.champion($0) })
        briefing.enemy = TeamProfile(champions: enemies.compactMap { data.champion($0.championId) })
        briefing.hints = CompHint.hints(ally: briefing.ally, enemy: briefing.enemy)
        let locks = session.completedActionCount
        // Lanes, matchups and counters only exist on Summoner's Rift with OP.GG lane statistics.
        guard mode == .summonersRift, !enemies.isEmpty else {
            briefing.lanes = [:]
            briefing.opponent = nil
            loadMatchup()
            loadCounters(isPicking: false, locks: locks)
            return
        }
        let isPicking = session.isLocalPickInProgress
        Task { await assignLanes(enemies, key: key, isPicking: isPicking, locks: locks) }
    }

    private func assignLanes(
        _ enemies: [ChampSelectSession.EnemyPick],
        key: String,
        isPicking: Bool,
        locks: Int
    ) async {
        let rates = await loadRoleRates()
        // Opted out while waiting (the key was reset) or a newer session took over.
        guard settings.briefingEnabled, key == briefing.teamsKey, let data = staticData else { return }
        let picks = enemies.compactMap { pick -> LaneAssigner.Pick? in
            guard let champion = data.champion(pick.championId) else { return nil }
            return .init(championId: pick.championId, name: champion.name, fixed: Role(lcuPosition: pick.position))
        }
        briefing.lanes = LaneAssigner.assign(picks, rates: rates)
        briefing.opponent = briefingRole.flatMap { briefing.lanes[$0] }
        loadMatchup()
        loadCounters(isPicking: isPicking, locks: locks)
    }

    /// Without OP.GG only positions the client revealed are known. Concurrent callers share one
    /// request; a failure clears it, so the next update retries.
    private func loadRoleRates() async -> RoleRates {
        if let roleRates {
            return roleRates
        }
        let task = roleRatesTask ?? Task { [briefingSources, logger] () -> RoleRates? in
            do {
                return try await briefingSources.laneMeta.roleRates()
            } catch {
                logger.notice("OP.GG lane meta unavailable: \(String(describing: error), privacy: .public)")
                return nil
            }
        }
        roleRatesTask = task
        let rates = await task.value
        if roleRatesTask == task {
            roleRatesTask = nil
        }
        roleRates = roleRates ?? rates
        return rates ?? RoleRates(rates: [:])
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

    /// Counter picks against the lane opponent – only during the player's own pick turn. The OP.GG
    /// statistics load once per opponent; pickability is re-read whenever someone locks or bans.
    private func loadCounters(isPicking: Bool, locks: Int) {
        guard isPicking, let role = briefingRole, let theirs = championRef(briefing.opponent?.championId),
              let queue = BuildQueue(queue: effectiveQueue)
        else {
            briefing.counterPicks = []
            briefing.countersKey = nil
            briefing.pickableKey = nil
            briefing.pickableIds = nil
            return
        }
        let key = "\(theirs.id)-\(role.rawValue)-\(queue.rawValue)"
        if key != briefing.countersKey {
            briefing.countersKey = key
            briefing.counterPicks = []
            Task { [briefingSources] in
                do {
                    let counters = try await briefingSources.counters.counters(
                        against: theirs,
                        role: role,
                        queue: queue
                    )
                    guard key == briefing.countersKey else { return }
                    briefing.counterPicks = counters
                } catch {
                    logger.notice("OP.GG counters unavailable: \(String(describing: error), privacy: .public)")
                }
            }
        }
        refreshPickable(key: "\(key)-\(locks)")
    }

    private func refreshPickable(key: String) {
        guard key != briefing.pickableKey else { return }
        briefing.pickableKey = key
        Task { [lcu] in
            let ids = try? await lcu?.pickableChampionIds()
            guard key == briefing.pickableKey else { return }
            briefing.pickableIds = ids
        }
    }
}
