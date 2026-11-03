import AppKit
import SwiftUI

/// Click-through overlay above the (fullscreen) game.
///
/// The game window sits on `CGShieldingWindowLevel()`; `.screenSaver` is invisible below it, so the
/// overlay uses shielding + 1 (docs/SPIKE.md, Spike 2). Hidden via `orderOut`, never `alphaValue = 0`.
public final class OverlayPanel: NSPanel {
    public static let overlayLevel = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)

    private let hostingView: NSHostingView<AnyView>

    public init(rootView: some View) {
        hostingView = NSHostingView(rootView: AnyView(rootView))
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = Self.overlayLevel
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        hasShadow = false
        isOpaque = false
        backgroundColor = .clear
        isReleasedWhenClosed = false
        animationBehavior = .none
        contentView = hostingView
    }

    override public var canBecomeKey: Bool {
        false
    }

    override public var canBecomeMain: Bool {
        false
    }

    /// Sizes the panel to its SwiftUI content and shows it horizontally centred near the top of `screen`.
    public func present(on screen: NSScreen?, topInset: CGFloat = 60) {
        guard let screen = screen ?? NSScreen.screens.first else { return }
        let size = hostingView.fittingSize
        let frame = screen.frame
        setFrame(NSRect(
            x: frame.midX - size.width / 2,
            y: frame.maxY - topInset - size.height,
            width: size.width,
            height: size.height
        ), display: true)
        if !isVisible {
            orderFrontRegardless()
        }
    }

    public func dismiss() {
        if isVisible {
            orderOut(nil)
        }
    }
}
