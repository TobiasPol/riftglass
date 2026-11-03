import AppKit
import Combine
import OverlayKit
import SwiftUI

/// First-launch window: what Riftglass does, the Riot notice, and Input Monitoring for the Tab overlay.
struct OnboardingView: View {
    let settings: AppSettings
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Willkommen bei Riftglass", systemImage: "diamond.fill")
                .font(.title2.weight(.semibold))
            Text("Riftglass lebt in der Menüleiste. Im Champ Select dockt es neben den League-Client und "
                + "importiert Runen, Spells und Item-Sets. Im Spiel zeigt es beim Halten von Tab Ränge, "
                + "CS/min und deinen Build-Fortschritt.")
                .fixedSize(horizontal: false, vertical: true)
            InputMonitoringStep()
            GroupBox("Datenquellen") {
                Text("Builds, Winrates und Ränge kommen von OP.GG (öffentliche Schnittstelle, ohne Konto). "
                    + "Für Ränge werden die Riot-IDs der Spieler deines Spiels an OP.GG gesendet – "
                    + "abschaltbar in den Einstellungen. Riot-Empfehlungen kommen direkt aus deinem Client.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(Disclaimer.full)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Los geht’s") {
                    settings.onboardingCompleted = true
                    dismissWindow(id: OnboardingView.windowID)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    static let windowID = "onboarding"
}

/// Input Monitoring status with request / open-settings / relaunch actions.
struct InputMonitoringStep: View {
    @State private var granted = HotkeyMonitor.hasPermission
    private let refresh = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        GroupBox("Tab-Overlay im Spiel") {
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    granted ? "Eingabeüberwachung erlaubt" : "Eingabeüberwachung fehlt",
                    systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle"
                )
                .foregroundStyle(granted ? .green : .orange)
                Text("Riftglass liest nur, ob Tab gedrückt ist (Listen-only, keine Eingaben werden verändert). "
                    + "Nach dem Erlauben muss Riftglass neu gestartet werden.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    if !granted {
                        Button("Zugriff anfragen") { granted = HotkeyMonitor.requestPermission() }
                        Button("Systemeinstellungen öffnen") { Self.openPrivacySettings() }
                    }
                    Button("Riftglass neu starten") { Self.relaunch() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onReceive(refresh) { _ in granted = HotkeyMonitor.hasPermission }
    }

    static func openPrivacySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
        if let url {
            NSWorkspace.shared.open(url)
        }
    }

    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            Task { @MainActor in NSApplication.shared.terminate(nil) }
        }
    }
}
