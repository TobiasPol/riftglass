import Foundation

/// Stat shard (perk mod) metadata from Data Dragon's CDN icon set (not included in `runesReforged.json`).
public struct StatShard: Equatable, Sendable {
    public let id: Int
    public let name: String
    public let iconPath: String

    public init(id: Int, name: String, iconPath: String) {
        self.id = id
        self.name = name
        self.iconPath = iconPath
    }

    private static let byId: [Int: StatShard] = [
        5008: StatShard(
            id: 5008,
            name: "Adaptive Force",
            iconPath: "perk-images/StatMods/StatModsAdaptiveForceIcon.png"
        ),
        5005: StatShard(
            id: 5005,
            name: "Attack Speed",
            iconPath: "perk-images/StatMods/StatModsAttackSpeedIcon.png"
        ),
        5007: StatShard(
            id: 5007,
            name: "Ability Haste",
            iconPath: "perk-images/StatMods/StatModsCDRScalingIcon.png"
        ),
        5010: StatShard(
            id: 5010,
            name: "Move Speed",
            iconPath: "perk-images/StatMods/StatModsMovementSpeedIcon.png"
        ),
        5001: StatShard(
            id: 5001,
            name: "Health Scaling",
            iconPath: "perk-images/StatMods/StatModsHealthScalingIcon.png"
        ),
        5011: StatShard(
            id: 5011,
            name: "Health",
            iconPath: "perk-images/StatMods/StatModsHealthPlusIcon.png"
        ),
        5013: StatShard(
            id: 5013,
            name: "Tenacity & Slow Resist",
            iconPath: "perk-images/StatMods/StatModsTenacityIcon.png"
        ),
        5002: StatShard(
            id: 5002,
            name: "Armor",
            iconPath: "perk-images/StatMods/StatModsArmorIcon.png"
        ),
        5003: StatShard(
            id: 5003,
            name: "Magic Resist",
            iconPath: "perk-images/StatMods/StatModsMagicResIcon.png"
        )
    ]

    public static func shard(_ id: Int) -> StatShard? {
        byId[id]
    }
}
