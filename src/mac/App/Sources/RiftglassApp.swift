import LeagueKit
import SwiftUI

@main
struct RiftglassApp: App {
    @State private var model = AppModel()
    @State private var updater = Updater()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(model: model, updater: updater)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Window("Welcome to Riftglass", id: OnboardingView.windowID) {
            OnboardingView(settings: model.settings)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView(settings: model.settings)
                .environment(updater)
        }
    }
}

/// Menu bar icon; also starts the app model and shows onboarding on first launch.
private struct MenuBarLabel: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: model.mode == .dormant ? "diamond" : "diamond.fill")
            .task {
                model.start()
                if !model.settings.onboardingCompleted {
                    WindowFront.open(OnboardingView.windowID, using: openWindow)
                }
            }
    }
}

/// Menu bar apps are not frontmost, so `activate()` alone leaves new windows behind other apps
/// (e.g. the League client). Open the window, then order it to the front explicitly.
@MainActor
enum WindowFront {
    /// SwiftUI's identifier for the `Settings` scene window.
    static let settingsID = "com_apple_SwiftUI_Settings_window"

    static func open(_ id: String, using openWindow: OpenWindowAction) {
        NSApplication.shared.activate()
        openWindow(id: id)
        raise(id)
    }

    /// `SettingsLink` cannot be used here: it opens the window behind everything else in an
    /// accessory (LSUIElement) app and offers no hook to raise it afterwards.
    static func openSettings(using openSettings: OpenSettingsAction) {
        NSApplication.shared.activate()
        openSettings()
        raise(settingsID)
    }

    private static func raise(_ id: String) {
        Task { @MainActor in
            // The window is created asynchronously; retry briefly until it exists.
            for _ in 0 ..< 10 {
                try? await Task.sleep(for: .milliseconds(50))
                let window = NSApplication.shared.windows.first {
                    $0.identifier?.rawValue.contains(id) == true
                }
                guard let window else { continue }
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
                return
            }
        }
    }
}
