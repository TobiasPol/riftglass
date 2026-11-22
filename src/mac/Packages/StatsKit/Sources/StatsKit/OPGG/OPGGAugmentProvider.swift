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
/// all tiers.
///
/// Request budget (docs/COMPLIANCE.md): op.gg answers at most one request per champion per cache
/// lifetime – also when the answer was an error or a page that no longer parses; that failure is
/// remembered on disk for the same time. Callers asking for the same champion at once share one
/// request. Only a request that got no answer at all (no network) is tried again, a minute later.
/// Whenever no fresh list can be had, the last known one is used however old it is – tier lists
/// move slowly, and a wrong parse must never replace them.
public struct OPGGAugmentProvider: Sendable {
    /// Seconds before a request that got no answer is tried again.
    static let unansweredRetryInterval: TimeInterval = 60

    private let getter: any HTTPGetting
    private let cache: ResponseCache
    private let userAgent: String
    private let now: @Sendable () -> Date
    private let gate = AugmentRequestGate()

    public init(
        getter: any HTTPGetting = URLSessionGetter(),
        cache: ResponseCache = ResponseCache(name: "opgg-augments"),
        userAgent: String = "Riftglass",
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.getter = getter
        self.cache = cache
        self.userAgent = userAgent
        self.now = now
    }

    public static let pagesURL = URL(string: "https://op.gg/lol/modes/aram-mayhem/")!

    /// OP.GG accepts the numeric champion ID in place of its name slug (62 ≙ `monkeyking`).
    public static func pageURL(championId: Int) -> URL {
        pagesURL.appending(path: "\(championId)/augments")
    }

    /// Every augment OP.GG lists for the champion, in OP.GG's order (`AugmentStat.tierListOrder`).
    public func augments(championId: Int) async throws -> [AugmentStat] {
        if let cached = await freshList(championId) {
            return cached
        }
        return try await gate.run(championId) { try await refresh(championId) }
    }

    /// Runs once per champion at a time (`gate`).
    private func refresh(_ championId: Int) async throws -> [AugmentStat] {
        // The request this call waited behind may just have filled the cache.
        if let cached = await freshList(championId) {
            return cached
        }
        let failure: any Error
        if let remembered = await rememberedFailure(championId) {
            failure = remembered
        } else {
            do {
                return try await fetch(championId)
            } catch {
                await remember(error, championId: championId)
                failure = error
            }
        }
        guard let stale = await cache.staleValue(for: Self.listKey(championId)).flatMap(Self.decode) else {
            throw failure
        }
        return stale
    }

    private func fetch(_ championId: Int) async throws -> [AugmentStat] {
        let html = try await getter.get(
            Self.pageURL(championId: championId),
            headers: ["User-Agent": userAgent, "Accept": "text/html"]
        )
        let stats = try OPGGAugmentPage.augments(fromHTML: html)
        if let encoded = try? JSONEncoder().encode(stats), let text = String(data: encoded, encoding: .utf8) {
            await cache.store(text, for: Self.listKey(championId))
        }
        return stats
    }

    private func freshList(_ championId: Int) async -> [AugmentStat]? {
        await cache.value(for: Self.listKey(championId)).flatMap(Self.decode)
    }

    /// An `OPGGError` means op.gg answered (HTTP status, changed page): no further request for a
    /// cache lifetime, across app restarts. Anything else is a transport error without an answer.
    private func remember(_ error: any Error, championId: Int) async {
        guard !(error is CancellationError) else { return }
        if let answered = error as? OPGGError {
            let code = if case let .http(status) = answered {
                "http:\(status)"
            } else {
                "page"
            }
            await cache.store(code, for: Self.failureKey(championId))
        } else {
            let retryAt = now().addingTimeInterval(Self.unansweredRetryInterval)
            await gate.remember(error, for: championId, until: retryAt)
        }
    }

    private func rememberedFailure(_ championId: Int) async -> (any Error)? {
        if let code = await cache.value(for: Self.failureKey(championId)) {
            return code.hasPrefix("http:") ? OPGGError.http(Int(code.dropFirst(5)) ?? 0) : OPGGError.unexpectedPage
        }
        return await gate.failure(for: championId, at: now())
    }

    /// v3: parsed page entries as JSON; v1/v2 held the MCP answer without the top tiers.
    private static func listKey(_ championId: Int) -> String {
        "aram-mayhem-augments-v3-\(championId)"
    }

    private static func failureKey(_ championId: Int) -> String {
        "aram-mayhem-augments-failure-\(championId)"
    }

    private static func decode(_ text: String) -> [AugmentStat]? {
        try? JSONDecoder().decode([AugmentStat].self, from: Data(text.utf8))
    }
}

/// Lets concurrent callers for one champion share a single page request and keeps unanswered
/// attempts in memory until they may be repeated.
actor AugmentRequestGate {
    private var inFlight: [Int: Task<[AugmentStat], any Error>] = [:]
    private var unanswered: [Int: (error: any Error, retryAt: Date)] = [:]

    func run(
        _ championId: Int,
        _ work: @escaping @Sendable () async throws -> [AugmentStat]
    ) async throws -> [AugmentStat] {
        if let running = inFlight[championId] {
            return try await running.value
        }
        let task = Task { try await work() }
        inFlight[championId] = task
        defer { inFlight[championId] = nil }
        return try await task.value
    }

    func remember(_ error: any Error, for championId: Int, until retryAt: Date) {
        unanswered[championId] = (error, retryAt)
    }

    func failure(for championId: Int, at date: Date) -> (any Error)? {
        guard let entry = unanswered[championId] else { return nil }
        if date >= entry.retryAt {
            unanswered[championId] = nil
            return nil
        }
        return entry.error
    }
}
