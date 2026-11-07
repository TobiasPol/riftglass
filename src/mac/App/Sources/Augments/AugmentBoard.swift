import DataKit
import Foundation
import os
import StatsKit

/// A champion's ARAM: Mayhem augments, ranked **within each rarity** – one selection screen offers
/// three augments of a single rarity, so a Silver augment only competes with other Silver ones.
struct AugmentBoard: Equatable, Sendable {
    struct Entry: Equatable, Identifiable, Sendable {
        let ranked: RankedAugment
        /// Localized name (CommunityDragon, matches the client), else OP.GG's English name.
        let name: String
        let iconURL: URL?

        var id: Int {
            ranked.id
        }
    }

    struct Column: Equatable, Identifiable, Sendable {
        /// Nil when rarities are unknown (CommunityDragon unreachable): one ranking over everything.
        let rarity: AugmentRarity?
        let entries: [Entry]

        var id: String {
            rarity?.rawValue ?? "all"
        }
    }

    let championId: Int
    /// Prismatic, Gold, Silver – empty rarities are left out.
    let columns: [Column]

    var isEmpty: Bool {
        columns.allSatisfy(\.entries.isEmpty)
    }

    var iconURLs: [URL] {
        columns.flatMap { $0.entries.compactMap(\.iconURL) }
    }

    static func make(championId: Int, stats: [AugmentStat], catalog: [Int: AugmentInfo]) -> AugmentBoard {
        func entries(_ stats: [AugmentStat]) -> [Entry] {
            AugmentRanking.rank(stats).map { ranked in
                let info = catalog[ranked.id]
                return Entry(ranked: ranked, name: info?.name ?? ranked.stat.name, iconURL: info?.iconURL)
            }
        }
        guard !catalog.isEmpty else {
            return AugmentBoard(championId: championId, columns: [Column(rarity: nil, entries: entries(stats))])
        }
        // Augments missing from the catalog are no longer in the game.
        let columns = AugmentRarity.allCases.reversed().map { rarity in
            Column(rarity: rarity, entries: entries(stats.filter { catalog[$0.id]?.rarity == rarity }))
        }
        return AugmentBoard(championId: championId, columns: columns.filter { !$0.entries.isEmpty })
    }
}

/// Loads boards for champ select and the in-game overlay. OP.GG answers are disk-cached (6 h) and
/// the catalog is held in memory, so the second load for the same champion costs nothing.
struct AugmentBoardLoader: Sendable {
    let provider = OPGGAugmentProvider()
    let catalog = AugmentCatalog(locale: GameDataLocale.communityDragon)
    private let logger = Logger(subsystem: "de.polleydigital.riftglass", category: "Augments")

    func board(championId: Int) async throws -> AugmentBoard {
        async let stats = provider.augments(championId: championId)
        let infos: [Int: AugmentInfo]
        do {
            infos = try await catalog.augments()
        } catch {
            // Rarities are a refinement; without them the board is a single ranking.
            logger.notice("Augment catalog unavailable: \(String(describing: error), privacy: .public)")
            infos = [:]
        }
        return try await AugmentBoard.make(championId: championId, stats: stats, catalog: infos)
    }
}
