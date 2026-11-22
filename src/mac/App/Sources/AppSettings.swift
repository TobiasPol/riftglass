import Foundation
import LeagueKit
import Observation
import OverlayKit
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
        static let manualRegion = "manualRegion"
        static let onboarding = "onboardingCompleted"
        static let plannedBuild = "plannedBuild"
        static let skillOverlay = "skillOverlayEnabled"
        static let skillOffset = "skillOverlayOffset"
        static let autoItemSet = "autoImportItemSet"
        static let autoRunes = "autoImportRunes"
        static let lastQueue = "lastQueue"
        static let briefing = "champSelectBriefingEnabled"
        static let draftOptions = "champSelectDraftOptionsEnabled"
        static let augmentOverlay = "augmentOverlayEnabled"
        static let toggleKey = "augmentToggleKeyCode"
        static let objectiveTimers = "objectiveTimersEnabled"
        static let recentGames = "recentGames"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var tabOverlayEnabled: Bool {
        didSet { defaults.set(tabOverlayEnabled, forKey: Key.tabOverlay) }
    }

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

    /// Optional manual region override (nil = Automatic from client).
    var manualRegion: String? {
        didSet { defaults.set(manualRegion, forKey: Key.manualRegion) }
    }

    var plannedBuild: BuildOption? {
        didSet { defaults.set(try? JSONEncoder().encode(plannedBuild), forKey: Key.plannedBuild) }
    }

    var skillOverlayEnabled: Bool {
        didSet { defaults.set(skillOverlayEnabled, forKey: Key.skillOverlay) }
    }

    var skillOverlayOffset: Double {
        didSet {
            let clamped = min(0.40, max(0.10, skillOverlayOffset))
            if clamped != skillOverlayOffset {
                skillOverlayOffset = clamped
                return
            }
            defaults.set(skillOverlayOffset, forKey: Key.skillOffset)
        }
    }

    var augmentOverlayEnabled: Bool {
        didSet { defaults.set(augmentOverlayEnabled, forKey: Key.augmentOverlay) }
    }

    var augmentToggleKeyCode: Int64 {
        didSet { defaults.set(Int(augmentToggleKeyCode), forKey: Key.toggleKey) }
    }

    var objectiveTimersEnabled: Bool {
        didSet { defaults.set(objectiveTimersEnabled, forKey: Key.objectiveTimers) }
    }

    var autoImportItemSet: Bool {
        didSet { defaults.set(autoImportItemSet, forKey: Key.autoItemSet) }
    }

    /// After lock-in: also import the first option's runes and spells (opt-in, COMPLIANCE.md).
    var autoImportRunes: Bool {
        didSet { defaults.set(autoImportRunes, forKey: Key.autoRunes) }
    }

    var briefingEnabled: Bool {
        didSet { defaults.set(briefingEnabled, forKey: Key.briefing) }
    }

    var draftOptionsEnabled: Bool {
        didSet { defaults.set(draftOptionsEnabled, forKey: Key.draftOptions) }
    }

    var lastQueue: GameQueue? {
        didSet { defaults.set(try? JSONEncoder().encode(lastQueue), forKey: Key.lastQueue) }
    }

    var recentGames: [GameSummary] {
        didSet { defaults.set(try? JSONEncoder().encode(recentGames), forKey: Key.recentGames) }
    }

    var onboardingCompleted: Bool {
        didSet { defaults.set(onboardingCompleted, forKey: Key.onboarding) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.tabOverlay: true, Key.ranks: true, Key.goldEstimate: false,
            Key.skillOverlay: true, Key.skillOffset: 0.20, Key.autoItemSet: true,
            Key.autoRunes: false, Key.briefing: true, Key.draftOptions: true,
            Key.augmentOverlay: true, Key.toggleKey: Int(HotkeyMonitor.toggleKeyCode),
            Key.objectiveTimers: true
        ])
        tabOverlayEnabled = defaults.bool(forKey: Key.tabOverlay)
        ranksEnabled = defaults.bool(forKey: Key.ranks)
        goldEstimateEnabled = defaults.bool(forKey: Key.goldEstimate)
        region = defaults.string(forKey: Key.region)
        manualRegion = defaults.string(forKey: Key.manualRegion).flatMap { $0.isEmpty ? nil : $0 }
        onboardingCompleted = defaults.bool(forKey: Key.onboarding)
        skillOverlayEnabled = defaults.bool(forKey: Key.skillOverlay)
        skillOverlayOffset = min(0.40, max(0.10, defaults.double(forKey: Key.skillOffset)))
        autoImportItemSet = defaults.bool(forKey: Key.autoItemSet)
        autoImportRunes = defaults.bool(forKey: Key.autoRunes)
        briefingEnabled = defaults.bool(forKey: Key.briefing)
        draftOptionsEnabled = defaults.bool(forKey: Key.draftOptions)
        augmentOverlayEnabled = defaults.bool(forKey: Key.augmentOverlay)
        augmentToggleKeyCode = Int64(defaults.integer(forKey: Key.toggleKey))
        objectiveTimersEnabled = defaults.bool(forKey: Key.objectiveTimers)
        lastQueue = defaults.data(forKey: Key.lastQueue).flatMap { try? JSONDecoder().decode(GameQueue.self, from: $0) }
        plannedBuild = defaults.data(forKey: Key.plannedBuild)
            .flatMap { try? JSONDecoder().decode(BuildOption.self, from: $0) }
        recentGames = defaults.data(forKey: Key.recentGames)
            .flatMap { try? JSONDecoder().decode([GameSummary].self, from: $0) } ?? []
    }
}

enum ToggleShortcut: Int64, CaseIterable, Identifiable {
    case optionA = 0
    case optionG = 5
    case optionZ = 6
    case optionX = 7
    case optionM = 46

    var id: Int64 {
        rawValue
    }

    var label: String {
        switch self {
        case .optionA: "⌥A"
        case .optionG: "⌥G"
        case .optionZ: "⌥Z"
        case .optionX: "⌥X"
        case .optionM: "⌥M"
        }
    }
}

extension AppSettings {
    static let knownRegions = [
        "EUW", "EUNE", "NA", "KR", "JP", "BR", "LAN", "LAS", "OCE", "TR", "RU", "SG", "TW", "VN", "ME"
    ]
    static let maxRecentGames = 10

    var effectiveRegion: String? {
        manualRegion ?? region
    }

    var toggleShortcutLabel: String {
        ToggleShortcut(rawValue: augmentToggleKeyCode)?.label ?? "⌥A"
    }

    func recordGame(_ summary: GameSummary) {
        recentGames = Array(([summary] + recentGames).prefix(Self.maxRecentGames))
    }

    func updateLatestGame(_ summary: GameSummary) {
        if let index = recentGames.firstIndex(where: { $0.id == summary.id }) {
            var updated = recentGames
            updated[index] = summary
            recentGames = updated
        } else {
            recordGame(summary)
        }
    }
}
