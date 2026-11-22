import Foundation

/// Decodable schema for OP.GG's `lol_get_lane_matchup_guide` JSON response.
struct Guide: Decodable {
    struct Payload: Decodable {
        let opponentChampionTip: String?
        let laneAdvantageChampion: String?
        let laneSoloKillAdvantageChampion: String?
        let recommendedPlayStyle: String?
        let counters: [Counter]?
        let runes: [RuneEntry]?
        let starterItems: [ItemEntry]?
        let coreItems: [ItemEntry]?
        let boots: [ItemEntry]?
        let lastItems: [ItemEntry]?
        let summonerSpells: [ItemEntry]?
        let skills: [SkillEntry]?
    }

    /// All optional: one incomplete entry must not discard the whole guide.
    struct Counter: Decodable {
        let championId: Int?
        let play: Int?
        let win: Int?
    }

    struct RuneEntry: Decodable {
        let primaryPageId: Int?
        let primaryRuneIds: [Int]?
        let secondaryPageId: Int?
        let secondaryRuneIds: [Int]?
        let statModIds: [Int]?
    }

    struct ItemEntry: Decodable {
        let ids: [Int]?
        let play: Int?
        let win: Int?
        let pickRate: Double?
    }

    struct SkillEntry: Decodable {
        let order: [String]?
    }

    let myChampion: String?
    let opponentChampion: String?
    let data: Payload?

    func buildOption(champion: ChampionRef?, opponentId: Int, role: Role?, queue: BuildQueue) -> BuildOption? {
        guard let champion, let role, let data, let runes = resolvedRunes(from: data) else { return nil }
        let title = (opponentChampion?.isEmpty == false)
            ? "Matchup Build vs. \(opponentChampion ?? "")"
            : "Matchup Build"
        let coreStat = data.coreItems?.first
        let stats: BuildOption.Stats? = coreStat.flatMap { entry -> BuildOption.Stats? in
            guard let play = entry.play, play > 0, let win = entry.win else { return nil }
            return BuildOption.Stats(
                winRate: Double(win) / Double(play),
                pickRate: entry.pickRate,
                games: play
            )
        }
        return BuildOption(
            id: "opgg-matchup-\(champion.key)-\(opponentId)-\(queue.rawValue)-\(role.rawValue)",
            title: title,
            role: role,
            championKey: champion.key,
            queue: queue,
            source: .opgg,
            runes: runes,
            summonerSpells: data.summonerSpells?.first?.ids ?? [],
            itemBlocks: resolvedItemBlocks(from: data),
            skillOrder: data.skills?.first?.order ?? [],
            stats: stats
        )
    }

    private func resolvedRunes(from data: Payload) -> BuildOption.Runes? {
        for entry in data.runes ?? [] {
            guard let primary = entry.primaryPageId, let secondary = entry.secondaryPageId else { continue }
            let perkIds = (entry.primaryRuneIds ?? []) + (entry.secondaryRuneIds ?? []) + (entry.statModIds ?? [])
            if perkIds.count == 9 {
                return BuildOption.Runes(primaryStyleId: primary, subStyleId: secondary, perkIds: perkIds)
            }
        }
        return nil
    }

    private func resolvedItemBlocks(from data: Payload) -> [BuildOption.ItemBlock] {
        let starter = data.starterItems?.first?.ids ?? []
        let core = data.coreItems?.first?.ids ?? []
        let boots = data.boots?.first?.ids ?? []
        let excluded = Set(core + boots)
        var seen = Set<Int>()
        let then = (data.lastItems ?? [])
            .compactMap { $0.ids?.first }
            .filter { !excluded.contains($0) && seen.insert($0).inserted }
        let blocks: [(String, [Int])] = [
            ("Starter", starter),
            ("Core", core),
            ("Boots", boots),
            ("Then", Array(then.prefix(3)))
        ]
        return blocks.filter { !$0.1.isEmpty }.map { BuildOption.ItemBlock(title: $0.0, itemIds: $0.1) }
    }
}
