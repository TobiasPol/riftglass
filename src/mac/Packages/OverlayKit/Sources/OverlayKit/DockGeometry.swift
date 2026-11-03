import CoreGraphics
import Foundation

/// Window info as reported by `CGWindowListCopyWindowInfo` (CG coordinates: origin top-left).
public struct WindowInfo: Equatable, Sendable {
    public let ownerPID: pid_t
    public let layer: Int
    public let bounds: CGRect

    public init(ownerPID: pid_t, layer: Int, bounds: CGRect) {
        self.ownerPID = ownerPID
        self.layer = layer
        self.bounds = bounds
    }

    init?(dictionary: [String: Any]) {
        guard let pid = dictionary[kCGWindowOwnerPID as String] as? Int,
              let layer = dictionary[kCGWindowLayer as String] as? Int,
              let boundsDict = dictionary[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDict)
        else { return nil }
        self.init(ownerPID: pid_t(pid), layer: layer, bounds: bounds)
    }
}

/// Pure geometry for docking – no AppKit state, fully unit-testable.
public enum DockGeometry {
    public static let minimumClientSize = CGSize(width: 400, height: 300)

    /// The client window: largest normal-layer window of `pid`. Window names are empty without
    /// screen-recording permission (docs/SPIKE.md), so they are not used.
    public static func clientWindow(in windows: [WindowInfo], pid: pid_t) -> WindowInfo? {
        windows
            .filter {
                $0.ownerPID == pid && $0.layer == 0
                    && $0.bounds.width >= minimumClientSize.width && $0.bounds.height >= minimumClientSize.height
            }
            .max { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }
    }

    /// CG (top-left origin of the primary screen) → AppKit (bottom-left origin).
    /// Uses the height of `NSScreen.screens[0]`, never `NSScreen.main`.
    public static func appKitRect(fromCG rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Panel frame next to the client: right side if it fits, else left, else inside the right edge.
    /// Height follows the client, capped at `panelSize.height`; top edges are aligned.
    public static func panelFrame(client: CGRect, panelSize: CGSize, screen: CGRect, gap: CGFloat = 8) -> CGRect {
        let height = min(panelSize.height, client.height)
        let y = client.maxY - height
        let right = CGRect(x: client.maxX + gap, y: y, width: panelSize.width, height: height)
        if right.maxX <= screen.maxX {
            return right
        }
        let left = CGRect(x: client.minX - gap - panelSize.width, y: y, width: panelSize.width, height: height)
        if left.minX >= screen.minX {
            return left
        }
        return CGRect(x: client.maxX - panelSize.width - gap, y: y, width: panelSize.width, height: height)
    }
}
