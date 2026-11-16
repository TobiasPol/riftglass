import Foundation

/// A champion that does well against a given opponent – one option among several, never a pick
/// instruction (docs/COMPLIANCE.md).
public struct CounterPick: Equatable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    /// The counter's win rate against the opponent.
    public let winRate: Double
    public let games: Int

    public init(id: Int, name: String, winRate: Double, games: Int) {
        self.id = id
        self.name = name
        self.winRate = winRate
        self.games = games
    }
}

/// OP.GG's strongest lane matchups of one champion, three in each direction.
public struct LaneCounters: Equatable, Sendable {
    /// Champions that beat it (OP.GG `weak_counters`); `winRate` is theirs. Best counter first.
    public let beatenBy: [CounterPick]
    /// Champions it beats (`strong_counters`); `winRate` is still the other champion's, so low.
    public let beats: [CounterPick]

    public init(beatenBy: [CounterPick], beats: [CounterPick]) {
        self.beatenBy = beatenBy
        self.beats = beats
    }

    /// The other champion's win rate against this one, if OP.GG lists the pair.
    public func winRate(of championId: Int) -> CounterPick? {
        (beatenBy + beats).first { $0.id == championId }
    }
}

/// Counter picks against a champion from OP.GG's `lol_get_champion_analysis`.
public struct OPGGCounterProvider: Sendable {
    static let fields = [
        "data.weak_counters[].{champion_id,champion_name,my_win_rate,counter_win_rate,play}",
        "data.strong_counters[].{champion_id,champion_name,my_win_rate,counter_win_rate,play}"
    ]
    /// OP.GG lists counters from a few hundred games; smaller samples are hidden.
    static let minimumGames = 200

    private let client: OPGGClient
    private let cache: ResponseCache

    public init(client: OPGGClient = OPGGClient(), cache: ResponseCache = ResponseCache(name: "opgg-counters")) {
        self.client = client
        self.cache = cache
    }

    public func counters(against champion: ChampionRef, role: Role, queue: BuildQueue) async throws -> [CounterPick] {
        try await laneCounters(of: champion, role: role, queue: queue).beatenBy
    }

    public func laneCounters(of champion: ChampionRef, role: Role, queue: BuildQueue) async throws -> LaneCounters {
        // v2: both directions; older cached answers only have `weak_counters`.
        let cacheKey = "\(champion.key)-\(queue.rawValue)-\(role.opggPosition)-v2"
        if let cached = await cache.value(for: cacheKey), let value = try? OPGGNotation.parse(cached) {
            return Self.laneCounters(from: value)
        }
        let text = try await client.callTool("lol_get_champion_analysis", arguments: [
            "game_mode": .string(queue.opggGameMode),
            "champion": .string(champion.key.uppercased()),
            "position": .string(role.opggPosition),
            "desired_output_fields": .strings(Self.fields)
        ])
        let value = try OPGGNotation.parse(text) // cached only when it parses
        await cache.store(text, for: cacheKey)
        return Self.laneCounters(from: value)
    }

    static func laneCounters(from value: NotationValue) -> LaneCounters {
        LaneCounters(
            beatenBy: counters(value["data"]?["weak_counters"]),
            beats: counters(value["data"]?["strong_counters"])
        )
    }

    /// Best counter first.
    static func counters(from value: NotationValue) -> [CounterPick] {
        counters(value["data"]?["weak_counters"])
    }

    private static func counters(_ list: NotationValue?) -> [CounterPick] {
        (list?.list ?? []).compactMap { entry -> CounterPick? in
            guard let id = entry["champion_id"]?.int, let name = entry["champion_name"]?.string,
                  let winRate = entry["counter_win_rate"]?.double, let games = entry["play"]?.int,
                  games >= minimumGames
            else { return nil }
            return CounterPick(id: id, name: name, winRate: winRate, games: games)
        }
        .sorted { $0.winRate > $1.winRate }
    }
}
