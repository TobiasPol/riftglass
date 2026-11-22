import Foundation

/// The items build progress is measured against. Starter items are not part of it – they are sold
/// during the game, so "owned" says nothing about them.
public struct ItemPlan: Equatable, Sendable {
    /// Items a finished build contains (core, boots), in buy order, without duplicates.
    public let required: [Int]
    /// Options for one further slot; owning any of them fills it. Never overlaps `required`.
    public let alternatives: [Int]

    public init(required: [Int], alternatives: [Int] = []) {
        var seen = Set<Int>()
        self.required = required.filter { seen.insert($0).inserted }
        self.alternatives = alternatives.filter { seen.insert($0).inserted }
    }

    public var isEmpty: Bool {
        required.isEmpty && alternatives.isEmpty
    }
}

/// Pure evaluations for the Tab overlay. Uses only information visible to the player in game.
public enum InGameAnalysis {
    /// Rough CS/min guide values per position (not statistics; shown as "Richtwert").
    public static let csBenchmarks: [String: Double] = [
        "TOP": 7.0, "JUNGLE": 5.5, "MIDDLE": 7.5, "BOTTOM": 8.0, "UTILITY": 1.0
    ]

    /// CS per minute; nil during the first minute (too noisy).
    public static func csPerMinute(_ player: LivePlayer, gameTime: Double) -> Double? {
        guard gameTime >= 60 else { return nil }
        return Double(player.scores.creepScore) / (gameTime / 60)
    }

    public static func csBenchmark(for player: LivePlayer) -> Double? {
        player.position.flatMap { csBenchmarks[$0] }
    }

    /// KDA ratio, `(K + A) / max(D, 1)`.
    public static func kda(_ player: LivePlayer) -> Double {
        Double(player.scores.kills + player.scores.assists) / Double(max(player.scores.deaths, 1))
    }

    /// How much of the plan the player owns: every required item counts, the alternatives together
    /// count as one slot.
    public static func buildProgress(owned items: [LivePlayer.Item], plan: ItemPlan) -> (done: Int, total: Int) {
        let owned = Set(items.map(\.itemID))
        let hasAlternative = plan.alternatives.contains(where: owned.contains)
        return (
            plan.required.filter(owned.contains).count + (hasAlternative ? 1 : 0),
            plan.required.count + (plan.alternatives.isEmpty ? 0 : 1)
        )
    }

    /// Next item to buy: the first missing required one, then the first alternative unless one of
    /// them is already owned. Nil when the plan is complete.
    public static func nextItem(owned items: [LivePlayer.Item], plan: ItemPlan) -> Int? {
        let owned = Set(items.map(\.itemID))
        if let missing = plan.required.first(where: { !owned.contains($0) }) {
            return missing
        }
        return plan.alternatives.contains(where: owned.contains) ? nil : plan.alternatives.first
    }

    /// Value of the items a player shows in the scoreboard (visible to everyone in game).
    /// **Policy risk** (see COMPLIANCE.md) – only used behind an off-by-default setting.
    public static func visibleItemGold(_ player: LivePlayer, prices: [Int: Int]) -> Int {
        player.items.reduce(0) { sum, item in
            sum + (prices[item.itemID] ?? item.price ?? 0) * max(item.count ?? 1, 1)
        }
    }

    /// Item-value difference to the lane opponent (positive = ahead); nil without opponent.
    public static func laneGoldDifference(
        for player: LivePlayer,
        in snapshot: LiveGameSnapshot,
        prices: [Int: Int]
    ) -> Int? {
        guard let opponent = snapshot.laneOpponent(of: player) else { return nil }
        return visibleItemGold(player, prices: prices) - visibleItemGold(opponent, prices: prices)
    }

    /// Remaining gold needed to buy `itemID`, subtracting owned recipe components and current gold.
    public static func goldNeeded(
        for itemID: Int,
        currentGold: Double,
        owned items: [LivePlayer.Item],
        prices: [Int: Int],
        recipes: [Int: [Int]]
    ) -> Int? {
        guard let totalPrice = prices[itemID] else { return nil }
        var inventory: [Int: Int] = [:]
        for item in items {
            inventory[item.itemID, default: 0] += max(item.count ?? 1, 1)
        }
        if inventory[itemID, default: 0] > 0 {
            return 0
        }
        let componentValue = (recipes[itemID] ?? []).reduce(0) { sum, componentID in
            sum + consumeOwnedComponents(
                for: componentID,
                inventory: &inventory,
                prices: prices,
                recipes: recipes,
                depth: 0
            )
        }
        let missingItemGold = max(0, totalPrice - componentValue)
        return max(0, missingItemGold - max(0, Int(currentGold)))
    }

    private static func consumeOwnedComponents(
        for itemID: Int,
        inventory: inout [Int: Int],
        prices: [Int: Int],
        recipes: [Int: [Int]],
        depth: Int
    ) -> Int {
        if let count = inventory[itemID], count > 0 {
            inventory[itemID] = count - 1
            return prices[itemID] ?? 0
        }
        guard depth < 8, let components = recipes[itemID] else { return 0 }
        return components.reduce(0) { sum, componentID in
            sum + consumeOwnedComponents(
                for: componentID,
                inventory: &inventory,
                prices: prices,
                recipes: recipes,
                depth: depth + 1
            )
        }
    }
}
