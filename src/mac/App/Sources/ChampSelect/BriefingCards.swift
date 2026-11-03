import DataKit
import StatsKit
import SwiftUI

/// Briefing above the build options: counter options (own pick turn), lane matchup, team comp.
struct BriefingSection: View {
    let coordinator: ChampSelectCoordinator

    var body: some View {
        let briefing = coordinator.briefing
        if coordinator.settings.briefingEnabled {
            if !briefing.counterPicks.isEmpty, let opponent = briefing.opponent {
                CounterPicksCard(coordinator: coordinator, opponentId: opponent.championId, briefing: briefing)
            }
            if let opponent = briefing.opponent {
                MatchupCard(coordinator: coordinator, opponent: opponent, matchup: briefing.matchup)
            }
            if !briefing.enemy.isEmpty {
                TeamCompCard(briefing: briefing)
            }
        }
    }
}

private struct CounterPicksCard: View {
    let coordinator: ChampSelectCoordinator
    let opponentId: Int
    let briefing: ChampSelectBriefing

    var body: some View {
        BriefingCard(title: "Counter-Optionen gegen \(coordinator.name(of: opponentId))", source: "Daten: OP.GG") {
            ForEach(briefing.counterPicks) { pick in
                let available = briefing.pickableIds?.contains(pick.id) ?? true
                HStack(spacing: 8) {
                    ChampionIcon(key: coordinator.key(of: pick.id), champSelect: coordinator, size: 20)
                    Text(pick.name).font(.system(size: 11)).lineLimit(1)
                    if !available {
                        Text("nicht verfügbar").font(.system(size: 10)).foregroundStyle(Palette.tertiaryText)
                    }
                    Spacer()
                    Text("\(percent(pick.winRate)) · \(pick.games.formatted()) Spiele")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(Palette.secondaryText)
                }
                .opacity(available ? 1 : 0.45)
            }
            Text("Siegquote des Counters in dieser Lane – Optionen, keine Empfehlung.")
                .font(.system(size: 10)).foregroundStyle(Palette.tertiaryText)
        }
    }
}

private struct MatchupCard: View {
    let coordinator: ChampSelectCoordinator
    let opponent: LaneAssigner.Assignment
    let matchup: MatchupBrief?

    var body: some View {
        BriefingCard(title: "Lane-Gegner", source: "Daten: OP.GG") {
            HStack(spacing: 8) {
                ChampionIcon(key: coordinator.key(of: opponent.championId), champSelect: coordinator, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(coordinator.name(of: opponent.championId)).font(.system(size: 12, weight: .semibold))
                    if !opponent.isLikely {
                        Text("vermutlich – Lane geschätzt").font(.system(size: 10))
                            .foregroundStyle(Palette.tertiaryText)
                    }
                }
                Spacer()
                if let winRate = matchup?.winRate, let games = matchup?.games {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(percent(winRate)).font(.system(size: 13, weight: .semibold).monospacedDigit())
                            .foregroundStyle(winRate >= 0.52 ? Palette.positive : winRate <= 0.48 ? Palette
                                .negative : Palette.text)
                        Text("\(games.formatted()) Spiele").font(.system(size: 10))
                            .foregroundStyle(Palette.secondaryText)
                    }
                }
            }
            if let matchup {
                details(matchup)
            }
        }
    }

    @ViewBuilder
    private func details(_ matchup: MatchupBrief) -> some View {
        let opponentName = coordinator.name(of: opponent.championId)
        let facts = [
            matchup.laneAdvantage.map { "Lane-Vorteil: \($0 == .me ? "du" : opponentName)" },
            matchup.soloKillAdvantage.map { "Solo-Kills: \($0 == .me ? "du" : opponentName)" },
            matchup.playStyle.map { "Spielweise: \(Self.playStyle($0))" }
        ].compactMap(\.self)
        if !facts.isEmpty {
            Text(facts.joined(separator: " · ")).font(.system(size: 11)).foregroundStyle(Palette.secondaryText)
        }
        if let tip = matchup.tip {
            Text(tip).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
        }
    }

    static func playStyle(_ value: String) -> String {
        switch value.lowercased() {
        case "even": "ausgeglichen"
        case "aggressive": "aggressiv"
        case "passive", "defensive": "defensiv"
        default: value
        }
    }
}

private struct TeamCompCard: View {
    let briefing: ChampSelectBriefing

    var body: some View {
        BriefingCard(title: "Teams", source: "Schätzung: Data Dragon") {
            row("Dein Team", briefing.ally)
            row("Gegner", briefing.enemy)
            ForEach(Array(briefing.hints.enumerated()), id: \.offset) { _, hint in
                Label(Self.text(hint), systemImage: "lightbulb")
                    .font(.system(size: 11))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func row(_ title: String, _ team: TeamProfile) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 11)).frame(width: 62, alignment: .leading)
            DamageBar(physicalShare: team.physicalShare)
            Text("Frontline \(team.frontline)").font(.system(size: 10).monospacedDigit())
                .foregroundStyle(Palette.secondaryText)
        }
    }

    static func text(_ hint: CompHint) -> String {
        switch hint {
        case let .enemyMostlyPhysical(share): "Gegner ~\(percent(share)) physisch – Rüstung ist eine Option."
        case let .enemyMostlyMagic(share): "Gegner ~\(percent(share)) magisch – Magieresistenz ist eine Option."
        case let .manyEnemyAssassins(count): "\(count) Assassinen beim Gegner – defensive Items sind eine Option."
        case .noAllyFrontline: "Kaum Frontline im eigenen Team – ein robuster Pick oder Build ist eine Option."
        }
    }
}

/// Physical (left, warm) vs. magic (right, cool) share; grey without data.
private struct DamageBar: View {
    let physicalShare: Double?

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                if let share = physicalShare {
                    Rectangle().fill(Palette.negative.opacity(0.8)).frame(width: proxy.size.width * share)
                    Rectangle().fill(Palette.accent.opacity(0.8))
                } else {
                    Rectangle().fill(Palette.hairline)
                }
            }
        }
        .frame(height: 6)
        .clipShape(Capsule())
        .help(physicalShare.map { "\(percent($0)) physisch · \(percent(1 - $0)) magisch" } ?? "Keine Daten")
    }
}

private struct BriefingCard<Content: View>: View {
    let title: String
    let source: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Spacer()
                Text(source).font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.secondaryText)
            }
            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private func percent(_ value: Double) -> String {
    value.formatted(.percent.precision(.fractionLength(0)))
}

extension ChampSelectCoordinator {
    func name(of championId: Int) -> String {
        staticData?.champion(championId)?.name ?? "Champion \(championId)"
    }

    /// Data Dragon key for `ChampionIcon`; empty (→ placeholder icon) when unknown.
    func key(of championId: Int) -> String {
        staticData?.champion(championId)?.id ?? ""
    }
}
