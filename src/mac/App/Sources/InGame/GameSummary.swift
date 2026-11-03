import Foundation
import LeagueKit

/// Compact post-game summary, shown in the menu bar popover.
struct GameSummary: Equatable {
    let championName: String
    let kills: Int
    let deaths: Int
    let assists: Int
    let csPerMinute: Double?
    let minutes: Int
    let buildDone: Int
    let buildTotal: Int

    init?(snapshot: LiveGameSnapshot, plannedItems: [Int]) {
        guard let me = snapshot.me ?? snapshot.players.first, snapshot.stats.gameTime > 60 else { return nil }
        championName = me.championName
        kills = me.scores.kills
        deaths = me.scores.deaths
        assists = me.scores.assists
        csPerMinute = InGameAnalysis.csPerMinute(me, gameTime: snapshot.stats.gameTime)
        minutes = Int(snapshot.stats.gameTime / 60)
        let progress = InGameAnalysis.buildProgress(owned: me.items, planned: plannedItems)
        buildDone = progress.done
        buildTotal = progress.total
    }

    var kdaText: String {
        "\(kills)/\(deaths)/\(assists)"
    }
}
