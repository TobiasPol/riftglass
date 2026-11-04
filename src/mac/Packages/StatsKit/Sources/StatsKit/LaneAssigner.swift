import Foundation

/// Share of a champion's games per lane, keyed by `RoleRates.normalized(name)`.
public struct RoleRates: Equatable, Sendable {
    public let rates: [String: [Role: Double]]

    public init(rates: [String: [Role: Double]]) {
        self.rates = rates
    }

    public func rate(of name: String, in role: Role) -> Double {
        rates[Self.normalized(name)]?[role] ?? 0
    }

    /// False when the champion has no lane share at all (not in OP.GG's meta, or no data).
    public func knows(_ name: String) -> Bool {
        rates[Self.normalized(name)]?.values.contains { $0 > 0 } ?? false
    }

    /// Letters and digits only, lowercased: "Kog'Maw", "Nunu & Willump" and "Dr. Mundo" match the
    /// spelling of every source.
    public static func normalized(_ name: String) -> String {
        String(name.lowercased().unicodeScalars.filter(CharacterSet.alphanumerics.contains).map(Character.init))
    }
}

/// Guesses which lane each enemy champion plays. The client does not reveal enemy positions in
/// draft, so the most likely complete assignment (by OP.GG lane share) is chosen. Champions without
/// any lane share get no lane – a guess without statistics would be arbitrary.
public enum LaneAssigner {
    public struct Pick: Equatable, Sendable {
        public let championId: Int
        public let name: String
        /// Position the client revealed; kept as is.
        public let fixed: Role?

        public init(championId: Int, name: String, fixed: Role? = nil) {
            self.championId = championId
            self.name = name
            self.fixed = fixed
        }
    }

    public struct Assignment: Equatable, Sendable {
        public let championId: Int
        /// The champion's share of games in this lane (1 for revealed positions).
        public let confidence: Double
        /// True when the client revealed the position; everything else is an estimate.
        public let isRevealed: Bool
    }

    public static func assign(_ picks: [Pick], rates: RoleRates) -> [Role: Assignment] {
        var result: [Role: Assignment] = [:]
        var open: [Pick] = []
        for pick in picks.prefix(Role.allCases.count) {
            if let role = pick.fixed, result[role] == nil {
                result[role] = Assignment(championId: pick.championId, confidence: 1, isRevealed: true)
            } else if rates.knows(pick.name) {
                open.append(pick)
            }
        }
        let freeRoles = Role.allCases.filter { result[$0] == nil }
        let best = bestRoles(for: open, roles: freeRoles, rates: rates)
        for (pick, role) in zip(open, best.roles) {
            let confidence = rates.rate(of: pick.name, in: role)
            result[role] = Assignment(championId: pick.championId, confidence: confidence, isRevealed: false)
        }
        return result
    }

    /// Exhaustive search over injective mappings (at most 5! = 120). Ties keep the earlier mapping,
    /// so the result is deterministic.
    private static func bestRoles(
        for picks: [Pick],
        roles: [Role],
        rates: RoleRates
    ) -> (score: Double, roles: [Role]) {
        guard let pick = picks.first else { return (0, []) }
        var best: (score: Double, roles: [Role]) = (-.infinity, [])
        for role in roles {
            let rest = bestRoles(for: Array(picks.dropFirst()), roles: roles.filter { $0 != role }, rates: rates)
            let score = log(max(rates.rate(of: pick.name, in: role), 0.01)) + rest.score
            if score > best.score {
                best = (score, [role] + rest.roles)
            }
        }
        return best
    }
}
