// Shows a red non-activating panel at a given window level for 15 s.
// Run while League is in (fullscreen) game: swift scripts/spike/08-overlay-level.swift [screensaver|shielding]
import AppKit

let useShielding = CommandLine.arguments.dropFirst().first == "shielding"
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let panel = NSPanel(
    contentRect: NSRect(x: 100, y: 100, width: 240, height: 80),
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered,
    defer: false
)
panel.isFloatingPanel = true
panel.level = useShielding ? NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1) : .screenSaver
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
panel.hidesOnDeactivate = false
panel.ignoresMouseEvents = true
panel.backgroundColor = .systemRed
panel
    .contentView = NSTextField(labelWithString: "Riftglass level test: \(useShielding ? "shielding+1" : "screenSaver")")
panel.orderFrontRegardless()
print("Panel level \(panel.level.rawValue) shown for 15 s – is it visible above the game?")
DispatchQueue.main.asyncAfter(deadline: .now() + 15) { app.terminate(nil) }
app.run()
