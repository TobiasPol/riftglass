import Observation
import Sparkle
import SwiftUI

/// Sparkle 2 auto-updates. Feed + EdDSA public key live in `App/Info.plist` (`SUFeedURL`, `SUPublicEDKey`);
/// update archives are signed with the private key from the developer's keychain (scripts/release.sh).
@MainActor
@Observable
final class Updater {
    @ObservationIgnored private let policy = UpdateCheckPolicy()
    @ObservationIgnored private let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: policy, userDriverDelegate: nil
        )
    }

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

/// Debug builds carry the release's version with build 1, so Sparkle would offer to replace them with
/// the published release mid-test. They refuse every background check for the whole session; "Check
/// now" still works and the stored automatic-check preference (shared with Release) is left alone.
final class UpdateCheckPolicy: NSObject, SPUUpdaterDelegate {
    func updater(_: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        #if DEBUG
            guard updateCheck == .updates else {
                throw NSError(domain: "Riftglass", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Automatic update checks are off in Debug builds."
                ])
            }
        #endif
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
