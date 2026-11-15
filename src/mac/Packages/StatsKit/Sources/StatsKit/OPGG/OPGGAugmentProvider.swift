import Foundation

/// An ARAM: Mayhem augment as OP.GG rates it for one champion.
public struct AugmentStat: Codable, Equatable, Identifiable, Sendable {
    public enum Rarity: String, Codable, Sendable {
        case silver, gold, prismatic

        /// OP.GG's `rarity` codes on the augment page.
        init?(opgg code: Int) {
            switch code {
            case 1: self = .silver
            case 4: self = .gold
            case 8: self = .prismatic
            default: return nil
            }
        }
    }

    public let id: Int
    /// OP.GG's English name; the UI prefers the localized one from CommunityDragon.
    public let name: String
    /// OP.GG's tier for this augment on this champion: 0 = S (best), then 1…5.
    public let tier: Int
    /// OP.GG `popular`: a relative popularity score (0 … ~3.5, 1 ≈ average) – **not** a pick share.
    public let popularity: Double
    public let rarity: Rarity?
    public let iconURL: URL?

    public init(id: Int, name: String, tier: Int, popularity: Double, rarity: Rarity? = nil, iconURL: URL? = nil) {
        self.id = id
        self.name = name
        self.tier = tier
        self.popularity = popularity
        self.rarity = rarity
        self.iconURL = iconURL
    }

    /// OP.GG's badge: `S` for tier 0, else the number.
    public var tierLabel: String {
        tier <= 0 ? "S" : String(tier)
    }

    /// The order of OP.GG's own list: best tier first, within a tier the more popular augment first.
    public static func tierListOrder(_ lhs: AugmentStat, _ rhs: AugmentStat) -> Bool {
        if lhs.tier != rhs.tier {
            return lhs.tier < rhs.tier
        }
        if lhs.popularity != rhs.popularity {
            return lhs.popularity > rhs.popularity
        }
        return lhs.id < rhs.id
    }
}

/// OP.GG's ARAM: Mayhem augment tier list per champion, read from the public champion page.
///
/// The MCP tool `lol_list_aram_augments` is not usable for this: it only returns tiers 3–5, i.e. it
/// leaves out exactly the augments OP.GG rates best for the champion (docs/SPIKE.md). The page has
/// all tiers. One request per champion per cache lifetime; when op.gg is unreachable or its page
/// format changed, the last known list is used however old it is – tier lists move slowly, and a
/// wrong parse must never replace them.
public struct OPGGAugmentProvider: Sendable {
    private let getter: any HTTPGetting
    private let cache: ResponseCache
    private let userAgent: String

    public init(
        getter: any HTTPGetting = URLSessionGetter(),
        cache: ResponseCache = ResponseCache(name: "opgg-augments"),
        userAgent: String = "Riftglass"
    ) {
        self.getter = getter
        self.cache = cache
        self.userAgent = userAgent
    }

    public static let pagesURL = URL(string: "https://op.gg/lol/modes/aram-mayhem/")!

    /// OP.GG accepts the numeric champion ID in place of its name slug (62 ≙ `monkeyking`).
    public static func pageURL(championId: Int) -> URL {
        pagesURL.appending(path: "\(championId)/augments")
    }

    /// Every augment OP.GG lists for the champion, in OP.GG's order (`AugmentStat.tierListOrder`).
    public func augments(championId: Int) async throws -> [AugmentStat] {
        // v3: parsed page entries as JSON; v1/v2 held the MCP answer without the top tiers.
        let cacheKey = "aram-mayhem-augments-v3-\(championId)"
        if let cached = await cache.value(for: cacheKey).flatMap(Self.decode) {
            return cached
        }
        do {
            let html = try await getter.get(
                Self.pageURL(championId: championId),
                headers: ["User-Agent": userAgent, "Accept": "text/html"]
            )
            let stats = try OPGGAugmentPage.augments(fromHTML: html)
            if let encoded = try? JSONEncoder().encode(stats), let text = String(data: encoded, encoding: .utf8) {
                await cache.store(text, for: cacheKey)
            }
            return stats
        } catch {
            guard let stale = await cache.staleValue(for: cacheKey).flatMap(Self.decode) else { throw error }
            return stale
        }
    }

    private static func decode(_ text: String) -> [AugmentStat]? {
        try? JSONDecoder().decode([AugmentStat].self, from: Data(text.utf8))
    }
}
