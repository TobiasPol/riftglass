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

    @ObservationIgnored private var machine = GameflowStateMachine()
    @ObservationIgnored private let watcher = ClientWatcher()
    @ObservationIgnored private var connection: LCUConnection?
    @ObservationIgnored private var watchTask: Task<Void, Never>?
    @ObservationIgnored private var evaluator: LocalTrustEvaluator?
    @ObservationIgnored private let logger = Logger(subsystem: "de.polleydigital.riftglass", category: "AppModel")

    init(champSelect: ChampSelectCoordinator = ChampSelectCoordinator()) {
        self.champSelect = champSelect
        do {
            evaluator = try LocalTrustEvaluator.bundled()
        } catch {
            setupError = "Riot-Zertifikat fehlt im App-Bundle."
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
        guard let connection else { return }
        connection.stop()
        self.connection = nil
        isLCUConnected = false
        champSelect.setActions(nil)
        apply(.lcuDisconnected)
    }

    private func handle(_ event: LCUConnectionEvent) {
        switch event {
        case let .connected(client):
            isLCUConnected = true
            champSelect.setActions(ChampSelectActions(lcu: client))
            champSelect.prepare()
        case let .phase(phase):
            apply(.phaseChanged(phase))
        case let .champSelect(session):
            champSelect.update(session: session)
        case .champSelectEnded:
            champSelect.update(session: nil)
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
    }
}
