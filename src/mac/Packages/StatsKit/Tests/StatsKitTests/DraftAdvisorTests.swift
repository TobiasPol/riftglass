import Foundation
@testable import StatsKit
import Testing

/// Mid lane with Ahri (strong), Zed (popular, often banned), Syndra, Galio, Lux; Lee Sin in the jungle.
private enum Draft {
    static let ahri = 103, zed = 238, syndra = 134, galio = 3, lux = 99, katarina = 55, leeSin = 64

    static let directory = ChampionDirectory([
        .init(id: ahri, name: "Ahri", key: "Ahri"), .init(id: zed, name: "Zed", key: "Zed"),
        .init(id: syndra, name: "Syndra", key: "Syndra"), .init(id: galio, name: "Galio", key: "Galio"),
        .init(id: lux, name: "Lux", key: "Lux"), .init(id: katarina, name: "Katarina", key: "Katarina"),
        .init(id: leeSin, name: "Lee Sin", key: "LeeSin")
    ])

    static func mid(_ name: String, _ winRate: Double, pick: Double = 0.05, ban: Double = 0.02, role: Double = 0.9)
        -> MetaChampion {
        MetaChampion(name: name, role: .middle, roleRate: role, tier: 2, winRate: winRate, pickRate: pick, banRate: ban)
    }

    static let meta = LaneMeta(lanes: [
        .middle: [
            mid("Ahri", 0.52, pick: 0.11), mid("Zed", 0.50, pick: 0.08, ban: 0.25), mid("Syndra", 0.50),
            mid("Galio", 0.50), mid("Lux", 0.51, role: 0.05), mid("Katarina", 0.51, pick: 0.06, ban: 0.13)
        ],
        .jungle: [MetaChampion(name: "Lee Sin", role: .jungle, roleRate: 0.96, winRate: 0.49, pickRate: 0.12)]
    ])

    static func pickContext() -> PickContext {
        PickContext(role: .middle, meta: meta, directory: directory)
    }
}

struct PickAdvisorTests {
    @Test func ranksByLaneStrengthAndSkipsOffRoleChampions() {
        let options = PickAdvisor.options(Draft.pickContext())
        #expect(options.first?.id == Draft.ahri)
        // Lux plays mid in only 5 % of her games.
        #expect(!options.map(\.id).contains(Draft.lux))
        let reason = options.first?.reasons.first
        #expect(reason?.reason == .meta(tier: 2, winRate: 0.52))
        #expect(abs((reason?.impact ?? 0) - 2) < 0.001)
    }

    @Test func excludesTakenUnavailableAndOpponent() {
        var context = Draft.pickContext()
        context.excluded = [Draft.ahri]
        context.available = [Draft.ahri, Draft.syndra, Draft.galio, Draft.zed]
        context.opponentId = Draft.zed
        #expect(Set(PickAdvisor.options(context).map(\.id)) == [Draft.syndra, Draft.galio])
    }

    /// Galio's 56 % against Zed is 6 points above what both base win rates predict.
    @Test func laneCountersAreNormalizedByBaseWinRates() throws {
        var context = Draft.pickContext()
        context.opponentId = Draft.zed
        context.opponentCounters = LaneCounters(
            beatenBy: [CounterPick(id: Draft.galio, name: "Galio", winRate: 0.56, games: 4000)],
            beats: [CounterPick(id: Draft.syndra, name: "Syndra", winRate: 0.45, games: 1000)]
        )
        let options = PickAdvisor.options(context)
        #expect(options.first?.id == Draft.galio)
        let galio = try #require(options.first?.reasons.first)
        #expect(galio.reason == .laneMatchup(opponentId: Draft.zed, winRate: 0.56, games: 4000))
        #expect(abs(galio.impact - 4.8) < 0.01) // 6 points × 4000 / (4000 + 1000)
        #expect(options.last?.id == Draft.syndra)
    }

    @Test func headToHeadWinsOverCounterLists() {
        var context = Draft.pickContext()
        context.opponentId = Draft.zed
        context.opponentCounters = LaneCounters(
            beatenBy: [],
            beats: [CounterPick(id: Draft.ahri, name: "Ahri", winRate: 0.4, games: 9000)]
        )
        context.headToHead = [Draft.ahri: CounterPick(id: Draft.ahri, name: "Ahri", winRate: 0.52, games: 9000)]
        let ahri = PickAdvisor.options(context).first { $0.id == Draft.ahri }
        #expect(ahri?.reasons
            .contains { $0.reason == .laneMatchup(opponentId: Draft.zed, winRate: 0.52, games: 9000) } == true)
    }

    @Test func synergyWithAlliesAndTeamNeeds() throws {
        var context = Draft.pickContext()
        context.allies = [DraftAlly(championId: Draft.leeSin, role: .jungle, synergies: [
            Synergy(id: Draft.syndra, name: "Syndra", winRate: 0.55, games: 6000)
        ])]
        context.traits = [Draft.galio: ChampionTraits(physicalShare: 0.2, isFrontline: true)]
        context.needs = TeamNeeds(frontline: true)
        let options = PickAdvisor.options(context)
        let syndra = try #require(options.first { $0.id == Draft.syndra })
        // Expected duo: 0.5 + 0 + (0.49 − 0.5) = 0.49 → +6 points, shrunk and capped at 3.
        #expect(syndra.reasons.first == ScoredReason(
            .synergy(allyId: Draft.leeSin, winRate: 0.55, games: 6000),
            impact: 3
        ))
        let galio = try #require(options.first { $0.id == Draft.galio })
        #expect(galio.reasons.contains(ScoredReason(.addsFrontline, impact: 1)))
    }

    @Test func masteryFavoursTheChampionsYouPlay() {
        var context = Draft.pickContext()
        context.mastery = [Draft.galio: 180_000, Draft.syndra: 20000]
        let options = PickAdvisor.options(context)
        #expect(options.map(\.id).prefix(2) == [Draft.galio, Draft.syndra])
        #expect(options.first { $0.id == Draft.ahri }?.reasons.contains(ScoredReason(
            .unfamiliar(points: 0),
            impact: -4
        )) == true)
        // Without mastery data nobody is called unfamiliar.
        #expect(PickAdvisor.options(Draft.pickContext()).allSatisfy { option in
            !option.reasons.contains {
                if case .unfamiliar = $0.reason {
                    true
                } else {
                    false
                }
            }
        })
    }

    @Test func shortlistIgnoresHeadToHead() {
        var context = Draft.pickContext()
        context.headToHead = [Draft.galio: CounterPick(id: Draft.galio, name: "Galio", winRate: 0.7, games: 9000)]
        context.opponentId = Draft.zed
        #expect(PickAdvisor.shortlist(context, count: 2) == [Draft.ahri, Draft.katarina])
    }
}

struct BanAdvisorTests {
    private func context() -> BanContext {
        BanContext(meta: Draft.meta, directory: Draft.directory)
    }

    @Test func popularStrongChampionsFirst() {
        let options = BanAdvisor.options(context(), limit: 3)
        // Ahri 2 + 1.1 + 0.1, Katarina 1 + 0.6 + 0.65, Zed 0 + 0.8 + 1.25 (strength + pick + ban).
        #expect(options.map(\.id) == [Draft.ahri, Draft.katarina, Draft.zed])
    }

    @Test func countersOfYourPickAndOwnLaneWeighMore() throws {
        var context = context()
        context.role = .jungle
        context.yourChampionId = Draft.leeSin
        context.yourCounters = LaneCounters(
            beatenBy: [CounterPick(id: Draft.zed, name: "Zed", winRate: 0.55, games: 3000)],
            beats: []
        )
        let options = BanAdvisor.options(context)
        let zed = try #require(options.first)
        #expect(zed.id == Draft.zed)
        #expect(zed.reasons.first?.reason == .countersYourPick(
            yourChampionId: Draft.leeSin,
            winRate: 0.55,
            games: 3000
        ))
    }

    @Test func skipsExcludedChampions() {
        var context = context()
        context.excluded = [Draft.ahri, Draft.zed]
        #expect(!BanAdvisor.options(context).map(\.id).contains { $0 == Draft.ahri || $0 == Draft.zed })
    }
}
