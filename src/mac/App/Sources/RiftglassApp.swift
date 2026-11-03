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

        Window("Willkommen bei Riftglass", id: OnboardingView.windowID) {
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
    static func open(_ id: String, using openWindow: OpenWindowAction) {
        NSApplication.shared.activate()
        openWindow(id: id)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            let window = NSApplication.shared.windows.first { $0.identifier?.rawValue.contains(id) == true }
            window?.makeKeyAndOrderFront(nil)
            window?.orderFrontRegardless()
        }
    }
}
