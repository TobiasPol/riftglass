import Foundation
import os

/// Polls the Live Client Data API (port 2999) once per second – only while a game runs.
///
/// Never uses `allgamedata` (its event list grows all game). `snapshots()` only yields when the
/// data changed, so the UI does not re-render for nothing.
public actor LiveClient {
    public static let port = 2999

    private let session: URLSession
    private let interval: Duration
    private var runner: Task<Void, Never>?
    private let logger = Logger(subsystem: "de.polleydigital.riftglass", category: "LiveClient")

    public init(evaluator: LocalTrustEvaluator, interval: Duration = .seconds(1)) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 2
        configuration.httpMaximumConnectionsPerHost = 3
        let delegate = LocalTrustDelegate(evaluator: evaluator, ports: [Self.port])
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        self.interval = interval
    }

    public func snapshots() -> AsyncStream<LiveGameSnapshot> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: LiveGameSnapshot.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        runner?.cancel()
        runner = Task { [weak self] in
            await self?.poll(continuation)
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
    }

    deinit {
        session.invalidateAndCancel()
    }

    private func poll(_ continuation: AsyncStream<LiveGameSnapshot>.Continuation) async {
        var last: LiveGameSnapshot?
        while !Task.isCancelled {
            if let snapshot = await fetchSnapshot(), snapshot != last {
                last = snapshot
                continuation.yield(snapshot)
            }
            try? await Task.sleep(for: interval, tolerance: .milliseconds(250))
        }
    }

    /// Nil while the game is still loading (the API answers 404/connection refused until then).
    private func fetchSnapshot() async -> LiveGameSnapshot? {
        async let stats: LiveGameStats? = fetch("gamestats")
        async let active: LiveActivePlayer? = fetch("activeplayer")
        async let players: [LivePlayer]? = fetch("playerlist")
        guard let stats = await stats, let players = await players else { return nil }
        return await LiveGameSnapshot(stats: stats, activePlayer: active, players: players)
    }

    private func fetch<T: Decodable & Sendable>(_ endpoint: String) async -> T? {
        // Force-unwrap safe: constant host/port and a fixed endpoint name.
        // swiftlint:disable:next force_unwrapping
        let url = URL(string: "https://127.0.0.1:\(Self.port)/liveclientdata/\(endpoint)")!
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            logger.error("Live Client \(endpoint, privacy: .public) decode failed: \(error, privacy: .public)")
            return nil
        }
    }
}
