import ServiceManagement
import SwiftUI

/// Riot's required legal notice – shown in onboarding, settings, the panels and the README (PLAN §4.6).
enum Disclaimer {
    static let full = """
    Riftglass isn't endorsed by Riot Games and doesn't reflect the views or opinions of Riot Games or \
    anyone officially involved in producing or managing Riot Games properties. Riot Games, and all \
    associated properties are trademarks or registered trademarks of Riot Games, Inc.
    """

    static let short = "Riftglass isn't endorsed by Riot Games. League of Legends is a trademark of Riot Games, Inc."
}

struct SettingsView: View {
    @Bindable var settings: AppSettings
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–"
        return "\(short) (\(build))"
    }

    var body: some View {
        Form {
            Section("Allgemein") {
                Toggle("Bei der Anmeldung starten", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                UpdateSettingsRow()
            }
            Section("Champ Select") {
                Toggle("Item-Set nach dem Lock-in automatisch übernehmen", isOn: $settings.autoImportItemSet)
                Toggle("Runen & Spells automatisch übernehmen", isOn: $settings.autoImportRunes)
                Text("Spielmodus wird erkannt (Ranked, ARAM, ARAM: Mayhem, Arena, URF …). Übernommen wird die "
                    + "erste Option für den passenden Modus; Riftglass ändert nur eigene Runenseiten und Item-Sets.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Im Spiel") {
                Toggle("Skillpunkt-Hinweis (welche Fähigkeit als Nächstes)", isOn: $settings.skillOverlayEnabled)
                Toggle("Tab-Overlay (Ränge, CS/min, Build-Fortschritt)", isOn: $settings.tabOverlayEnabled)
                InputMonitoringStep()
                Toggle("Ränge über OP.GG laden", isOn: $settings.ranksEnabled)
                Text("Sendet die Riot-IDs der Spieler deines aktuellen Spiels an OP.GG.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Item-Gold-Schätzung pro Lane (experimentell)", isOn: $settings.goldEstimateEnabled)
                Text("Nur aus sichtbaren Items. Ob Riot das erlaubt, ist ungeklärt – daher standardmäßig aus.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Über Riftglass") {
                LabeledContent("Version", value: version)
                Text("Liest nur lokale Schnittstellen des League-Clients (LCU, Live Client Data API). Kein "
                    + "Speicherlesen, keine Injection, keine Eingabe-Automatisierung, keine Telemetrie. "
                    + "Builds und Ränge: OP.GG. Riftglass ändert nur eigene Runenseiten und Item-Sets.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Text(Disclaimer.full)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 760)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
