import CoreGraphics
@testable import OverlayKit
import Testing

struct OverlayPlacementTests {
    private let cards = OverlayPanel.Anchor.besideCentre(.left, clearHalfWidth: 0.5, gap: 24, centreY: 0.42)
    private let panel = CGSize(width: 250, height: 400)

    /// 3440 × 1440 (21:9, live game 2026-11-07): the cards span ±0.49 × height around the middle.
    @Test func sitsLeftOfTheCardsOnUltrawide() {
        let screen = CGRect(x: 0, y: 0, width: 3440, height: 1440)
        let origin = OverlayPanel.origin(for: cards, size: panel, in: screen)
        #expect(abs(origin.x + panel.width - (1720 - 720 - 24)) < 0.5)
        #expect(abs(origin.y + panel.height / 2 - 1440 * 0.58) < 0.5)
    }

    @Test func clampsToTheScreenOnNarrowDisplays() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let origin = OverlayPanel.origin(for: cards, size: panel, in: screen)
        #expect(origin.x == 16)
        // Taller than the screen allows: the top edge stays visible.
        let tall = CGSize(width: 250, height: 980)
        #expect(abs(OverlayPanel.origin(for: cards, size: tall, in: screen).y + tall.height - 966) < 0.5)
    }

    @Test func respectsSecondaryScreenOffsets() {
        let screen = CGRect(x: 3440, y: 200, width: 2560, height: 1440)
        let origin = OverlayPanel.origin(for: cards, size: panel, in: screen)
        #expect(abs(origin.x - (3440 + 1280 - 720 - 24 - 250)) < 0.5)
    }

    @Test func rightSideMirrorsAndClamps() {
        let right = OverlayPanel.Anchor.besideCentre(.right, clearHalfWidth: 0.5, gap: 24, centreY: 0.42)
        let wide = OverlayPanel.origin(for: right, size: panel, in: CGRect(x: 0, y: 0, width: 3440, height: 1440))
        #expect(abs(wide.x - (1720 + 720 + 24)) < 0.5)
        let narrow = OverlayPanel.origin(for: right, size: panel, in: CGRect(x: 0, y: 0, width: 1512, height: 982))
        #expect(abs(narrow.x - (1512 - 16 - 250)) < 0.5)
    }

    @Test func centredAnchorsKeepTheirMeaning() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let size = CGSize(width: 200, height: 100)
        #expect(OverlayPanel.origin(for: .top(28), size: size, in: screen) == CGPoint(x: 400, y: 872))
        #expect(OverlayPanel.origin(for: .bottomFraction(0.2), size: size, in: screen) == CGPoint(x: 400, y: 200))
    }
}
