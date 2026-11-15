import DataKit
import Foundation
import os
import StatsKit

/// A champion's ARAM: Mayhem augments in OP.GG's tier order, **split by rarity** – one selection
/// screen offers three augments of a single rarity, so a Silver augment only competes with other
/// Silver ones.
struct AugmentBoard: Equatable, Sendable {
    struct Entry: Equatable, Identifiable, Sendable {
        let stat: AugmentStat
        /// Localized name (CommunityDragon, matches the client), else OP.GG's English name.
        let name: String
        let iconURL: URL?

        var id: Int {
            stat.id
        }
    }

    struct Column: Equatable, Identifiable, Sendable {
        let rarity: AugmentRarity
        /// Best tier first, as on OP.GG.
        let entries: [Entry]

        var id: String {
            rarity.rawValue
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

    /// `catalog` only refines the board (localized names, game icons, a rarity OP.GG left out); it may
    /// be empty. Augments without any rarity are no longer in the game and are dropped.
    static func make(championId: Int, stats: [AugmentStat], catalog: [Int: AugmentInfo]) -> AugmentBoard {
        var byRarity: [AugmentRarity: [Entry]] = [:]
        for stat in stats.sorted(by: AugmentStat.tierListOrder) {
            let info = catalog[stat.id]
            guard let rarity = stat.rarity.flatMap({ AugmentRarity(rawValue: $0.rawValue) }) ?? info?.rarity
            else { continue }
            let entry = Entry(stat: stat, name: info?.name ?? stat.name, iconURL: info?.iconURL ?? stat.iconURL)
            byRarity[rarity, default: []].append(entry)
        }
        let columns = AugmentRarity.allCases.reversed().compactMap { rarity in
            byRarity[rarity].map { Column(rarity: rarity, entries: $0) }
        }
        return AugmentBoard(championId: championId, columns: columns)
    }
}

/// Loads boards for champ select and the in-game overlay. OP.GG's tier list is disk-cached (6 h) and
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
            // Localized names are a refinement; OP.GG's page has English names, rarities and icons.
            logger.notice("Augment catalog unavailable: \(String(describing: error), privacy: .public)")
            infos = [:]
        }
        return try await AugmentBoard.make(championId: championId, stats: stats, catalog: infos)
    }
}
