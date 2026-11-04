import DataKit
import LeagueKit
import StatsKit
import SwiftUI

/// Shown at the top of the screen while an augment choice is likely open (`AugmentPickTracker`),
/// clear of the selection cards in the middle. Static OP.GG statistics only – the offered cards are
/// not read; several options per rarity, no win rates (Riot policy, docs/COMPLIANCE.md).
struct AugmentOverlayView: View {
    let board: AugmentBoard
    let prompt: AugmentPickPrompt
    let icons: IconCache

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Augment-Wahl \(prompt.pick)/\(prompt.total)").font(.system(size: 13, weight: .semibold))
                if prompt.available > prompt.pick {
                    Text("+\(prompt.available - prompt.pick) weitere offen")
                        .font(.system(size: 10)).foregroundStyle(Palette.accent)
                }
                Spacer()
                Text("Starke Optionen pro Seltenheit · OP.GG-Statistik")
                    .font(.system(size: 10)).foregroundStyle(Palette.tertiaryText)
            }
            AugmentColumnsView(board: board, limit: 5, icons: icons, iconSize: 22)
        }
        .padding(12)
        .frame(width: board.columns.count > 1 ? 660 : 280)
        .background(Palette.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.hairline))
        .foregroundStyle(Palette.text)
        .environment(\.colorScheme, .dark)
    }
}

/// One column per rarity (Prismatic, Gold, Silver), best first within each.
struct AugmentColumnsView: View {
    let board: AugmentBoard
    let limit: Int
    let icons: IconCache
    let iconSize: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(board.columns) { column in
                VStack(alignment: .leading, spacing: 5) {
                    RarityLabel(rarity: column.rarity)
                    ForEach(column.entries.prefix(limit)) { entry in
                        HStack(spacing: 6) {
                            if let url = entry.iconURL {
                                IconView(url: url, icons: icons, size: iconSize)
                            }
                            GradeBadge(grade: entry.ranked.grade)
                            Text(entry.name).font(.system(size: 11)).lineLimit(1)
                            Spacer(minLength: 2)
                            Text(entry.ranked.stat.pickRate.formatted(.percent.precision(.fractionLength(0))))
                                .font(.system(size: 10).monospacedDigit())
                                .foregroundStyle(Palette.tertiaryText)
                                .help("Pick-Anteil")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct RarityLabel: View {
    let rarity: AugmentRarity?

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(color)
    }

    private var title: String {
        switch rarity {
        case .prismatic: "Prismatisch"
        case .gold: "Gold"
        case .silver: "Silber"
        case nil: "Alle Seltenheiten"
        }
    }

    private var color: Color {
        switch rarity {
        case .prismatic: Color(red: 0.86, green: 0.62, blue: 0.98)
        case .gold: Color(red: 0.95, green: 0.78, blue: 0.38)
        case .silver: Color(red: 0.78, green: 0.82, blue: 0.86)
        case nil: Palette.secondaryText
        }
    }
}

/// Relative grade within the champion's augments of one rarity.
struct GradeBadge: View {
    let grade: RankedAugment.Grade

    var body: some View {
        Text(grade.rawValue)
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .frame(width: 16, height: 16)
            .background(color.opacity(0.9), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .foregroundStyle(Color.black)
    }

    private var color: Color {
        switch grade {
        case .top: Palette.accent
        case .strong: Palette.positive
        case .solid: Color.white.opacity(0.55)
        case .niche: Color.white.opacity(0.3)
        }
    }
}

/// Champ select (ARAM: Mayhem): the top options per rarity, as a preview of the in-game list.
struct AugmentsCard: View {
    let board: AugmentBoard
    let icons: IconCache

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Starke Augments").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("Daten: OP.GG").font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.secondaryText)
            }
            ForEach(board.columns) { column in
                RarityLabel(rarity: column.rarity).padding(.top, 2)
                ForEach(column.entries.prefix(3)) { entry in
                    HStack(spacing: 6) {
                        if let url = entry.iconURL {
                            IconView(url: url, icons: icons, size: 16)
                        }
                        GradeBadge(grade: entry.ranked.grade)
                        Text(entry.name).font(.system(size: 11)).lineLimit(1)
                    }
                }
            }
            Text("Runen sind in Mayhem deaktiviert. Im Spiel erscheint die Liste bei jeder Augment-Wahl.")
                .font(.system(size: 9)).foregroundStyle(Palette.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
