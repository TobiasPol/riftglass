import Foundation

/// One champion in one lane of OP.GG's tier list (`lol_list_lane_meta_champions`).
public struct MetaChampion: Equatable, Sendable {
    /// OP.GG's English display name ("Kog'Maw", "Nunu & Willump") – see `ChampionDirectory`.
    public let name: String
    public let role: Role
    /// Share of the champion's games in this lane.
    public let roleRate: Double
    /// OP.GG tier, 1 = OP … 5 = weak.
    public let tier: Int?
    public let winRate: Double?
    public let pickRate: Double?
    public let banRate: Double?
    public let games: Int?
    /// OP.GG marks champions that are not viable in this lane.
    public let isRip: Bool

    public init(
        name: String,
        role: Role,
        roleRate: Double,
        tier: Int? = nil,
        winRate: Double? = nil,
        pickRate: Double? = nil,
        banRate: Double? = nil,
        games: Int? = nil,
        isRip: Bool = false
    ) {
        self.name = name
        self.role = role
        self.roleRate = roleRate
        self.tier = tier
        self.winRate = winRate
        self.pickRate = pickRate
        self.banRate = banRate
        self.games = games
        self.isRip = isRip
    }
}

/// OP.GG's tier list for every lane – one request feeds lane guesses, pick and ban options.
public struct LaneMeta: Equatable, Sendable {
    public let lanes: [Role: [MetaChampion]]
    public let roleRates: RoleRates

    public init(lanes: [Role: [MetaChampion]]) {
        self.lanes = lanes
        var rates: [String: [Role: Double]] = [:]
        for (role, champions) in lanes {
            for champion in champions {
                rates[RoleRates.normalized(champion.name), default: [:]][role] = champion.roleRate
            }
        }
        roleRates = RoleRates(rates: rates)
    }

    public var isEmpty: Bool {
        lanes.values.allSatisfy(\.isEmpty)
    }

    public func champion(named name: String, in role: Role) -> MetaChampion? {
        let key = RoleRates.normalized(name)
        return lanes[role]?.first { RoleRates.normalized($0.name) == key }
    }

    /// Entries without a lane share are dropped; everything else is optional, so the older
    /// `{champion,role_rate}` answers still parse.
    static func parse(_ value: NotationValue) -> LaneMeta {
        var lanes: [Role: [MetaChampion]] = [:]
        let positions = value["data"]?["positions"]
        for role in Role.allCases {
            lanes[role] = (positions?[role.opggPosition]?.list ?? []).compactMap { entry in
                guard let name = entry["champion"]?.string, let rate = entry["role_rate"]?.double else { return nil }
                return MetaChampion(
                    name: name,
                    role: role,
                    roleRate: rate,
                    tier: entry["tier"]?.int,
                    winRate: entry["win_rate"]?.double,
                    pickRate: entry["pick_rate"]?.double,
                    banRate: entry["ban_rate"]?.double,
                    games: entry["play"]?.int,
                    isRip: entry["is_rip"] == .bool(true)
                )
            }
        }
        return LaneMeta(lanes: lanes)
    }
}

/// Maps OP.GG's English champion names to LCU IDs. Data Dragon names may be localized (German
/// "Nunu und Willump"), so the Data Dragon key ("Nunu", "MonkeyKing") is tried as well.
public struct ChampionDirectory: Sendable {
    public struct Entry: Sendable {
        public let id: Int
        public let name: String
        public let key: String

        public init(id: Int, name: String, key: String) {
            self.id = id
            self.name = name
            self.key = key
        }
    }

    private let byName: [String: Int]
    private let byKey: [(key: String, id: Int)]

    public init(_ entries: [Entry]) {
        var byName: [String: Int] = [:]
        for entry in entries {
            byName[RoleRates.normalized(entry.name)] = entry.id
            byName[RoleRates.normalized(entry.key)] = byName[RoleRates.normalized(entry.key)] ?? entry.id
        }
        self.byName = byName
        // Longest key first, so "nunu" does not shadow a longer key with the same prefix.
        byKey = entries.map { (RoleRates.normalized($0.key), $0.id) }.sorted { $0.key.count > $1.key.count }
    }

    public func id(forName name: String) -> Int? {
        let normalized = RoleRates.normalized(name)
        if let id = byName[normalized] {
            return id
        }
        // "nunuwillump" starts with the key "nunu"; short keys ("vi") would match unrelated names.
        return byKey.first { $0.key.count >= 4 && normalized.hasPrefix($0.key) }?.id
    }
}
