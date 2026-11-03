import Foundation

/// Abstraction over HTTP GET so Data Dragon can be tested offline.
public protocol HTTPFetching: Sendable {
    func data(from url: URL) async throws -> Data
}

public struct URLSessionFetcher: HTTPFetching {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(from url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

public struct DDImage: Decodable, Equatable, Sendable {
    public let full: String
}

public struct Champion: Decodable, Equatable, Sendable {
    /// Alias used in asset paths, e.g. "MonkeyKing".
    public let id: String
    /// Numeric champion ID as used by the LCU, e.g. "62".
    public let key: String
    public let name: String
    public let image: DDImage
}

public struct SummonerSpell: Decodable, Equatable, Sendable {
    public let id: String
    public let key: String
    public let name: String
    public let image: DDImage
}

public struct RuneStyle: Decodable, Equatable, Sendable {
    public struct Slot: Decodable, Equatable, Sendable {
        public let runes: [Rune]
    }

    public struct Rune: Decodable, Equatable, Sendable {
        public let id: Int
        public let key: String
        public let icon: String
        public let name: String
    }

    public let id: Int
    public let key: String
    public let icon: String
    public let name: String
    public let slots: [Slot]
}

public struct Item: Decodable, Equatable, Sendable {
    public struct Gold: Decodable, Equatable, Sendable {
        public let total: Int
    }

    public let name: String
    public let image: DDImage
    public let gold: Gold?
}

/// `{ "data": { key: value } }` wrapper used by champion/summoner/item JSONs.
struct DataContainer<Value: Decodable & Sendable>: Decodable, Sendable {
    let data: [String: Value]
}

/// All static data of one patch, indexed the way the LCU refers to things.
public struct StaticData: Equatable, Sendable {
    public let version: String
    public let championsById: [Int: Champion]
    public let spellsById: [Int: SummonerSpell]
    public let runesById: [Int: RuneStyle.Rune]
    public let runeStylesById: [Int: RuneStyle]
    public let itemsById: [Int: Item]

    public func champion(_ id: Int) -> Champion? {
        championsById[id]
    }

    /// Total item prices for the gold estimate.
    public var itemPrices: [Int: Int] {
        itemsById.compactMapValues { $0.gold?.total }
    }

    /// Data Dragon key (e.g. "MonkeyKing") → champion.
    public func champion(key: String) -> Champion? {
        championsById.values.first { $0.id == key }
    }
}
