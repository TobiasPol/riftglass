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
                    ForEach(
                        [("ORDER", String(localized: "Blue")), ("CHAOS", String(localized: "Red"))],
                        id: \.0
                    ) { team, title in
                        let players = snapshot.players.filter { $0.team == team }
                        if !players.isEmpty {
                            TeamColumn(title: title, players: players, coordinator: coordinator)
                        }
                    }
                }
                if let me = snapshot.me, hasMetrics(me: me, snapshot: snapshot) {
                    Divider().overlay(Palette.hairline)
                    MyGameRow(me: me, snapshot: snapshot, coordinator: coordinator)
                }
                let timers = coordinator.settings.objectiveTimersEnabled
                    ? ObjectiveTimerTracker.activeTimers(from: snapshot.events, at: snapshot.stats.gameTime)
                    : []
                if !timers.isEmpty {
                    Divider().overlay(Palette.hairline)
                    ObjectivesBar(timers: timers, gameTime: snapshot.stats.gameTime)
                }
                // ARAM: Mayhem – always reachable, also when the automatic list guessed the timing wrong.
                if let board = coordinator.augmentBoard, !board.isEmpty {
                    Divider().overlay(Palette.hairline)
                    AugmentColumnsView(board: board, limit: 3, icons: coordinator.champSelect.icons, iconSize: 18)
                }
            }
            Text("Riftglass · Ranks: OP.GG · \(Disclaimer.short)")
                .font(.system(size: 9))
                .foregroundStyle(Palette.tertiaryText)
        }
        .padding(14)
        .frame(width: 620)
        .background(Palette.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .foregroundStyle(Palette.text)
        .environment(\.colorScheme, .dark)
    }

    private func hasMetrics(me: LivePlayer, snapshot: LiveGameSnapshot) -> Bool {
        let hasCS = InGameAnalysis.csPerMinute(me, gameTime: snapshot.stats.gameTime) != nil
        let hasPlan = coordinator.itemPlan(for: me) != nil
        let hasGold = coordinator.settings.goldEstimateEnabled
            && coordinator.champSelect.staticData?.itemPrices != nil
            && snapshot.laneOpponent(of: me) != nil
        return hasCS || hasPlan || hasGold
    }
}

private struct TeamColumn: View {
    let title: String
    let players: [LivePlayer]
    let coordinator: InGameCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.secondaryText)
            ForEach(Array(players.enumerated()), id: \.offset) { _, player in
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

    private var subtitle: String {
        if let rank {
            if rank.isRanked, let winRate = rank.winRate, let games = rank.games {
                let percent = winRate.formatted(.percent.precision(.fractionLength(0)))
                return "\(rank.label) · \(percent) (\(games))"
            }
            return rank.label
        }
        if player.isBot == true || !coordinator.settings.ranksEnabled || coordinator.settings.effectiveRegion == nil {
            return player.championName
        }
        return "…"
    }

    var body: some View {
        HStack(spacing: 8) {
            ChampionIcon(key: player.championKey, champSelect: coordinator.champSelect, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(player.riotIDParts?.gameName ?? player.championName)
                    .font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(subtitle)
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

    private var plan: ItemPlan? {
        coordinator.itemPlan(for: me)
    }

    var body: some View {
        HStack(spacing: 18) {
            if let cs = InGameAnalysis.csPerMinute(me, gameTime: snapshot.stats.gameTime) {
                metric(
                    "CS/min",
                    value: cs.formatted(.number.precision(.fractionLength(1))),
                    detail: InGameAnalysis.csBenchmark(for: me)
                        .map { String(localized: "Guide value \($0.formatted())") },
                    good: InGameAnalysis.csBenchmark(for: me).map { cs >= $0 }
                )
            }
            if let plan {
                let progress = InGameAnalysis.buildProgress(owned: me.items, plan: plan)
                metric("Build", value: "\(progress.done)/\(progress.total)", detail: nextItemName, good: nil)
            }
            if coordinator.settings.goldEstimateEnabled, let prices = coordinator.champSelect.staticData?.itemPrices,
               let diff = InGameAnalysis.laneGoldDifference(for: me, in: snapshot, prices: prices) {
                metric(
                    "Item gold vs. lane",
                    value: (diff > 0 ? "+" : "") + diff.formatted(),
                    detail: String(localized: "Estimate from visible items"),
                    good: diff >= 0
                )
            }
            Spacer()
        }
    }

    private var nextItemName: String? {
        guard let itemID = plan.flatMap({ InGameAnalysis.nextItem(owned: me.items, plan: $0) }),
              let data = coordinator.champSelect.staticData,
              let name = data.itemsById[itemID]?.name
        else { return nil }
        if let active = snapshot.activePlayer,
           let needed = InGameAnalysis.goldNeeded(
               for: itemID,
               currentGold: active.currentGold,
               owned: me.items,
               prices: data.itemPrices,
               recipes: data.itemRecipes
           ) {
            return needed == 0
                ? String(localized: "Next: \(name) (Ready)")
                : String(localized: "Next: \(name) (\(needed)g)")
        }
        return String(localized: "Next: \(name)")
    }

    private func metric(_ title: LocalizedStringKey, value: String, detail: String?, good: Bool?) -> some View {
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

private struct ObjectivesBar: View {
    let timers: [ObjectiveTimer]
    let gameTime: Double

    var body: some View {
        HStack(spacing: 8) {
            Text("Objectives").font(.system(size: 10)).foregroundStyle(Palette.secondaryText)
            ForEach(timers) { timer in
                HStack(spacing: 4) {
                    Circle().fill(color(for: timer.kind)).frame(width: 6, height: 6)
                    Text(timer.label).font(.system(size: 10))
                    Text(timer.formattedRemaining(at: gameTime))
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            Spacer(minLength: 0)
        }
    }

    private func color(for kind: ObjectiveTimer.Kind) -> Color {
        switch kind {
        case .dragon: Palette.accent
        case .elder: Palette.negative
        case .baron: Color(red: 0.86, green: 0.62, blue: 0.98)
        case .inhibitor: Palette.positive
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
