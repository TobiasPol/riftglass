import Foundation

/// One build suggestion. Riftglass always shows several options – never a single instruction
/// (Riot policy: apps must not dictate player decisions).
public struct BuildOption: Codable, Equatable, Identifiable, Sendable {
    public struct Runes: Codable, Equatable, Sendable {
        public let primaryStyleId: Int
        public let subStyleId: Int
        /// 6 runes followed by 3 stat shards.
        public let perkIds: [Int]
    }

    public struct ItemBlock: Codable, Equatable, Sendable {
        public let title: String
        public let itemIds: [Int]
    }

    public let id: String
    public let title: String
    public let role: Role
    public let runes: Runes
    public let summonerSpells: [Int]
    public let itemBlocks: [ItemBlock]
    /// Placeholder data, not statistics. Shown in the UI.
    public let isPlaceholder: Bool
}

public enum Role: String, Codable, CaseIterable, Sendable {
    case top, jungle, middle, bottom, utility

    /// Maps the LCU's `assignedPosition` (lowercased) to a role.
    public init?(lcuPosition: String?) {
        guard let position = lcuPosition?.lowercased() else { return nil }
        self.init(rawValue: position)
    }
}

/// Source of build options. Phase 1: bundled placeholders; Phase 3: own backend.
public protocol BuildProvider: Sendable {
    /// Options for a champion; `role == nil` returns all roles (blind pick, custom games).
    func builds(championId: Int, role: Role?, patch: String?) async throws -> [BuildOption]
}
