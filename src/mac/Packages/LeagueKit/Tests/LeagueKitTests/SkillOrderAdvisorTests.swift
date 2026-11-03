@testable import LeagueKit
import Testing

struct SkillOrderAdvisorTests {
    /// OP.GG's most common Ahri mid order (recorded fixture `opgg/ahri-mid.json`).
    private let ahri = ["W", "Q", "E", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E"]

    private func ranks(_ q: Int, _ w: Int, _ e: Int, _ r: Int) -> [SkillSlot: Int] {
        [.q: q, .w: w, .e: e, .r: r]
    }

    @Test func followsTheOrderStepByStep() {
        let first = SkillOrderAdvisor.advice(order: ahri, championLevel: 1, ranks: ranks(0, 0, 0, 0))
        #expect(first == SkillAdvice(next: .w, then: [.q, .e, .q], unspentPoints: 1))
        #expect(SkillOrderAdvisor.advice(order: ahri, championLevel: 2, ranks: ranks(0, 1, 0, 0))?.next == .q)
        #expect(SkillOrderAdvisor.advice(order: ahri, championLevel: 6, ranks: ranks(3, 1, 1, 0))?.next == .r)
    }

    @Test func nothingToSpendMeansNoAdvice() {
        #expect(SkillOrderAdvisor.advice(order: ahri, championLevel: 3, ranks: ranks(1, 1, 1, 0)) == nil)
        #expect(SkillOrderAdvisor.advice(order: [], championLevel: 3, ranks: ranks(0, 0, 0, 0)) == nil)
    }

    @Test func toleratesDeviationsFromTheOrder() {
        // Player took E twice early; the earliest missing step (Q rank 2) comes next.
        let advice = SkillOrderAdvisor.advice(order: ahri, championLevel: 5, ranks: ranks(1, 1, 2, 0))
        #expect(advice?.next == .q)
        // Two points saved up: the first one goes to the earliest missing step.
        #expect(SkillOrderAdvisor.advice(order: ahri, championLevel: 3, ranks: ranks(0, 1, 0, 0))?.unspentPoints == 2)
    }

    @Test func neverSuggestsAnUnlearnableRank() {
        // Order wants Q twice in a row; at level 2 rank 2 is not learnable yet, so W comes first.
        let advice = SkillOrderAdvisor.advice(order: ["Q", "Q", "W", "E"], championLevel: 2, ranks: ranks(1, 0, 0, 0))
        #expect(advice?.next == .w)
    }

    @Test func fallsBackToPriorityAfterTheOrderEnds() {
        // Level 16, the 15-step order is done: ultimate rank 3 first, then the remaining basic (E).
        #expect(SkillOrderAdvisor.advice(order: ahri, championLevel: 16, ranks: ranks(5, 5, 3, 2))?.next == .r)
        #expect(SkillOrderAdvisor.advice(order: ahri, championLevel: 17, ranks: ranks(5, 5, 3, 3))?.next == .e)
        #expect(SkillOrderAdvisor.priority(ahri.compactMap { SkillSlot(rawValue: $0) }) == [.r, .q, .w, .e])
    }

    @Test func trustsTheOrderForChampionsWithEarlyUltimates() {
        // Udyr/Jayce-style orders level "R" at level 1 – the recorded order proves it is allowed.
        let advice = SkillOrderAdvisor.advice(order: ["R", "Q", "W"], championLevel: 1, ranks: ranks(0, 0, 0, 0))
        #expect(advice?.next == .r)
    }

    @Test func readsAbilityRanksFromRecordedActivePlayer() throws {
        let active: LiveActivePlayer = try Fixture.decode("liveclient/activeplayer.json")
        #expect(active.abilityRanks == ranks(1, 0, 0, 0))
    }
}
