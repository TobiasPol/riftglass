import LeagueKit
@testable import Riftglass
import StatsKit
import Testing

struct BuildMappingTests {
    private func sampleBuild(spells: [Int], queue: BuildQueue = .ranked, skillOrder: [String] = []) -> BuildOption {
        BuildOption(
            id: "b1",
            title: "OP.GG Build",
            role: .middle,
            championKey: "Ahri",
            queue: queue,
            source: .opgg,
            runes: .init(
                primaryStyleId: 8100,
                subStyleId: 8200,
                perkIds: [8112, 8139, 8140, 8106, 8210, 8226, 5005, 5008, 5001]
            ),
            summonerSpells: spells,
            itemBlocks: [.init(title: "Core", itemIds: [3118, 4645])],
            skillOrder: skillOrder
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

    @MainActor
    @Test func combineBuildsChecksQueueAndSkillOrder() {
        let general = sampleBuild(spells: [4, 14], queue: .ranked, skillOrder: ["Q", "W", "E"])
        let flexGeneral = sampleBuild(spells: [4, 14], queue: .flex, skillOrder: ["Q", "W", "E"])

        // Mismatched queue matchup build is excluded.
        let wrongQueue = ChampSelectCoordinator.combineBuilds(
            [flexGeneral], matchup: general, championKey: "Ahri", role: .middle, queue: .flex
        )
        #expect(wrongQueue == [flexGeneral])

        // Same runes/items/spells but different skill order is preserved.
        let distinctSkill = sampleBuild(spells: [4, 14], queue: .ranked, skillOrder: ["W", "Q", "E"])
        let kept = ChampSelectCoordinator.combineBuilds(
            [general], matchup: distinctSkill, championKey: "Ahri", role: .middle, queue: .ranked
        )
        #expect(kept.count == 2)

        // Identical skill order as well is deduplicated.
        let identical = ChampSelectCoordinator.combineBuilds(
            [general], matchup: general, championKey: "Ahri", role: .middle, queue: .ranked
        )
        #expect(identical == [general])
    }
}
