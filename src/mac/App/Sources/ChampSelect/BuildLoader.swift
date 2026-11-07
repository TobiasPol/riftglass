import LeagueKit
import os
import StatsKit

/// Collects build options from all sources: OP.GG first (with stats), then Riot's own
/// recommendations from the LCU – which also serve as the fallback when OP.GG is unreachable.
/// Which statistics are used depends on the detected queue (`BuildQueue(queue:)`).
struct BuildLoader {
    let opgg: any BuildProvider
    private let logger = Logger(subsystem: "de.polleydigital.riftglass", category: "BuildLoader")

    init(opgg: any BuildProvider = OPGGBuildProvider()) {
        self.opgg = opgg
    }

    /// Role from champ select; in blind/custom games Riot's main position for the champion.
    /// Modes without lanes (ARAM, Arena, …) have no meaningful role.
    func resolveRole(session: ChampSelectSession?, championId: Int, mode: GameMode, lcu: (any LCURequesting)?) async
        -> Role? {
        guard mode.hasLanes else { return nil }
        if let role = Role(lcuPosition: session?.localPosition) {
            return role
        }
        let recommended = await (try? lcu?.recommendedPositions(championId: championId)) ?? []
        return recommended.lazy.compactMap { Role(lcuPosition: $0) }.first ?? .middle
    }

    func load(champion: ChampionRef, role: Role?, queue: GameQueue, patch: String?, lcu: (any LCURequesting)?) async
        -> [BuildOption] {
        let role = role ?? .middle
        async let fromOPGG = opggBuilds(champion: champion, role: role, queue: queue, patch: patch)
        async let fromRiot = riotBuilds(champion: champion, role: role, queue: queue, lcu: lcu)
        let primary = await fromOPGG
        let knownRunes = Set(primary.map(\.runes.perkIds))
        // Riot pages carry no skill order; OP.GG's for the same champion and queue applies to them too.
        let skillOrder = primary.first?.skillOrder ?? []
        return await primary + fromRiot.filter { !knownRunes.contains($0.runes.perkIds) }
            .map { $0.with(skillOrder: skillOrder) }
    }

    /// Skill order for the in-game overlay when champ select did not provide one (app started late).
    func skillOrder(champion: ChampionRef, role: Role?, queue: GameQueue) async -> [String] {
        await opggBuilds(champion: champion, role: role ?? .middle, queue: queue, patch: nil).first?.skillOrder ?? []
    }

    private func opggBuilds(champion: ChampionRef, role: Role, queue: GameQueue, patch: String?) async
        -> [BuildOption] {
        guard let buildQueue = BuildQueue(queue: queue) else { return [] }
        do {
            return try await opgg.builds(for: champion, role: role, queue: buildQueue, patch: patch)
        } catch {
            logger.notice("OP.GG unavailable: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    private func riotBuilds(champion: ChampionRef, role: Role, queue: GameQueue, lcu: (any LCURequesting)?) async
        -> [BuildOption] {
        guard let lcu, let mapId = queue.mode.recommendationMapId else { return [] }
        let position = queue.mode.hasLanes ? role.lcuPosition : "NONE"
        let pages = await (try? lcu.recommendedPages(championId: champion.id, position: position, mapId: mapId)) ?? []
        return pages.prefix(3).enumerated().compactMap { index, page in
            Self.option(from: page, index: index, champion: champion, role: role, queue: BuildQueue(queue: queue))
        }
    }

    /// `queue` tags the option with the statistics queue it was loaded for, so the in-game skill
    /// overlay never reuses it (and the attached OP.GG skill order) in another queue.
    static func option(
        from page: RecommendedRunePage,
        index: Int,
        champion: ChampionRef,
        role: Role,
        queue: BuildQueue?
    ) -> BuildOption? {
        guard page.perkIds.count == 9 else { return nil }
        return BuildOption(
            id: "riot-\(champion.id)-\(role.rawValue)-\(index)",
            title: "Riot · \(page.keystone?.name ?? String(localized: "Recommendation"))",
            role: role,
            championKey: champion.key,
            queue: queue,
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

extension BuildQueue {
    /// OP.GG statistics for a detected queue. Nil when OP.GG has nothing fitting (Arena, Brawl,
    /// Swarm, Nexus Blitz, League Classic). Fun modes on Summoner's Rift use ranked data as the
    /// closest approximation.
    init?(queue: GameQueue) {
        switch queue.mode {
        case .summonersRift: self = queue.isFlex ? .flex : .ranked
        case .urf, .oneForAll, .ultimateSpellbook: self = .ranked
        case .aram, .aramMayhem: self = .aram
        case .arena, .nexusBlitz, .brawl, .swarm, .leagueClassic, .unknown: return nil
        }
    }
}

extension BuildOption {
    func with(skillOrder: [String]) -> BuildOption {
        guard self.skillOrder.isEmpty, !skillOrder.isEmpty else { return self }
        return BuildOption(
            id: id, title: title, role: role, championKey: championKey, queue: queue, source: source,
            runes: runes, summonerSpells: summonerSpells, itemBlocks: itemBlocks,
            skillOrder: skillOrder, stats: stats
        )
    }
}
