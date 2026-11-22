import Foundation

/// End-of-game scoreboard block (`GET /lol-end-of-game/v1/eog-stats-block`).
public struct EndOfGameStats: Decodable, Equatable, Sendable {
    public struct Team: Decodable, Equatable, Sendable {
        public let teamId: Int?
        public let isWinningTeam: Bool?
        public let players: [Player]?

        public init(teamId: Int? = nil, isWinningTeam: Bool? = nil, players: [Player]? = nil) {
            self.teamId = teamId
            self.isWinningTeam = isWinningTeam
            self.players = players
        }
    }

    public struct Player: Decodable, Equatable, Sendable {
        public let championId: Int?
        public let teamId: Int?
        public let isLocalPlayer: Bool?
        public let stats: [String: Double]?

        public init(
            championId: Int? = nil,
            teamId: Int? = nil,
            isLocalPlayer: Bool? = nil,
            stats: [String: Double]? = nil
        ) {
            self.championId = championId
            self.teamId = teamId
            self.isLocalPlayer = isLocalPlayer
            self.stats = stats
        }
    }

    public struct LocalPlayer: Decodable, Equatable, Sendable {
        public let championId: Int?
        public let teamId: Int?
        public let stats: [String: Double]?

        public init(championId: Int? = nil, teamId: Int? = nil, stats: [String: Double]? = nil) {
            self.championId = championId
            self.teamId = teamId
            self.stats = stats
        }
    }

    public let gameId: Int64?
    public let gameLength: Int?
    public let localPlayer: LocalPlayer?
    public let teams: [Team]?

    public init(gameId: Int64? = nil, gameLength: Int? = nil, localPlayer: LocalPlayer? = nil, teams: [Team]? = nil) {
        self.gameId = gameId
        self.gameLength = gameLength
        self.localPlayer = localPlayer
        self.teams = teams
    }

    public var championId: Int? {
        localPlayer?.championId ?? localTeamPlayer?.championId
    }

    public var won: Bool? {
        if let isWinningTeam = localTeam?.isWinningTeam {
            return isWinningTeam
        }
        return resolvedLocalStats?["WIN"].map { $0 > 0 }
    }

    public var kills: Int? {
        resolvedLocalStats?["CHAMPIONS_KILLED"].map { Int($0.rounded()) }
    }

    public var deaths: Int? {
        resolvedLocalStats?["NUM_DEATHS"].map { Int($0.rounded()) }
    }

    public var assists: Int? {
        resolvedLocalStats?["ASSISTS"].map { Int($0.rounded()) }
    }

    public var visionScore: Int? {
        resolvedLocalStats?["VISION_SCORE"].map { Int($0.rounded()) }
    }

    public var killParticipation: Double? {
        guard let kills, let assists, let players = localTeam?.players, !players.isEmpty else { return nil }
        let teamKills = players.reduce(0.0) { $0 + ($1.stats?["CHAMPIONS_KILLED"] ?? 0) }
        guard teamKills > 0 else { return nil }
        return min(1, Double(kills + assists) / teamKills)
    }

    public var damageShare: Double? {
        guard let myDamage = resolvedLocalStats?["TOTAL_DAMAGE_DEALT_TO_CHAMPIONS"],
              let players = localTeam?.players, !players.isEmpty
        else { return nil }
        let teamDamage = players.reduce(0.0) { $0 + ($1.stats?["TOTAL_DAMAGE_DEALT_TO_CHAMPIONS"] ?? 0) }
        guard teamDamage > 0 else { return nil }
        return min(1, max(0, myDamage / teamDamage))
    }

    private var localTeam: Team? {
        if let teamId = localPlayer?.teamId, let matched = teams?.first(where: { $0.teamId == teamId }) {
            return matched
        }
        return teams?.first { $0.players?.contains(where: { $0.isLocalPlayer == true }) == true }
    }

    private var localTeamPlayer: Player? {
        localTeam?.players?.first { $0.isLocalPlayer == true }
    }

    private var resolvedLocalStats: [String: Double]? {
        localPlayer?.stats ?? localTeamPlayer?.stats
    }
}

public extension LCURequesting {
    func endOfGameStats() async throws -> EndOfGameStats {
        try await get("/lol-end-of-game/v1/eog-stats-block")
    }
}
