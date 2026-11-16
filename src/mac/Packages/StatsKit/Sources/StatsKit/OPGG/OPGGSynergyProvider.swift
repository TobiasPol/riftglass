import Foundation

/// How a duo of champions in two lanes does together, from the first champion's point of view.
public struct Synergy: Equatable, Identifiable, Sendable {
    /// The partner champion (LCU ID).
    public let id: Int
    public let name: String
    /// Win rate of the duo.
    public let winRate: Double
    public let games: Int
    /// OP.GG synergy tier, 0 = OP … 4 = C.
    public let tier: Int?

    public init(id: Int, name: String, winRate: Double, games: Int, tier: Int? = nil) {
        self.id = id
        self.name = name
        self.winRate = winRate
        self.games = games
        self.tier = tier
    }
}

/// The most played partners of a champion in another lane, from `lol_get_champion_synergies`
/// (10 per lane pair, most games first). Duos are symmetric, so an ally's list says how well each
/// option for the player's own lane goes with that ally.
public struct OPGGSynergyProvider: Sendable {
    static let fields = [
        "data.synergies[].{synergy_champion_id,synergy_champion_name,play,win_rate}",
        "data.synergies[].synergy_tier_data.{tier}"
    ]
    /// Duo samples below this are noise.
    static let minimumGames = 300

    private let client: OPGGClient
    private let cache: ResponseCache

    public init(client: OPGGClient = OPGGClient(), cache: ResponseCache = ResponseCache(name: "opgg-synergies")) {
        self.client = client
        self.cache = cache
    }

    /// - Parameter championName: OP.GG's English name (`MetaChampion.name`). Unlike the other tools,
    ///   this one rejects Data Dragon keys (`LEESIN`, `MONKEYKING`).
    public func synergies(of championName: String, in role: Role, with partnerRole: Role) async throws -> [Synergy] {
        let champion = Self.argument(forName: championName)
        let cacheKey = "\(champion)-\(role.opggPosition)-\(partnerRole.opggPosition)"
        if let cached = await cache.value(for: cacheKey), let value = try? OPGGNotation.parse(cached) {
            return Self.synergies(from: value)
        }
        let text = try await cache.fetchOnce(for: cacheKey) { [client] in
            let text = try await client.callTool("lol_get_champion_synergies", arguments: [
                "champion": .string(champion),
                "my_position": .string(role.opggPosition),
                "synergy_position": .string(partnerRole.opggPosition),
                "desired_output_fields": .strings(Self.fields)
            ])
            _ = try OPGGNotation.parse(text) // cached only when it parses
            return text
        }
        return try Self.synergies(from: OPGGNotation.parse(text))
    }

    /// "Lee Sin" → `LEE_SIN`, "Dr. Mundo" → `DR_MUNDO`, "Kog'Maw" → `KOGMAW`, "Nunu & Willump" →
    /// `NUNU_WILLUMP` (verified against the live tool, docs/SPIKE.md).
    static func argument(forName name: String) -> String {
        name.split(whereSeparator: \.isWhitespace)
            .map { RoleRates.normalized(String($0)).uppercased() }
            .filter { !$0.isEmpty }
            .joined(separator: "_")
    }

    static func synergies(from value: NotationValue) -> [Synergy] {
        (value["data"]?["synergies"]?.list ?? []).compactMap { entry -> Synergy? in
            guard let id = entry["synergy_champion_id"]?.int, let name = entry["synergy_champion_name"]?.string,
                  let winRate = entry["win_rate"]?.double, let games = entry["play"]?.int,
                  games >= minimumGames
            else { return nil }
            return Synergy(
                id: id,
                name: name,
                winRate: winRate,
                games: games,
                tier: entry["synergy_tier_data"]?["tier"]?.int
            )
        }
    }
}
