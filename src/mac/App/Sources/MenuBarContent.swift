import LeagueKit
import SwiftUI

struct MenuBarContent: View {
    let model: AppModel
    let updater: Updater
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Riftglass").font(.headline)
            Label(statusText, systemImage: statusIcon)
                .font(.callout)
            if let error = model.setupError {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            if let game = model.inGame.lastGame {
                lastGame(game)
            }
            Divider()
            Text(Disclaimer.short)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                SettingsLink { Text("Einstellungen …") }
                Button("Einrichtung") { WindowFront.open(OnboardingView.windowID, using: openWindow) }
                Spacer()
                Button("Beenden") { NSApplication.shared.terminate(nil) }
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 300)
    }

    private func lastGame(_ game: GameSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Letztes Spiel").font(.caption).foregroundStyle(.secondary)
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
                Text("Build: \(game.buildDone)/\(game.buildTotal) geplante Items").font(.caption)
            }
        }
    }

    private var statusText: String {
        switch model.mode {
        case .dormant: "League ist nicht gestartet"
        case .client: model.isLCUConnected ? "Mit dem Client verbunden" : "Verbinde mit dem Client …"
        case .champSelect: "Champ Select · " + (model.champSelect.queue?.displayName ?? "…")
        case .inGame: model.inGame.snapshot == nil
            ? "Spiel lädt …" : "\(model.inGame.queue?.displayName ?? "Im Spiel") – Tab halten für Overlay"
        case .postGame: "Nach dem Spiel"
        }
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
