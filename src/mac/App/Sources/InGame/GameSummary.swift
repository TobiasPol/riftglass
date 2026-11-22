import Foundation
import LeagueKit

/// Compact post-game summary, shown in the menu bar popover and persisted in recent history.
struct GameSummary: Codable, Equatable, Identifiable {
    let id: UUID
    let playedAt: Date
    let championName: String
    let kills: Int
    let deaths: Int
    let assists: Int
    let csPerMinute: Double?
    let minutes: Int
    let buildDone: Int
    let buildTotal: Int
    let won: Bool?
    let damageShare: Double?
    let killParticipation: Double?
    let visionScore: Int?

    init(
        id: UUID = UUID(),
        playedAt: Date = Date(),
        championName: String,
        kills: Int,
        deaths: Int,
        assists: Int,
        csPerMinute: Double?,
        minutes: Int,
        buildDone: Int,
        buildTotal: Int,
        won: Bool? = nil,
        damageShare: Double? = nil,
        killParticipation: Double? = nil,
        visionScore: Int? = nil
    ) {
        self.id = id
        self.playedAt = playedAt
        self.championName = championName
        self.kills = kills
        self.deaths = deaths
        self.assists = assists
        self.csPerMinute = csPerMinute
        self.minutes = minutes
        self.buildDone = buildDone
        self.buildTotal = buildTotal
        self.won = won
        self.damageShare = damageShare
        self.killParticipation = killParticipation
        self.visionScore = visionScore
    }

    /// Nil without the own player (spectating) – another player's game is not summarised.
    init?(snapshot: LiveGameSnapshot, plan: ItemPlan?) {
        guard let me = snapshot.me, snapshot.stats.gameTime > 60 else { return nil }
        self.init(
            championName: me.championName,
            kills: me.scores.kills,
            deaths: me.scores.deaths,
            assists: me.scores.assists,
            csPerMinute: InGameAnalysis.csPerMinute(me, gameTime: snapshot.stats.gameTime),
            minutes: Int(snapshot.stats.gameTime / 60),
            buildDone: plan.map { InGameAnalysis.buildProgress(owned: me.items, plan: $0).done } ?? 0,
            buildTotal: plan.map { InGameAnalysis.buildProgress(owned: me.items, plan: $0).total } ?? 0
        )
    }

    init?(endOfGame stats: EndOfGameStats, championName: String) {
        guard let kills = stats.kills, let deaths = stats.deaths, let assists = stats.assists else { return nil }
        self.init(
            championName: championName,
            kills: kills,
            deaths: deaths,
            assists: assists,
            csPerMinute: nil,
            minutes: max(1, (stats.gameLength ?? 0) / 60),
            buildDone: 0,
            buildTotal: 0,
            won: stats.won,
            damageShare: stats.damageShare,
            killParticipation: stats.killParticipation,
            visionScore: stats.visionScore
        )
    }

    func enriched(with stats: EndOfGameStats) -> GameSummary {
        GameSummary(
            id: id,
            playedAt: playedAt,
            championName: championName,
            kills: stats.kills ?? kills,
            deaths: stats.deaths ?? deaths,
            assists: stats.assists ?? assists,
            csPerMinute: csPerMinute,
            minutes: minutes,
            buildDone: buildDone,
            buildTotal: buildTotal,
            won: stats.won ?? won,
            damageShare: stats.damageShare ?? damageShare,
            killParticipation: stats.killParticipation ?? killParticipation,
            visionScore: stats.visionScore ?? visionScore
        )
    }

    var kdaText: String {
        "\(kills)/\(deaths)/\(assists)"
    }
}
