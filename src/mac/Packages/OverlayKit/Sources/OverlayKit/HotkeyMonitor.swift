import AppKit
import CoreGraphics
import os

/// Watches the Tab key with a **listen-only** event tap (never blocks or alters input).
///
/// Runs on the main run loop – a listen-only tap cannot delay input, so no extra thread is needed.
/// Requires Input Monitoring; after granting it macOS needs an app restart.
@MainActor
public final class HotkeyMonitor {
    public static let tabKeyCode: Int64 = 48

    /// Called with `true` on key down and `false` on key up (repeats are ignored).
    public var onTabChange: ((Bool) -> Void)?
    /// Events are only reported while this returns true (e.g. the game is frontmost).
    public var isActive: () -> Bool = { true }

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var isDown = false
    private let logger = Logger(subsystem: "de.polleydigital.riftglass", category: "Hotkey")

    public init() {}

    public static var hasPermission: Bool {
        CGPreflightListenEventAccess()
    }

    /// Shows the system prompt (once) and returns the current state.
    @discardableResult
    public static func requestPermission() -> Bool {
        CGRequestListenEventAccess()
    }

    public var isRunning: Bool {
        tap != nil
    }

    /// Returns false without Input Monitoring permission.
    @discardableResult
    public func start() -> Bool {
        guard tap == nil else { return true }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: hotkeyCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        else {
            logger.notice("Event tap not created – Input Monitoring missing")
            return false
        }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    /// Must be called before the monitor is released (the tap holds an unretained pointer).
    public func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        tap = nil
        source = nil
        setDown(false)
    }

    fileprivate func handle(_ type: CGEventType, keyCode: Int64, isRepeat: Bool) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        case .keyDown, .keyUp:
            guard keyCode == Self.tabKeyCode, !isRepeat else { return }
            setDown(type == .keyDown && isActive())
        default:
            break
        }
    }

    private func setDown(_ down: Bool) {
        guard down != isDown else { return }
        isDown = down
        onTabChange?(down)
    }
}

private func hotkeyCallback(
    proxy _: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if let refcon {
        let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
        // Read plain values here; the CGEvent itself must not cross into the actor.
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        // The tap's run loop source is on the main run loop.
        MainActor.assumeIsolated { monitor.handle(type, keyCode: keyCode, isRepeat: isRepeat) }
    }
    return Unmanaged.passUnretained(event)
}
