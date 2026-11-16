import DataKit
import Foundation
import LeagueKit
import StatsKit

/// What the draft cards show: ban and pick options, and after the lock-in the own champion's duo
/// statistics with each ally. The key remembers what was computed, so identical WAMP updates cost
/// nothing and late answers for an old state are dropped.
struct DraftAdvice {
    var bans: [DraftOption] = []
    var picks: [DraftOption] = []
    var teamSynergies: [TeamSynergy] = []
    /// Lane the pick options are for.
    var role: Role?
    /// Opponent the matchups refer to (likely lane opponent, or revealed).
    var opponent: LaneAssigner.Assignment?
    var key: String?
}

struct TeamSynergy: Identifiable, Equatable {
    let allyId: Int
    let winRate: Double
    let games: Int
    var id: Int {
        allyId
    }
}

/// The parts of the champ-select session the options depend on.
struct DraftInput: Equatable, Sendable {
    struct Ally: Equatable, Sendable {
        let championId: Int
        let role: Role?
    }

    let role: Role
    let queue: BuildQueue
    let ownChampionId: Int?
    let isBanPending: Bool
    let isPickPending: Bool
    let allies: [Ally]
    let enemies: [ChampSelectSession.EnemyPick]
    let teammateBans: Set<Int>
    /// Changes with every pick or ban, so pickability is read again.
    let locks: Int

    var key: String {
        [
            role.rawValue, queue.rawValue, "\(ownChampionId ?? 0)", "\(isBanPending)", "\(isPickPending)",
            allies.map { "\($0.championId):\($0.role?.rawValue ?? "-")" }.joined(separator: ","),
            enemies.map { "\($0.championId):\($0.position ?? "-")" }.joined(separator: ","),
            "\(teammateBans.sorted())", "\(locks)"
        ].joined(separator: "|")
    }
}

extension ChampSelectCoordinator {
    /// Recomputes the options when anything they depend on changed. Only on Summoner's Rift with a
    /// known own lane – OP.GG's tier list is per lane.
    func updateDraft() {
        guard settings.draftOptionsEnabled, let input = draftInput() else {
            if draft.key != nil {
                draft = DraftAdvice()
            }
            return
        }
        let key = input.key
        guard key != draft.key else { return }
        draft.key = key
        Task { await loadDraft(input, key: key) }
    }

    private func draftInput() -> DraftInput? {
        guard let session, mode == .summonersRift, let queue = BuildQueue(queue: effectiveQueue), queue.usesRoles,
              let role = briefingRole
        else { return nil }
        return DraftInput(
            role: role,
            queue: queue,
            ownChampionId: championId,
            isBanPending: session.isLocalBanPending,
            isPickPending: session.isLocalPickPending,
            allies: session.allies.compactMap { member in
                member.shownChampionId.map { .init(championId: $0, role: Role(lcuPosition: member.position)) }
            },
            enemies: session.enemyPicks,
            teammateBans: session.teammateBanIds,
            locks: session.completedActionCount
        )
    }

    private func loadDraft(_ input: DraftInput, key: String) async {
        guard let meta = await loadLaneMeta(), let data = staticData else {
            // OP.GG or Data Dragon not there yet: forget the key, so the next session update retries.
            if draft.key == key {
                draft.key = nil
            }
            return
        }
        let sources = DraftSources(briefing: briefingSources, lcu: lcu, logger: logger)
        let directory = Self.directory(data)
        let opponent = input.isPickPending ? enemyLanes(input.enemies, rates: meta.roleRates)[input.role] : nil
        let mastery = await loadMastery()
        async let pickable = input.isPickPending ? sources.pickable() : nil
        async let allies = sources.allySynergies(input, meta: meta, directory: directory)
        async let opponentCounters = sources.laneCounters(championRef(opponent?.championId), input)
        async let yourCounters = input.isBanPending ? sources
            .laneCounters(championRef(input.ownChampionId), input) : nil
        var picks = DraftContexts.pick(input, meta: meta, directory: directory, data: data)
        picks.available = await pickable
        picks.allies = await allies
        picks.opponentId = opponent?.championId
        picks.opponentCounters = await opponentCounters
        picks.mastery = mastery
        var bans = DraftContexts.ban(input, meta: meta, directory: directory)
        bans.yourCounters = await yourCounters
        guard key == draft.key else { return }
        draft.role = input.role
        draft.opponent = opponent
        draft.bans = input.isBanPending ? BanAdvisor.options(bans) : []
        draft.picks = input.isPickPending ? PickAdvisor.options(picks) : []
        draft.teamSynergies = input.isPickPending ? [] : DraftContexts.teamSynergies(input, allies: picks.allies)
        prefetchChampionIcons(draft.bans.map(\.id) + draft.picks.map(\.id))
        await refineWithHeadToHead(picks, input: input, sources: sources, key: key)
    }

    /// The lane matchup guide has the real head-to-head; it is requested for the shortlist only.
    private func refineWithHeadToHead(
        _ context: PickContext,
        input: DraftInput,
        sources: DraftSources,
        key: String
    ) async {
        guard input.isPickPending, let opponent = championRef(context.opponentId) else { return }
        let shortlist = PickAdvisor.shortlist(context, count: 5).compactMap { championRef($0) }
        let headToHead = await sources.headToHead(shortlist, against: opponent, role: input.role)
        guard !headToHead.isEmpty, key == draft.key else { return }
        var context = context
        context.headToHead = headToHead
        draft.picks = PickAdvisor.options(context)
    }

    /// The player's mastery, read once per champ select. Failure means no comfort factor, not an error.
    func loadMastery() async -> [Int: Int]? {
        if let mastery {
            return mastery
        }
        let task = masteryTask ?? Task { [lcu, logger] () -> [Int: Int]? in
            do {
                return try await lcu?.localChampionMastery()
            } catch {
                logger.notice("Champion mastery unavailable: \(String(describing: error), privacy: .public)")
                return nil
            }
        }
        masteryTask = task
        mastery = await task.value
        return mastery
    }

    static func directory(_ data: StaticData) -> ChampionDirectory {
        ChampionDirectory(data.championsById.map { .init(id: $0.key, name: $0.value.name, key: $0.value.id) })
    }
}
