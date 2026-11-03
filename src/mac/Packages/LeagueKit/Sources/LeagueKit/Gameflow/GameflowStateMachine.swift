import Foundation

/// What Riftglass should be doing right now. Determines which subsystems run (PLAN §4.1).
public enum AppMode: Equatable, Sendable {
    /// League not running: only the `ClientWatcher` is active.
    case dormant
    /// Client running, LCU WebSocket connected/connecting.
    case client
    /// Champ select: panel, docking, icon prefetch.
    case champSelect
    /// Game running (detected via process, independent of the LCU).
    case inGame
    /// Post-game summary.
    case postGame
}

/// Pure state machine: inputs are process presence, LCU connectivity and the gameflow phase.
///
/// The game is detected via its process, not the LCU: the client may close during a game
/// ("close client during game"), and losing the LCU then is not an error.
public struct GameflowStateMachine: Equatable, Sendable {
    public private(set) var processes: LeagueProcesses = .none
    public private(set) var phase: GameflowPhase?
    public private(set) var mode: AppMode = .dormant

    public init() {}

    public enum Input: Equatable, Sendable {
        case processesChanged(LeagueProcesses)
        case phaseChanged(GameflowPhase)
        case lcuDisconnected
    }

    /// Applies an input and returns the new mode if it changed.
    @discardableResult
    public mutating func handle(_ input: Input) -> AppMode? {
        switch input {
        case let .processesChanged(newProcesses):
            processes = newProcesses
            if !newProcesses.isClientRunning {
                phase = nil
            }
        case let .phaseChanged(newPhase):
            phase = newPhase == .terminatedInError ? .idle : newPhase
        case .lcuDisconnected:
            phase = nil
        }
        let newMode = Self.resolveMode(processes: processes, phase: phase)
        guard newMode != mode else { return nil }
        mode = newMode
        return newMode
    }

    static func resolveMode(processes: LeagueProcesses, phase: GameflowPhase?) -> AppMode {
        if processes.isGameRunning {
            return .inGame
        }
        guard processes.isClientRunning else { return .dormant }
        guard let phase else { return .client }
        switch phase {
        case .champSelect:
            return .champSelect
        case .gameStart, .inProgress, .reconnect:
            // Phase says in-game, but the game process is not (yet) visible.
            return .inGame
        case .preEndOfGame, .waitingForStats, .endOfGame:
            return .postGame
        case .idle, .lobby, .matchmaking, .readyCheck, .terminatedInError, .unknown:
            return .client
        }
    }
}
