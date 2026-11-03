import Foundation
import os

/// WAMP WebSocket connection to the LCU with reconnect + exponential backoff.
///
/// What the stream delivers: `.subscribed` after every (re)connect – events may have been missed,
/// so the consumer should re-read state via REST – and the events for the requested URIs.
public enum LCUStreamMessage: Equatable, Sendable {
    case subscribed
    case event(LCUEvent)
}

/// `messages()` yields only events for `uris`. The stream ends when `stop()` is called; connection
/// losses are retried until then (the LCU restarts on a new port → the owner creates a new stream).
public actor LCUEventStream {
    public static let defaultURIs: Set<String> = [
        "/lol-gameflow/v1/gameflow-phase",
        // The queue: changes on mode switches inside the lobby, which raise no phase event.
        "/lol-gameflow/v1/session",
        "/lol-champ-select/v1/session"
    ]

    private let credentials: LCUCredentials
    private let uris: Set<String>
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var runner: Task<Void, Never>?
    private let logger = Logger(subsystem: "de.polleydigital.riftglass", category: "LCUEventStream")

    public init(credentials: LCUCredentials, evaluator: LocalTrustEvaluator, uris: Set<String> = defaultURIs) {
        self.credentials = credentials
        self.uris = uris
        let delegate = LocalTrustDelegate(evaluator: evaluator, ports: [credentials.port])
        session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
    }

    public func messages() -> AsyncStream<LCUStreamMessage> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: LCUStreamMessage.self,
            bufferingPolicy: .bufferingNewest(32)
        )
        runner?.cancel()
        runner = Task { [weak self] in
            await self?.run(continuation)
            continuation.finish()
        }
        continuation.onTermination = { [weak self] _ in
            Task { await self?.stop() }
        }
        return stream
    }

    public func stop() {
        runner?.cancel()
        runner = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session.invalidateAndCancel()
    }

    private func run(_ continuation: AsyncStream<LCUStreamMessage>.Continuation) async {
        var backoff = Backoff()
        while !Task.isCancelled {
            let receivedAny = await connectAndReceive(continuation)
            if receivedAny {
                backoff.reset()
            }
            let delay = backoff.next()
            logger.info("LCU WebSocket closed, reconnecting in \(delay, format: .fixed(precision: 1)) s")
            try? await Task.sleep(for: .seconds(delay))
        }
    }

    /// Returns whether at least one message arrived (used to reset the backoff).
    private func connectAndReceive(_ continuation: AsyncStream<LCUStreamMessage>.Continuation) async -> Bool {
        let task = session.webSocketTask(with: makeRequest())
        task.maximumMessageSize = 8 * 1024 * 1024
        self.task = task
        task.resume()
        var receivedAny = false
        while !Task.isCancelled {
            guard let message = try? await task.receive() else { break }
            receivedAny = true
            await handle(message, on: task, continuation: continuation)
        }
        task.cancel(with: .goingAway, reason: nil)
        return receivedAny
    }

    private func handle(
        _ message: URLSessionWebSocketTask.Message,
        on task: URLSessionWebSocketTask,
        continuation: AsyncStream<LCUStreamMessage>.Continuation
    ) async {
        let data: Data
        switch message {
        case let .string(text): data = Data(text.utf8)
        case let .data(bytes): data = bytes
        @unknown default: return
        }
        switch WAMPMessage.parse(data, keeping: uris) {
        case .welcome:
            try? await task.send(.string(WAMPMessage.subscribe()))
            continuation.yield(.subscribed)
        case let .event(event):
            continuation.yield(.event(event))
        case nil:
            break
        }
    }

    private func makeRequest() -> URLRequest {
        // Force-unwrap safe: host and port are numeric.
        // swiftlint:disable:next force_unwrapping
        let url = URL(string: "wss://127.0.0.1:\(credentials.port)/")!
        var request = URLRequest(url: url)
        request.setValue(credentials.basicAuthorization, forHTTPHeaderField: "Authorization")
        request.setValue("wamp", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        return request
    }
}

/// Exponential backoff: 0.5 s, 1 s, 2 s … capped at 10 s.
struct Backoff {
    private var attempt = 0
    let base: Double = 0.5
    let cap: Double = 10

    mutating func next() -> Double {
        defer { attempt += 1 }
        return min(cap, base * pow(2, Double(attempt)))
    }

    mutating func reset() {
        attempt = 0
    }
}
