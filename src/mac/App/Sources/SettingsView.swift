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
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                UpdateSettingsRow()
            }
            Section("Champ Select") {
                Toggle("Import item set automatically after lock-in", isOn: $settings.autoImportItemSet)
                Toggle("Import runes & spells automatically", isOn: $settings.autoImportRunes)
                Text("""
                The game mode is detected (Ranked, ARAM, ARAM: Mayhem, Arena, URF …). The first option for that \
                mode is imported; Riftglass only changes its own rune pages and item sets.
                """)
                .font(.caption).foregroundStyle(.secondary)
                Toggle("Matchup briefing (lane opponent, teams, counter picks)", isOn: $settings.briefingEnabled)
                Text("""
                Only uses champions you can see in champ select. Enemy lanes are estimated from OP.GG \
                statistics; counter picks only appear during your pick.
                """)
                .font(.caption).foregroundStyle(.secondary)
            }
            Section("In game") {
                Toggle("Skill point hint (which ability to level next)", isOn: $settings.skillOverlayEnabled)
                Toggle("ARAM: Mayhem – augment list at every augment choice", isOn: $settings.augmentOverlayEnabled)
                Text("""
                Appears next to the selection cards at game start and after levels 7, 11 and 15, once you are \
                dead or in the fountain: your champion's strong augments per rarity (OP.GG). Riftglass does not \
                read the offered cards. ⌥A hides the list until the next choice and shows it again (needs Input \
                Monitoring); holding Tab shows it any time.
                """)
                .font(.caption).foregroundStyle(.secondary)
                Toggle("Tab overlay (ranks, CS/min, build progress)", isOn: $settings.tabOverlayEnabled)
                InputMonitoringStep()
                Toggle("Load ranks from OP.GG", isOn: $settings.ranksEnabled)
                Text("Sends the Riot IDs of the players in your current game to OP.GG.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Item gold estimate per lane (experimental)", isOn: $settings.goldEstimateEnabled)
                Text("Only from visible items. Whether Riot allows this is unclear – so it is off by default.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("About Riftglass") {
                LabeledContent("Version", value: version)
                Text("""
                Only reads local interfaces of the League client (LCU, Live Client Data API). No memory reading, \
                no injection, no input automation, no telemetry. Builds and ranks: OP.GG. Riftglass only changes \
                its own rune pages and item sets.
                """)
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
