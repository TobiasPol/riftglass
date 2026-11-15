import Foundation
@testable import StatsKit
import Testing

/// Returns a canned page (or fails) and counts requests; `delay` keeps a request open.
actor FakeGetter: HTTPGetting {
    private(set) var requests: [(url: URL, headers: [String: String])] = []
    private var response: Result<Data, any Error>
    private let delay: Duration

    init(response: Data, delay: Duration = .zero) {
        self.response = .success(response)
        self.delay = delay
    }

    func fail(with error: any Error) {
        response = .failure(error)
    }

    func respond(with data: Data) {
        response = .success(data)
    }

    func get(_ url: URL, headers: [String: String]) async throws -> Data {
        requests.append((url, headers))
        let response = response
        try await Task.sleep(for: delay)
        return try response.get()
    }
}

struct OPGGAugmentTests {
    private static let page = "opgg/garen-mayhem-augments-page.html"

    private func cacheDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "rg-\(UUID().uuidString)")
    }

    @Test func readsTierListFromRecordedPage() throws {
        let stats = try OPGGAugmentPage.augments(fromHTML: Fixture.data(Self.page))
        // OP.GG's own order: S tier first, most popular first within a tier.
        #expect(stats.prefix(6).map(\.name) == [
            "Spin To Win", "Vulnerability", "Upgrade Infinity Edge", "BONK!", "Empower!", "Soul Siphon"
        ])
        #expect(stats.prefix(6).allSatisfy { $0.tier == 0 && $0.tierLabel == "S" })
        let spin = try #require(stats.first)
        #expect(spin.id == 1214 && spin.rarity == .silver && abs(spin.popularity - 3.46) < 0.0001)
        #expect(spin.iconURL?.lastPathComponent == "SpinToWin_small.png")
        #expect(stats.map(\.tier) == stats.map(\.tier).sorted())
        // Entries OP.GG lists without a name are no longer in the game.
        #expect(stats.count == 26 && !stats.contains { $0.name.isEmpty })
    }

    /// The regression behind "always the same augments": generically strong augments with a high
    /// `performance` (Hand of Baron, Omni Soul, DOOM) must not outrank the champion's own top tiers.
    @Test func championSpecificTiersBeatGenericPerformance() throws {
        let stats = try OPGGAugmentPage.augments(fromHTML: Fixture.data(Self.page))
        let position = { (name: String) in stats.firstIndex { $0.name == name } ?? -1 }
        #expect(position("Hand of Baron") > position("Overloaded"))
        #expect(position("Overloaded") > position("Icathia's Fall"))
        #expect(position("Icathia's Fall") > position("Soul Siphon"))
        #expect(stats.first { $0.name == "Hand of Baron" }?.tier == 4)
        #expect(stats.last?.tier == 5)
    }

    @Test func rowSplitAcrossChunksAndForeignArraysAreHandled() throws {
        let payload = try OPGGAugmentPage.flightPayload(fromHTML: Fixture.data(Self.page))
        let text = try #require(String(data: payload, encoding: .utf8))
        // The page's first `[{"id":` array is not the augment list.
        #expect(text.contains(#""homeCard":[{"id":"palworld""#))
        #expect(OPGGAugmentPage.augmentEntries(in: payload)?.count == 28)
    }

    @Test func pageWithoutAugmentsIsAnError() {
        let html = Data(#"<script>self.__next_f.push([1,"1:{\"items\":[{\"id\":\"lol\"}]}\n"])</script>"#.utf8)
        #expect(throws: OPGGError.unexpectedPage) { try OPGGAugmentPage.augments(fromHTML: html) }
        #expect(throws: OPGGError.unexpectedPage) { try OPGGAugmentPage.augments(fromHTML: Data("<html>".utf8)) }
    }

    @Test func bracketsInsideStringsDoNotEndTheArray() throws {
        let json = #"[{"id":1,"tier":2,"popular":0.5,"name":"A ] \" [ B","rarity":4}] tail ]"#
        let entries = try #require(OPGGAugmentPage.augmentEntries(in: Data(json.utf8)))
        #expect(entries.map(\.name) == [#"A ] " [ B"#])
        #expect(entries.first?.stat?.rarity == .gold)
    }

    @Test func requestsThePageOncePerCacheLifetime() async throws {
        let getter = try FakeGetter(response: Fixture.data(Self.page))
        let provider = OPGGAugmentProvider(getter: getter, cache: ResponseCache(name: "t", directory: cacheDirectory()))
        let first = try await provider.augments(championId: 86)
        let second = try await provider.augments(championId: 86)
        #expect(first == second && first.count == 26)
        let requests = await getter.requests
        #expect(requests.count == 1)
        #expect(requests.first?.url.absoluteString == "https://op.gg/lol/modes/aram-mayhem/86/augments")
        #expect(requests.first?.headers["User-Agent"] == "Riftglass")
    }

    @Test func expiredListSurvivesAnOutageOrAChangedPage() async throws {
        let clock = TestClock()
        let getter = try FakeGetter(response: Fixture.data(Self.page))
        let cache = ResponseCache(name: "t", timeToLive: 60, directory: cacheDirectory(), now: { clock.date })
        let provider = OPGGAugmentProvider(getter: getter, cache: cache, now: { clock.date })
        let fresh = try await provider.augments(championId: 86)
        clock.date = clock.date.addingTimeInterval(61)
        await getter.fail(with: OPGGError.http(503))
        #expect(try await provider.augments(championId: 86) == fresh)
        clock.date = clock.date.addingTimeInterval(61)
        await getter.respond(with: Data("<html>redesigned</html>".utf8))
        #expect(try await provider.augments(championId: 86) == fresh)
        #expect(await getter.requests.count == 3)
    }

    /// The request budget: once op.gg has answered – even with an error or an unusable page – it is
    /// not asked again for the champion until the cache lifetime is over.
    @Test func answeredFailureIsNotRepeatedWithinTheCacheLifetime() async throws {
        let clock = TestClock()
        let getter = FakeGetter(response: Data("<html>redesigned</html>".utf8))
        let directory = cacheDirectory()
        let cache = ResponseCache(name: "t", timeToLive: 60, directory: directory, now: { clock.date })
        let provider = OPGGAugmentProvider(getter: getter, cache: cache, now: { clock.date })
        for _ in 0 ..< 3 {
            await #expect(throws: OPGGError.unexpectedPage) { try await provider.augments(championId: 1) }
        }
        #expect(await getter.requests.count == 1)
        await getter.fail(with: OPGGError.http(503))
        // Remembered on disk: a new provider (app restart) does not ask either.
        let restarted = OPGGAugmentProvider(
            getter: getter,
            cache: ResponseCache(name: "t", timeToLive: 60, directory: directory, now: { clock.date }),
            now: { clock.date }
        )
        await #expect(throws: OPGGError.unexpectedPage) { try await restarted.augments(championId: 1) }
        #expect(await getter.requests.count == 1)
        clock.date = clock.date.addingTimeInterval(61)
        await #expect(throws: OPGGError.http(503)) { try await restarted.augments(championId: 1) }
        await #expect(throws: OPGGError.http(503)) { try await restarted.augments(championId: 1) }
        #expect(await getter.requests.count == 2)
        // Another champion has its own budget.
        await #expect(throws: OPGGError.http(503)) { try await restarted.augments(championId: 2) }
        #expect(await getter.requests.count == 3)
    }

    /// No answer at all (offline) is not held against op.gg's budget, but still not hammered.
    @Test func unansweredRequestIsRetriedAfterAMinute() async throws {
        let clock = TestClock()
        let getter = try FakeGetter(response: Fixture.data(Self.page))
        await getter.fail(with: URLError(.notConnectedToInternet))
        let cache = ResponseCache(name: "t", directory: cacheDirectory(), now: { clock.date })
        let provider = OPGGAugmentProvider(getter: getter, cache: cache, now: { clock.date })
        await #expect(throws: URLError.self) { try await provider.augments(championId: 86) }
        await #expect(throws: URLError.self) { try await provider.augments(championId: 86) }
        #expect(await getter.requests.count == 1)
        clock.date = clock.date.addingTimeInterval(OPGGAugmentProvider.unansweredRetryInterval + 1)
        try await getter.respond(with: Fixture.data(Self.page))
        #expect(try await provider.augments(championId: 86).count == 26)
        #expect(await getter.requests.count == 2)
    }

    /// Champ select and the in-game overlay can ask for the same champion at the same moment.
    @Test func concurrentCallersShareOneRequest() async throws {
        let getter = try FakeGetter(response: Fixture.data(Self.page), delay: .milliseconds(100))
        let provider = OPGGAugmentProvider(getter: getter, cache: ResponseCache(name: "t", directory: cacheDirectory()))
        async let first = provider.augments(championId: 86)
        async let second = provider.augments(championId: 86)
        async let third = provider.augments(championId: 86)
        let lists = try await [first, second, third]
        #expect(lists.allSatisfy { $0.count == 26 })
        #expect(await getter.requests.count == 1)
    }
}

final class TestClock: @unchecked Sendable {
    var date = Date(timeIntervalSince1970: 1_800_000_000)
}
