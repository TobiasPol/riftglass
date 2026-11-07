import AppKit
import SwiftUI

/// Which side of a centred area an `OverlayPanel.Anchor.besideCentre` panel takes.
public enum OverlaySide: Equatable, Sendable {
    case left, right
}

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

    /// Placement on the screen; all but `besideCentre` centre the panel horizontally.
    public enum Anchor: Equatable, Sendable {
        /// Distance from the top edge of the screen.
        case top(CGFloat)
        /// Distance from the top edge, as a fraction of the screen height (clears League's top HUD
        /// independently of resolution).
        case topFraction(CGFloat)
        /// Distance from the bottom edge, as a fraction of the screen height (resolution-independent,
        /// e.g. 0.2 sits above League's ability bar).
        case bottomFraction(CGFloat)
        /// Beside a centred area `clearHalfWidth × screen height` wide on each side of the middle (e.g.
        /// League's selection cards), `gap` points away, vertically centred at `centreY` (fraction of
        /// the height from the top). Never leaves the screen.
        case besideCentre(OverlaySide, clearHalfWidth: CGFloat, gap: CGFloat, centreY: CGFloat)
    }

    /// Pure placement math (AppKit coordinates, origin bottom-left).
    public nonisolated static func origin(for anchor: Anchor, size: CGSize, in frame: CGRect) -> CGPoint {
        let centredX = frame.midX - size.width / 2
        switch anchor {
        case let .top(inset):
            return CGPoint(x: centredX, y: frame.maxY - inset - size.height)
        case let .topFraction(fraction):
            return CGPoint(x: centredX, y: frame.maxY - frame.height * fraction - size.height)
        case let .bottomFraction(fraction):
            return CGPoint(x: centredX, y: frame.minY + frame.height * fraction)
        case let .besideCentre(side, clearHalfWidth, gap, centreY):
            let margin: CGFloat = 16, offset = frame.height * clearHalfWidth + gap
            let x = switch side {
            case .left: max(frame.minX + margin, frame.midX - offset - size.width)
            case .right: min(frame.maxX - margin - size.width, frame.midX + offset)
            }
            let centre = frame.maxY - frame.height * centreY
            let y = min(max(frame.minY + margin, centre - size.height / 2), frame.maxY - margin - size.height)
            return CGPoint(x: x, y: y)
        }
    }

    /// Sizes the panel to its SwiftUI content and shows it horizontally centred near the top of `screen`.
    public func present(on screen: NSScreen?, topInset: CGFloat = 60) {
        present(on: screen, anchor: .top(topInset))
    }

    public func present(on screen: NSScreen?, anchor: Anchor) {
        guard let screen = screen ?? NSScreen.screens.first else { return }
        let size = hostingView.fittingSize
        let origin = Self.origin(for: anchor, size: size, in: screen.frame)
        setFrame(NSRect(origin: origin, size: size), display: true)
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
