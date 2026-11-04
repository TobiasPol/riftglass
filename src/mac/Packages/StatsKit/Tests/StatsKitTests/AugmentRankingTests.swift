import Foundation
@testable import StatsKit
import Testing

struct AugmentRankingTests {
    private func stat(_ id: Int, pick: Double, perf: Double?) -> AugmentStat {
        AugmentStat(id: id, name: "A\(id)", pickRate: pick, performance: perf)
    }

    @Test func rareOutlierRegressesToMean() {
        let ranked = AugmentRanking.rank([
            stat(1, pick: 0.20, perf: 90),
            stat(2, pick: 0.20, perf: 80),
            stat(3, pick: 0.01, perf: 100) // small sample, higher score
        ])
        #expect(ranked.map(\.stat.id) == [1, 3, 2])
        #expect(ranked[1].score < 90 && ranked[1].score > ranked[2].score)
    }

    @Test func dropsUnusableEntries() {
        let ranked = AugmentRanking.rank([
            stat(1, pick: 0.1, perf: 85),
            stat(2, pick: 0.005, perf: 200), // below minimum pick share
            stat(3, pick: 0.2, perf: nil) // no performance
        ])
        #expect(ranked.map(\.stat.id) == [1])
        #expect(ranked.first?.rank == 1 && ranked.first?.grade == .top)
        #expect(AugmentRanking.rank([]).isEmpty)
    }

    @Test func gradesAreRelativeShares() {
        let grades = (0 ..< 20).map { AugmentRanking.grade(position: $0, count: 20) }
        #expect(grades.filter { $0 == .top }.count == 3)
        #expect(grades.filter { $0 == .strong }.count == 5)
        #expect(grades.filter { $0 == .solid }.count == 7)
        #expect(grades.filter { $0 == .niche }.count == 5)
    }

    @Test func recordedAhriRanking() throws {
        let text = try OPGGClient.text(fromResponse: Fixture.data("opgg/ahri-aram-augments.json"))
        let stats = try OPGGAugmentProvider.augments(from: OPGGNotation.parse(text))
        let ranked = AugmentRanking.rank(stats)
        #expect(ranked.prefix(3).map(\.stat.name) == ["Hand of Baron", "Back To Basics", "Don't Blink"])
        // 141.67 at 0 % picks must not make it into the list at all.
        #expect(!ranked.contains { $0.stat.name == "Snowball Roulette" })
        #expect(ranked.map(\.rank) == Array(1 ... ranked.count))
    }
}
