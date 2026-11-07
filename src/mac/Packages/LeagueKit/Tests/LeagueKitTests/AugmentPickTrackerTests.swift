@testable import LeagueKit
import Testing

struct AugmentPickTrackerTests {
    @Test func firstPickAtMatchStartUntilFountainWindowEnds() {
        var tracker = AugmentPickTracker()
        #expect(tracker.update(level: 3, isDead: false, gameTime: 2)?.pick == 1)
        #expect(tracker.update(level: 3, isDead: false, gameTime: 60)?.pick == 1)
        #expect(tracker.update(level: 3, isDead: false, gameTime: 80) == nil)
        // Pick 1 counts as made; dying at level 5 owes nothing new.
        #expect(tracker.update(level: 5, isDead: true, gameTime: 200) == nil)
    }

    @Test func pickReachedAliveShowsOnDeathAndRespawn() {
        var tracker = AugmentPickTracker()
        _ = tracker.update(level: 3, isDead: false, gameTime: 1)
        _ = tracker.update(level: 3, isDead: false, gameTime: 90)
        #expect(tracker.update(level: 7, isDead: false, gameTime: 300) == nil) // in combat: no screen
        #expect(tracker.update(level: 7, isDead: true, gameTime: 310) == AugmentPickPrompt(
            pick: 2, available: 2, total: 4
        ))
        #expect(tracker.update(level: 7, isDead: false, gameTime: 330)?.pick == 2) // fountain after respawn
        #expect(tracker.update(level: 7, isDead: false, gameTime: 340)?.pick == 2)
        #expect(tracker.update(level: 7, isDead: false, gameTime: 346) == nil) // left the fountain
        #expect(tracker.update(level: 8, isDead: true, gameTime: 500) == nil)
    }

    @Test func stackedPicksAreReported() {
        var tracker = AugmentPickTracker()
        _ = tracker.update(level: 3, isDead: false, gameTime: 1)
        _ = tracker.update(level: 3, isDead: false, gameTime: 100)
        let prompt = tracker.update(level: 11, isDead: true, gameTime: 600)
        #expect(prompt == AugmentPickPrompt(pick: 2, available: 3, total: 4))
    }

    @Test func appStartedMidGameSkipsEarlierPicks() {
        var tracker = AugmentPickTracker()
        #expect(tracker.update(level: 9, isDead: true, gameTime: 700) == nil)
        _ = tracker.update(level: 9, isDead: false, gameTime: 720)
        _ = tracker.update(level: 9, isDead: false, gameTime: 800)
        #expect(tracker.update(level: 11, isDead: true, gameTime: 900)?.pick == 3)
    }

    @Test func levelFifteenIsTheLastPick() {
        var tracker = AugmentPickTracker()
        _ = tracker.update(level: 18, isDead: false, gameTime: 1500)
        #expect(tracker.update(level: 18, isDead: true, gameTime: 1600) == nil)
    }

    @Test func levelReachedAsWindowClosesStaysPending() {
        var tracker = AugmentPickTracker()
        _ = tracker.update(level: 3, isDead: false, gameTime: 1)
        _ = tracker.update(level: 3, isDead: false, gameTime: 100)
        #expect(tracker.update(level: 10, isDead: true, gameTime: 400)?.pick == 2)
        #expect(tracker.update(level: 10, isDead: false, gameTime: 420)?.pick == 2)
        #expect(tracker.update(level: 11, isDead: false, gameTime: 435) == nil) // window closes, level 11 arrives
        #expect(tracker.update(level: 11, isDead: true, gameTime: 600)?.pick == 3)
    }

    /// Live game 2026-11-07: level 7 reached 14 s after a respawn, the grace ended one second later.
    @Test func shortWindowLeavesPickPending() {
        var tracker = AugmentPickTracker()
        _ = tracker.update(level: 3, isDead: false, gameTime: 1)
        _ = tracker.update(level: 3, isDead: false, gameTime: 76)
        _ = tracker.update(level: 6, isDead: true, gameTime: 220)
        _ = tracker.update(level: 6, isDead: false, gameTime: 238)
        #expect(tracker.update(level: 7, isDead: false, gameTime: 252)?.pick == 2)
        #expect(tracker.update(level: 7, isDead: false, gameTime: 253) == nil)
        #expect(tracker.update(level: 7, isDead: true, gameTime: 302)?.pick == 2)
    }

    /// Review case: pick 3 arrives one second before the window closes – only pick 2 counts as made.
    @Test func eachPickNeedsItsOwnMinimumWindow() {
        var tracker = AugmentPickTracker()
        _ = tracker.update(level: 3, isDead: false, gameTime: 1)
        _ = tracker.update(level: 3, isDead: false, gameTime: 76)
        #expect(tracker.update(level: 10, isDead: true, gameTime: 400)?.pick == 2)
        #expect(tracker.update(level: 10, isDead: false, gameTime: 420)?.pick == 2)
        #expect(tracker.update(level: 11, isDead: false, gameTime: 434) == AugmentPickPrompt(
            pick: 2, available: 3, total: 4
        ))
        #expect(tracker.update(level: 11, isDead: false, gameTime: 435) == nil)
        #expect(tracker.update(level: 11, isDead: true, gameTime: 600)?.pick == 3)
    }
}
