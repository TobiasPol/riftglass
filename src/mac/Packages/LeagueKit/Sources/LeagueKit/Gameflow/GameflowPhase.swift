import Foundation

/// Value of `/lol-gameflow/v1/gameflow-phase`. Unknown values are kept, never fatal.
/// `"None"` maps to `.idle` so it can never be confused with `Optional.none`.
public enum GameflowPhase: Equatable, Sendable {
    case idle, lobby, matchmaking, readyCheck, champSelect
    case gameStart, inProgress, reconnect
    case preEndOfGame, waitingForStats, endOfGame
    case terminatedInError
    case unknown(String)

    private static let byRawValue: [String: GameflowPhase] = [
        "None": .idle, "Lobby": .lobby, "Matchmaking": .matchmaking, "ReadyCheck": .readyCheck,
        "ChampSelect": .champSelect, "GameStart": .gameStart, "InProgress": .inProgress,
        "Reconnect": .reconnect, "PreEndOfGame": .preEndOfGame, "WaitingForStats": .waitingForStats,
        "EndOfGame": .endOfGame, "TerminatedInError": .terminatedInError
    ]

    public init(rawValue: String) {
        self = Self.byRawValue[rawValue] ?? .unknown(rawValue)
    }
}

extension GameflowPhase: Decodable {
    public init(from decoder: Decoder) throws {
        try self.init(rawValue: decoder.singleValueContainer().decode(String.self))
    }
}
