import Foundation

/// Solo-queue rank of a player.
public struct PlayerRank: Equatable, Sendable {
    public let tier: String?
    public let division: Int?
    public let leaguePoints: Int?
    public let wins: Int?
    public let losses: Int?

    public static let unranked = PlayerRank(tier: nil, division: nil, leaguePoints: nil, wins: nil, losses: nil)

    public init(tier: String?, division: Int?, leaguePoints: Int?, wins: Int?, losses: Int?) {
        self.tier = tier
        self.division = division
        self.leaguePoints = leaguePoints
        self.wins = wins
        self.losses = losses
    }

    public var isRanked: Bool {
        tier != nil
    }

    /// "Gold II · 45 LP", "Master · 120 LP" or "Unranked".
    public var label: String {
        guard let tier else { return "Unranked" }
        let name = tier.prefix(1).uppercased() + tier.dropFirst().lowercased()
        let apex = ["master", "grandmaster", "challenger"].contains(tier.lowercased())
        let roman = ["", "I", "II", "III", "IV"]
        let division = (!apex && (1 ... 4).contains(division ?? 0)) ? " \(roman[division ?? 0])" : ""
        return name + division + (leaguePoints.map { " · \($0) LP" } ?? "")
    }

    /// Win rate 0…1, if games are known.
    public var winRate: Double? {
        guard let wins, let losses, wins + losses > 0 else { return nil }
        return Double(wins) / Double(wins + losses)
    }

    public var games: Int? {
        guard let wins, let losses, wins + losses > 0 else { return nil }
        return wins + losses
    }
}

public enum RankQueue: String, Equatable, Sendable {
    case solo = "SOLORANKED"
    case flex = "FLEXRANKED"
}

/// Ranks via OP.GG's `lol_get_summoner_profile` – used for the loading screen, where the LCU is
/// already closed and only the Riot IDs from the Live Client API are known.
public struct OPGGRankProvider: Sendable {
    private let client: OPGGClient

    public init(client: OPGGClient = OPGGClient()) {
        self.client = client
    }

    public func soloRank(gameName: String, tagLine: String, region: String) async throws -> PlayerRank {
        try await rank(gameName: gameName, tagLine: tagLine, region: region, preferredQueue: .solo)
    }

    public func rank(
        gameName: String,
        tagLine: String,
        region: String,
        preferredQueue: RankQueue = .solo
    ) async throws -> PlayerRank {
        let text = try await client.callTool("lol_get_summoner_profile", arguments: [
            "game_name": .string(gameName),
            "tag_line": .string(tagLine),
            "region": .string(region.uppercased()),
            "desired_output_fields": .strings([
                "data.summoner.league_stats[].{game_type,win,lose}",
                "data.summoner.league_stats[].tier_info.{tier,division,lp}"
            ])
        ])
        return try Self.rank(from: OPGGNotation.parse(text), preferredQueue: preferredQueue)
    }

    static func soloRank(from value: NotationValue) -> PlayerRank {
        rank(from: value, preferredQueue: .solo)
    }

    static func rank(from value: NotationValue, preferredQueue: RankQueue = .solo) -> PlayerRank {
        let stats = value["data"]?["summoner"]?["league_stats"]?.list ?? []
        let preferred = extractRank(stats, queue: preferredQueue)
        if preferred.isRanked || preferredQueue == .solo {
            return preferred
        }
        return extractRank(stats, queue: .solo)
    }

    private static func extractRank(_ stats: [NotationValue], queue: RankQueue) -> PlayerRank {
        guard let entry = stats.first(where: { $0["game_type"]?.string == queue.rawValue }),
              let tier = entry["tier_info"]?["tier"]?.string, !tier.isEmpty, tier.uppercased() != "UNRANKED"
        else { return .unranked }
        let info = entry["tier_info"]
        let roman = ["I": 1, "II": 2, "III": 3, "IV": 4]
        let division = info?["division"]?.int ?? info?["division"]?.string.flatMap { roman[$0.uppercased()] }
        return PlayerRank(
            tier: tier,
            division: division,
            leaguePoints: info?["lp"]?.int,
            wins: entry["win"]?.int,
            losses: entry["lose"]?.int
        )
    }
}
