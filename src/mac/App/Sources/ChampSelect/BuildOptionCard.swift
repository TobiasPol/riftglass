import DataKit
import StatsKit
import SwiftUI

/// One build option with its runes, spells, items and the import buttons.
struct BuildOptionCard: View {
    let build: BuildOption
    let coordinator: ChampSelectCoordinator

    private var data: StaticData? {
        coordinator.staticData
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(build.title).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(build.source.attribution)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.secondaryText)
            }
            if let stats = build.stats {
                Text(Self.statsLine(stats))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(stats.winRate >= 0.5 ? Palette.positive : Palette.secondaryText)
            }
            HStack(spacing: 4) {
                ForEach(Array(build.runes.perkIds.prefix(6).enumerated()), id: \.offset) { index, perkId in
                    runeIcon(perkId, size: index == 0 ? 28 : 20)
                }
                Spacer(minLength: 8)
                ForEach(build.summonerSpells, id: \.self) { spellIcon($0) }
            }
            ForEach(build.itemBlocks, id: \.title) { block in
                HStack(spacing: 4) {
                    Text(block.title)
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.secondaryText)
                        .frame(width: 52, alignment: .leading)
                    ForEach(block.itemIds, id: \.self) { itemIcon($0) }
                }
            }
            if !build.skillOrder.isEmpty {
                Text("Skills: " + build.skillOrder.prefix(9).joined(separator: " › "))
                    .font(.system(size: 10).monospaced())
                    .foregroundStyle(Palette.secondaryText)
            }
            buttons
        }
        .padding(10)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var buttons: some View {
        HStack(spacing: 6) {
            Button("Alles übernehmen") { coordinator.importAll(build) }
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
            Button("Runen") { coordinator.importRunes(build) }
            Button("Spells") { coordinator.setSpells(build) }
                .disabled(build.summonerSpells.count < 2)
            Button("Items") { coordinator.importItemSet(build) }
                .disabled(build.itemBlocks.isEmpty)
        }
        .controlSize(.small)
        .disabled(isRunning)
    }

    static func statsLine(_ stats: BuildOption.Stats) -> String {
        let winRate = stats.winRate.formatted(.percent.precision(.fractionLength(1)))
        let games = stats.games.formatted(.number.notation(.compactName))
        let pick = stats.pickRate.map { " · Pick " + $0.formatted(.percent.precision(.fractionLength(0))) } ?? ""
        return "\(winRate) Winrate · \(games) Spiele" + pick
    }

    private var isRunning: Bool {
        if case .running = coordinator.actionState {
            return true
        }
        return false
    }

    @ViewBuilder
    private func runeIcon(_ id: Int, size: CGFloat) -> some View {
        if let rune = data?.runesById[id] {
            IconView(url: coordinator.dataDragon.runeIconURL(rune.icon), icons: coordinator.icons, size: size)
                .help(rune.name)
        } else {
            IconView.missing(size: size)
        }
    }

    @ViewBuilder
    private func spellIcon(_ id: Int) -> some View {
        if let data, let spell = data.spellsById[id] {
            IconView(
                url: coordinator.dataDragon.spellIconURL(spell, version: data.version),
                icons: coordinator.icons,
                size: 22
            )
            .help(spell.name)
        } else {
            IconView.missing(size: 22)
        }
    }

    @ViewBuilder
    private func itemIcon(_ id: Int) -> some View {
        if let data {
            IconView(
                url: coordinator.dataDragon.itemIconURL(id, version: data.version),
                icons: coordinator.icons,
                size: 24
            )
            .help(data.itemsById[id]?.name ?? "Item \(id)")
        } else {
            IconView.missing(size: 24)
        }
    }
}

/// Icon from the `IconCache`; synchronous memory hit, otherwise loaded once.
struct IconView: View {
    let url: URL
    let icons: IconCache
    let size: CGFloat
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image = image ?? icons.cachedImage(for: url) {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                Self.missing(size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .task(id: url) { image = await icons.image(for: url) }
    }

    static func missing(size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.white.opacity(0.08))
            .frame(width: size, height: size)
    }
}
