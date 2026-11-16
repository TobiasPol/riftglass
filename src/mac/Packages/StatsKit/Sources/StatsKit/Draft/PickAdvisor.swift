import Foundation

/// Everything known in champ select that matters for the player's own pick.
public struct PickContext: Sendable {
    public var role: Role
    public var meta: LaneMeta
    public var directory: ChampionDirectory
    /// Champions the player may pick (LCU `pickable-champion-ids`); nil when unknown.
    public var available: Set<Int>?
    /// Taken or claimed by someone else: allies' picks and hovers, visible enemy picks.
    public var excluded: Set<Int> = []
    /// The (likely) lane opponent with OP.GG's counter lists for it.
    public var opponentId: Int?
    public var opponentCounters: LaneCounters?
    /// Head-to-head of options against the opponent (`lol_get_lane_matchup_guide`), option's win rate.
    public var headToHead: [Int: CounterPick] = [:]
    public var allies: [DraftAlly] = []
    public var traits: [Int: ChampionTraits] = [:]
    public var needs = TeamNeeds()
    /// The player's mastery points per champion; nil when the client did not answer.
    public var mastery: [Int: Int]?

    public init(role: Role, meta: LaneMeta, directory: ChampionDirectory) {
        self.role = role
        self.meta = meta
        self.directory = directory
    }
}

/// Ranks pick options for the player's lane. Every factor is in percentage points of win rate, so
/// they add up and each reason can show its share:
/// - lane strength (OP.GG win rate),
/// - lane matchup, normalized by both champions' base win rates – raw matchup win rates mostly
///   repeat overall strength (League PhD: lane matchups explain ~14 % of performance),
/// - duo synergy with each ally, normalized the same way,
/// - team fit (damage mix, frontline; Data Dragon estimate),
/// - the player's mastery: below ~12k mastery points players win ~44 % instead of ~51.5 %
///   (itero.gg, 1M solo-queue games).
public enum PickAdvisor {
    /// Champions played in a lane less often than this are not offered for it.
    public static let minimumRoleRate = 0.1
    static let unfamiliarPoints = 12600
    static let comfortPoints = 50000

    public static func options(_ context: PickContext, limit: Int = 5) -> [DraftOption] {
        let metaIds = metaByID(context.meta, directory: context.directory)
        return candidates(context, metaIds: metaIds)
            .map { option(for: $0, context: context, metaIds: metaIds) }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.id < $1.id }
            .prefix(limit)
            .map(\.self)
    }

    /// The `count` best options before head-to-head data – these are worth a matchup request each.
    public static func shortlist(_ context: PickContext, count: Int) -> [Int] {
        var context = context
        context.headToHead = [:]
        return options(context, limit: count).map(\.id)
    }

    /// OP.GG's lane entries keyed by LCU ID.
    public static func metaByID(_ meta: LaneMeta, directory: ChampionDirectory) -> [Role: [Int: MetaChampion]] {
        meta.lanes.mapValues { champions in
            var byID: [Int: MetaChampion] = [:]
            for champion in champions {
                guard let id = directory.id(forName: champion.name) else { continue }
                byID[id] = champion
            }
            return byID
        }
    }

    private static func candidates(_ context: PickContext, metaIds: [Role: [Int: MetaChampion]]) -> [Int] {
        let lane = metaIds[context.role] ?? [:]
        var ids = Set(lane.filter { $0.value.roleRate >= minimumRoleRate && !$0.value.isRip }.keys)
        // Counters of the opponent are lane options by definition, even when rarely played there.
        ids.formUnion(context.opponentCounters?.beatenBy.map(\.id) ?? [])
        return ids.filter { id in
            !context.excluded.contains(id) && id != context.opponentId && context.available?.contains(id) ?? true
        }
        .sorted()
    }

    private static func option(for id: Int, context: PickContext, metaIds: [Role: [Int: MetaChampion]]) -> DraftOption {
        let entry = metaIds[context.role]?[id]
        let winRate = entry?.winRate ?? 0.5
        var reasons: [ScoredReason] = []
        if let rate = entry?.winRate {
            reasons.append(.init(.meta(tier: entry?.tier, winRate: rate), impact: clamped((rate - 0.5) * 100, 3)))
        }
        if let matchup = matchup(for: id, baseWinRate: winRate, context: context, metaIds: metaIds) {
            reasons.append(matchup)
        }
        reasons += synergies(for: id, baseWinRate: winRate, context: context, metaIds: metaIds)
        reasons += teamFit(for: id, context: context)
        if let comfort = comfort(for: id, mastery: context.mastery) {
            reasons.append(comfort)
        }
        return DraftOption(id: id, reasons: reasons, winRate: entry?.winRate)
    }

    private static func matchup(
        for id: Int,
        baseWinRate: Double,
        context: PickContext,
        metaIds: [Role: [Int: MetaChampion]]
    ) -> ScoredReason? {
        guard let opponent = context.opponentId,
              let stat = context.headToHead[id] ?? context.opponentCounters?.winRate(of: id)
        else { return nil }
        let opponentRate = metaIds[context.role]?[opponent]?.winRate ?? 0.5
        // What the two base win rates alone predict; only the rest is the matchup itself.
        let expected = 0.5 + (baseWinRate - 0.5) - (opponentRate - 0.5)
        let impact = clamped(shrunk((stat.winRate - expected) * 100, games: stat.games), 6)
        return .init(.laneMatchup(opponentId: opponent, winRate: stat.winRate, games: stat.games), impact: impact)
    }

    private static func synergies(
        for id: Int,
        baseWinRate: Double,
        context: PickContext,
        metaIds: [Role: [Int: MetaChampion]]
    ) -> [ScoredReason] {
        let reasons = context.allies.compactMap { ally -> ScoredReason? in
            guard let duo = ally.synergies.first(where: { $0.id == id }) else { return nil }
            let allyRate = metaIds[ally.role]?[ally.championId]?.winRate ?? 0.5
            let expected = 0.5 + (baseWinRate - 0.5) + (allyRate - 0.5)
            let impact = clamped(shrunk((duo.winRate - expected) * 100, games: duo.games), 3)
            return .init(.synergy(allyId: ally.championId, winRate: duo.winRate, games: duo.games), impact: impact)
        }
        // Several allies cannot add up to more than one strong matchup.
        let total = reasons.reduce(0) { $0 + $1.impact }
        let scale = abs(total) > 4 ? 4 / abs(total) : 1
        return reasons.map { .init($0.reason, impact: $0.impact * scale) }.filter { abs($0.impact) >= 0.25 }
    }

    private static func teamFit(for id: Int, context: PickContext) -> [ScoredReason] {
        guard let traits = context.traits[id] else { return [] }
        var reasons: [ScoredReason] = []
        if context.needs.magicDamage, let share = traits.physicalShare, share <= 0.4 {
            reasons.append(.init(.addsMagicDamage, impact: 1))
        }
        if context.needs.physicalDamage, let share = traits.physicalShare, share >= 0.6 {
            reasons.append(.init(.addsPhysicalDamage, impact: 1))
        }
        if context.needs.frontline, traits.isFrontline {
            reasons.append(.init(.addsFrontline, impact: 1))
        }
        return reasons
    }

    private static func comfort(for id: Int, mastery: [Int: Int]?) -> ScoredReason? {
        guard let mastery else { return nil }
        let points = mastery[id] ?? 0
        if points < unfamiliarPoints {
            return .init(.unfamiliar(points: points), impact: -4)
        }
        return .init(.comfort(points: points), impact: points >= comfortPoints ? 1 : 0.5)
    }
}
