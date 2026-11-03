import Foundation

/// Rough shape of a team from Data Dragon's ratings and tags – an estimate for champ select, not a
/// statistic. Only champions the player can see go in.
public struct TeamProfile: Equatable, Sendable {
    public let count: Int
    /// Estimated share of physical damage (0…1); nil when no champion has ratings.
    public let physicalShare: Double?
    /// Tanks, and fighters with high defense.
    public let frontline: Int
    /// Champions whose primary class is assassin.
    public let assassins: Int

    public let isEmpty: Bool

    public init(champions: [Champion]) {
        count = champions.count
        isEmpty = champions.isEmpty
        var weighted = 0.0
        var weights = 0.0
        for champion in champions {
            guard let info = champion.info, info.attack + info.magic > 0 else { continue }
            // Tanks and supports deal less of a team's damage.
            let weight = ["Tank", "Support"].contains(champion.tags?.first) ? 0.5 : 1
            weighted += weight * Double(info.attack) / Double(info.attack + info.magic)
            weights += weight
        }
        physicalShare = weights > 0 ? weighted / weights : nil
        frontline = champions.count(where: Self.isFrontline)
        assassins = champions.count { $0.tags?.first == "Assassin" }
    }

    static func isFrontline(_ champion: Champion) -> Bool {
        let tags = champion.tags ?? []
        return tags.contains("Tank") || (tags.first == "Fighter" && (champion.info?.defense ?? 0) >= 5)
    }
}

/// Neutral observations about both teams; the UI words them as options, never as instructions.
public enum CompHint: Equatable, Sendable {
    case enemyMostlyPhysical(Double)
    case enemyMostlyMagic(Double)
    case manyEnemyAssassins(Int)
    case noAllyFrontline

    /// At most two hints, most relevant first. Damage needs three visible enemies to mean anything.
    public static func hints(ally: TeamProfile, enemy: TeamProfile) -> [CompHint] {
        var hints: [CompHint] = []
        if enemy.count >= 3, let share = enemy.physicalShare {
            if share >= 0.7 {
                hints.append(.enemyMostlyPhysical(share))
            } else if share <= 0.3 {
                hints.append(.enemyMostlyMagic(1 - share))
            }
        }
        if enemy.assassins >= 2 {
            hints.append(.manyEnemyAssassins(enemy.assassins))
        }
        if ally.count >= 4, ally.frontline == 0 {
            hints.append(.noAllyFrontline)
        }
        return Array(hints.prefix(2))
    }
}
