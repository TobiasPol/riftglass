import LeagueKit
@testable import Riftglass
import StatsKit
import Testing

struct BuildMappingTests {
    private func sampleBuild(spells: [Int]) -> BuildOption {
        BuildOption(
            id: "b1",
            title: "OP.GG Build",
            role: .middle,
            championKey: "Ahri",
            queue: .ranked,
            source: .opgg,
            runes: .init(
                primaryStyleId: 8100,
                subStyleId: 8200,
                perkIds: [8112, 8139, 8140, 8106, 8210, 8226, 5005, 5008, 5001]
            ),
            summonerSpells: spells,
            itemBlocks: [.init(title: "Core", itemIds: [3118, 4645])]
        )
    }

    @Test func mapsRunesSpellsAndItemSet() {
        let mapping = BuildMapping(
            build: sampleBuild(spells: [4, 14]),
            championId: 103,
            championName: "Ahri",
            itemSetMapId: 11
        )
        #expect(mapping.runePage.name == "Riftglass: Ahri")
        #expect(mapping.runePage.primaryStyleId == 8100)
        #expect(mapping.runePage.subStyleId == 8200)
        #expect(mapping.spells == SpellSelection(spell1Id: 4, spell2Id: 14))
        #expect(mapping.itemSet.title == "Riftglass: Ahri – OP.GG Build")
        #expect(mapping.itemSet.mapId == 11)
        #expect(mapping.itemSet.blocks.first?.itemIds == [3118, 4645])
    }

    @Test func validSpellsRejectsEmptyZeroOrDuplicateSpells() {
        #expect(sampleBuild(spells: [4]).validSpells == nil)
        #expect(sampleBuild(spells: [0, 4]).validSpells == nil)
        #expect(sampleBuild(spells: [4, 4]).validSpells == nil)
        let valid = sampleBuild(spells: [4, 12]).validSpells
        #expect(valid?.0 == 4 && valid?.1 == 12)
    }
}
