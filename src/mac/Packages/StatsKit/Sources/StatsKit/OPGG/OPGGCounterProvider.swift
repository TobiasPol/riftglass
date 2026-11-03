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

/// Counter picks against a champion from OP.GG's `lol_get_champion_analysis` (`weak_counters`).
public struct OPGGCounterProvider: Sendable {
    static let fields = ["data.weak_counters[].{champion_id,champion_name,my_win_rate,counter_win_rate,play}"]
    /// OP.GG lists counters from a few hundred games; smaller samples are hidden.
    static let minimumGames = 200

    private let client: OPGGClient
    private let cache: ResponseCache

    public init(client: OPGGClient = OPGGClient(), cache: ResponseCache = ResponseCache(name: "opgg-counters")) {
        self.client = client
        self.cache = cache
    }

    public func counters(against champion: ChampionRef, role: Role, queue: BuildQueue) async throws -> [CounterPick] {
        let cacheKey = "\(champion.key)-\(queue.rawValue)-\(role.opggPosition)"
        let text: String
        if let cached = await cache.value(for: cacheKey) {
            text = cached
        } else {
            text = try await client.callTool("lol_get_champion_analysis", arguments: [
                "game_mode": .string(queue.opggGameMode),
                "champion": .string(champion.key.uppercased()),
                "position": .string(role.opggPosition),
                "desired_output_fields": .strings(Self.fields)
            ])
            await cache.store(text, for: cacheKey)
        }
        return try Self.counters(from: OPGGNotation.parse(text))
    }

    /// Best counter first.
    static func counters(from value: NotationValue) -> [CounterPick] {
        let entries = value["data"]?["weak_counters"]?.list ?? []
        return entries.compactMap { entry -> CounterPick? in
            guard let id = entry["champion_id"]?.int, let name = entry["champion_name"]?.string,
                  let winRate = entry["counter_win_rate"]?.double, let games = entry["play"]?.int,
                  games >= minimumGames
            else { return nil }
            return CounterPick(id: id, name: name, winRate: winRate, games: games)
        }
        .sorted { $0.winRate > $1.winRate }
    }
}
