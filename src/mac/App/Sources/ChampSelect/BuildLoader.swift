import LeagueKit
import os
import StatsKit

/// Loads build options from OP.GG – the only build source. Riot's own recommendations from the
/// client are deliberately not used (neither as extra options nor as a fallback).
/// Which statistics are used depends on the detected queue (`BuildQueue(queue:)`).
struct BuildLoader {
    let opgg: any BuildProvider
    private let logger = Logger(subsystem: "de.polleydigital.riftglass", category: "BuildLoader")

    init(opgg: any BuildProvider = OPGGBuildProvider()) {
        self.opgg = opgg
    }

    /// Role for the build: what champ select assigned, else the lane OP.GG sees the champion played
    /// most (blind pick, custom games), else mid. Modes without lanes (ARAM, Arena, …) have no role.
    static func resolveRole(assigned position: String?, championName: String, mode: GameMode, rates: RoleRates?)
        -> Role? {
        guard mode.hasLanes else { return nil }
        return Role(lcuPosition: position) ?? rates?.mainRole(of: championName) ?? .middle
    }

    func load(champion: ChampionRef, role: Role?, queue: GameQueue, patch: String?) async -> [BuildOption] {
        await fetch(champion: champion, role: role, queue: queue, patch: patch) ?? []
    }

    /// Skill order for the in-game overlay when champ select did not provide one (app started late).
    /// Empty when OP.GG has none for the champion; nil when OP.GG could not be asked (worth a retry).
    func skillOrder(champion: ChampionRef, role: Role?, queue: GameQueue) async -> [String]? {
        await fetch(champion: champion, role: role, queue: queue, patch: nil).map { $0.first?.skillOrder ?? [] }
    }

    /// Nil when the request failed; empty when OP.GG has nothing for this champion, role or queue.
    private func fetch(champion: ChampionRef, role: Role?, queue: GameQueue, patch: String?) async
        -> [BuildOption]? {
        guard let buildQueue = BuildQueue(queue: queue) else { return [] }
        do {
            return try await opgg.builds(for: champion, role: role ?? .middle, queue: buildQueue, patch: patch)
        } catch {
            logger.notice("OP.GG unavailable: \(String(describing: error), privacy: .public)")
            return nil
        }
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
