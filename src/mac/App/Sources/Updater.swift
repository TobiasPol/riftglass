import Observation
import Sparkle
import SwiftUI

/// Sparkle 2 auto-updates. Feed + EdDSA public key live in `App/Info.plist` (`SUFeedURL`, `SUPublicEDKey`);
/// update archives are signed with the private key from the developer's keychain (scripts/release.sh).
@MainActor
@Observable
final class Updater {
    @ObservationIgnored private let controller = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
    )

    var automaticallyChecksForUpdates: Bool {
        get {
            access(keyPath: \.automaticallyChecksForUpdates)
            return controller.updater.automaticallyChecksForUpdates
        }
        set {
            withMutation(keyPath: \.automaticallyChecksForUpdates) {
                controller.updater.automaticallyChecksForUpdates = newValue
            }
        }
    }

    func checkForUpdates() {
        NSApplication.shared.activate()
        controller.checkForUpdates(nil)
    }
}

struct UpdateSettingsRow: View {
    @Environment(Updater.self) private var updater

    var body: some View {
        @Bindable var updater = updater
        HStack {
            Toggle("Automatisch nach Updates suchen", isOn: $updater.automaticallyChecksForUpdates)
            Spacer()
            Button("Jetzt prüfen") { updater.checkForUpdates() }
        }
    }
}
