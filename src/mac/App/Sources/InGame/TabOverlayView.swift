import LeagueKit
import StatsKit
import SwiftUI

/// Shown while Tab is held: both teams with ranks, plus the player's own CS and build progress.
/// No `Material` blur in game (GPU cost); a solid translucent background instead.
struct TabOverlayView: View {
    let coordinator: InGameCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let snapshot = coordinator.snapshot {
                HStack(alignment: .top, spacing: 16) {
                    // Practice tool / custom games may have an empty team.
                    ForEach([("ORDER", "Blau"), ("CHAOS", "Rot")], id: \.0) { team, title in
                        let players = snapshot.players.filter { $0.team == team }
                        if !players.isEmpty {
                            TeamColumn(title: title, players: players, coordinator: coordinator)
                        }
                    }
                }
                if let me = snapshot.me {
                    Divider().overlay(Palette.hairline)
                    MyGameRow(me: me, snapshot: snapshot, coordinator: coordinator)
                }
            }
            Text("Riftglass · Ränge: OP.GG · " + Disclaimer.short)
                .font(.system(size: 9))
                .foregroundStyle(Palette.tertiaryText)
        }
        .padding(14)
        .frame(width: 620)
        .background(Palette.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .foregroundStyle(Palette.text)
        .environment(\.colorScheme, .dark)
    }
}

private struct TeamColumn: View {
    let title: String
    let players: [LivePlayer]
    let coordinator: InGameCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.secondaryText)
            ForEach(players, id: \.displayID) { player in
                PlayerRow(player: player, rank: coordinator.ranks[player.displayID], coordinator: coordinator)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PlayerRow: View {
    let player: LivePlayer
    let rank: PlayerRank?
    let coordinator: InGameCoordinator

    var body: some View {
        HStack(spacing: 8) {
            ChampionIcon(key: player.championKey, champSelect: coordinator.champSelect, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(player.riotIDParts?.gameName ?? player.championName)
                    .font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(rank?.label ?? (coordinator.settings.ranksEnabled ? "…" : player.championName))
                    .font(.system(size: 10)).foregroundStyle(Palette.secondaryText).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text("\(player.scores.kills)/\(player.scores.deaths)/\(player.scores.assists)")
                .font(.system(size: 11).monospacedDigit())
            Text("\(player.scores.creepScore)")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(Palette.secondaryText)
                .frame(width: 28, alignment: .trailing)
        }
    }
}

private struct MyGameRow: View {
    let me: LivePlayer
    let snapshot: LiveGameSnapshot
    let coordinator: InGameCoordinator

    private var plannedItems: [Int] {
        coordinator.champSelect.plannedBuild?.allItemIds ?? []
    }

    var body: some View {
        HStack(spacing: 18) {
            if let cs = InGameAnalysis.csPerMinute(me, gameTime: snapshot.stats.gameTime) {
                metric(
                    "CS/min",
                    value: cs.formatted(.number.precision(.fractionLength(1))),
                    detail: InGameAnalysis.csBenchmark(for: me).map { "Richtwert \($0.formatted())" },
                    good: InGameAnalysis.csBenchmark(for: me).map { cs >= $0 }
                )
            }
            if !plannedItems.isEmpty {
                let progress = InGameAnalysis.buildProgress(owned: me.items, planned: plannedItems)
                metric("Build", value: "\(progress.done)/\(progress.total)", detail: nextItemName, good: nil)
            }
            if coordinator.settings.goldEstimateEnabled, let prices = coordinator.champSelect.staticData?.itemPrices,
               let diff = InGameAnalysis.laneGoldDifference(for: me, in: snapshot, prices: prices) {
                metric(
                    "Item-Gold vs. Lane",
                    value: (diff >= 0 ? "+" : "") + diff.formatted(),
                    detail: "Schätzung aus sichtbaren Items",
                    good: diff >= 0
                )
            }
            Spacer()
        }
    }

    private var nextItemName: String? {
        InGameAnalysis.nextItem(owned: me.items, planned: plannedItems)
            .flatMap { coordinator.champSelect.staticData?.itemsById[$0]?.name }
            .map { "Nächstes: \($0)" }
    }

    private func metric(_ title: String, value: String, detail: String?, good: Bool?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 10)).foregroundStyle(Palette.secondaryText)
            Text(value).font(.system(size: 16, weight: .semibold).monospacedDigit())
                .foregroundStyle(good.map { $0 ? Palette.positive : Palette.negative } ?? Palette.text)
            if let detail {
                Text(detail).font(.system(size: 9)).foregroundStyle(Palette.tertiaryText)
            }
        }
    }
}

/// Champion icon by Data Dragon key, from the shared icon cache.
struct ChampionIcon: View {
    let key: String
    let champSelect: ChampSelectCoordinator
    let size: CGFloat

    var body: some View {
        if let data = champSelect.staticData, let champion = data.champion(key: key) {
            IconView(
                url: champSelect.dataDragon.championIconURL(champion, version: data.version),
                icons: champSelect.icons,
                size: size
            )
        } else {
            IconView.missing(size: size)
        }
    }
}
