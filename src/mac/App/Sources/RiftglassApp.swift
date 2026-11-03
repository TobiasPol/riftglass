import LeagueKit
import SwiftUI

@main
struct RiftglassApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(model: model)
        } label: {
            Image(systemName: model.mode == .dormant ? "diamond" : "diamond.fill")
                .task { model.start() }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}

struct MenuBarContent: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Riftglass").font(.headline)
            Label(statusText, systemImage: statusIcon)
                .font(.callout)
            if let error = model.setupError {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            Divider()
            Text(Disclaimer.short)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                SettingsLink { Text("Einstellungen …") }
                Spacer()
                Button("Beenden") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 280)
    }

    private var statusText: String {
        switch model.mode {
        case .dormant: "League ist nicht gestartet"
        case .client: model.isLCUConnected ? "Mit dem Client verbunden" : "Verbinde mit dem Client …"
        case .champSelect: "Champ Select"
        case .inGame: "Im Spiel"
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
