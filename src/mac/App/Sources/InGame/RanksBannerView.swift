import LeagueKit
import StatsKit
import SwiftUI

/// Shown for a few seconds at game start: champion + solo rank of all ten players.
struct RanksBannerView: View {
    let coordinator: InGameCoordinator

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            team("ORDER")
            Rectangle().fill(Palette.hairline).frame(width: 1)
            team("CHAOS")
        }
        .padding(12)
        .background(Palette.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .foregroundStyle(Palette.text)
        .environment(\.colorScheme, .dark)
    }

    private func team(_ side: String) -> some View {
        let players = coordinator.snapshot?.players.filter { $0.team == side } ?? []
        return VStack(alignment: .leading, spacing: 5) {
            ForEach(players, id: \.displayID) { player in
                HStack(spacing: 6) {
                    ChampionIcon(key: player.championKey, champSelect: coordinator.champSelect, size: 20)
                    Text(coordinator.ranks[player.displayID]?.label ?? "…")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .frame(width: 130, alignment: .leading)
                }
            }
        }
    }
}
