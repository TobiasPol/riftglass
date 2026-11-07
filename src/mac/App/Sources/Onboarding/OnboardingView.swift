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
            Label("Welcome to Riftglass", systemImage: "diamond.fill")
                .font(.title2.weight(.semibold))
            Text("""
            Riftglass lives in the menu bar. In champ select it docks next to the League client and imports \
            runes, spells and item sets. In game, holding Tab shows ranks, CS/min and your build progress.
            """)
            .fixedSize(horizontal: false, vertical: true)
            InputMonitoringStep()
            GroupBox("Data sources") {
                Text("""
                Builds, win rates and ranks come from OP.GG (public interface, no account). For ranks, the Riot \
                IDs of the players in your game are sent to OP.GG – you can turn this off in Settings. Riot's \
                recommendations come straight from your client.
                """)
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
                Button("Let’s go") {
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
        GroupBox("In-game hotkeys (Tab, ⌥A)") {
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    granted ? "Input Monitoring allowed" : "Input Monitoring missing",
                    systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle"
                )
                .foregroundStyle(granted ? .green : .orange)
                Text("""
                Riftglass only reads whether Tab or ⌥A is pressed (listen-only, no input is changed). Riftglass \
                has to be restarted after allowing it.
                """)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                HStack {
                    if !granted {
                        Button("Request access") { granted = HotkeyMonitor.requestPermission() }
                        Button("Open System Settings") { Self.openPrivacySettings() }
                    }
                    Button("Restart Riftglass") { Self.relaunch() }
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
