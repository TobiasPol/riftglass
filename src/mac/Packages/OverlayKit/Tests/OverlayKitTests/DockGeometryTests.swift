import CoreGraphics
@testable import OverlayKit
import Testing

struct DockGeometryTests {
    private let screen = CGRect(x: 0, y: 0, width: 3008, height: 1692)
    private let panel = CGSize(width: 340, height: 560)

    @Test func picksLargestNormalLayerWindowOfClient() {
        let windows = [
            WindowInfo(ownerPID: 1, layer: 0, bounds: CGRect(x: 0, y: 0, width: 2000, height: 1000)), // other app
            WindowInfo(ownerPID: 7, layer: 0, bounds: CGRect(x: 0, y: 0, width: 300, height: 200)), // popup
            WindowInfo(ownerPID: 7, layer: 0, bounds: CGRect(x: 920, y: 285, width: 1600, height: 900)),
            WindowInfo(ownerPID: 7, layer: 25, bounds: CGRect(x: 0, y: 0, width: 3000, height: 1600))
        ]
        #expect(DockGeometry.clientWindow(in: windows, pid: 7)?.bounds == CGRect(
            x: 920,
            y: 285,
            width: 1600,
            height: 900
        ))
        #expect(DockGeometry.clientWindow(in: windows, pid: 99) == nil)
    }

    @Test func convertsRecordedSpikeBounds() {
        // Spike: CG (920, 285, 1600×900) on a 1692 pt high primary screen → AppKit y = 507.
        let rect = DockGeometry.appKitRect(
            fromCG: CGRect(x: 920, y: 285, width: 1600, height: 900),
            primaryScreenHeight: 1692
        )
        #expect(rect == CGRect(x: 920, y: 507, width: 1600, height: 900))
    }

    @Test func docksRightAlignedToTop() {
        let client = CGRect(x: 100, y: 500, width: 1600, height: 900)
        let frame = DockGeometry.panelFrame(client: client, panelSize: panel, screen: screen)
        #expect(frame == CGRect(x: 1708, y: 840, width: 340, height: 560))
    }

    @Test func fallsBackToLeftThenInside() {
        let nearRight = CGRect(x: 1300, y: 500, width: 1600, height: 900)
        #expect(DockGeometry.panelFrame(client: nearRight, panelSize: panel, screen: screen).maxX == 1292)
        let fullWidth = CGRect(x: 0, y: 0, width: 3008, height: 1692)
        let inside = DockGeometry.panelFrame(client: fullWidth, panelSize: panel, screen: screen)
        #expect(inside.maxX == 3000)
        #expect(screen.contains(inside))
    }

    @Test func heightIsCappedByClient() {
        let small = CGRect(x: 100, y: 100, width: 1024, height: 400)
        #expect(DockGeometry.panelFrame(client: small, panelSize: panel, screen: screen).height == 400)
    }
}
