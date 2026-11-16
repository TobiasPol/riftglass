import StatsKit
import SwiftUI

/// Ban options while the own ban is open, pick options until the own lock-in, then the own
/// champion's duo statistics with the team. Always several options with their reasons – the
/// player decides (docs/COMPLIANCE.md).
struct DraftSection: View {
    let coordinator: ChampSelectCoordinator

    var body: some View {
        let draft = coordinator.draft
        if !draft.bans.isEmpty {
            BriefingCard(title: "Ban options", source: "Data: OP.GG") {
                ForEach(draft.bans) { DraftOptionRow(option: $0, coordinator: coordinator, isBan: true) }
                note("Likely enemy picks that are strong – options, not a recommendation.")
            }
        }
        if !draft.picks.isEmpty {
            BriefingCard(title: pickTitle(draft.role), source: "Data: OP.GG") {
                opponentLine(draft)
                ForEach(draft.picks.prefix(draft.bans.isEmpty ? 5 : 3)) {
                    DraftOptionRow(option: $0, coordinator: coordinator, isBan: false)
                }
                note(Self.pickNote)
            }
        }
        if !draft.teamSynergies.isEmpty {
            TeamSynergyCard(coordinator: coordinator, synergies: draft.teamSynergies)
        }
    }

    private static let pickNote: LocalizedStringKey = """
    Ranked by lane strength, matchup, synergy, team fit and your mastery – options, not a recommendation.
    """

    private func pickTitle(_ role: Role?) -> LocalizedStringKey {
        guard let role else { return "Pick options" }
        return "Pick options · \(role.displayName)"
    }

    private func opponentLine(_ draft: DraftAdvice) -> some View {
        Text(opponentText(draft.opponent)).font(.system(size: 10)).foregroundStyle(Palette.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func opponentText(_ opponent: LaneAssigner.Assignment?) -> String {
        guard let opponent else {
            return String(localized: "Lane opponent not picked yet – safe options rank by strength and team.")
        }
        let name = coordinator.name(of: opponent.championId)
        if opponent.isRevealed {
            return String(localized: "Against \(name)")
        }
        return String(localized: "Against \(name) (likely)")
    }

    private func note(_ text: LocalizedStringKey) -> some View {
        Text(text).font(.system(size: 10)).foregroundStyle(Palette.tertiaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct DraftOptionRow: View {
    let option: DraftOption
    let coordinator: ChampSelectCoordinator
    let isBan: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ChampionIcon(key: coordinator.key(of: option.id), champSelect: coordinator, size: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(coordinator.name(of: option.id)).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    if !isBan, option.id == coordinator.championId {
                        Text("hovered").font(.system(size: 10)).foregroundStyle(Palette.accent)
                    }
                    Spacer(minLength: 4)
                    if let winRate = option.winRate {
                        Text(percent(winRate)).font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(Palette.secondaryText)
                    }
                }
                Text(reasons).font(.system(size: 10)).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The three weightiest reasons, coloured by their effect (bans: neutral, the counter stands out).
    private var reasons: AttributedString {
        var result = AttributedString()
        for (index, scored) in option.reasons.prefix(3).enumerated() {
            if index > 0 {
                var separator = AttributedString(" · ")
                separator.foregroundColor = Palette.tertiaryText
                result.append(separator)
            }
            var part = AttributedString(DraftReasonText.text(scored.reason, coordinator: coordinator))
            part.foregroundColor = color(scored)
            result.append(part)
        }
        return result
    }

    private func color(_ scored: ScoredReason) -> Color {
        if isBan {
            if case .countersYourPick = scored.reason {
                return Palette.negative
            }
            return Palette.secondaryText
        }
        if scored.impact >= 0.25 {
            return Palette.positive
        }
        return scored.impact <= -0.25 ? Palette.negative : Palette.secondaryText
    }
}

private struct TeamSynergyCard: View {
    let coordinator: ChampSelectCoordinator
    let synergies: [TeamSynergy]

    var body: some View {
        BriefingCard(title: "Synergy with your team", source: "Data: OP.GG") {
            ForEach(synergies) { duo in
                HStack(spacing: 8) {
                    ChampionIcon(key: coordinator.key(of: duo.allyId), champSelect: coordinator, size: 20)
                    Text(coordinator.name(of: duo.allyId)).font(.system(size: 11)).lineLimit(1)
                    Spacer()
                    Text("\(percent(duo.winRate)) together · \(duo.games.formatted()) games")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(duo.winRate >= 0.52 ? Palette.positive : duo.winRate <= 0.48 ? Palette
                            .negative : Palette.secondaryText)
                }
            }
        }
    }
}

/// Neutral wording of a reason ("an option", never "you should").
enum DraftReasonText {
    @MainActor
    static func text(_ reason: DraftReason, coordinator: ChampSelectCoordinator) -> String {
        switch reason {
        case let .meta(tier, _):
            tier.map { String(localized: "Tier \($0)") } ?? String(localized: "Lane statistics")
        case let .laneMatchup(opponentId, winRate, _):
            String(localized: "\(percent(winRate)) vs. \(coordinator.name(of: opponentId))")
        case let .synergy(allyId, winRate, _):
            String(localized: "\(percent(winRate)) with \(coordinator.name(of: allyId))")
        case let .countersYourPick(yourChampionId, winRate, _):
            String(localized: "Beats your \(coordinator.name(of: yourChampionId)) (\(percent(winRate)))")
        case let .presence(pickRate, banRate):
            String(localized: "Picked \(percent(pickRate)) · banned \(percent(banRate))")
        default:
            fixedText(reason)
        }
    }

    /// Reasons without champion names.
    private static func fixedText(_ reason: DraftReason) -> String {
        switch reason {
        case .addsMagicDamage: String(localized: "Adds magic damage")
        case .addsPhysicalDamage: String(localized: "Adds physical damage")
        case .addsFrontline: String(localized: "Adds frontline")
        case let .comfort(points):
            String(localized: "Your champion (\(points.formatted(.number.notation(.compactName))) mastery)")
        case .unfamiliar: String(localized: "Little mastery")
        case .inYourLane: String(localized: "Your lane")
        default: ""
        }
    }
}

extension Role {
    var displayName: String {
        switch self {
        case .top: String(localized: "Top")
        case .jungle: String(localized: "Jungle")
        case .middle: String(localized: "Mid")
        case .bottom: String(localized: "Bot")
        case .utility: String(localized: "Support")
        }
    }
}
