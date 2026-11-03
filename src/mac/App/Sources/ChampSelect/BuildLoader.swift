import LeagueKit
import os
import StatsKit

/// Collects build options from all sources: OP.GG first (with stats), then Riot's own
/// recommendations from the LCU – which also serve as the fallback when OP.GG is unreachable.
struct BuildLoader {
    let opgg: any BuildProvider
    private let logger = Logger(subsystem: "de.polleydigital.riftglass", category: "BuildLoader")

    init(opgg: any BuildProvider = OPGGBuildProvider()) {
        self.opgg = opgg
    }

    /// Role from champ select; in blind/custom games Riot's main position for the champion.
    func resolveRole(session: ChampSelectSession?, championId: Int, lcu: (any LCURequesting)?) async -> Role {
        if let role = Role(lcuPosition: session?.localPosition) {
            return role
        }
        let recommended = await (try? lcu?.recommendedPositions(championId: championId)) ?? []
        return recommended.lazy.compactMap { Role(lcuPosition: $0) }.first ?? .middle
    }

    func load(champion: ChampionRef, role: Role, patch: String?, lcu: (any LCURequesting)?) async -> [BuildOption] {
        async let fromOPGG = opggBuilds(champion: champion, role: role, patch: patch)
        async let fromRiot = riotBuilds(championId: champion.id, role: role, lcu: lcu)
        let primary = await fromOPGG
        let knownRunes = Set(primary.map(\.runes.perkIds))
        return await primary + fromRiot.filter { !knownRunes.contains($0.runes.perkIds) }
    }

    private func opggBuilds(champion: ChampionRef, role: Role, patch: String?) async -> [BuildOption] {
        do {
            return try await opgg.builds(for: champion, role: role, patch: patch)
        } catch {
            logger.notice("OP.GG unavailable: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    private func riotBuilds(championId: Int, role: Role, lcu: (any LCURequesting)?) async -> [BuildOption] {
        guard let lcu,
              let pages = try? await lcu.recommendedPages(championId: championId, position: role.lcuPosition)
        else { return [] }
        return pages.prefix(3).enumerated().compactMap { index, page in
            Self.option(from: page, index: index, championId: championId, role: role)
        }
    }

    static func option(from page: RecommendedRunePage, index: Int, championId: Int, role: Role) -> BuildOption? {
        guard page.perkIds.count == 9 else { return nil }
        return BuildOption(
            id: "riot-\(championId)-\(role.rawValue)-\(index)",
            title: "Riot · \(page.keystone?.name ?? "Empfehlung")",
            role: role,
            source: .riot,
            runes: .init(
                primaryStyleId: page.primaryPerkStyleId,
                subStyleId: page.secondaryPerkStyleId,
                perkIds: page.perkIds
            ),
            summonerSpells: page.summonerSpellIds ?? [],
            itemBlocks: []
        )
    }
}
