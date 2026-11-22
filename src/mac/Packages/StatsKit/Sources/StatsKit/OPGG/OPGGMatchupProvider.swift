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
    /// Matchup-specific build extracted from the guide (runes, spells, items, skills).
    public let build: BuildOption?

    public init(
        opponentId: Int,
        winRate: Double?,
        games: Int,
        laneAdvantage: Side?,
        soloKillAdvantage: Side?,
        playStyle: String?,
        tip: String?,
        build: BuildOption? = nil
    ) {
        self.opponentId = opponentId
        self.winRate = winRate
        self.games = games
        self.laneAdvantage = laneAdvantage
        self.soloKillAdvantage = soloKillAdvantage
        self.playStyle = playStyle
        self.tip = tip
        self.build = build
    }
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

    public func matchup(
        my champion: ChampionRef,
        against opponent: ChampionRef,
        role: Role,
        queue: BuildQueue = .ranked
    ) async throws -> MatchupBrief {
        let cacheKey = "\(champion.key)-\(opponent.key)-\(role.opggPosition)-\(language)"
        if let cached = await cache.value(for: cacheKey),
           let brief = try? Self.brief(
               from: Data(cached.utf8),
               my: champion,
               opponentId: opponent.id,
               role: role,
               queue: queue
           ) {
            return brief
        }
        let text = try await cache.fetchOnce(for: cacheKey) { [client, language] in
            let text = try await client.callTool("lol_get_lane_matchup_guide", arguments: [
                "position": .string(role.opggPosition),
                "my_champion": .string(champion.key.uppercased()),
                "opponent_champion": .string(opponent.key.uppercased()),
                "lang": .string(language)
            ])
            _ = try Self.brief(
                from: Data(text.utf8),
                my: champion,
                opponentId: opponent.id,
                role: role,
                queue: queue
            ) // cached only when it parses
            return text
        }
        return try Self.brief(from: Data(text.utf8), my: champion, opponentId: opponent.id, role: role, queue: queue)
    }

    static func brief(
        from json: Data,
        my champion: ChampionRef? = nil,
        opponentId: Int,
        role: Role? = nil,
        queue: BuildQueue = .ranked
    ) throws -> MatchupBrief {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let guide = try decoder.decode(Guide.self, from: json)
        let data = guide.data
        let headToHead = data?.counters?.first { $0.championId == opponentId }
        let games = headToHead?.play ?? 0
        let wins = headToHead?.win
        func side(_ name: String?) -> MatchupBrief.Side? {
            guard let name, !name.isEmpty else { return nil }
            let normalized = RoleRates.normalized(name)
            if let mine = guide.myChampion, normalized == RoleRates.normalized(mine) {
                return .me
            }
            if let opponent = guide.opponentChampion, normalized == RoleRates.normalized(opponent) {
                return .opponent
            }
            return nil
        }
        return MatchupBrief(
            opponentId: opponentId,
            winRate: games >= minimumGames ? wins.map { Double($0) / Double(games) } : nil,
            games: games,
            laneAdvantage: side(data?.laneAdvantageChampion),
            soloKillAdvantage: side(data?.laneSoloKillAdvantageChampion),
            playStyle: data?.recommendedPlayStyle,
            tip: data?.opponentChampionTip.flatMap { $0.isEmpty ? nil : $0 },
            build: guide.buildOption(champion: champion, opponentId: opponentId, role: role, queue: queue)
        )
    }
}
