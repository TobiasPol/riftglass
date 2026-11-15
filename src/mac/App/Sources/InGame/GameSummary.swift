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

    /// Nil without the own player (spectating) – another player's game is not summarised.
    init?(snapshot: LiveGameSnapshot, plan: ItemPlan?) {
        guard let me = snapshot.me, snapshot.stats.gameTime > 60 else { return nil }
        championName = me.championName
        kills = me.scores.kills
        deaths = me.scores.deaths
        assists = me.scores.assists
        csPerMinute = InGameAnalysis.csPerMinute(me, gameTime: snapshot.stats.gameTime)
        minutes = Int(snapshot.stats.gameTime / 60)
        let progress = plan.map { InGameAnalysis.buildProgress(owned: me.items, plan: $0) }
        buildDone = progress?.done ?? 0
        buildTotal = progress?.total ?? 0
    }

    var kdaText: String {
        "\(kills)/\(deaths)/\(assists)"
    }
}
