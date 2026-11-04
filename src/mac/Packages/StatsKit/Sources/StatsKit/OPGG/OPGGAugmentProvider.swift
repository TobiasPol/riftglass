import Foundation

/// An ARAM: Mayhem augment with OP.GG's statistics for one champion.
public struct AugmentStat: Codable, Equatable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    /// Share of games in which the augment was picked (OP.GG `popular`, 0…1).
    public let pickRate: Double
    /// OP.GG `performance`: "performance score for the augment on the selected champion" – higher is
    /// better, roughly 60…140; values with a tiny pick rate are noise (see `AugmentRanking`).
    public let performance: Double?

    public init(id: Int, name: String, pickRate: Double, performance: Double? = nil) {
        self.id = id
        self.name = name
        self.pickRate = pickRate
        self.performance = performance
    }
}

/// ARAM: Mayhem augment statistics per champion from OP.GG's `lol_list_aram_augments`.
///
/// OP.GG's `tier` field is not used: it only buckets the pick rate (3 = most picked … 5 = rare).
public struct OPGGAugmentProvider: Sendable {
    private let client: OPGGClient
    private let cache: ResponseCache

    public init(client: OPGGClient = OPGGClient(), cache: ResponseCache = ResponseCache(name: "opgg-augments")) {
        self.client = client
        self.cache = cache
    }

    /// All augments OP.GG lists for the champion, most picked first.
    public func augments(championId: Int, limit: Int? = nil) async throws -> [AugmentStat] {
        // v2: the cached text includes `performance`; v1 entries lack it.
        let cacheKey = "aram-augments-v2-\(championId)"
        let text: String
        if let cached = await cache.value(for: cacheKey) {
            text = cached
        } else {
            text = try await client.callTool("lol_list_aram_augments", arguments: [
                "champion_id": .int(championId),
                "desired_output_fields": .strings(["data.augments[].{id,name,performance,popular}"])
            ])
            await cache.store(text, for: cacheKey)
        }
        let all = try Self.augments(from: OPGGNotation.parse(text))
        return limit.map { Array(all.prefix($0)) } ?? all
    }

    /// Sorted by pick share, most popular first. Entries without a name (OP.GG sends `null` for some
    /// rarely picked augments) are dropped.
    static func augments(from value: NotationValue) -> [AugmentStat] {
        let entries = value["data"]?["augments"]?.list ?? []
        return entries.compactMap { entry -> AugmentStat? in
            guard let id = entry["id"]?.int, let name = entry["name"]?.string, !name.isEmpty else { return nil }
            return AugmentStat(
                id: id,
                name: name,
                pickRate: entry["popular"]?.double ?? 0,
                performance: entry["performance"]?.double
            )
        }
        .sorted { ($0.pickRate, $1.id) > ($1.pickRate, $0.id) }
    }
}
