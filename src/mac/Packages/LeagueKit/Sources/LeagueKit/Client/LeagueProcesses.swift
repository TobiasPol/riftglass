import Foundation

/// Bundle identifiers of the League processes on macOS (verified in docs/SPIKE.md).
public enum LeagueBundleID {
    /// Background process (LSUIElement) that owns the lockfile.
    public static let client = "com.riotgames.LeagueofLegends.LeagueClient"
    /// UI process: carries `--app-port`/`--remoting-auth-token` and owns the client window.
    public static let clientUx = "com.riotgames.LeagueofLegends.LeagueClientUx"
    /// The game itself (Live Client Data API on port 2999).
    public static let game = "com.riotgames.LeagueofLegends.GameClient"
}

/// A running application reduced to what Riftglass cares about.
public struct RunningProcess: Sendable, Equatable {
    public let bundleID: String?
    public let pid: pid_t

    public init(bundleID: String?, pid: pid_t) {
        self.bundleID = bundleID
        self.pid = pid
    }
}

/// Which League processes are currently running.
public struct LeagueProcesses: Sendable, Equatable {
    public var clientUxPID: pid_t?
    public var gamePID: pid_t?

    public static let none = LeagueProcesses(clientUxPID: nil, gamePID: nil)

    public init(clientUxPID: pid_t?, gamePID: pid_t?) {
        self.clientUxPID = clientUxPID
        self.gamePID = gamePID
    }

    /// Picks the League processes out of a list of running applications.
    public init(from processes: [RunningProcess]) {
        clientUxPID = processes.first { $0.bundleID == LeagueBundleID.clientUx }?.pid
        gamePID = processes.first { $0.bundleID == LeagueBundleID.game }?.pid
    }

    public var isClientRunning: Bool {
        clientUxPID != nil
    }

    public var isGameRunning: Bool {
        gamePID != nil
    }
}
