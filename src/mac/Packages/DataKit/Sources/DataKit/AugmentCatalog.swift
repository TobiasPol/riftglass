import Foundation
import os

/// Rarity of an Arena / ARAM: Mayhem augment. One selection screen offers a single rarity.
public enum AugmentRarity: String, CaseIterable, Codable, Sendable {
    case silver
    case gold
    case prismatic

    /// CommunityDragon's `kSilver` / `kGold` / `kPrismatic`; event choices (`kEventChoice`) are none.
    init?(communityDragon raw: String) {
        switch raw {
        case "kSilver": self = .silver
        case "kGold": self = .gold
        case "kPrismatic": self = .prismatic
        default: return nil
        }
    }
}

/// Static augment data: localized name, rarity and icon.
public struct AugmentInfo: Equatable, Sendable {
    public let id: Int
    public let name: String
    public let rarity: AugmentRarity
    public let iconURL: URL?
}

/// Augment metadata from CommunityDragon's `cherry-augments.json` (Arena and ARAM: Mayhem share it;
/// IDs match OP.GG's `lol_list_aram_augments`). Riot's Data Dragon has no augment data.
///
/// CommunityDragon only serves `latest`, so the file is cached for a day and the stale copy is used
/// when offline.
public actor AugmentCatalog {
    public static let baseURL =
        URL(string: "https://raw.communitydragon.org/latest/plugins/rcp-be-lol-game-data/global/")!
    static let timeToLive: TimeInterval = 24 * 3600

    private let fetcher: any HTTPFetching
    private let cacheFile: URL
    /// CommunityDragon locale folder (`de_de`, `default` = en_US).
    private let locale: String
    private var loaded: [Int: AugmentInfo]?
    private let logger = Logger(subsystem: "de.polleydigital.riftglass", category: "AugmentCatalog")

    public init(
        fetcher: any HTTPFetching = URLSessionFetcher(),
        cacheDirectory: URL = DataDragon.defaultCacheDirectory.deletingLastPathComponent()
            .appending(path: "cdragon", directoryHint: .isDirectory),
        locale: String = "de_de"
    ) {
        self.fetcher = fetcher
        self.locale = locale
        cacheFile = cacheDirectory.appending(path: "cherry-augments-\(locale).json")
    }

    /// All augments with a rarity, by ID.
    public func augments() async throws -> [Int: AugmentInfo] {
        if let loaded {
            return loaded
        }
        let data = try await fileData()
        let result = try Self.parse(data)
        loaded = result
        return result
    }

    static func parse(_ data: Data) throws -> [Int: AugmentInfo] {
        let raw = try JSONDecoder().decode([RawAugment].self, from: data)
        let infos = raw.compactMap { entry -> AugmentInfo? in
            guard let rarity = AugmentRarity(communityDragon: entry.rarity), !entry.nameTRA.isEmpty else { return nil }
            return AugmentInfo(
                id: entry.id,
                name: entry.nameTRA,
                rarity: rarity,
                iconURL: entry.augmentSmallIconPath.flatMap(iconURL(forGamePath:))
            )
        }
        return Dictionary(infos.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// `/lol-game-data/assets/ASSETS/UX/…/X_small.png` → lowercased path below `global/default/`.
    static func iconURL(forGamePath path: String) -> URL? {
        let prefix = "/lol-game-data/assets/"
        guard path.hasPrefix(prefix) else { return nil }
        return baseURL.appending(path: "default/" + path.dropFirst(prefix.count).lowercased())
    }

    private func fileData() async throws -> Data {
        let attributes = try? FileManager.default.attributesOfItem(atPath: cacheFile.path)
        let modified = attributes?[.modificationDate] as? Date
        let cached = try? Data(contentsOf: cacheFile)
        if let cached, let modified, Date().timeIntervalSince(modified) < Self.timeToLive {
            return cached
        }
        do {
            let data = try await fetcher.data(from: Self.baseURL.appending(path: "\(locale)/v1/cherry-augments.json"))
            _ = try Self.parse(data) // never cache an unusable answer
            try? FileManager.default.createDirectory(
                at: cacheFile.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? data.write(to: cacheFile, options: .atomic)
            return data
        } catch {
            guard let cached else { throw error }
            logger.notice("CommunityDragon unavailable, using cached augments")
            return cached
        }
    }
}

private struct RawAugment: Decodable {
    let id: Int
    let nameTRA: String
    let augmentSmallIconPath: String?
    let rarity: String
}
