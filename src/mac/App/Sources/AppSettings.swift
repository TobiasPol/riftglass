import Foundation
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

    var onboardingCompleted: Bool {
        didSet { defaults.set(onboardingCompleted, forKey: Key.onboarding) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Key.tabOverlay: true, Key.ranks: true, Key.goldEstimate: false])
        tabOverlayEnabled = defaults.bool(forKey: Key.tabOverlay)
        ranksEnabled = defaults.bool(forKey: Key.ranks)
        goldEstimateEnabled = defaults.bool(forKey: Key.goldEstimate)
        region = defaults.string(forKey: Key.region)
        onboardingCompleted = defaults.bool(forKey: Key.onboarding)
        plannedBuild = defaults.data(forKey: Key.plannedBuild)
            .flatMap { try? JSONDecoder().decode(BuildOption.self, from: $0) }
    }
}
