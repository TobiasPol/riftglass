@testable import DataKit
import Foundation
import Testing

struct TeamCompositionTests {
    private let champions: [String: Champion]

    init() throws {
        let url = FixtureFetcher.root.appending(path: "champion.json")
        champions = try JSONDecoder().decode(DataContainer<Champion>.self, from: Data(contentsOf: url)).data
    }

    private func team(_ keys: String...) -> TeamProfile {
        TeamProfile(champions: keys.compactMap { champions[$0] })
    }

    @Test func decodesRatingsAndTags() throws {
        let ahri = try #require(champions["Ahri"])
        #expect(ahri.info?.attack == 3 && ahri.info?.magic == 8)
        #expect(ahri.tags == ["Mage", "Assassin"])
    }

    @Test func physicalTeamWithAssassins() {
        let enemy = team("Zed", "LeeSin", "Jinx", "Talon")
        #expect((enemy.physicalShare ?? 0) > 0.8)
        #expect(enemy.assassins == 2)
        #expect(enemy.frontline == 1) // Lee Sin: fighter with defense 5
        let hints = CompHint.hints(ally: team("Garen", "Ahri"), enemy: enemy)
        #expect(hints.count == 2)
        guard case .enemyMostlyPhysical = hints.first else { Issue.record("expected physical hint"); return }
        #expect(hints.last == .manyEnemyAssassins(2))
    }

    @Test func magicTeamAndMissingFrontline() {
        let enemy = team("Ahri", "Lux", "Malphite")
        #expect((enemy.physicalShare ?? 1) < 0.3)
        let ally = team("Ahri", "Lux", "Jinx", "Zed")
        #expect(ally.frontline == 0)
        let hints = CompHint.hints(ally: ally, enemy: enemy)
        guard case .enemyMostlyMagic = hints.first else { Issue.record("expected magic hint"); return }
        #expect(hints.last == .noAllyFrontline)
    }

    @Test func tooFewEnemiesGiveNoDamageHint() {
        #expect(CompHint.hints(ally: team("Garen"), enemy: team("Zed", "Talon")) == [.manyEnemyAssassins(2)])
        #expect(TeamProfile(champions: []).physicalShare == nil)
    }
}
