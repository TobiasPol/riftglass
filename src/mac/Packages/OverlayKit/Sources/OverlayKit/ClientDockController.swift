import AppKit
import os

/// Keeps a panel docked to the League client window – **only while champ select is active**.
///
/// Polls `CGWindowListCopyWindowInfo` at 2 Hz (bounds + PID need no screen-recording permission)
/// and hides the panel while another app is frontmost, so it never floats over unrelated windows.
@MainActor
public final class ClientDockController {
    private let panel: NSPanel
    private let panelSize: CGSize
    private var clientPID: pid_t?
    private var timer: Timer?
    private var activationObserver: NSObjectProtocol?
    private var lastFrame: CGRect?
    private let logger = Logger(subsystem: "de.polleydigital.riftglass", category: "ClientDock")

    public init(panel: NSPanel, panelSize: CGSize = CGSize(width: 340, height: 560)) {
        self.panel = panel
        self.panelSize = panelSize
    }

    public var isActive: Bool {
        timer != nil
    }

    /// Starts docking to the window owned by `clientPID` (the `LeagueClientUx` process).
    public func start(clientPID: pid_t) {
        self.clientPID = clientPID
        guard timer == nil else { return update() }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        update()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
        lastFrame = nil
        panel.orderOut(nil)
    }

    private func update() {
        guard let clientPID, let frame = currentPanelFrame(clientPID: clientPID), isRelevantAppFrontmost(clientPID)
        else {
            if panel.isVisible {
                panel.orderOut(nil)
            }
            return
        }
        if frame != lastFrame {
            panel.setFrame(frame, display: true)
            lastFrame = frame
        }
        if !panel.isVisible {
            panel.orderFrontRegardless()
            logger.info("Panel shown at \(frame.debugDescription, privacy: .public)")
        }
    }

    private func currentPanelFrame(clientPID: pid_t) -> CGRect? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        let windows = raw.compactMap(WindowInfo.init(dictionary:))
        guard let client = DockGeometry.clientWindow(in: windows, pid: clientPID),
              let primary = NSScreen.screens.first
        else { return nil }
        let clientRect = DockGeometry.appKitRect(fromCG: client.bounds, primaryScreenHeight: primary.frame.height)
        let screen = NSScreen.screens.first { $0.frame.intersects(clientRect) } ?? primary
        return DockGeometry.panelFrame(client: clientRect, panelSize: panelSize, screen: screen.visibleFrame)
    }

    /// The panel is shown while League (or Riftglass itself, e.g. its settings) is frontmost.
    private func isRelevantAppFrontmost(_ clientPID: pid_t) -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication else { return false }
        return front.processIdentifier == clientPID || front.processIdentifier == getpid()
    }
}
