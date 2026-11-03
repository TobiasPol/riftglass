import AppKit
import SwiftUI

/// Clickable, non-activating panel docked next to the League client.
///
/// Order matters (PLAN §4.5): `.nonactivatingPanel` must be part of the style mask passed to
/// `init` – setting it later does not reliably take effect – then `isFloatingPanel`, then `level`.
public final class ChampSelectPanel: NSPanel {
    public init(rootView: some View, size: NSSize = NSSize(width: 340, height: 560)) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        hasShadow = true
        backgroundColor = .clear
        isOpaque = false
        animationBehavior = .none
        contentView = FirstMouseHostingView(rootView: rootView)
    }

    /// Never steal key/main status from the League client.
    override public var canBecomeMain: Bool {
        false
    }

    override public var canBecomeKey: Bool {
        false
    }
}

/// Hosting view whose first click acts immediately instead of only focusing the window.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }
}
