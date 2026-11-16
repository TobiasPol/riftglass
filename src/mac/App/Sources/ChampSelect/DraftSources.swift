import DataKit
import Foundation
import LeagueKit
import os
import StatsKit

/// The requests behind the draft options, off the main actor. Every source is optional: a missing
/// answer removes its factor from the score instead of failing the whole card.
struct DraftSources: Sendable {
    let briefing: BriefingSources
    let lcu: LCUClient?
    let logger: Logger

    /// Nil when the client did not answer (or answered with nothing, e.g. outside the pick phase);
    /// then nothing is filtered instead of hiding every option.
    func pickable() async -> Set<Int>? {
        guard let ids = try? await lcu?.pickableChampionIds(), !ids.isEmpty else { return nil }
        return ids
    }

    /// OP.GG's strongest matchups of a champion in the player's lane.
    func laneCounters(_ champion: ChampionRef?, _ input: DraftInput) async -> LaneCounters? {
        guard let champion else { return nil }
        do {
            return try await briefing.counters.laneCounters(of: champion, role: input.role, queue: input.queue)
        } catch {
            logger.notice("OP.GG counters unavailable: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Each ally's most played partners in the player's lane. Needs the ally's lane, so only for
    /// queues with assigned positions; at most four requests, cached for 6 h.
    func allySynergies(_ input: DraftInput, meta: LaneMeta, directory: ChampionDirectory) async -> [DraftAlly] {
        let byID = PickAdvisor.metaByID(meta, directory: directory)
        let requests = input.allies.compactMap { ally -> SynergyRequest? in
            guard let role = ally.role, role != input.role else { return nil }
            // The synergy tool wants OP.GG's English name; the tier list has it.
            let name = byID[role]?[ally.championId]?.name
                ?? byID.values.lazy.compactMap { $0[ally.championId]?.name }.first
            return name.map { SynergyRequest(id: ally.championId, role: role, name: $0) }
        }
        return await withTaskGroup(of: DraftAlly?.self) { group in
            for request in requests {
                group.addTask {
                    do {
                        let synergies = try await briefing.synergies.synergies(
                            of: request.name,
                            in: request.role,
                            with: input.role
                        )
                        return DraftAlly(championId: request.id, role: request.role, synergies: synergies)
                    } catch {
                        logger.notice("OP.GG synergies unavailable: \(String(describing: error), privacy: .public)")
                        return nil
                    }
                }
            }
            var allies: [DraftAlly] = []
            for await ally in group {
                if let ally {
                    allies.append(ally)
                }
            }
            return allies.sorted { $0.championId < $1.championId }
        }
    }

    /// Head-to-head win rates of the candidates against the opponent (lane matchup guide).
    func headToHead(
        _ candidates: [ChampionRef],
        against opponent: ChampionRef,
        role: Role
    ) async -> [Int: CounterPick] {
        await withTaskGroup(of: CounterPick?.self) { group in
            for candidate in candidates {
                group.addTask {
                    guard let brief = try? await briefing.matchups.matchup(
                              my: candidate,
                              against: opponent,
                              role: role
                          ),
                          let winRate = brief.winRate
                    else { return nil }
                    return CounterPick(id: candidate.id, name: candidate.key, winRate: winRate, games: brief.games)
                }
            }
            var result: [Int: CounterPick] = [:]
            for await pick in group {
                if let pick {
                    result[pick.id] = pick
                }
            }
            return result
        }
    }
}

private struct SynergyRequest {
    let id: Int
    let role: Role
    let name: String
}

/// Builds the advisors' inputs from the session and Data Dragon (pure).
enum DraftContexts {
    static func pick(
        _ input: DraftInput,
        meta: LaneMeta,
        directory: ChampionDirectory,
        data: StaticData
    ) -> PickContext {
        var context = PickContext(role: input.role, meta: meta, directory: directory)
        context.excluded = Set(input.allies.map(\.championId))
            .union(input.enemies.map(\.championId))
            .union(input.teammateBans)
        context.traits = data.championsById.mapValues {
            ChampionTraits(physicalShare: TeamProfile.physicalShare(of: $0), isFrontline: TeamProfile.isFrontline($0))
        }
        context.needs = needs(allies: input.allies.compactMap { data.champion($0.championId) })
        return context
    }

    /// What the allies shown so far lack. Damage needs two allies, frontline three, to mean anything.
    static func needs(allies: [Champion]) -> TeamNeeds {
        let team = TeamProfile(champions: allies)
        var needs = TeamNeeds()
        if team.count >= 2, let share = team.physicalShare {
            needs.magicDamage = share >= 0.7
            needs.physicalDamage = share <= 0.3
        }
        needs.frontline = team.count >= 3 && team.frontline == 0
        return needs
    }

    static func ban(_ input: DraftInput, meta: LaneMeta, directory: ChampionDirectory) -> BanContext {
        var context = BanContext(meta: meta, directory: directory)
        context.role = input.role
        context.excluded = Set(input.allies.map(\.championId)).union(input.teammateBans)
        if let own = input.ownChampionId {
            context.excluded.insert(own)
            context.yourChampionId = own
        }
        return context
    }

    /// The own champion's duo statistics with each ally that lists it.
    static func teamSynergies(_ input: DraftInput, allies: [DraftAlly]) -> [TeamSynergy] {
        guard let own = input.ownChampionId else { return [] }
        return allies.compactMap { ally in
            ally.synergies.first { $0.id == own }
                .map { TeamSynergy(allyId: ally.championId, winRate: $0.winRate, games: $0.games) }
        }
    }
}
