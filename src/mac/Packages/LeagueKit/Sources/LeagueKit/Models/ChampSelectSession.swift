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
        guard let player = localPlayer else { return nil }
        for candidate in [player.championId, player.championPickIntent] {
            if let id = candidate, id > 0 {
                return id
            }
        }
        return nil
    }

    /// Normalised role (`top`, `jungle`, `middle`, `bottom`, `utility`) or nil in blind/custom games.
    public var localPosition: String? {
        guard let position = localPlayer?.assignedPosition?.lowercased(), !position.isEmpty else { return nil }
        return position
    }
}
