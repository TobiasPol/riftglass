import Foundation

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

    /// How many of the planned build items the player already owns.
    public static func buildProgress(owned items: [LivePlayer.Item], planned: [Int]) -> (done: Int, total: Int) {
        let owned = Set(items.map(\.itemID))
        let unique = planned.reduce(into: [Int]()) { result, id in
            if !result.contains(id) {
                result.append(id)
            }
        }
        return (unique.filter(owned.contains).count, unique.count)
    }

    /// Next planned item the player does not own yet.
    public static func nextItem(owned items: [LivePlayer.Item], planned: [Int]) -> Int? {
        let owned = Set(items.map(\.itemID))
        return planned.first { !owned.contains($0) }
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
}
