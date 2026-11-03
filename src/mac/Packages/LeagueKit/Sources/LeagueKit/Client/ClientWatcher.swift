import AppKit
import os

/// Detects League client/game processes via KVO on `NSWorkspace.runningApplications`.
///
/// KVO instead of `didLaunchApplicationNotification`: the launch notification is not sent for
/// background (LSUIElement) processes such as `LeagueClient`. No timers – zero wake-ups while
/// League is closed.
@MainActor
public final class ClientWatcher {
    private let workspace: NSWorkspace
    private var observation: NSKeyValueObservation?
    private var continuation: AsyncStream<LeagueProcesses>.Continuation?
    private var last: LeagueProcesses?
    private let logger = Logger(subsystem: "de.polleydigital.riftglass", category: "ClientWatcher")

    public init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    /// Emits the current state immediately and then every change.
    public func processes() -> AsyncStream<LeagueProcesses> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: LeagueProcesses.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        self.continuation = continuation
        last = nil
        observation = workspace.observe(\.runningApplications, options: [.initial, .new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.publish() }
        }
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }
        return stream
    }

    public func stop() {
        observation?.invalidate()
        observation = nil
        continuation?.finish()
        continuation = nil
    }

    private func publish() {
        let running = workspace.runningApplications.map {
            RunningProcess(bundleID: $0.bundleIdentifier, pid: $0.processIdentifier)
        }
        let current = LeagueProcesses(from: running)
        guard current != last else { return }
        last = current
        logger.debug("League processes changed: client=\(current.isClientRunning) game=\(current.isGameRunning)")
        continuation?.yield(current)
    }
}
