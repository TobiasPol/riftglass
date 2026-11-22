import LeagueKit
import Observation
import os

/// Root of the app: watches League processes, owns the LCU connection and switches subsystems
/// on and off according to `GameflowStateMachine` (PLAN §4.1).
@MainActor
@Observable
final class AppModel {
    private(set) var mode: AppMode = .dormant
    private(set) var isLCUConnected = false
    private(set) var setupError: String?
    let champSelect: ChampSelectCoordinator
    let inGame: InGameCoordinator
    let settings: AppSettings

    @ObservationIgnored private var machine = GameflowStateMachine()
    @ObservationIgnored private let watcher = ClientWatcher()
    @ObservationIgnored private var connection: LCUConnection?
    @ObservationIgnored private var watchTask: Task<Void, Never>?
    @ObservationIgnored private var regionTask: Task<Void, Never>?
    @ObservationIgnored private var postGameTask: Task<Void, Never>?
    @ObservationIgnored private var evaluator: LocalTrustEvaluator?
    @ObservationIgnored private let logger = Logger(subsystem: "de.polleydigital.riftglass", category: "AppModel")

    init(settings: AppSettings = .shared) {
        let champSelect = ChampSelectCoordinator(settings: settings)
        self.champSelect = champSelect
        self.settings = settings
        inGame = InGameCoordinator(champSelect: champSelect, settings: settings)
        do {
            evaluator = try LocalTrustEvaluator.bundled()
        } catch {
            setupError = String(localized: "Riot certificate missing from the app bundle.")
            logger.fault("riotgames.pem missing: \(error.localizedDescription, privacy: .public)")
        }
    }

    func start() {
        guard watchTask == nil else { return }
        let stream = watcher.processes()
        watchTask = Task { [weak self] in
            for await processes in stream {
                self?.handle(processes)
            }
        }
    }

    private func handle(_ processes: LeagueProcesses) {
        apply(.processesChanged(processes))
        guard let pid = processes.clientUxPID else { return disconnect() }
        if connection?.pid != pid {
            connect(to: pid)
        }
    }

    private func connect(to pid: pid_t) {
        disconnect()
        guard let evaluator else { return }
        let connection = LCUConnection(pid: pid, evaluator: evaluator) { [weak self] event in
            self?.handle(event)
        }
        self.connection = connection
        connection.start()
    }

    private func disconnect() {
        regionTask?.cancel()
        regionTask = nil
        postGameTask?.cancel()
        postGameTask = nil
        guard let connection else { return }
        connection.stop()
        self.connection = nil
        isLCUConnected = false
        champSelect.setClient(nil)
        apply(.lcuDisconnected)
    }

    private func handle(_ event: LCUConnectionEvent) {
        switch event {
        case let .connected(client):
            isLCUConnected = true
            champSelect.setClient(client)
            champSelect.prepare()
            rememberRegion(client)
        case let .phase(phase):
            apply(.phaseChanged(phase))
        case let .queue(queue):
            if let queue, queue != settings.lastQueue {
                logger.info("Queue \(queue.id ?? 0) → \(queue.mode.rawValue, privacy: .public)")
                settings.lastQueue = queue
            }
            champSelect.setQueue(queue)
        case let .champSelect(session):
            champSelect.update(session: session)
        case .champSelectEnded:
            champSelect.update(session: nil)
        }
    }

    /// The LCU is closed in game, so the region for rank lookups is stored while it runs.
    private func rememberRegion(_ client: LCUClient) {
        regionTask?.cancel()
        regionTask = Task { [weak self] in
            for attempt in 0 ..< 3 {
                guard !Task.isCancelled, let self, isLCUConnected else { return }
                if let region = try? await client.region() {
                    guard !Task.isCancelled, isLCUConnected else { return }
                    settings.region = region
                    return
                }
                if attempt < 2 {
                    try? await Task.sleep(for: .seconds(2))
                }
            }
        }
    }

    private func apply(_ input: GameflowStateMachine.Input) {
        guard let newMode = machine.handle(input) else { return }
        logger.info("Mode → \(String(describing: newMode), privacy: .public)")
        mode = newMode
        if newMode == .champSelect, let pid = machine.processes.clientUxPID {
            champSelect.activate(clientPID: pid)
        } else {
            champSelect.deactivate()
        }
        if newMode == .inGame, let evaluator {
            champSelect.prepare()
            inGame.start(evaluator: evaluator, rememberedQueue: settings.lastQueue)
        } else {
            inGame.stop()
        }
        if newMode == .postGame {
            fetchPostGameStats()
        } else {
            postGameTask?.cancel()
            postGameTask = nil
        }
    }

    private func fetchPostGameStats() {
        postGameTask?.cancel()
        postGameTask = Task { [weak self] in
            for attempt in 0 ..< 3 {
                guard !Task.isCancelled, let self, let lcu = champSelect.lcu else { return }
                if let stats = try? await lcu.endOfGameStats() {
                    guard !Task.isCancelled else { return }
                    inGame.applyEndOfGameStats(stats)
                    return
                }
                if attempt < 2 {
                    try? await Task.sleep(for: .seconds(2))
                }
            }
        }
    }
}
