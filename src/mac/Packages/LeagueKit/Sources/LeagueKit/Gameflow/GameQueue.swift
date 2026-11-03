import Foundation

/// The queue of the current lobby/game, classified into a `GameMode`.
///
/// Source of truth is the LCU (`/lol-gameflow/v1/session` → `gameData.queue`), available from the
/// lobby on. In game the LCU is closed (docs/SPIKE.md), so the Live Client's `gameMode`/`mapNumber`
/// are the fallback – see `resolvedInGame(liveGameMode:mapNumber:)`.
public struct GameQueue: Codable, Equatable, Sendable {
    public let id: Int?
    public let mode: GameMode
    public let mapId: Int?
    public let isRanked: Bool
    /// Queue name as the client shows it (e.g. "Ranked Solo/Duo"), if known.
    public let name: String?

    public init(id: Int?, mode: GameMode, mapId: Int?, isRanked: Bool = false, name: String? = nil) {
        self.id = id
        self.mode = mode
        self.mapId = mapId
        self.isRanked = isRanked
        self.name = name
    }

    /// Ranked Flex has its own OP.GG statistics.
    public var isFlex: Bool {
        id == 440
    }

    public var displayName: String {
        if let name, !name.isEmpty, mode == .summonersRift {
            return name
        }
        return mode.displayName
    }

    /// From champ select alone (`queueId`), when the gameflow session is not known yet.
    public init(queueId: Int) {
        let mode = GameMode.classify(queueId: queueId, gameMode: nil, mapId: nil)
        self.init(id: queueId, mode: mode, mapId: mode.itemSetMapId, isRanked: [420, 440].contains(queueId))
    }

    /// From the Live Client alone (app started mid-game, or the LCU never reported a queue).
    public init(liveGameMode: String?, mapNumber: Int?) {
        let mode = GameMode.classify(queueId: nil, gameMode: liveGameMode, mapId: mapNumber)
        self.init(id: nil, mode: mode, mapId: mapNumber)
    }

    /// The queue to use in game: the one remembered from the lobby if it is plausibly the same game
    /// (same map), otherwise what the Live Client says.
    public static func resolvedInGame(
        remembered: GameQueue?,
        liveGameMode: String?,
        mapNumber: Int?
    ) -> GameQueue {
        let live = GameQueue(liveGameMode: liveGameMode, mapNumber: mapNumber)
        guard let remembered else { return live }
        if let mapNumber, let mapId = remembered.mapId, mapId != mapNumber {
            return live
        }
        return remembered
    }
}

/// `GET /lol-gameflow/v1/session`, reduced to the queue.
public struct GameflowSession: Decodable, Equatable, Sendable {
    public struct GameData: Decodable, Equatable, Sendable {
        public let queue: Queue?
    }

    public struct Queue: Decodable, Equatable, Sendable {
        public let id: Int?
        public let mapId: Int?
        public let gameMode: String?
        public let description: String?
        public let type: String?
        public let isRanked: Bool?
    }

    public let gameData: GameData?

    /// Nil outside a lobby (the client reports queue ID -1 then).
    public var queue: GameQueue? {
        guard let queue = gameData?.queue, let id = queue.id, id > 0 else { return nil }
        let mode = GameMode.classify(
            queueId: id,
            gameMode: queue.gameMode,
            mapId: queue.mapId,
            description: queue.description
        )
        return GameQueue(
            id: id,
            mode: mode,
            mapId: queue.mapId,
            isRanked: queue.isRanked ?? false,
            name: queue.description
        )
    }
}

public extension LCURequesting {
    /// Current queue, nil outside a lobby.
    func currentQueue() async throws -> GameQueue? {
        let session: GameflowSession = try await get("/lol-gameflow/v1/session")
        return session.queue
    }
}
