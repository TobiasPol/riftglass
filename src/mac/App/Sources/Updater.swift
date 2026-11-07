import Observation
import Sparkle
import SwiftUI

/// Sparkle 2 auto-updates. Feed + EdDSA public key live in `App/Info.plist` (`SUFeedURL`, `SUPublicEDKey`);
/// update archives are signed with the private key from the developer's keychain (scripts/release.sh).
@MainActor
@Observable
final class Updater {
    // Debug builds carry the release's version with build 1, so Sparkle would offer to replace them
    // with the published release mid-test; they only check when asked to.
    #if DEBUG
        private static let startsAutomatically = false
    #else
        private static let startsAutomatically = true
    #endif

    @ObservationIgnored private let controller = SPUStandardUpdaterController(
        startingUpdater: startsAutomatically, updaterDelegate: nil, userDriverDelegate: nil
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
        if !Self.startsAutomatically {
            try? controller.updater.start()
        }
        controller.checkForUpdates(nil)
    }
}

struct UpdateSettingsRow: View {
    @Environment(Updater.self) private var updater

    var body: some View {
        @Bindable var updater = updater
        HStack {
            Toggle("Check for updates automatically", isOn: $updater.automaticallyChecksForUpdates)
            Spacer()
            Button("Check now") { updater.checkForUpdates() }
        }
    }
}
