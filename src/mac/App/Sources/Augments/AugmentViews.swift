import DataKit
import LeagueKit
import StatsKit
import SwiftUI

/// Shown left of League's selection cards while an augment choice is likely open
/// (`AugmentPickTracker`) or pinned with ⌥A – one narrow column, rarities stacked, so it fits beside
/// the cards also on 16:10. Static OP.GG statistics only – the offered cards are not read; several
/// options per rarity, no win rates (Riot policy, docs/COMPLIANCE.md).
struct AugmentOverlayView: View {
    let board: AugmentBoard
    /// Nil when pinned with ⌥A without a pending choice.
    let prompt: AugmentPickPrompt?
    let icons: IconCache

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            ForEach(board.columns) { column in
                RarityLabel(rarity: column.rarity).padding(.top, 4)
                ForEach(column.entries.prefix(4)) { entry in
                    AugmentRow(entry: entry, icons: icons, iconSize: 20)
                }
            }
            Text("OP.GG statistics · ⌥A hides")
                .font(.system(size: 9)).foregroundStyle(Palette.tertiaryText)
                .padding(.top, 2)
        }
        .padding(12)
        .frame(width: 250)
        .background(Palette.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.hairline))
        .foregroundStyle(Palette.text)
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            if let prompt {
                Text("Augment choice \(prompt.pick)/\(prompt.total)").font(.system(size: 13, weight: .semibold))
                if prompt.available > prompt.pick {
                    Text("+\(prompt.available - prompt.pick) pending")
                        .font(.system(size: 10)).foregroundStyle(Palette.accent)
                }
            } else {
                Text("Strong augments").font(.system(size: 13, weight: .semibold))
            }
        }
    }
}

/// Icon, grade, name and pick share of one augment.
struct AugmentRow: View {
    let entry: AugmentBoard.Entry
    let icons: IconCache
    let iconSize: CGFloat

    var body: some View {
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
                .help(String(localized: "Pick share"))
        }
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
                        AugmentRow(entry: entry, icons: icons, iconSize: iconSize)
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
        case .prismatic: String(localized: "Prismatic")
        case .gold: String(localized: "Gold")
        case .silver: String(localized: "Silver")
        case nil: String(localized: "All rarities")
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
                Text("Strong augments").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("Data: OP.GG").font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.secondaryText)
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
            Text("Runes are disabled in Mayhem. In game the list appears at every augment choice.")
                .font(.system(size: 9)).foregroundStyle(Palette.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
