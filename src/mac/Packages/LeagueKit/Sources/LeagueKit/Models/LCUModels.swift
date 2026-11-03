import Foundation

// Tolerant models of the (unofficial) LCU endpoints Riftglass uses. Every field that is not
// strictly needed is optional so that client updates do not break decoding.

/// `GET /lol-summoner/v1/current-summoner`
public struct CurrentSummoner: Decodable, Equatable, Sendable {
    public let summonerId: Int64
    public let puuid: String?
    public let gameName: String?
    public let tagLine: String?
    public let summonerLevel: Int?
}

/// `GET /lol-perks/v1/inventory`
public struct PerkInventory: Decodable, Equatable, Sendable {
    public let canAddCustomPage: Bool
    public let customPageCount: Int?
    public let ownedPageCount: Int?

    public init(canAddCustomPage: Bool, customPageCount: Int? = nil, ownedPageCount: Int? = nil) {
        self.canAddCustomPage = canAddCustomPage
        self.customPageCount = customPageCount
        self.ownedPageCount = ownedPageCount
    }
}

/// Element of `GET /lol-perks/v1/pages`.
public struct RunePage: Decodable, Equatable, Sendable {
    public let id: Int64
    public let name: String
    public let isDeletable: Bool?
    public let isEditable: Bool?
    public let isTemporary: Bool?
    public let current: Bool?
    public let primaryStyleId: Int?
    public let subStyleId: Int?
    public let selectedPerkIds: [Int]?

    public init(
        id: Int64,
        name: String,
        isDeletable: Bool? = true,
        isEditable: Bool? = true,
        isTemporary: Bool? = false,
        current: Bool? = false,
        primaryStyleId: Int? = nil,
        subStyleId: Int? = nil,
        selectedPerkIds: [Int]? = nil
    ) {
        self.id = id
        self.name = name
        self.isDeletable = isDeletable
        self.isEditable = isEditable
        self.isTemporary = isTemporary
        self.current = current
        self.primaryStyleId = primaryStyleId
        self.subStyleId = subStyleId
        self.selectedPerkIds = selectedPerkIds
    }
}

/// Body of `POST /lol-perks/v1/pages`.
public struct NewRunePage: Encodable, Equatable, Sendable {
    public let name: String
    public let primaryStyleId: Int
    public let subStyleId: Int
    public let selectedPerkIds: [Int]
    public let current: Bool

    public init(name: String, primaryStyleId: Int, subStyleId: Int, selectedPerkIds: [Int], current: Bool = true) {
        self.name = name
        self.primaryStyleId = primaryStyleId
        self.subStyleId = subStyleId
        self.selectedPerkIds = selectedPerkIds
        self.current = current
    }
}

/// Body of `PATCH /lol-champ-select/v1/session/my-selection`.
public struct SpellSelection: Encodable, Equatable, Sendable {
    public let spell1Id: Int
    public let spell2Id: Int

    public init(spell1Id: Int, spell2Id: Int) {
        self.spell1Id = spell1Id
        self.spell2Id = spell2Id
    }
}
