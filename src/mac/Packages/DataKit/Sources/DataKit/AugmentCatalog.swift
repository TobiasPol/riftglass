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
/// when offline. The in-memory copy follows the same rule (a stale one is retried after a few minutes),
/// so a patch day mid-session still brings new augments.
public actor AugmentCatalog {
    public static let baseURL =
        URL(string: "https://raw.communitydragon.org/latest/plugins/rcp-be-lol-game-data/global/")!
    static let timeToLive: TimeInterval = 24 * 3600
    /// Retry interval after falling back to a stale copy.
    static let retryInterval: TimeInterval = 10 * 60

    private let fetcher: any HTTPFetching
    private let cacheFile: URL
    /// CommunityDragon locale folder (`de_de`, `default` = en_US).
    private let locale: String
    private var loaded: (augments: [Int: AugmentInfo], validUntil: Date)?
    private let now: @Sendable () -> Date
    private let logger = Logger(subsystem: "de.polleydigital.riftglass", category: "AugmentCatalog")

    public init(
        fetcher: any HTTPFetching = URLSessionFetcher(),
        cacheDirectory: URL = DataDragon.defaultCacheDirectory.deletingLastPathComponent()
            .appending(path: "cdragon", directoryHint: .isDirectory),
        locale: String = "de_de",
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.fetcher = fetcher
        self.locale = locale
        self.now = now
        cacheFile = cacheDirectory.appending(path: "cherry-augments-\(locale).json")
    }

    /// All augments with a rarity, by ID.
    public func augments() async throws -> [Int: AugmentInfo] {
        if let loaded, now() < loaded.validUntil {
            return loaded.augments
        }
        let (data, freshUntil) = try await fileData()
        let result = try Self.parse(data)
        loaded = (result, freshUntil)
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

    /// The file's data and until when it counts as fresh.
    private func fileData() async throws -> (Data, Date) {
        let attributes = try? FileManager.default.attributesOfItem(atPath: cacheFile.path)
        let modified = attributes?[.modificationDate] as? Date
        let cached = try? Data(contentsOf: cacheFile)
        if let cached, let modified, now().timeIntervalSince(modified) < Self.timeToLive {
            return (cached, modified.addingTimeInterval(Self.timeToLive))
        }
        do {
            let data = try await fetcher.data(from: Self.baseURL.appending(path: "\(locale)/v1/cherry-augments.json"))
            _ = try Self.parse(data) // never cache an unusable answer
            try? FileManager.default.createDirectory(
                at: cacheFile.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? data.write(to: cacheFile, options: .atomic)
            try? FileManager.default.setAttributes([.modificationDate: now()], ofItemAtPath: cacheFile.path)
            return (data, now().addingTimeInterval(Self.timeToLive))
        } catch {
            guard let cached else { throw error }
            logger.notice("CommunityDragon unavailable, using cached augments")
            return (cached, now().addingTimeInterval(Self.retryInterval))
        }
    }
}

private struct RawAugment: Decodable {
    let id: Int
    let nameTRA: String
    let augmentSmallIconPath: String?
    let rarity: String
}
