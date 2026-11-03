import AppKit
import LeagueKit
import os

/// What a live LCU connection reports to the app.
enum LCUConnectionEvent: Sendable {
    case connected(LCUClient)
    case phase(GameflowPhase)
    case champSelect(ChampSelectSession)
    case champSelectEnded
}

/// Lifecycle of one LCU instance (one `LeagueClientUx` PID): resolve credentials, open REST + WAMP,
/// re-read state after every (re)subscribe and forward relevant events. Cancelled when the PID goes away.
@MainActor
final class LCUConnection {
    let pid: pid_t
    private let installDirectory: URL?
    private let evaluator: LocalTrustEvaluator
    private let handler: @MainActor (LCUConnectionEvent) -> Void
    private var task: Task<Void, Never>?
    private let logger = Logger(subsystem: "de.polleydigital.riftglass", category: "LCUConnection")

    init(pid: pid_t, evaluator: LocalTrustEvaluator, handler: @escaping @MainActor (LCUConnectionEvent) -> Void) {
        self.pid = pid
        self.evaluator = evaluator
        self.handler = handler
        // `.../Contents/LoL/League of Legends.app` → install directory `.../Contents/LoL`.
        installDirectory = NSRunningApplication(processIdentifier: pid)?.bundleURL?.deletingLastPathComponent()
    }

    func start() {
        task = Task { [weak self] in await self?.run() }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func run() async {
        guard let credentials = await resolveCredentials() else { return }
        logger.info("LCU found on port \(credentials.port)")
        let client = LCUClient(credentials: credentials, evaluator: evaluator)
        handler(.connected(client))
        let stream = LCUEventStream(credentials: credentials, evaluator: evaluator)
        for await message in await stream.messages() {
            switch message {
            case .subscribed: await refreshState(client)
            case let .event(event): dispatch(event)
            }
        }
        await stream.stop()
    }

    /// Arguments are there immediately after launch; retry briefly in case the process is still starting.
    private func resolveCredentials() async -> LCUCredentials? {
        let resolver = CredentialResolver()
        var delay = 0.25
        while !Task.isCancelled {
            if let credentials = resolver.resolve(clientUxPID: pid, installDirectory: installDirectory) {
                return credentials
            }
            try? await Task.sleep(for: .seconds(delay))
            delay = min(delay * 2, 5)
        }
        return nil
    }

    private func refreshState(_ client: LCUClient) async {
        guard let phase = try? await client.get("/lol-gameflow/v1/gameflow-phase", as: GameflowPhase.self) else {
            return
        }
        handler(.phase(phase))
        if phase == .champSelect,
           let session = try? await client.get("/lol-champ-select/v1/session", as: ChampSelectSession.self) {
            handler(.champSelect(session))
        }
    }

    private func dispatch(_ event: LCUEvent) {
        switch event.uri {
        case "/lol-gameflow/v1/gameflow-phase":
            if let phase = try? event.decode(GameflowPhase.self) {
                handler(.phase(phase))
            }
        case "/lol-champ-select/v1/session":
            if event.eventType == .delete {
                handler(.champSelectEnded)
            } else if let session = try? event.decode(ChampSelectSession.self) {
                handler(.champSelect(session))
            } else {
                logger.error("Could not decode champ-select session event")
            }
        default:
            break
        }
    }
}
