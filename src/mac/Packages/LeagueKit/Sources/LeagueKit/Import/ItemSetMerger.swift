import Foundation

/// An item set Riftglass wants to write for one champion.
public struct ItemSetDraft: Equatable, Sendable {
    public struct Block: Equatable, Sendable {
        public let title: String
        public let itemIds: [Int]

        public init(title: String, itemIds: [Int]) {
            self.title = title
            self.itemIds = itemIds
        }
    }

    public let championId: Int
    public let title: String
    public let blocks: [Block]
    /// Map the set is shown on (11 = Summoner's Rift, 12 = Howling Abyss).
    public let mapId: Int

    public init(championId: Int, title: String, blocks: [Block], mapId: Int = 11) {
        self.championId = championId
        self.title = title
        self.blocks = blocks
        self.mapId = mapId
    }

    /// Deterministic per champion and map: `52494654-474c-4153-53xx-…` ("RIFTGLASS" in hex), where
    /// `xx` is `00` for Summoner's Rift (the format before v0.2) or the map ID, + champion ID.
    public var uid: String {
        let mapByte = mapId == 11 ? 0 : mapId & 0xFF
        return ItemSetMerger.uidPrefix + String(format: "%02x-%012x", mapByte, championId)
    }

    var json: JSONValue {
        .object([
            "uid": .string(uid),
            "title": .string(title),
            "type": .string("custom"),
            "map": .string("any"),
            "mode": .string("any"),
            "priority": .bool(false),
            "sortrank": .number(0),
            "startedFrom": .string("blank"),
            "associatedChampions": .array([.number(Double(championId))]),
            "associatedMaps": .array([.number(Double(mapId))]),
            "preferredItemSlots": .array([]),
            "blocks": .array(blocks.map(Self.blockJSON))
        ])
    }

    private static func blockJSON(_ block: Block) -> JSONValue {
        .object([
            "type": .string(block.title),
            "showIfSummonerSpell": .string(""),
            "hideIfSummonerSpell": .string(""),
            "items": .array(block.itemIds.map { .object(["id": .string(String($0)), "count": .number(1)]) })
        ])
    }
}

public enum ItemSetMergeError: Error, Equatable {
    case unexpectedDocument
}

/// Merges a Riftglass item set into the account's item-set document.
///
/// `PUT /lol-item-sets/v1/item-sets/{summonerId}/sets` replaces the **whole** list, so every other
/// set is passed through as raw JSON – unknown fields of other tools survive byte-for-byte.
public enum ItemSetMerger {
    static let uidPrefix = "52494654-474c-4153-53"

    public static func merge(_ draft: ItemSetDraft, into document: JSONValue) throws -> JSONValue {
        guard case var .object(root) = document else { throw ItemSetMergeError.unexpectedDocument }
        let existing: [JSONValue]
        switch root["itemSets"] {
        case let .array(sets): existing = sets
        case nil, .null?: existing = []
        default: throw ItemSetMergeError.unexpectedDocument
        }
        let others = existing.filter { $0["uid"]?.stringValue != draft.uid }
        root["itemSets"] = .array(others + [draft.json])
        return .object(root)
    }

    /// Number of sets Riftglass owns in a document (for diagnostics/tests).
    public static func ownSetCount(in document: JSONValue) -> Int {
        guard case let .array(sets)? = document["itemSets"] else { return 0 }
        return sets.filter { $0["uid"]?.stringValue?.hasPrefix(uidPrefix) == true }.count
    }
}
