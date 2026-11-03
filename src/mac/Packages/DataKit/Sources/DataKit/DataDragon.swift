import Foundation
import os

/// Riot's Data Dragon CDN with a per-patch disk cache in
/// `~/Library/Application Support/Riftglass/ddragon/<version>/`.
public actor DataDragon {
    public static let baseURL = URL(string: "https://ddragon.leagueoflegends.com")!

    private let fetcher: any HTTPFetching
    private let cacheDirectory: URL
    private let locale: String
    private var loaded: [String: StaticData] = [:]
    private let logger = Logger(subsystem: "de.polleydigital.riftglass", category: "DataDragon")

    public init(
        fetcher: any HTTPFetching = URLSessionFetcher(),
        cacheDirectory: URL = DataDragon.defaultCacheDirectory,
        locale: String = "de_DE"
    ) {
        self.fetcher = fetcher
        self.cacheDirectory = cacheDirectory
        self.locale = locale
    }

    public static var defaultCacheDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Riftglass/ddragon", directoryHint: .isDirectory)
    }

    /// Newest patch version. Offline: the newest version already in the cache.
    public func latestVersion() async throws -> String {
        do {
            let data = try await fetcher.data(from: Self.baseURL.appending(path: "api/versions.json"))
            guard let latest = try JSONDecoder().decode([String].self, from: data).first else {
                throw URLError(.cannotParseResponse)
            }
            return latest
        } catch {
            guard let cached = cachedVersions().first else { throw error }
            logger.notice("Data Dragon offline, using cached \(cached, privacy: .public)")
            return cached
        }
    }

    public func staticData(version: String) async throws -> StaticData {
        if let data = loaded[version] {
            return data
        }
        async let champions: DataContainer<Champion> = file("champion.json", version: version)
        async let spells: DataContainer<SummonerSpell> = file("summoner.json", version: version)
        async let items: DataContainer<Item> = file("item.json", version: version)
        async let styles: [RuneStyle] = file("runesReforged.json", version: version)
        let result = try await StaticDataBuilder.build(
            version: version,
            champions: champions.data.values,
            spells: spells.data.values,
            items: items.data,
            styles: styles
        )
        loaded[version] = result
        return result
    }

    // MARK: - Asset URLs

    public nonisolated func championIconURL(_ champion: Champion, version: String) -> URL {
        Self.baseURL.appending(path: "cdn/\(version)/img/champion/\(champion.image.full)")
    }

    public nonisolated func spellIconURL(_ spell: SummonerSpell, version: String) -> URL {
        Self.baseURL.appending(path: "cdn/\(version)/img/spell/\(spell.image.full)")
    }

    public nonisolated func itemIconURL(_ itemId: Int, version: String) -> URL {
        Self.baseURL.appending(path: "cdn/\(version)/img/item/\(itemId).png")
    }

    public nonisolated func runeIconURL(_ iconPath: String) -> URL {
        Self.baseURL.appending(path: "cdn/img/\(iconPath)")
    }

    // MARK: - Cache

    private func file<T: Decodable & Sendable>(_ name: String, version: String) async throws -> T {
        let local = cacheDirectory.appending(path: "\(version)/\(locale)/\(name)")
        if let data = try? Data(contentsOf: local), let value = try? JSONDecoder().decode(T.self, from: data) {
            return value
        }
        let remote = Self.baseURL.appending(path: "cdn/\(version)/data/\(locale)/\(name)")
        let data = try await fetcher.data(from: remote)
        let value = try JSONDecoder().decode(T.self, from: data)
        try? FileManager.default.createDirectory(
            at: local.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: local, options: .atomic)
        return value
    }

    private func cachedVersions() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: cacheDirectory.path)) ?? []
        return names.filter { $0.first?.isNumber == true }
            .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
    }
}

enum StaticDataBuilder {
    static func build(
        version: String,
        champions: some Sequence<Champion>,
        spells: some Sequence<SummonerSpell>,
        items: [String: Item],
        styles: [RuneStyle]
    ) -> StaticData {
        let championsById = Dictionary(
            champions.compactMap { champion in Int(champion.key).map { ($0, champion) } },
            uniquingKeysWith: { first, _ in first }
        )
        let spellsById = Dictionary(
            spells.compactMap { spell in Int(spell.key).map { ($0, spell) } },
            uniquingKeysWith: { first, _ in first }
        )
        let itemsById = Dictionary(
            items.compactMap { key, item in Int(key).map { ($0, item) } },
            uniquingKeysWith: { first, _ in first }
        )
        let runes = styles.flatMap { $0.slots.flatMap(\.runes) }
        return StaticData(
            version: version,
            championsById: championsById,
            spellsById: spellsById,
            runesById: Dictionary(runes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
            runeStylesById: Dictionary(
                styles.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            ),
            itemsById: itemsById
        )
    }
}
