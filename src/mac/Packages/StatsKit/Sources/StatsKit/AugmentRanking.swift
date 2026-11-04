import Foundation

/// An augment placed in the champion's statistical ranking.
public struct RankedAugment: Equatable, Identifiable, Sendable {
    /// Relative grade within the champion's augments – a statistic, not a pick instruction.
    public enum Grade: String, CaseIterable, Sendable {
        case top = "S"
        case strong = "A"
        case solid = "B"
        case niche = "C"
    }

    public let stat: AugmentStat
    /// Performance after shrinkage towards the champion's average (see `AugmentRanking`).
    public let score: Double
    public let grade: Grade
    /// 1-based position in the champion's ranking.
    public let rank: Int

    public var id: Int {
        stat.id
    }
}

/// Ranks a champion's ARAM: Mayhem augments by OP.GG performance, robust against small samples.
///
/// OP.GG only reports a pick *share*, no game count. An augment's own performance is trusted in
/// proportion to that share: `score = mean + w · (performance − mean)` with
/// `w = pickRate / (pickRate + priorPickRate)`. A rarely picked augment with an extreme score (e.g.
/// 141 at 0 % picks) thereby regresses to the champion's average instead of topping the list.
public enum AugmentRanking {
    /// Pick share at which an augment's own performance counts half.
    public static let priorPickRate = 0.05
    /// Augments below this pick share are left out entirely (no meaningful data).
    public static let minimumPickRate = 0.01

    public static func rank(_ stats: [AugmentStat]) -> [RankedAugment] {
        let usable = stats.filter { $0.performance != nil && $0.pickRate >= minimumPickRate }
        guard !usable.isEmpty else { return [] }
        let mean = weightedMean(usable)
        let scored = usable.map { stat in
            let weight = stat.pickRate / (stat.pickRate + priorPickRate)
            return (stat, mean + weight * ((stat.performance ?? mean) - mean))
        }
        .sorted { ($0.1, $0.0.pickRate) > ($1.1, $1.0.pickRate) }
        return scored.enumerated().map { index, entry in
            RankedAugment(
                stat: entry.0,
                score: entry.1,
                grade: grade(position: index, count: scored.count),
                rank: index + 1
            )
        }
    }

    /// Fixed shares of the list: top 15 % S, next 25 % A, next 35 % B, rest C. Relative on purpose –
    /// OP.GG's scale is undocumented, so only the order within one champion is meaningful.
    static func grade(position: Int, count: Int) -> RankedAugment.Grade {
        let percentile = Double(position) / Double(max(count, 1))
        switch percentile {
        case ..<0.15: return .top
        case ..<0.40: return .strong
        case ..<0.75: return .solid
        default: return .niche
        }
    }

    /// Pick-weighted average performance: what a typical game on this champion looks like.
    static func weightedMean(_ stats: [AugmentStat]) -> Double {
        let totalWeight = stats.reduce(0) { $0 + $1.pickRate }
        guard totalWeight > 0 else {
            return stats.compactMap(\.performance).reduce(0, +) / Double(max(stats.count, 1))
        }
        return stats.reduce(0) { $0 + ($1.performance ?? 0) * $1.pickRate } / totalWeight
    }
}
