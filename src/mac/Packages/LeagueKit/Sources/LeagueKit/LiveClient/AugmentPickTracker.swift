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
/// match start, or shortly after respawning. When such a shop window closes while the list was shown,
/// the choice counts as made. Holding Tab shows the list regardless.
public struct AugmentPickTracker: Equatable, Sendable {
    /// Riot: first augment at match start (ARAM starts at level 3), more at 7, 11 and 15.
    public static let pickLevels = [3, 7, 11, 15]
    /// Game seconds after the start during which the player is in the fountain.
    public static let startWindow: Double = 75
    /// Seconds after a respawn the player is still in the fountain.
    public static let respawnGrace: Double = 15

    private var covered = 0
    private var wasDead = false
    private var respawnedAt: Double?
    private var wasPrompting = false
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
        let prompting = canShop && available > covered
        if wasPrompting, !canShop {
            covered = available // the window closed while the list was shown
        }
        wasPrompting = prompting
        guard prompting else { return nil }
        return AugmentPickPrompt(pick: covered + 1, available: available, total: Self.pickLevels.count)
    }
}
