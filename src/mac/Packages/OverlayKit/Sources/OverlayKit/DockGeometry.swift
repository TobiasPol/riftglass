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

    public init?(dictionary: [String: Any]) {
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

    /// Largest window of `pid` across any window layer (e.g. the fullscreen game on shielding level).
    public static func largestWindow(in windows: [WindowInfo], pid: pid_t) -> WindowInfo? {
        windows
            .filter {
                $0.ownerPID == pid
                    && $0.bounds.width >= minimumClientSize.width && $0.bounds.height >= minimumClientSize.height
            }
            .max { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }
    }

    /// Index of the screen with the largest overlap with `rect`, falling back to `0` if non-empty.
    public static func bestScreenIndex(for rect: CGRect, in screens: [CGRect]) -> Int? {
        guard !screens.isEmpty else { return nil }
        let area = { (screen: CGRect) -> CGFloat in
            let overlap = screen.intersection(rect)
            return overlap.isNull ? 0 : overlap.width * overlap.height
        }
        guard let best = screens.enumerated().max(by: { area($0.element) < area($1.element) }),
              area(best.element) > 0
        else { return 0 }
        return best.offset
    }

    /// CG (top-left origin of the primary screen) → AppKit (bottom-left origin).
    /// Uses the height of `NSScreen.screens[0]`, never `NSScreen.main`.
    public static func appKitRect(fromCG rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Panel frame next to the client: right side if it fits, else left, else inside the right edge.
    /// Height follows the client, capped at `panelSize.height` and `screen.height`; top edges align.
    public static func panelFrame(client: CGRect, panelSize: CGSize, screen: CGRect, gap: CGFloat = 8) -> CGRect {
        let height = min(panelSize.height, min(client.height, screen.height))
        let maxY = max(screen.minY, screen.maxY - height)
        let y = min(max(screen.minY, client.maxY - height), maxY)
        let right = CGRect(x: client.maxX + gap, y: y, width: panelSize.width, height: height)
        if right.maxX <= screen.maxX, right.minX >= screen.minX {
            return right
        }
        let left = CGRect(x: client.minX - gap - panelSize.width, y: y, width: panelSize.width, height: height)
        if left.minX >= screen.minX, left.maxX <= screen.maxX {
            return left
        }
        let maxX = max(screen.minX, screen.maxX - panelSize.width)
        let x = min(max(screen.minX, client.maxX - panelSize.width - gap), maxX)
        return CGRect(x: x, y: y, width: panelSize.width, height: height)
    }
}
