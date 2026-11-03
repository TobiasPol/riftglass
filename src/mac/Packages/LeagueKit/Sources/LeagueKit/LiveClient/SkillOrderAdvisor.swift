import Foundation

/// A levelable ability slot.
public enum SkillSlot: String, CaseIterable, Codable, Sendable {
    case q = "Q", w = "W", e = "E", r = "R"

    public var maxRank: Int {
        self == .r ? 3 : 5
    }

    /// Lowest champion level for `rank` (1-based) under the standard rules. Champions like Udyr or
    /// Jayce deviate; their recorded skill order proves the exception (see `SkillOrderAdvisor`).
    func standardRequiredLevel(forRank rank: Int) -> Int {
        self == .r ? [6, 11, 16][min(max(rank, 1), 3) - 1] : 2 * rank - 1
    }
}

/// What the skill-point overlay shows.
public struct SkillAdvice: Equatable, Sendable {
    /// Ability to level now.
    public let next: SkillSlot
    /// The following steps of the order (for a short preview).
    public let then: [SkillSlot]
    public let unspentPoints: Int
}

/// Suggests which ability to level, following a recorded skill order (e.g. OP.GG's most common one).
///
/// Pure: inputs are the order, the champion level and the current ability ranks from the Live
/// Client (`activeplayer.abilities`). Tolerates players deviating from the order: the suggestion is
/// always the earliest step the player has not taken yet that can be learned right now.
public enum SkillOrderAdvisor {
    public static func advice(order: [String], championLevel: Int, ranks: [SkillSlot: Int]) -> SkillAdvice? {
        let steps = order.compactMap { SkillSlot(rawValue: $0.uppercased()) }
        let unspent = championLevel - ranks.values.reduce(0, +)
        guard unspent > 0, !steps.isEmpty else { return nil }
        let orderLevels = Self.orderLevels(steps)
        var planned: [SkillSlot: Int] = [:]
        for (index, slot) in steps.enumerated() {
            planned[slot, default: 0] += 1
            let current = ranks[slot, default: 0]
            guard current < planned[slot, default: 0] else { continue }
            if learnable(slot, rank: current + 1, championLevel: championLevel, orderLevels: orderLevels) {
                let then = Array(steps.dropFirst(index + 1).prefix(3))
                return SkillAdvice(next: slot, then: then, unspentPoints: unspent)
            }
        }
        // Order exhausted (it usually covers levels 1–15) or nothing learnable from it: priority.
        let fallback = priority(steps).first { slot in
            let rank = ranks[slot, default: 0] + 1
            return learnable(slot, rank: rank, championLevel: championLevel, orderLevels: orderLevels)
        }
        return fallback.map { SkillAdvice(next: $0, then: [], unspentPoints: unspent) }
    }

    /// Ultimate first, then the basic abilities by how early the order maxes them.
    static func priority(_ steps: [SkillSlot]) -> [SkillSlot] {
        let basics: [SkillSlot] = [.q, .w, .e]
        let ranked = basics.sorted { lhs, rhs in
            let left = steps.count { $0 == lhs }, right = steps.count { $0 == rhs }
            if left != right {
                return left > right
            }
            return (steps.lastIndex(of: lhs) ?? .max) < (steps.lastIndex(of: rhs) ?? .max)
        }
        return [.r] + ranked
    }

    /// Champion level at which the order takes each rank: `[slot: [rank: level]]`.
    private static func orderLevels(_ steps: [SkillSlot]) -> [SkillSlot: [Int: Int]] {
        var result: [SkillSlot: [Int: Int]] = [:]
        var counts: [SkillSlot: Int] = [:]
        for (index, slot) in steps.enumerated() {
            counts[slot, default: 0] += 1
            result[slot, default: [:]][counts[slot, default: 0]] = index + 1
        }
        return result
    }

    private static func learnable(
        _ slot: SkillSlot,
        rank: Int,
        championLevel: Int,
        orderLevels: [SkillSlot: [Int: Int]]
    ) -> Bool {
        let fromOrder = orderLevels[slot] ?? [:]
        // Champions like Udyr have more ultimate/ability ranks than usual; the order shows how many.
        guard rank <= max(slot.maxRank, fromOrder.count) else { return false }
        let standard = slot.standardRequiredLevel(forRank: rank)
        // Only an early ultimate (Udyr, Jayce, Elise, …) is taken from the order – basic abilities
        // always follow the level rule, so a malformed order cannot suggest an impossible rank.
        guard slot == .r, let orderLevel = fromOrder[rank] else { return championLevel >= standard }
        return championLevel >= min(standard, orderLevel)
    }
}
