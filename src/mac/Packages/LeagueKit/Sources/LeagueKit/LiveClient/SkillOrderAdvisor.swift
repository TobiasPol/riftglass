import Foundation

/// A levelable ability slot.
public enum SkillSlot: String, CaseIterable, Codable, Sendable {
    case q = "Q", w = "W", e = "E", r = "R"
}

/// How a champion's abilities are ranked. Most champions use `.standard`; a few kits differ in
/// ways the Live Client does not reveal (it only reports current ranks, not spent points).
public struct SkillRules: Equatable, Sendable {
    public var maxRank: [SkillSlot: Int]
    /// Ranks a champion starts with for free (Karma's Mantra).
    public var startingRanks: [SkillSlot: Int] = [:]
    /// Slots that rank up by themselves and never cost a point (Jayce, Elise, Nidalee: R).
    public var automatic: Set<SkillSlot> = []
    /// Champion level required for each ultimate rank (index 0 = rank 1).
    public var ultimateLevels: [Int] = [6, 11, 16]
    /// The ultimate is gated like a basic ability (Udyr has four basic stances).
    public var ultimateIsBasic = false
    /// Suggest from priority once the recorded order (levels 1–15) is used up. Off for kits whose
    /// late ranks the order does not show.
    public var fallbackAfterOrder = true

    public static let standard = SkillRules(maxRank: [.q: 5, .w: 5, .e: 5, .r: 3])

    /// Rules for a Data Dragon champion key; unknown champions use `.standard`.
    public static func forChampion(_ key: String) -> SkillRules {
        var rules = SkillRules.standard
        switch key {
        case "Jayce", "Elise", "Nidalee":
            rules.automatic = [.r]
        case "Karma":
            rules.startingRanks = [.r: 1]
            rules.maxRank[.r] = 4
            rules.ultimateLevels = [1, 6, 11, 16]
        case "Udyr":
            // Rank-6 unlocks lie beyond OP.GG's 15-step order → no advice after it, rather than a guess.
            rules.maxRank = [.q: 6, .w: 6, .e: 6, .r: 6]
            rules.ultimateIsBasic = true
            rules.fallbackAfterOrder = false
        default:
            break
        }
        return rules
    }

    /// Lowest champion level for `rank` (1-based) of `slot`.
    func requiredLevel(_ slot: SkillSlot, rank: Int) -> Int {
        guard slot == .r, !ultimateIsBasic else { return 2 * rank - 1 }
        return rank <= ultimateLevels.count ? ultimateLevels[rank - 1] : .max
    }

    /// Points actually spent: ranks minus free starting ranks, automatic slots excluded.
    func spentPoints(_ ranks: [SkillSlot: Int]) -> Int {
        SkillSlot.allCases.filter { !automatic.contains($0) }
            .reduce(0) { $0 + max(0, ranks[$1, default: 0] - startingRanks[$1, default: 0]) }
    }

    func learnable(_ slot: SkillSlot, rank: Int, championLevel: Int) -> Bool {
        !automatic.contains(slot) && rank <= maxRank[slot, default: 0]
            && championLevel >= requiredLevel(slot, rank: rank)
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
/// Pure: inputs are the order, the champion level, the current ability ranks from the Live
/// Client (`activeplayer.abilities`) and the champion's `SkillRules`. Tolerates players deviating
/// from the order: the suggestion is the earliest step not taken yet that can be learned now.
public enum SkillOrderAdvisor {
    public static func advice(
        order: [String],
        championLevel: Int,
        ranks: [SkillSlot: Int],
        rules: SkillRules = .standard
    ) -> SkillAdvice? {
        let steps = order.compactMap { SkillSlot(rawValue: $0.uppercased()) }
            .filter { !rules.automatic.contains($0) }
        let unspent = championLevel - rules.spentPoints(ranks)
        guard unspent > 0, !steps.isEmpty else { return nil }
        var planned = rules.startingRanks
        for (index, slot) in steps.enumerated() {
            planned[slot, default: 0] += 1
            let current = ranks[slot, default: 0]
            guard current < planned[slot, default: 0] else { continue }
            if rules.learnable(slot, rank: current + 1, championLevel: championLevel) {
                let then = Array(steps.dropFirst(index + 1).prefix(3))
                return SkillAdvice(next: slot, then: then, unspentPoints: unspent)
            }
        }
        // Order exhausted (it usually covers levels 1–15) or nothing learnable from it: priority.
        guard rules.fallbackAfterOrder else { return nil }
        let fallback = priority(steps).first { slot in
            rules.learnable(slot, rank: ranks[slot, default: 0] + 1, championLevel: championLevel)
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
}
