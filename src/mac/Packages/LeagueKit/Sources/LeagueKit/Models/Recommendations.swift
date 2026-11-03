import Foundation

/// Element of `GET /lol-perks/v1/recommended-pages/champion/{id}/position/{POS}/map/11` –
/// Riot's own rune (and summoner spell) recommendations, as shown by the client.
public struct RecommendedRunePage: Decodable, Equatable, Sendable {
    public struct Perk: Decodable, Equatable, Sendable {
        public let id: Int
        public let name: String?
    }

    public let primaryPerkStyleId: Int
    public let secondaryPerkStyleId: Int
    public let perks: [Perk]
    public let summonerSpellIds: [Int]?
    public let position: String?
    public let keystone: Perk?
    public let recommendationId: String?

    public var perkIds: [Int] {
        perks.map(\.id)
    }
}

/// `GET /lol-perks/v1/recommended-champion-positions` → `{ "103": { "recommendedPositions": [...] } }`.
public struct RecommendedPositions: Decodable, Equatable, Sendable {
    public let recommendedPositions: [String]
}

public extension LCURequesting {
    func recommendedPages(championId: Int, position: String) async throws -> [RecommendedRunePage] {
        try await get("/lol-perks/v1/recommended-pages/champion/\(championId)/position/\(position)/map/11")
    }

    /// Riot's recommended positions for a champion (first = main role), empty if unknown.
    func recommendedPositions(championId: Int) async throws -> [String] {
        let all: [String: RecommendedPositions] = try await get("/lol-perks/v1/recommended-champion-positions")
        return all[String(championId)]?.recommendedPositions ?? []
    }

    /// Platform region (e.g. `EUW`) for OP.GG rank lookups.
    func region() async throws -> String {
        let value: RegionLocale = try await get("/riotclient/region-locale")
        return value.region
    }
}

/// `GET /riotclient/region-locale`
struct RegionLocale: Decodable {
    let region: String
}
