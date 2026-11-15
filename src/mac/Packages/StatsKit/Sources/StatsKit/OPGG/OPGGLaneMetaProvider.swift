import Foundation

/// Lane shares of all meta champions from OP.GG's `lol_list_lane_meta_champions` – one request for
/// every champion, used to guess enemy lanes in draft (`LaneAssigner`).
public struct OPGGLaneMetaProvider: Sendable {
    static let fields = Role.allCases.map { "data.positions.\($0.opggPosition)[].{champion,role_rate}" }

    private let client: OPGGClient
    private let cache: ResponseCache

    public init(client: OPGGClient = OPGGClient(), cache: ResponseCache = ResponseCache(name: "opgg-lane-meta")) {
        self.client = client
        self.cache = cache
    }

    public func roleRates() async throws -> RoleRates {
        let cacheKey = "lane-meta"
        if let cached = await cache.value(for: cacheKey), let value = try? OPGGNotation.parse(cached) {
            return Self.roleRates(from: value)
        }
        let text = try await client.callTool("lol_list_lane_meta_champions", arguments: [
            "position": .string("all"),
            "desired_output_fields": .strings(Self.fields)
        ])
        // Cached only when it parses and has lanes – this one answer feeds every lane guess for hours.
        let rates = try Self.roleRates(from: OPGGNotation.parse(text))
        if !rates.rates.isEmpty {
            await cache.store(text, for: cacheKey)
        }
        return rates
    }

    static func roleRates(from value: NotationValue) -> RoleRates {
        var rates: [String: [Role: Double]] = [:]
        let positions = value["data"]?["positions"]
        for role in Role.allCases {
            for entry in positions?[role.opggPosition]?.list ?? [] {
                guard let name = entry["champion"]?.string, let rate = entry["role_rate"]?.double else { continue }
                rates[RoleRates.normalized(name), default: [:]][role] = rate
            }
        }
        return RoleRates(rates: rates)
    }
}
