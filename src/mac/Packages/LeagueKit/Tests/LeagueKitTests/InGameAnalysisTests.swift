import Foundation
@testable import LeagueKit
import Testing

struct InGameAnalysisTests {
    private func items(_ ids: [Int]) throws -> [LivePlayer.Item] {
        let json = "[" + ids.enumerated().map { #"{"itemID":\#($1),"slot":\#($0)}"# }.joined(separator: ",") + "]"
        return try JSONDecoder().decode([LivePlayer.Item].self, from: Data(json.utf8))
    }

    /// Ahri mid as OP.GG recommends it: core, boots, then one of three fourth items.
    private let plan = ItemPlan(required: [3118, 4645, 3157, 3020], alternatives: [3089, 3157, 3135])

    @Test func planHasNoDuplicates() {
        #expect(plan.alternatives == [3089, 3135])
        #expect(ItemPlan(required: [1, 1, 2]).required == [1, 2])
        #expect(ItemPlan(required: []).isEmpty && !plan.isEmpty)
    }

    /// The bug: starters and all three alternatives counted, so a finished build read "5/8" and the
    /// next item was the Doran's Ring sold long ago.
    @Test func finishedBuildIsCompleteWithoutStartersAndWithOneAlternative() throws {
        let owned = try items([3118, 4645, 3157, 3020, 3089, 3340])
        let progress = InGameAnalysis.buildProgress(owned: owned, plan: plan)
        #expect(progress.done == 5 && progress.total == 5)
        #expect(InGameAnalysis.nextItem(owned: owned, plan: plan) == nil)
    }

    @Test func nextItemFollowsTheCoreThenOffersTheFirstAlternative() throws {
        let starting = try items([1056, 2003])
        #expect(InGameAnalysis.buildProgress(owned: starting, plan: plan).done == 0)
        #expect(InGameAnalysis.nextItem(owned: starting, plan: plan) == 3118)
        let core = try items([3118, 4645, 3157, 3020])
        #expect(InGameAnalysis.buildProgress(owned: core, plan: plan).done == 4)
        #expect(InGameAnalysis.nextItem(owned: core, plan: plan) == 3089)
        let coreOnly = ItemPlan(required: [3118])
        #expect(InGameAnalysis.buildProgress(owned: core, plan: coreOnly).total == 1)
        #expect(InGameAnalysis.nextItem(owned: core, plan: coreOnly) == nil)
    }

    @Test func ownPlayerIsMatchedByFullRiotIdBeforeTheGameName() throws {
        func player(_ champion: String, tag: String) -> String {
            #"{"championName":"\#(champion)","riotId":"Same#\#(tag)","riotIdGameName":"Same","#
                + #""riotIdTagLine":"\#(tag)","team":"ORDER","level":1,"items":[],"#
                + #""scores":{"kills":0,"deaths":0,"assists":0,"creepScore":0}}"#
        }
        let players = try JSONDecoder().decode(
            [LivePlayer].self,
            from: Data("[\(player("Lux", tag: "AAA")),\(player("Garen", tag: "BBB"))]".utf8)
        )
        let active = try JSONDecoder().decode(
            LiveActivePlayer.self,
            from: Data(#"{"riotId":"Same#BBB","riotIdGameName":"Same","level":1,"currentGold":0}"#.utf8)
        )
        let stats = LiveGameStats(gameMode: "CLASSIC", gameTime: 100, mapNumber: 11)
        let snapshot = LiveGameSnapshot(stats: stats, activePlayer: active, players: players)
        #expect(snapshot.me?.championName == "Garen")
    }
}
