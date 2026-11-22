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
    private var streamID: UUID?
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
        let id = UUID()
        streamID = id
        runner = Task { [weak self] in
            await self?.poll(continuation)
            continuation.finish()
        }
        continuation.onTermination = { [weak self] _ in
            Task { await self?.stopIfCurrent(id) }
        }
        return stream
    }

    public func stop() {
        streamID = nil
        runner?.cancel()
        runner = nil
    }

    private func stopIfCurrent(_ id: UUID) {
        guard streamID == id else { return }
        stop()
    }

    deinit {
        session.invalidateAndCancel()
    }

    private func poll(_ continuation: AsyncStream<LiveGameSnapshot>.Continuation) async {
        var last: LiveGameSnapshot?
        var eventsByID: [Int: LiveGameEvent] = [:]
        var nextEventID = 0
        var lastGameTime: Double = 0
        while !Task.isCancelled {
            let result = await fetchSnapshot(nextEventID: nextEventID)
            guard !Task.isCancelled else { break }
            if let result {
                if result.snapshot.stats.gameTime < lastGameTime {
                    eventsByID = [:]
                    nextEventID = 0
                }
                lastGameTime = result.snapshot.stats.gameTime
                for event in result.newEvents {
                    eventsByID[event.eventID] = event
                }
                if let maxID = eventsByID.keys.max() {
                    nextEventID = max(nextEventID, maxID + 1)
                }
                let events = eventsByID.values.sorted { $0.eventID < $1.eventID }
                let full = LiveGameSnapshot(
                    stats: result.snapshot.stats,
                    activePlayer: result.snapshot.activePlayer,
                    players: result.snapshot.players,
                    events: events
                )
                if full != last {
                    last = full
                    continuation.yield(full)
                }
            }
            try? await Task.sleep(for: interval, tolerance: .milliseconds(250))
        }
    }

    /// Nil while the game is still loading (the API answers 404/connection refused until then).
    private func fetchSnapshot(nextEventID: Int) async -> (snapshot: LiveGameSnapshot, newEvents: [LiveGameEvent])? {
        async let stats: LiveGameStats? = fetch("gamestats")
        async let active: LiveActivePlayer? = fetch("activeplayer")
        async let players: [LivePlayer]? = fetch("playerlist")
        async let response: LiveEventsResponse? = fetch("eventdata?eventID=\(nextEventID)")
        guard let stats = await stats, let players = await players else { return nil }
        let snapshot = await LiveGameSnapshot(stats: stats, activePlayer: active, players: players)
        let newEvents = await response?.events ?? []
        return (snapshot, newEvents)
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
