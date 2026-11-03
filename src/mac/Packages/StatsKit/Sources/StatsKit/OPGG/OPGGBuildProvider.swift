import Foundation
import os

/// Builds from OP.GG's public MCP server: one aggregated build per champion and role, with stats.
public struct OPGGBuildProvider: BuildProvider {
    static let fields = [
        "champion",
        "data.summary.average_stats.{play,win_rate,pick_rate,ban_rate,tier}",
        "data.runes.{primary_page_id,primary_rune_ids[],secondary_page_id,secondary_rune_ids[],"
            + "stat_mod_ids[],play,win}",
        "data.starter_items.{ids[],play,win}",
        "data.core_items.{ids[],play,win,pick_rate}",
        "data.boots.{ids[],play,win}",
        "data.fourth_items[].{ids[],play,win}",
        "data.summoner_spells.{ids[],play,win}",
        "data.skills.{order[],play,win}"
    ]

    private let client: OPGGClient
    private let cache: ResponseCache
    private let logger = Logger(subsystem: "de.polleydigital.riftglass", category: "OPGG")

    public init(client: OPGGClient = OPGGClient(), cache: ResponseCache = ResponseCache(name: "opgg-builds")) {
        self.client = client
        self.cache = cache
    }

    public func builds(for champion: ChampionRef, role: Role, patch: String?) async throws -> [BuildOption] {
        let cacheKey = "\(champion.key)-\(role.opggPosition)-\(patch ?? "latest")"
        let text: String
        if let cached = await cache.value(for: cacheKey) {
            text = cached
        } else {
            text = try await client.callTool("lol_get_champion_analysis", arguments: [
                "game_mode": .string("ranked"),
                "champion": .string(champion.key.uppercased()),
                "position": .string(role.opggPosition),
                "desired_output_fields": .strings(Self.fields)
            ])
            await cache.store(text, for: cacheKey)
        }
        let option = try Self.buildOption(from: OPGGNotation.parse(text), champion: champion, role: role)
        if option == nil {
            logger.info("OP.GG has no build for \(champion.key, privacy: .public) \(role.rawValue, privacy: .public)")
        }
        return option.map { [$0] } ?? []
    }

    /// Maps `lol_get_champion_analysis` output to a build option. Nil when OP.GG has too little data.
    static func buildOption(from value: NotationValue, champion: ChampionRef, role: Role) -> BuildOption? {
        guard let data = value["data"], let runes = data["runes"],
              let primary = runes["primary_page_id"]?.int, let secondary = runes["secondary_page_id"]?.int
        else { return nil }
        let perkIds = (runes["primary_rune_ids"]?.ints ?? []) + (runes["secondary_rune_ids"]?.ints ?? [])
            + (runes["stat_mod_ids"]?.ints ?? [])
        guard perkIds.count == 9 else { return nil }
        let summary = data["summary"]?["average_stats"]
        let stats = winRate(data["core_items"]).map {
            BuildOption.Stats(
                winRate: $0,
                pickRate: data["core_items"]?["pick_rate"]?.double,
                games: data["core_items"]?["play"]?.int ?? 0
            )
        }
        return BuildOption(
            id: "opgg-\(champion.key)-\(role.rawValue)",
            title: title(summary: summary),
            role: role,
            source: .opgg,
            runes: .init(primaryStyleId: primary, subStyleId: secondary, perkIds: perkIds),
            summonerSpells: data["summoner_spells"]?["ids"]?.ints ?? [],
            itemBlocks: itemBlocks(data),
            skillOrder: data["skills"]?["order"]?.list.compactMap(\.string) ?? [],
            stats: stats
        )
    }

    private static func itemBlocks(_ data: NotationValue) -> [BuildOption.ItemBlock] {
        let alternatives = data["fourth_items"]?.list.compactMap { $0["ids"]?.ints.first } ?? []
        let blocks: [(String, [Int])] = [
            ("Start", data["starter_items"]?["ids"]?.ints ?? []),
            ("Kern", data["core_items"]?["ids"]?.ints ?? []),
            ("Stiefel", data["boots"]?["ids"]?.ints ?? []),
            ("Danach", Array(alternatives.prefix(3)))
        ]
        return blocks.filter { !$0.1.isEmpty }.map { BuildOption.ItemBlock(title: $0.0, itemIds: $0.1) }
    }

    private static func title(summary: NotationValue?) -> String {
        guard let tier = summary?["tier"]?.int else { return "OP.GG-Build" }
        return "OP.GG-Build · Tier \(tier)"
    }

    private static func winRate(_ entry: NotationValue?) -> Double? {
        guard let play = entry?["play"]?.double, play > 0, let win = entry?["win"]?.double else { return nil }
        return win / play
    }
}
