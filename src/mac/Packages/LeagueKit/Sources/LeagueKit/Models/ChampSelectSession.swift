import Foundation

/// `GET /lol-champ-select/v1/session` (and the matching WAMP event), reduced to what Riftglass uses.
public struct ChampSelectSession: Decodable, Equatable, Sendable {
    public let gameId: Int64?
    public let queueId: Int?
    public let isCustomGame: Bool?
    public let localPlayerCellId: Int
    public let myTeam: [Member]
    public let theirTeam: [Member]?
    public let actions: [[Action]]?
    public let timer: Timer?

    public struct Member: Decodable, Equatable, Sendable {
        public let cellId: Int
        public let championId: Int?
        public let championPickIntent: Int?
        public let assignedPosition: String?
        public let spell1Id: Int?
        public let spell2Id: Int?

        /// Locked or hovered champion (0 means "none").
        public var shownChampionId: Int? {
            [championId, championPickIntent].lazy.compactMap(\.self).first { $0 > 0 }
        }

        /// Normalised position, nil when the client assigns none (blind, custom, enemies).
        public var position: String? {
            guard let position = assignedPosition?.lowercased(), !position.isEmpty else { return nil }
            return position
        }
    }

    /// An enemy champion the player can see, with its position if the client reveals it.
    public struct EnemyPick: Equatable, Hashable, Sendable {
        public let championId: Int
        public let position: String?
    }

    public struct Action: Decodable, Equatable, Sendable {
        public let id: Int?
        public let actorCellId: Int
        public let championId: Int?
        public let type: String?
        public let completed: Bool?
        public let isInProgress: Bool?
    }

    public struct Timer: Decodable, Equatable, Sendable {
        public let phase: String?
        public let adjustedTimeLeftInPhase: Int?
    }

    public var localPlayer: Member? {
        myTeam.first { $0.cellId == localPlayerCellId }
    }

    /// Locked or hovered champion of the local player (0 means "none").
    public var localChampionId: Int? {
        localPlayer?.shownChampionId
    }

    /// Normalised role (`top`, `jungle`, `middle`, `bottom`, `utility`) or nil in blind/custom games.
    public var localPosition: String? {
        localPlayer?.position
    }

    /// Champions of the own team, picked or hovered (the client shows ally hovers).
    public var allyChampionIds: [Int] {
        myTeam.compactMap(\.shownChampionId)
    }

    /// Enemy champions visible to the player. Only `championId` counts: enemy hovers are hidden in
    /// draft, so a `championPickIntent` there would be information the player cannot see.
    public var enemyPicks: [EnemyPick] {
        (theirTeam ?? []).compactMap { member in
            guard let id = member.championId, id > 0 else { return nil }
            return EnemyPick(championId: id, position: member.position)
        }
    }

    /// True while it is the local player's turn to pick.
    public var isLocalPickInProgress: Bool {
        (actions ?? []).joined().contains { action in
            action.type == "pick" && action.actorCellId == localPlayerCellId && action.isInProgress == true
        }
    }
}

public extension LCURequesting {
    /// `GET /lol-champ-select/v1/pickable-champion-ids`: champions the player may pick right now
    /// (owned or free, not banned or taken).
    func pickableChampionIds() async throws -> Set<Int> {
        try await Set(get("/lol-champ-select/v1/pickable-champion-ids", as: [Int].self))
    }
}
