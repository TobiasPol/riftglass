import DataKit
import Foundation
import StatsKit

/// Icon prefetching, so cards open with their icons instead of placeholders.
extension ChampSelectCoordinator {
    func prefetchIcons(for builds: [BuildOption]) {
        guard let data = staticData else { return }
        var urls: [URL] = []
        for build in builds {
            urls += build.allItemIds.map { dataDragon.itemIconURL($0, version: data.version) }
            urls += build.summonerSpells.compactMap { data.spellsById[$0] }
                .map { dataDragon.spellIconURL($0, version: data.version) }
            urls += build.runes.perkIds.compactMap { data.runesById[$0] }.map { dataDragon.runeIconURL($0.icon) }
            urls += build.runes.perkIds.dropFirst(6).compactMap { StatShard.shard($0) }
                .map { dataDragon.runeIconURL($0.iconPath) }
        }
        if let championId, let champion = data.champion(championId) {
            urls.append(dataDragon.championIconURL(champion, version: data.version))
        }
        icons.prefetch(urls)
    }

    func prefetchChampionIcons(_ ids: [Int]) {
        guard let data = staticData else { return }
        icons
            .prefetch(ids.compactMap { data.champion($0) }
                .map { dataDragon.championIconURL($0, version: data.version) })
    }
}
