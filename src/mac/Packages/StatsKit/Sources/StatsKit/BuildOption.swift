import Foundation

/// One build suggestion. Riftglass always shows several options – never a single instruction
/// (Riot policy: apps must not dictate player decisions).
public struct BuildOption: Codable, Equatable, Identifiable, Sendable {
    public struct Runes: Codable, Equatable, Sendable {
        public let primaryStyleId: Int
        public let subStyleId: Int
        /// 6 runes followed by 3 stat shards.
        public let perkIds: [Int]

        public init(primaryStyleId: Int, subStyleId: Int, perkIds: [Int]) {
            self.primaryStyleId = primaryStyleId
            self.subStyleId = subStyleId
            self.perkIds = perkIds
        }
    }

    public struct ItemBlock: Codable, Equatable, Sendable {
        public let title: String
        public let itemIds: [Int]

        public init(title: String, itemIds: [Int]) {
            self.title = title
            self.itemIds = itemIds
        }
    }

    public struct Stats: Codable, Equatable, Sendable {
        public let winRate: Double
        public let pickRate: Double?
        public let games: Int

        public init(winRate: Double, pickRate: Double?, games: Int) {
            self.winRate = winRate
            self.pickRate = pickRate
            self.games = games
        }
    }

    public enum Source: String, Codable, Sendable {
        case opgg, riot

        public var attribution: String {
            switch self {
            case .opgg: "Daten: OP.GG"
            case .riot: "Riot-Empfehlung"
            }
        }
    }

    public let id: String
    public let title: String
    public let role: Role
    /// Data Dragon key (`Ahri`); nil for builds persisted before v0.2.
    public let championKey: String?
    public let queue: BuildQueue?
    public let source: Source
    public let runes: Runes
    public let summonerSpells: [Int]
    public let itemBlocks: [ItemBlock]
    public let skillOrder: [String]
    public let stats: Stats?

    public init(
        id: String,
        title: String,
        role: Role,
        championKey: String? = nil,
        queue: BuildQueue? = nil,
        source: Source,
        runes: Runes,
        summonerSpells: [Int],
        itemBlocks: [ItemBlock],
        skillOrder: [String] = [],
        stats: Stats? = nil
    ) {
        self.id = id
        self.title = title
        self.role = role
        self.championKey = championKey
        self.queue = queue
        self.source = source
        self.runes = runes
        self.summonerSpells = summonerSpells
        self.itemBlocks = itemBlocks
        self.skillOrder = skillOrder
        self.stats = stats
    }

    /// All item IDs in block order, without duplicates (e.g. two potions).
    public var allItemIds: [Int] {
        var seen = Set<Int>()
        return itemBlocks.flatMap(\.itemIds).filter { seen.insert($0).inserted }
    }
}

public enum Role: String, Codable, CaseIterable, Sendable {
    case top, jungle, middle, bottom, utility

    /// Maps the LCU's position strings (`MIDDLE`, `utility`, …) to a role.
    public init?(lcuPosition: String?) {
        guard let position = lcuPosition?.lowercased() else { return nil }
        self.init(rawValue: position)
    }

    /// OP.GG's position names.
    public var opggPosition: String {
        switch self {
        case .top: "top"
        case .jungle: "jungle"
        case .middle: "mid"
        case .bottom: "adc"
        case .utility: "support"
        }
    }

    public var lcuPosition: String {
        rawValue.uppercased()
    }
}

/// Champion as build sources need it: LCU ID plus Data Dragon key (e.g. 62 / "MonkeyKing").
public struct ChampionRef: Equatable, Hashable, Sendable {
    public let id: Int
    public let key: String

    public init(id: Int, key: String) {
        self.id = id
        self.key = key
    }
}

/// Which statistics a build is based on. OP.GG's MCP only has reliable data for these
/// (`urf`/`nexus_blitz` are listed but reject every position – docs/SPIKE.md, Spike 3).
public enum BuildQueue: String, Codable, Sendable {
    /// Summoner's Rift solo/duo – also the approximation for normals, Swiftplay, URF and the like.
    case ranked
    case flex
    /// Howling Abyss; also used for ARAM: Mayhem (same map and items, augments on top).
    case aram

    public var opggGameMode: String {
        rawValue
    }

    /// ARAM has no lanes; OP.GG still requires a position and ignores it.
    public var usesRoles: Bool {
        self != .aram
    }
}

/// Source of build options.
public protocol BuildProvider: Sendable {
    func builds(for champion: ChampionRef, role: Role, queue: BuildQueue, patch: String?) async throws -> [BuildOption]
}
