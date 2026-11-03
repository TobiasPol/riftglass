import Foundation

// Live Client Data API models (https://127.0.0.1:2999/liveclientdata/…). Only data the player can
// see in game. Tolerant decoding: everything not strictly needed is optional.

/// `GET /liveclientdata/gamestats`
public struct LiveGameStats: Decodable, Equatable, Sendable {
    public let gameMode: String?
    public let gameTime: Double
    public let mapNumber: Int?

    public init(gameMode: String?, gameTime: Double, mapNumber: Int?) {
        self.gameMode = gameMode
        self.gameTime = gameTime
        self.mapNumber = mapNumber
    }
}

/// `GET /liveclientdata/activeplayer` (reduced).
public struct LiveActivePlayer: Decodable, Equatable, Sendable {
    public struct Ability: Decodable, Equatable, Sendable {
        public let abilityLevel: Int?
    }

    /// Keys `Q`, `W`, `E`, `R` (and `Passive`, which has no level).
    public let abilities: [String: Ability]?
    public let riotId: String?
    public let riotIdGameName: String?
    public let summonerName: String?
    public let level: Int
    public let currentGold: Double

    /// Current rank of each levelable ability.
    public var abilityRanks: [SkillSlot: Int] {
        var ranks: [SkillSlot: Int] = [:]
        for slot in SkillSlot.allCases {
            ranks[slot] = abilities?[slot.rawValue]?.abilityLevel ?? 0
        }
        return ranks
    }
}

/// Element of `GET /liveclientdata/playerlist`.
public struct LivePlayer: Decodable, Equatable, Sendable {
    public struct Item: Decodable, Equatable, Sendable {
        public let itemID: Int
        public let slot: Int
        public let count: Int?
        public let price: Int?
    }

    public struct Scores: Decodable, Equatable, Sendable {
        public let kills: Int
        public let deaths: Int
        public let assists: Int
        public let creepScore: Int
        public let wardScore: Double?
    }

    public let championName: String
    public let rawChampionName: String?
    public let riotId: String?
    public let riotIdGameName: String?
    public let riotIdTagLine: String?
    public let summonerName: String?
    /// `ORDER` (blue) or `CHAOS` (red).
    public let team: String
    /// `TOP`, `JUNGLE`, `MIDDLE`, `BOTTOM`, `UTILITY` or `NONE`.
    public let position: String?
    public let level: Int
    public let isBot: Bool?
    public let isDead: Bool?
    public let items: [Item]
    public let scores: Scores

    /// Data Dragon champion key from `game_character_displayname_<Key>`, falls back to the display name.
    public var championKey: String {
        let prefix = "game_character_displayname_"
        if let raw = rawChampionName, raw.hasPrefix(prefix) {
            return String(raw.dropFirst(prefix.count))
        }
        return championName.filter(\.isLetter)
    }

    /// Riot ID split into name and tag; nil for bots or old clients.
    public var riotIDParts: (gameName: String, tagLine: String)? {
        if let name = riotIdGameName, let tag = riotIdTagLine, !name.isEmpty, !tag.isEmpty {
            return (name, tag)
        }
        guard let riotId, let hash = riotId.lastIndex(of: "#") else { return nil }
        return (String(riotId[..<hash]), String(riotId[riotId.index(after: hash)...]))
    }

    /// Identity used to match the active player and to key caches.
    public var displayID: String {
        riotId ?? riotIdGameName ?? summonerName ?? championName
    }
}

/// Everything the overlay needs from one poll.
public struct LiveGameSnapshot: Equatable, Sendable {
    public let stats: LiveGameStats
    public let activePlayer: LiveActivePlayer?
    public let players: [LivePlayer]

    public init(stats: LiveGameStats, activePlayer: LiveActivePlayer?, players: [LivePlayer]) {
        self.stats = stats
        self.activePlayer = activePlayer
        self.players = players
    }

    public var me: LivePlayer? {
        guard let activePlayer else { return nil }
        let ids = [activePlayer.riotId, activePlayer.riotIdGameName, activePlayer.summonerName].compactMap(\.self)
        return players.first { player in
            ids.contains { $0 == player.riotId || $0 == player.riotIdGameName || $0 == player.summonerName }
        }
    }

    /// Opponent in the same position (lane opponent), if positions are known.
    public func laneOpponent(of player: LivePlayer) -> LivePlayer? {
        guard let position = player.position, position != "NONE", !position.isEmpty else { return nil }
        return players.first { $0.team != player.team && $0.position == position }
    }
}
