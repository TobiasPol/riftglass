import LeagueKit
import StatsKit
import SwiftUI

/// Shown for a few seconds at game start: champion + solo rank of all ten players. `stacked` puts the
/// teams in one narrow column (≈ 180 pt), which fits beside League's selection cards even on 16:10.
struct RanksBannerView: View {
    static let stackedWidth: CGFloat = 180

    let coordinator: InGameCoordinator
    var stacked = false

    var body: some View {
        Group {
            if stacked {
                VStack(alignment: .leading, spacing: 8) {
                    team("ORDER")
                    Rectangle().fill(Palette.hairline).frame(height: 1)
                    team("CHAOS")
                }
                .frame(width: Self.stackedWidth - 24, alignment: .leading)
            } else {
                HStack(alignment: .top, spacing: 24) {
                    team("ORDER")
                    Rectangle().fill(Palette.hairline).frame(width: 1)
                    team("CHAOS")
                }
            }
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
