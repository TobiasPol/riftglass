import Foundation

/// An ARAM: Mayhem augment with how often players of this champion take it.
public struct AugmentStat: Equatable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    /// Share of games in which the augment was picked (OP.GG `popular`, 0…1).
    public let pickRate: Double

    public init(id: Int, name: String, pickRate: Double) {
        self.id = id
        self.name = name
        self.pickRate = pickRate
    }
}

/// Popular ARAM: Mayhem augments per champion from OP.GG's `lol_list_aram_augments`.
///
/// Only the pick share is shown: OP.GG's `tier`/`performance` fields are undocumented, and
/// Riftglass does not present augment picks as instructions (docs/COMPLIANCE.md).
public struct OPGGAugmentProvider: Sendable {
    private let client: OPGGClient
    private let cache: ResponseCache

    public init(client: OPGGClient = OPGGClient(), cache: ResponseCache = ResponseCache(name: "opgg-augments")) {
        self.client = client
        self.cache = cache
    }

    public func augments(championId: Int, limit: Int = 8) async throws -> [AugmentStat] {
        let cacheKey = "aram-augments-\(championId)"
        let text: String
        if let cached = await cache.value(for: cacheKey) {
            text = cached
        } else {
            text = try await client.callTool("lol_list_aram_augments", arguments: [
                "champion_id": .int(championId),
                "desired_output_fields": .strings(["data.augments[].{id,name,tier,popular}"])
            ])
            await cache.store(text, for: cacheKey)
        }
        return try Array(Self.augments(from: OPGGNotation.parse(text)).prefix(limit))
    }

    /// Sorted by pick share, most popular first.
    static func augments(from value: NotationValue) -> [AugmentStat] {
        let entries = value["data"]?["augments"]?.list ?? []
        return entries.compactMap { entry -> AugmentStat? in
            guard let id = entry["id"]?.int, let name = entry["name"]?.string else { return nil }
            return AugmentStat(id: id, name: name, pickRate: entry["popular"]?.double ?? 0)
        }
        .sorted { $0.pickRate > $1.pickRate }
    }
}
