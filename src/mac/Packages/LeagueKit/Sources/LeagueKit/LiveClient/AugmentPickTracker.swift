import Foundation

/// A pending ARAM: Mayhem augment choice the overlay should accompany.
public struct AugmentPickPrompt: Equatable, Sendable {
    /// 1-based number of the oldest choice not yet covered (1…4).
    public let pick: Int
    /// Choices reached so far; more than `pick` when several stacked up while alive.
    public let available: Int
    public let total: Int

    public init(pick: Int, available: Int, total: Int) {
        self.pick = pick
        self.available = available
        self.total = total
    }
}

/// Decides when the in-game augment list is useful, from Live Client data only.
///
/// Neither the LCU nor the Live Client report the offered or chosen augments (docs/SPIKE.md), so the
/// tracker approximates the selection screen: a choice is owed once the champion reaches one of
/// `pickLevels`, and the screen can only open while the player may shop – dead, in the fountain at
/// match start, or shortly after respawning. When such a shop window closes, each choice that was shown
/// in it for at least `minimumWindow` seconds counts as made (a one-second tail of the respawn grace is
/// no chance to pick – seen live). Holding Tab shows the list regardless.
public struct AugmentPickTracker: Equatable, Sendable {
    /// Riot: first augment at match start (ARAM starts at level 3), more at 7, 11 and 15.
    public static let pickLevels = [3, 7, 11, 15]
    /// Game seconds after the start during which the player is in the fountain.
    public static let startWindow: Double = 75
    /// Seconds after a respawn the player is still in the fountain.
    public static let respawnGrace: Double = 15
    /// Shorter shop windows leave the choice pending.
    public static let minimumWindow: Double = 5

    private var covered = 0
    private var wasDead = false
    private var respawnedAt: Double?
    /// Game time each choice (1-based) was first shown in the current shop window.
    private var shownSince: [Int: Double] = [:]
    private var started = false

    public init() {}

    /// Feed every Live Client snapshot; returns the prompt to show, nil to hide.
    public mutating func update(level: Int, isDead: Bool, gameTime: Double) -> AugmentPickPrompt? {
        let available = Self.pickLevels.filter { $0 <= level }.count
        if !started {
            started = true
            // App started mid-game: earlier choices were made without us.
            if gameTime >= Self.startWindow {
                covered = available
            }
        }
        if wasDead, !isDead {
            respawnedAt = gameTime
        }
        wasDead = isDead
        let canShop = isDead || gameTime < Self.startWindow
            || respawnedAt.map { gameTime - $0 < Self.respawnGrace } == true
        if !shownSince.isEmpty, !canShop {
            // The window closed – choices count as made in order, each only if it was shown long enough;
            // a level reached on this very snapshot was never shown and stays pending.
            while let since = shownSince[covered + 1], gameTime - since >= Self.minimumWindow {
                covered += 1
            }
            shownSince = [:]
        }
        guard canShop, available > covered else { return nil }
        for pick in covered + 1 ... available where shownSince[pick] == nil {
            shownSince[pick] = gameTime
        }
        return AugmentPickPrompt(pick: covered + 1, available: available, total: Self.pickLevels.count)
    }
}
