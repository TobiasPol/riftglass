import Foundation
import LeagueKit
import os
import StatsKit

/// Looks up each player's solo-queue rank once per game via OP.GG (max. 4 requests at a time).
@MainActor
final class RankLookup {
    private struct Request: Sendable {
        let key: String
        let gameName: String
        let tagLine: String
    }

    private let provider: OPGGRankProvider
    private var requested: Set<String> = []
    /// Failed lookups wait this long before the next attempt (be gentle with OP.GG).
    private let retryDelay: TimeInterval = 30
    private var failedAt: [String: Date] = [:]
    private let logger = Logger(subsystem: "de.polleydigital.riftglass", category: "Ranks")

    init(provider: OPGGRankProvider = OPGGRankProvider()) {
        self.provider = provider
    }

    func reset() {
        requested = []
        failedAt = [:]
    }

    /// Calls `update` for every resolved player, keyed by `LivePlayer.displayID`.
    /// Failed lookups are retried with a later snapshot, at most every `retryDelay` seconds.
    func lookUp(
        _ players: [LivePlayer],
        region: String,
        update: @escaping @MainActor (String, PlayerRank) -> Void
    ) {
        let requests = players.compactMap { player -> Request? in
            let key = player.displayID
            guard player.isBot != true, !requested.contains(key),
                  failedAt[key].map({ Date().timeIntervalSince($0) > retryDelay }) ?? true,
                  let parts = player.riotIDParts
            else { return nil }
            return Request(key: key, gameName: parts.gameName, tagLine: parts.tagLine)
        }
        guard !requests.isEmpty else { return }
        requests.forEach { requested.insert($0.key) }
        logger.info("Looking up \(requests.count) ranks in \(region, privacy: .public)")
        Task {
            await withTaskGroup(of: (String, PlayerRank?).self) { group in
                for (index, request) in requests.enumerated() {
                    if index >= 4, let result = await group.next() {
                        deliver(result, update: update)
                    }
                    group.addTask { [provider] in
                        let rank = try? await provider.soloRank(
                            gameName: request.gameName,
                            tagLine: request.tagLine,
                            region: region
                        )
                        return (request.key, rank)
                    }
                }
                for await result in group {
                    deliver(result, update: update)
                }
            }
        }
    }

    private func deliver(_ result: (String, PlayerRank?), update: @MainActor (String, PlayerRank) -> Void) {
        guard let rank = result.1 else {
            let delay = Int(retryDelay)
            logger.notice("Rank lookup failed – retrying in \(delay) s")
            requested.remove(result.0)
            failedAt[result.0] = Date()
            return
        }
        logger.info("Rank resolved")
        update(result.0, rank)
    }
}
