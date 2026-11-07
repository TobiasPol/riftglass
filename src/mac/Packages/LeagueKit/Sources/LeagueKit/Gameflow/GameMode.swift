import Foundation

/// What is being played, coarse enough to decide build sources, imports and overlays.
public enum GameMode: String, Codable, CaseIterable, Sendable {
    case summonersRift
    case aram
    case aramMayhem
    case arena
    case urf
    case oneForAll
    case ultimateSpellbook
    case nexusBlitz
    case brawl
    case swarm
    /// "League of Legends Classic" (Season-3 kits, old runes/masteries, Patch 26.15+). Modern rune
    /// pages and item sets do not apply.
    case leagueClassic
    case unknown

    /// Riot map IDs (Data Dragon `maps.json`).
    public enum Map {
        public static let summonersRift = 11
        public static let howlingAbyss = 12
        public static let nexusBlitz = 21
        public static let arena = 30
    }

    /// Classifies a game from whatever is known: the queue ID (LCU, most precise), the `gameMode`
    /// string (LCU queue or Live Client `gamestats`) and the map. Unknown queues fall back step by step.
    public static func classify(queueId: Int?, gameMode: String?, mapId: Int?, description: String? = nil) -> Self {
        if let queueId, let mode = byQueueId[queueId] {
            return mode
        }
        if let description, description.localizedCaseInsensitiveContains("league classic") {
            return .leagueClassic
        }
        if let gameMode, let mode = byGameModeString[gameMode.uppercased()] {
            return mode
        }
        switch mapId {
        case Map.summonersRift: return .summonersRift
        case Map.howlingAbyss: return .aram
        case Map.nexusBlitz: return .nexusBlitz
        case Map.arena: return .arena
        default: return .unknown
        }
    }

    /// Queue IDs from Riot's `queues.json` (static.developer.riotgames.com/docs/lol/queues.json),
    /// plus IDs seen live but missing there (1750 "Arena 3x6", docs/SPIKE.md).
    static let byQueueId: [Int: Self] = {
        var table: [Int: Self] = [:]
        // Draft, Ranked Solo, Blind, Flex, Swiftplay, Quickplay, Clash, Co-op vs. AI, Tutorials.
        for id in [400, 420, 430, 440, 480, 490, 700, 820, 830, 840, 850, 870, 880, 890, 2000, 2010, 2020] {
            table[id] = .summonersRift
        }
        for id in [450, 720] {
            table[id] = .aram
        }
        for id in [900, 1010, 1900] {
            table[id] = .urf
        }
        for id in [1700, 1710, 1750] {
            table[id] = .arena
        }
        for id in [1810, 1820, 1830, 1840] {
            table[id] = .swarm
        }
        table[2400] = .aramMayhem
        table[1020] = .oneForAll
        table[1400] = .ultimateSpellbook
        table[1300] = .nexusBlitz
        table[2300] = .brawl
        return table
    }()

    /// `gameMode` strings (Riot `gameModes.json` plus match-v5 codenames `CHERRY`, `KIWI`, `STRAWBERRY`).
    static let byGameModeString: [String: Self] = [
        "CLASSIC": .summonersRift, "SWIFTPLAY": .summonersRift, "TUTORIAL": .summonersRift,
        "PRACTICETOOL": .summonersRift,
        "ARAM": .aram, "KIWI": .aramMayhem, "CHERRY": .arena,
        "URF": .urf, "ARURF": .urf, "ONEFORALL": .oneForAll, "ULTBOOK": .ultimateSpellbook,
        "NEXUSBLITZ": .nexusBlitz, "GAMEMODEX": .nexusBlitz, "BRAWL": .brawl, "STRAWBERRY": .swarm
    ]

    public var displayName: String {
        switch self {
        case .summonersRift: "Summoner's Rift"
        case .aram: "ARAM"
        case .aramMayhem: "ARAM: Mayhem"
        case .arena: "Arena"
        case .urf: "URF"
        case .oneForAll: "One for All"
        case .ultimateSpellbook: "Ultimate Spellbook"
        case .nexusBlitz: "Nexus Blitz"
        case .brawl: "Brawl"
        case .swarm: "Swarm"
        case .leagueClassic: "League Classic"
        case .unknown: "Unknown mode"
        }
    }

    /// Players have assigned lanes (role-specific builds make sense).
    public var hasLanes: Bool {
        switch self {
        case .summonersRift, .urf, .oneForAll, .ultimateSpellbook: true
        default: false
        }
    }

    /// Modern rune pages apply. Arena/Swarm have none; ARAM: Mayhem disables them ("Rune settings are
    /// disabled in Mayhem", Riot support; augments replace them); League Classic uses old runes/masteries.
    public var usesRunePages: Bool {
        switch self {
        case .arena, .swarm, .aramMayhem, .leagueClassic: false
        default: true
        }
    }

    /// Map an item set should be bound to, nil when Riftglass has no fitting item data for the mode.
    public var itemSetMapId: Int? {
        switch self {
        case .summonersRift, .urf, .oneForAll, .ultimateSpellbook: Map.summonersRift
        case .aram, .aramMayhem: Map.howlingAbyss
        default: nil
        }
    }

    /// Map ID for Riot's `recommended-pages` endpoint, nil when the client has no recommendations.
    public var recommendationMapId: Int? {
        switch self {
        case .summonersRift, .urf, .oneForAll, .ultimateSpellbook: Map.summonersRift
        case .aram, .aramMayhem: Map.howlingAbyss
        default: nil
        }
    }

    /// The mode has augments (ARAM: Mayhem augment stats come from OP.GG; see `AugmentPickTracker`).
    public var hasAugments: Bool {
        self == .aramMayhem || self == .arena
    }
}
