import Foundation

/// Why a champion is listed as a pick or ban option. Values are facts from OP.GG, Data Dragon or
/// the player's own mastery; the UI words them neutrally ("options, not a recommendation").
public enum DraftReason: Equatable, Sendable {
    /// OP.GG tier (1 = OP) and lane win rate.
    case meta(tier: Int?, winRate: Double)
    /// Win rate of the option against the (likely) lane opponent.
    case laneMatchup(opponentId: Int, winRate: Double, games: Int)
    /// Win rate of the duo with an ally (OP.GG synergy).
    case synergy(allyId: Int, winRate: Double, games: Int)
    /// The ally team is mostly physical / magic, or has no frontline (Data Dragon estimate).
    case addsMagicDamage
    case addsPhysicalDamage
    case addsFrontline
    /// The player's own mastery points: a champion they play, or one they barely know.
    case comfort(points: Int)
    case unfamiliar(points: Int)
    /// Ban: the champion beats the player's own (hovered or locked) pick in lane.
    case countersYourPick(yourChampionId: Int, winRate: Double, games: Int)
    /// Ban: how often OP.GG sees it picked and banned.
    case presence(pickRate: Double, banRate: Double)
    /// Ban: it is played in the player's own lane.
    case inYourLane
}

/// A reason with its effect on the score, in percentage points of win rate.
public struct ScoredReason: Equatable, Sendable {
    public let reason: DraftReason
    public let impact: Double

    public init(_ reason: DraftReason, impact: Double) {
        self.reason = reason
        self.impact = impact
    }
}

/// One pick or ban option. Several are always shown together (docs/COMPLIANCE.md).
public struct DraftOption: Equatable, Identifiable, Sendable {
    public let id: Int
    /// Sum of the impacts; only used for ordering.
    public let score: Double
    /// Most important first.
    public let reasons: [ScoredReason]
    /// OP.GG lane win rate, shown next to the name.
    public let winRate: Double?

    public init(id: Int, reasons: [ScoredReason], winRate: Double?) {
        self.id = id
        self.reasons = reasons.sorted { abs($0.impact) > abs($1.impact) }
        score = reasons.reduce(0) { $0 + $1.impact }
        self.winRate = winRate
    }
}

/// What Data Dragon says about a champion, enough to judge team fit.
public struct ChampionTraits: Equatable, Sendable {
    /// Share of physical damage (0…1), nil without ratings.
    public let physicalShare: Double?
    public let isFrontline: Bool

    public init(physicalShare: Double?, isFrontline: Bool) {
        self.physicalShare = physicalShare
        self.isFrontline = isFrontline
    }
}

/// What the player's team lacks, from the allies already shown (Data Dragon estimate).
public struct TeamNeeds: Equatable, Sendable {
    public var magicDamage = false
    public var physicalDamage = false
    public var frontline = false

    public init(magicDamage: Bool = false, physicalDamage: Bool = false, frontline: Bool = false) {
        self.magicDamage = magicDamage
        self.physicalDamage = physicalDamage
        self.frontline = frontline
    }
}

/// An ally with a known lane and champion, plus OP.GG's synergy list for the player's lane.
public struct DraftAlly: Equatable, Sendable {
    public let championId: Int
    public let role: Role
    /// The ally's most played partners in the player's lane.
    public let synergies: [Synergy]

    public init(championId: Int, role: Role, synergies: [Synergy]) {
        self.championId = championId
        self.role = role
        self.synergies = synergies
    }
}

/// Shrinks a statistic towards zero by its sample size: noisy small samples count less. Synergy
/// and matchup samples are 500–8000 games, so `half` is where a sample counts half.
func shrunk(_ delta: Double, games: Int, half: Double = 1000) -> Double {
    delta * Double(games) / (Double(games) + half)
}

func clamped(_ value: Double, _ limit: Double) -> Double {
    min(max(value, -limit), limit)
}
