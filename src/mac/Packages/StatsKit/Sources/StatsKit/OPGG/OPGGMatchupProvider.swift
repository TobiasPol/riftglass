import Foundation

/// What OP.GG knows about one lane matchup, from the local player's point of view.
public struct MatchupBrief: Equatable, Sendable {
    public enum Side: Equatable, Sendable {
        case me, opponent
    }

    public let opponentId: Int
    /// Own win rate against the opponent; nil when the sample is too small.
    public let winRate: Double?
    public let games: Int
    public let laneAdvantage: Side?
    public let soloKillAdvantage: Side?
    /// OP.GG's `recommended_play_style`, e.g. `even`.
    public let playStyle: String?
    /// Tip against the opponent (OP.GG answers in English even with `lang`).
    public let tip: String?
}

/// Lane matchups from OP.GG's `lol_get_lane_matchup_guide`. Unlike the other tools it answers in
/// JSON, not class notation, and ignores `desired_output_fields` (about 50 KB, so cached).
public struct OPGGMatchupProvider: Sendable {
    /// Below this many games the head-to-head win rate is noise.
    static let minimumGames = 100

    private let client: OPGGClient
    private let cache: ResponseCache
    /// OP.GG `lang`, e.g. `en_US` or `de_DE`.
    private let language: String

    public init(
        client: OPGGClient = OPGGClient(),
        cache: ResponseCache = ResponseCache(name: "opgg-matchups"),
        language: String = "en_US"
    ) {
        self.client = client
        self.cache = cache
        self.language = language
    }

    public func matchup(my champion: ChampionRef, against opponent: ChampionRef, role: Role) async throws
        -> MatchupBrief {
        let cacheKey = "\(champion.key)-\(opponent.key)-\(role.opggPosition)-\(language)"
        let text: String
        if let cached = await cache.value(for: cacheKey) {
            text = cached
        } else {
            text = try await client.callTool("lol_get_lane_matchup_guide", arguments: [
                "position": .string(role.opggPosition),
                "my_champion": .string(champion.key.uppercased()),
                "opponent_champion": .string(opponent.key.uppercased()),
                "lang": .string(language)
            ])
            await cache.store(text, for: cacheKey)
        }
        return try Self.brief(from: Data(text.utf8), opponentId: opponent.id)
    }

    static func brief(from json: Data, opponentId: Int) throws -> MatchupBrief {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let guide = try decoder.decode(Guide.self, from: json)
        let data = guide.data
        let headToHead = data?.counters?.first { $0.championId == opponentId }
        let games = headToHead?.play ?? 0
        func side(_ name: String?) -> MatchupBrief.Side? {
            guard let name else { return nil }
            if name == guide.myChampion {
                return .me
            }
            if name == guide.opponentChampion {
                return .opponent
            }
            return nil
        }
        return MatchupBrief(
            opponentId: opponentId,
            winRate: games >= minimumGames ? headToHead.map { Double($0.win) / Double(games) } : nil,
            games: games,
            laneAdvantage: side(data?.laneAdvantageChampion),
            soloKillAdvantage: side(data?.laneSoloKillAdvantageChampion),
            playStyle: data?.recommendedPlayStyle,
            tip: data?.opponentChampionTip.flatMap { $0.isEmpty ? nil : $0 }
        )
    }
}

private struct Guide: Decodable {
    struct Payload: Decodable {
        let opponentChampionTip: String?
        let laneAdvantageChampion: String?
        let laneSoloKillAdvantageChampion: String?
        let recommendedPlayStyle: String?
        let counters: [Counter]?
    }

    struct Counter: Decodable {
        let championId: Int
        let play: Int
        let win: Int
    }

    let myChampion: String?
    let opponentChampion: String?
    let data: Payload?
}
