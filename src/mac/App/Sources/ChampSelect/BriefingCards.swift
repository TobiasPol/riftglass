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
        BriefingCard(title: "Counter options vs. \(coordinator.name(of: opponentId))", source: "Data: OP.GG") {
            ForEach(briefing.counterPicks) { pick in
                let available = briefing.pickableIds?.contains(pick.id) ?? true
                HStack(spacing: 8) {
                    ChampionIcon(key: coordinator.key(of: pick.id), champSelect: coordinator, size: 20)
                    Text(pick.name).font(.system(size: 11)).lineLimit(1)
                    if !available {
                        Text("unavailable").font(.system(size: 10)).foregroundStyle(Palette.tertiaryText)
                    }
                    Spacer()
                    Text("\(percent(pick.winRate)) · \(pick.games.formatted()) games")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(Palette.secondaryText)
                }
                .opacity(available ? 1 : 0.45)
            }
            Text("Win rate of the counter in this lane – options, not a recommendation.")
                .font(.system(size: 10)).foregroundStyle(Palette.tertiaryText)
        }
    }
}

private struct MatchupCard: View {
    let coordinator: ChampSelectCoordinator
    let opponent: LaneAssigner.Assignment
    let matchup: MatchupBrief?

    var body: some View {
        BriefingCard(title: "Lane opponent", source: "Data: OP.GG") {
            HStack(spacing: 8) {
                ChampionIcon(key: coordinator.key(of: opponent.championId), champSelect: coordinator, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(coordinator.name(of: opponent.championId)).font(.system(size: 12, weight: .semibold))
                    if !opponent.isRevealed {
                        Text("likely – lane estimated").font(.system(size: 10))
                            .foregroundStyle(Palette.tertiaryText)
                    }
                }
                Spacer()
                if let winRate = matchup?.winRate, let games = matchup?.games {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(percent(winRate)).font(.system(size: 13, weight: .semibold).monospacedDigit())
                            .foregroundStyle(winRate >= 0.52 ? Palette.positive : winRate <= 0.48 ? Palette
                                .negative : Palette.text)
                        Text("\(games.formatted()) games").font(.system(size: 10))
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
        let opponentName = coordinator.name(of: opponent.championId), you = String(localized: "you")
        let facts = [
            matchup.laneAdvantage.map { String(localized: "Lane advantage: \($0 == .me ? you : opponentName)") },
            matchup.soloKillAdvantage.map { String(localized: "Solo kills: \($0 == .me ? you : opponentName)") },
            matchup.playStyle.map { String(localized: "Play style: \(Self.playStyle($0))") }
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
        case "even": String(localized: "even")
        case "aggressive": String(localized: "aggressive")
        case "passive", "defensive": String(localized: "defensive")
        default: value
        }
    }
}

private struct TeamCompCard: View {
    let briefing: ChampSelectBriefing

    var body: some View {
        BriefingCard(title: "Teams", source: "Estimate: Data Dragon") {
            row("Your team", briefing.ally)
            row("Enemy", briefing.enemy)
            ForEach(Array(briefing.hints.enumerated()), id: \.offset) { _, hint in
                Label(Self.text(hint), systemImage: "lightbulb")
                    .font(.system(size: 11))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func row(_ title: LocalizedStringKey, _ team: TeamProfile) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 11)).frame(width: 62, alignment: .leading)
            DamageBar(physicalShare: team.physicalShare)
            Text("Frontline \(team.frontline)").font(.system(size: 10).monospacedDigit())
                .foregroundStyle(Palette.secondaryText)
        }
    }

    static func text(_ hint: CompHint) -> String {
        switch hint {
        case let .enemyMostlyPhysical(share):
            String(localized: "Enemy ~\(percent(share)) physical – armor is an option.")
        case let .enemyMostlyMagic(share):
            String(localized: "Enemy ~\(percent(share)) magic – magic resist is an option.")
        case let .manyEnemyAssassins(count):
            String(localized: "\(count) enemy assassins – defensive items are an option.")
        case .noAllyFrontline:
            String(localized: "Little frontline on your team – a sturdy pick or build is an option.")
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
        .help(physicalShare.map { String(localized: "\(percent($0)) physical · \(percent(1 - $0)) magic") }
            ?? String(localized: "No data"))
    }
}

private struct BriefingCard<Content: View>: View {
    let title: LocalizedStringKey
    let source: LocalizedStringKey
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
