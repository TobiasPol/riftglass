import Foundation

public enum RuneImportError: Error, Equatable {
    /// Rune page storage is full and Riftglass has no page of its own to replace.
    case noFreeSlot
    case invalidPage
}

/// What to do to get the desired rune page into the client.
public enum RunePagePlan: Equatable, Sendable {
    case create(NewRunePage)
    /// Delete Riftglass' own page (by ID), then create the new one.
    case replace(ownPageId: Int64, with: NewRunePage)
}

/// Decides how to import a rune page **without ever touching pages Riftglass did not create**.
public enum RunePagePlanner {
    /// Riftglass pages are recognised by this name prefix.
    public static let pageNamePrefix = "Riftglass"

    public static func pageName(for championName: String) -> String {
        "\(pageNamePrefix): \(championName)"
    }

    public static func plan(
        desired: NewRunePage,
        existing pages: [RunePage],
        inventory: PerkInventory
    ) throws -> RunePagePlan {
        guard isValid(desired) else { throw RuneImportError.invalidPage }
        if let own = ownPage(in: pages) {
            return .replace(ownPageId: own.id, with: desired)
        }
        guard inventory.canAddCustomPage else { throw RuneImportError.noFreeSlot }
        return .create(desired)
    }

    static func ownPage(in pages: [RunePage]) -> RunePage? {
        pages.first {
            $0.name.hasPrefix(pageNamePrefix) && $0.isDeletable != false && $0.isTemporary != true
        }
    }

    /// 6 runes + 3 stat shards, all positive IDs, two different styles.
    static func isValid(_ page: NewRunePage) -> Bool {
        page.selectedPerkIds.count == 9
            && page.selectedPerkIds.allSatisfy { $0 > 0 }
            && page.primaryStyleId > 0 && page.subStyleId > 0
            && page.primaryStyleId != page.subStyleId
            && page.name.hasPrefix(pageNamePrefix)
    }
}
