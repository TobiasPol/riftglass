import LeagueKit
import SwiftUI

struct MenuBarContent: View {
    let model: AppModel
    let updater: Updater
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Riftglass").font(.headline)
            Label(statusText, systemImage: statusIcon)
                .font(.callout)
            if let error = model.setupError {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            Toggle("ARAM: Mayhem – augment overlay (⌥A)", isOn: Bindable(model.settings).augmentOverlayEnabled)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.callout)
            if let game = model.inGame.lastGame {
                lastGame(game)
            }
            Divider()
            Text(Disclaimer.short)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Settings …") { WindowFront.openSettings(using: openSettings) }
                Button("Setup") { WindowFront.open(OnboardingView.windowID, using: openWindow) }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 300)
    }

    private func lastGame(_ game: GameSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Last game").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Text(game.championName).font(.callout.weight(.semibold))
                Text(game.kdaText).monospacedDigit()
                if let cs = game.csPerMinute {
                    Text("\(cs.formatted(.number.precision(.fractionLength(1)))) CS/min").monospacedDigit()
                }
                Text("\(game.minutes) min").foregroundStyle(.secondary)
            }
            .font(.callout)
            if game.buildTotal > 0 {
                Text("Build: \(game.buildDone)/\(game.buildTotal) planned items").font(.caption)
            }
        }
    }

    private var statusText: String {
        switch model.mode {
        case .dormant: String(localized: "League is not running")
        case .client:
            if model.isLCUConnected {
                String(localized: "Connected to the client")
            } else {
                String(localized: "Connecting to the client …")
            }
        case .champSelect: String(localized: "Champ Select · \(model.champSelect.queue?.displayName ?? "…")")
        case .inGame: inGameStatus
        case .postGame: String(localized: "After the game")
        }
    }

    private var inGameStatus: String {
        guard model.inGame.snapshot != nil else { return String(localized: "Game loading …") }
        let mode = model.inGame.queue?.displayName ?? String(localized: "In game")
        return String(localized: "\(mode) – hold Tab for overlay")
    }

    private var statusIcon: String {
        switch model.mode {
        case .dormant: "moon.zzz"
        case .client: model.isLCUConnected ? "checkmark.circle" : "arrow.triangle.2.circlepath"
        case .champSelect: "person.crop.square"
        case .inGame: "gamecontroller"
        case .postGame: "chart.bar"
        }
    }
}
