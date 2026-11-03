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

    /// Vertical placement; the panel is always centred horizontally.
    public enum Anchor: Equatable, Sendable {
        /// Distance from the top edge of the screen.
        case top(CGFloat)
        /// Distance from the bottom edge, as a fraction of the screen height (resolution-independent,
        /// e.g. 0.2 sits above League's ability bar).
        case bottomFraction(CGFloat)
    }

    /// Sizes the panel to its SwiftUI content and shows it horizontally centred near the top of `screen`.
    public func present(on screen: NSScreen?, topInset: CGFloat = 60) {
        present(on: screen, anchor: .top(topInset))
    }

    public func present(on screen: NSScreen?, anchor: Anchor) {
        guard let screen = screen ?? NSScreen.screens.first else { return }
        let size = hostingView.fittingSize
        let frame = screen.frame
        let y = switch anchor {
        case let .top(inset): frame.maxY - inset - size.height
        case let .bottomFraction(fraction): frame.minY + frame.height * fraction
        }
        setFrame(NSRect(x: frame.midX - size.width / 2, y: y, width: size.width, height: size.height), display: true)
        if !isVisible {
            orderFrontRegardless()
        }
    }

    /// Replaces the content synchronously, so the next `present` measures the new size (an
    /// `@Observable`-driven update would only re-render on the next run-loop pass).
    public func update(rootView: some View) {
        hostingView.rootView = AnyView(rootView)
    }

    public func dismiss() {
        if isVisible {
            orderOut(nil)
        }
    }
}
