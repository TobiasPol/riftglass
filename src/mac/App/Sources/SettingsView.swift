import SwiftUI

/// Riot's required legal notice – shown in onboarding, settings, about and README (PLAN §4.6).
enum Disclaimer {
    static let full = """
    Riftglass isn't endorsed by Riot Games and doesn't reflect the views or opinions of Riot Games or \
    anyone officially involved in producing or managing Riot Games properties. Riot Games, and all \
    associated properties are trademarks or registered trademarks of Riot Games, Inc.
    """

    static let short = "Riftglass isn't endorsed by Riot Games. League of Legends is a trademark of Riot Games, Inc."
}

struct SettingsView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
    }

    var body: some View {
        Form {
            Section("Über Riftglass") {
                LabeledContent("Version", value: version)
                Text("Riftglass liest nur lokale Schnittstellen des League-Clients (LCU, Live Client Data API). "
                    + "Kein Speicherlesen, keine Injection, keine Eingabe-Automatisierung, keine Telemetrie.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Builds") {
                Text("Phase 1 zeigt handgepflegte Platzhalter-Builds für fünf Champions. "
                    + "Importiert werden nur eigene „Riftglass“-Runenseiten und -Item-Sets; "
                    + "fremde Seiten und Sets bleiben unangetastet.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Rechtliches") {
                Text(Disclaimer.full)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 420)
    }
}
