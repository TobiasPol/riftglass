import Foundation

/// OP.GG's tier list for all lanes from `lol_list_lane_meta_champions` – one request (~14 KB) for
/// every champion, used to guess enemy lanes (`LaneAssigner`) and for pick and ban options.
public struct OPGGLaneMetaProvider: Sendable {
    static let fields = Role.allCases.map {
        "data.positions.\($0.opggPosition)[].{champion,role_rate,tier,win_rate,pick_rate,ban_rate,play,is_rip}"
    }

    private let client: OPGGClient
    private let cache: ResponseCache

    public init(client: OPGGClient = OPGGClient(), cache: ResponseCache = ResponseCache(name: "opgg-lane-meta")) {
        self.client = client
        self.cache = cache
    }

    public func laneMeta() async throws -> LaneMeta {
        // v2: the full tier list; older cached answers only have lane shares.
        let cacheKey = "lane-meta-v2"
        if let cached = await cache.value(for: cacheKey), let value = try? OPGGNotation.parse(cached) {
            return LaneMeta.parse(value)
        }
        let text = try await client.callTool("lol_list_lane_meta_champions", arguments: [
            "position": .string("all"),
            "desired_output_fields": .strings(Self.fields)
        ])
        // Cached only when it parses and has lanes – this one answer feeds every lane guess for hours.
        let meta = try LaneMeta.parse(OPGGNotation.parse(text))
        if !meta.isEmpty {
            await cache.store(text, for: cacheKey)
        }
        return meta
    }

    public func roleRates() async throws -> RoleRates {
        try await laneMeta().roleRates
    }

    static func roleRates(from value: NotationValue) -> RoleRates {
        LaneMeta.parse(value).roleRates
    }
}
