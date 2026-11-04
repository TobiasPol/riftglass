import Foundation
import LeagueKit
import Observation
import StatsKit

/// User preferences, persisted in `UserDefaults`.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private enum Key {
        static let tabOverlay = "tabOverlayEnabled"
        static let ranks = "opggRanksEnabled"
        static let goldEstimate = "goldEstimateEnabled"
        static let region = "lastRegion"
        static let onboarding = "onboardingCompleted"
        static let plannedBuild = "plannedBuild"
        static let skillOverlay = "skillOverlayEnabled"
        static let autoItemSet = "autoImportItemSet"
        static let autoRunes = "autoImportRunes"
        static let lastQueue = "lastQueue"
        static let briefing = "champSelectBriefingEnabled"
        static let augmentOverlay = "augmentOverlayEnabled"
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// Tab-held overlay in game.
    var tabOverlayEnabled: Bool {
        didSet { defaults.set(tabOverlayEnabled, forKey: Key.tabOverlay) }
    }

    /// Look up ranks of the 10 players via OP.GG (sends their Riot IDs to OP.GG).
    var ranksEnabled: Bool {
        didSet { defaults.set(ranksEnabled, forKey: Key.ranks) }
    }

    /// Item-value difference per lane. Policy risk → off by default (COMPLIANCE.md).
    var goldEstimateEnabled: Bool {
        didSet { defaults.set(goldEstimateEnabled, forKey: Key.goldEstimate) }
    }

    /// Platform region from the LCU, remembered because the client is closed in game.
    var region: String? {
        didSet { defaults.set(region, forKey: Key.region) }
    }

    /// Build chosen in champ select; persisted so build progress survives an app restart in game.
    var plannedBuild: BuildOption? {
        didSet { defaults.set(try? JSONEncoder().encode(plannedBuild), forKey: Key.plannedBuild) }
    }

    /// Shows which ability to level whenever a skill point is unspent (no hotkey needed).
    var skillOverlayEnabled: Bool {
        didSet { defaults.set(skillOverlayEnabled, forKey: Key.skillOverlay) }
    }

    /// ARAM: Mayhem: the champion's augment list appears while an augment choice is likely open.
    var augmentOverlayEnabled: Bool {
        didSet { defaults.set(augmentOverlayEnabled, forKey: Key.augmentOverlay) }
    }

    /// After lock-in: write the first option's item set for the detected mode's map.
    var autoImportItemSet: Bool {
        didSet { defaults.set(autoImportItemSet, forKey: Key.autoItemSet) }
    }

    /// After lock-in: also import the first option's runes and spells. Off by default – it changes
    /// the player's active page and spells (docs/COMPLIANCE.md).
    var autoImportRunes: Bool {
        didSet { defaults.set(autoImportRunes, forKey: Key.autoRunes) }
    }

    /// Champ select: lane matchup, team comp and counter picks (OP.GG + Data Dragon).
    var briefingEnabled: Bool {
        didSet { defaults.set(briefingEnabled, forKey: Key.briefing) }
    }

    /// Queue of the last lobby, kept because the LCU is closed in game.
    var lastQueue: GameQueue? {
        didSet { defaults.set(try? JSONEncoder().encode(lastQueue), forKey: Key.lastQueue) }
    }

    var onboardingCompleted: Bool {
        didSet { defaults.set(onboardingCompleted, forKey: Key.onboarding) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.tabOverlay: true, Key.ranks: true, Key.goldEstimate: false,
            Key.skillOverlay: true, Key.autoItemSet: true, Key.autoRunes: false,
            Key.briefing: true, Key.augmentOverlay: true
        ])
        tabOverlayEnabled = defaults.bool(forKey: Key.tabOverlay)
        ranksEnabled = defaults.bool(forKey: Key.ranks)
        goldEstimateEnabled = defaults.bool(forKey: Key.goldEstimate)
        region = defaults.string(forKey: Key.region)
        onboardingCompleted = defaults.bool(forKey: Key.onboarding)
        skillOverlayEnabled = defaults.bool(forKey: Key.skillOverlay)
        autoImportItemSet = defaults.bool(forKey: Key.autoItemSet)
        autoImportRunes = defaults.bool(forKey: Key.autoRunes)
        briefingEnabled = defaults.bool(forKey: Key.briefing)
        augmentOverlayEnabled = defaults.bool(forKey: Key.augmentOverlay)
        lastQueue = defaults.data(forKey: Key.lastQueue).flatMap { try? JSONDecoder().decode(GameQueue.self, from: $0) }
        plannedBuild = defaults.data(forKey: Key.plannedBuild)
            .flatMap { try? JSONDecoder().decode(BuildOption.self, from: $0) }
    }
}
