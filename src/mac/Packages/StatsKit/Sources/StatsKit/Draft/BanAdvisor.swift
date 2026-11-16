import Foundation

/// Everything known in champ select that matters for the player's ban.
public struct BanContext: Sendable {
    public var meta: LaneMeta
    public var directory: ChampionDirectory
    /// The player's lane, if assigned.
    public var role: Role?
    /// Not worth a ban: allies' picks and hovers, allies' bans, the player's own champion.
    public var excluded: Set<Int> = []
    /// The player's hovered or locked champion and OP.GG's counter lists for it in the player's lane.
    public var yourChampionId: Int?
    public var yourCounters: LaneCounters?

    public init(meta: LaneMeta, directory: ChampionDirectory) {
        self.meta = meta
        self.directory = directory
    }
}

/// Ranks ban options. Bans happen before the enemy picks, so the question is which champion the
/// enemy is likely to pick and would do well with:
/// - strength: OP.GG lane win rate,
/// - presence: pick rate (how likely the enemy picks it) and ban rate (what other players fear) –
///   similar to the pick-ban influence tier lists of stats sites use,
/// - the player's own lane counts half again, since the lane opponent is the one enemy the
///   player faces most,
/// - champions that beat the player's declared pick in lane count most.
public enum BanAdvisor {
    static let ownLaneWeight = 1.5

    public static func options(_ context: BanContext, limit: Int = 5) -> [DraftOption] {
        let metaIds = PickAdvisor.metaByID(context.meta, directory: context.directory)
        var best: [Int: DraftOption] = [:]
        for (role, lane) in metaIds {
            for (id, entry) in lane where entry.roleRate >= PickAdvisor.minimumRoleRate && !entry.isRip {
                guard !context.excluded.contains(id) else { continue }
                let option = option(for: id, entry: entry, isOwnLane: role == context.role, context: context)
                if option.score > best[id]?.score ?? -.infinity {
                    best[id] = option
                }
            }
        }
        for counter in context.yourCounters?.beatenBy ?? [] where best[counter.id] == nil {
            guard !context.excluded.contains(counter.id) else { continue }
            best[counter.id] = DraftOption(id: counter.id, reasons: counterReasons(counter.id, context), winRate: nil)
        }
        return best.values
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.id < $1.id }
            .prefix(limit)
            .map(\.self)
    }

    private static func option(for id: Int, entry: MetaChampion, isOwnLane: Bool, context: BanContext) -> DraftOption {
        let winRate = entry.winRate ?? 0.5
        let pickRate = entry.pickRate ?? 0
        let banRate = entry.banRate ?? 0
        let strength = clamped((winRate - 0.5) * 100, 3)
        // 10 % pick rate ≈ 1 point, 20 % ban rate ≈ 1 point.
        let presence = pickRate * 10 + banRate * 5
        var reasons = [
            ScoredReason(.meta(tier: entry.tier, winRate: winRate), impact: strength),
            ScoredReason(.presence(pickRate: pickRate, banRate: banRate), impact: presence)
        ]
        if isOwnLane {
            reasons.append(.init(.inYourLane, impact: max(0, strength + presence) * (ownLaneWeight - 1)))
        }
        reasons += counterReasons(id, context)
        return DraftOption(id: id, reasons: reasons, winRate: entry.winRate)
    }

    private static func counterReasons(_ id: Int, _ context: BanContext) -> [ScoredReason] {
        guard let yours = context.yourChampionId,
              let counter = context.yourCounters?.beatenBy.first(where: { $0.id == id })
        else { return [] }
        let edge = shrunk((counter.winRate - 0.5) * 100, games: counter.games)
        let reason = DraftReason.countersYourPick(yourChampionId: yours, winRate: counter.winRate, games: counter.games)
        return [.init(reason, impact: 2 + max(0, edge) * 1.5)]
    }
}
