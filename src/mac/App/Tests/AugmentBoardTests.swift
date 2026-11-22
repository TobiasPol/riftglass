import DataKit
import Foundation
@testable import Riftglass
import StatsKit
import Testing

struct AugmentBoardTests {
    @Test func groupsSortsDeduplicatesAndDropsUnknownRarities() throws {
        let iconOPGG = try #require(URL(string: "https://op.gg/aug1.png"))
        let iconCDragon = try #require(URL(string: "https://cdragon.org/aug1.png"))
        let stats = [
            AugmentStat(id: 10, name: "Slow Prism", tier: 2, popularity: 0.1, rarity: .prismatic, iconURL: iconOPGG),
            AugmentStat(id: 11, name: "Top Prism", tier: 0, popularity: 0.2, rarity: .prismatic, iconURL: iconOPGG),
            AugmentStat(id: 11, name: "Dup Prism", tier: 1, popularity: 0.1, rarity: .prismatic, iconURL: iconOPGG),
            AugmentStat(id: 20, name: "Gold One", tier: 1, popularity: 0.1, rarity: nil, iconURL: iconOPGG),
            AugmentStat(id: 30, name: "Orphan", tier: 1, popularity: 0.1, rarity: nil, iconURL: iconOPGG)
        ]
        let catalog: [Int: AugmentInfo] = [
            11: AugmentInfo(id: 11, name: "Localized Prism", rarity: .prismatic, iconURL: iconCDragon),
            20: AugmentInfo(id: 20, name: "Gold Localized", rarity: .gold, iconURL: nil)
        ]
        let board = AugmentBoard.make(championId: 103, stats: stats, catalog: catalog)
        #expect(board.columns.map(\.rarity) == [.prismatic, .gold])
        #expect(board.columns[0].entries.map(\.id) == [11, 10])
        #expect(board.columns[0].entries[0].name == "Localized Prism")
        #expect(board.columns[0].entries[0].iconURL == iconCDragon)
        #expect(board.columns[1].entries.map(\.id) == [20])
        #expect(board.columns[1].entries[0].iconURL == iconOPGG)
    }
}
