import Foundation
@testable import StatsKit
import Testing

enum Fixture {
    static let root: URL = {
        // Tests/StatsKitTests/OPGGTests.swift → 7 levels up is the repo root.
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 7 {
            url.deleteLastPathComponent()
        }
        return url.appending(path: "tests/fixtures")
    }()

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: root.appending(path: name))
    }
}

/// Returns canned responses and records request bodies.
actor FakePoster: HTTPPosting {
    private(set) var bodies: [Data] = []
    private let response: Data

    init(response: Data) {
        self.response = response
    }

    func post(_: URL, body: Data, headers _: [String: String]) async throws -> Data {
        bodies.append(body)
        return response
    }
}

struct OPGGNotationTests {
    @Test func parsesClassesListsStringsAndNull() throws {
        let text = """
        class Outer: name,items,inner,missing
        class Inner: value

        Outer("A \\"quoted\\" \\u00e9",[1,-2.5,3e2],Inner(true),null)
        """
        let value = try OPGGNotation.parse(text)
        #expect(value["name"]?.string == "A \"quoted\" é")
        #expect(value["items"]?.list == [.number(1), .number(-2.5), .number(300)])
        #expect(value["inner"]?["value"] == .bool(true))
        #expect(value["missing"] == .null)
    }

    @Test func rejectsMalformedInput() {
        #expect(throws: NotationError.unknownClass("Nope")) { try OPGGNotation.parse("Nope(1)") }
        #expect(throws: NotationError.fieldCountMismatch("A", expected: 2, got: 1)) {
            try OPGGNotation.parse("class A: x,y\n\nA(1)")
        }
        #expect(throws: NotationError.unexpectedEnd) { try OPGGNotation.parse("class A: x\n\nA(1") }
    }

    @Test func parsesRecordedChampionAnalysis() throws {
        let text = try OPGGClient.text(fromResponse: Fixture.data("opgg/ahri-mid.json"))
        let value = try OPGGNotation.parse(text)
        #expect(value["champion"]?.string == "AHRI")
        #expect(value["data"]?["runes"]?["primary_page_id"]?.int == 8100)
    }
}

struct OPGGBuildProviderTests {
    private let ahri = ChampionRef(id: 103, key: "Ahri")

    @Test func mapsRecordedAnalysisToBuildOption() async throws {
        let poster = try FakePoster(response: Fixture.data("opgg/ahri-mid.json"))
        let directory = FileManager.default.temporaryDirectory.appending(path: "rg-\(UUID().uuidString)")
        let provider = OPGGBuildProvider(
            client: OPGGClient(poster: poster),
            cache: ResponseCache(name: "t", directory: directory)
        )
        let builds = try await provider.builds(for: ahri, role: .middle, queue: .ranked, patch: "15.22.1")
        let build = try #require(builds.first)
        #expect(build.source == .opgg)
        #expect(build.runes.primaryStyleId == 8100 && build.runes.subStyleId == 8200)
        #expect(build.runes.perkIds == [8112, 8139, 8140, 8106, 8210, 8226, 5005, 5008, 5001])
        #expect(build.summonerSpells == [4, 14])
        #expect(build.itemBlocks.map(\.title) == ["Start", "Kern", "Stiefel", "Danach"])
        #expect(build.itemBlocks[1].itemIds == [3118, 4645, 3157])
        #expect(build.skillOrder.prefix(3) == ["W", "Q", "E"])
        #expect(abs((build.stats?.winRate ?? 0) - 9325.0 / 17690.0) < 0.0001)
        // Second call is served from the cache.
        _ = try await provider.builds(for: ahri, role: .middle, queue: .ranked, patch: "15.22.1")
        #expect(await poster.bodies.count == 1)
        let body = try #require(await poster.bodies.first)
        let request = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let arguments = (request?["params"] as? [String: Any])?["arguments"] as? [String: Any]
        #expect(arguments?["champion"] as? String == "AHRI")
        #expect(arguments?["position"] as? String == "mid")
    }

    @Test func insufficientDataYieldsNoOption() throws {
        let text = try OPGGClient.text(fromResponse: Fixture.data("opgg/kaisa-jungle-nodata.json"))
        let value = try OPGGNotation.parse(text)
        #expect(OPGGBuildProvider.buildOption(from: value, champion: ahri, role: .jungle) == nil)
    }
}

struct OPGGClientTests {
    @Test func decodesErrorsAndServerSentEvents() throws {
        let rpcError = Data(#"{"jsonrpc":"2.0","id":1,"error":{"code":-32602,"message":"bad"}}"#.utf8)
        #expect(throws: OPGGError.rpc("bad")) { try OPGGClient.text(fromResponse: rpcError) }
        let toolError = Data(#"{"result":{"content":[{"type":"text","text":"nope"}],"isError":true}}"#.utf8)
        #expect(throws: OPGGError.toolError("nope")) { try OPGGClient.text(fromResponse: toolError) }
        let sse = Data("event: message\ndata: {\"result\":{\"content\":[{\"type\":\"text\",\"text\":\"ok\"}]}}\n".utf8)
        #expect(try OPGGClient.text(fromResponse: sse) == "ok")
    }
}

struct RankTests {
    @Test func unrankedFromRecordedProfile() throws {
        let text = try OPGGClient.text(fromResponse: Fixture.data("opgg/profile-unranked.json"))
        let rank = try OPGGRankProvider.soloRank(from: OPGGNotation.parse(text))
        #expect(rank == .unranked)
        #expect(rank.label == "Unranked")
    }

    @Test func rankedLabelsAndWinRate() throws {
        let text = """
        class P: data
        class D: summoner
        class S: league_stats
        class L: game_type,tier_info,win,lose
        class T: tier,division,lp

        P(D(S([L("FLEXRANKED",T("SILVER",1,0),1,1),L("SOLORANKED",T("GOLD","II",45),30,20)])))
        """
        let rank = try OPGGRankProvider.soloRank(from: OPGGNotation.parse(text))
        #expect(rank.label == "Gold II · 45 LP")
        #expect(rank.winRate == 0.6)
        let apex = PlayerRank(tier: "MASTER", division: 1, leaguePoints: 120, wins: nil, losses: nil)
        #expect(apex.label == "Master · 120 LP")
    }
}

struct ResponseCacheTests {
    @Test func expiresAfterTimeToLive() async {
        let directory = FileManager.default.temporaryDirectory.appending(path: "rg-\(UUID().uuidString)")
        let early = ResponseCache(
            name: "t",
            timeToLive: 60,
            directory: directory,
            now: { Date(timeIntervalSince1970: 1000) }
        )
        await early.store("x", for: "k")
        #expect(await early.value(for: "k") == "x")
        let late = ResponseCache(
            name: "t",
            timeToLive: 60,
            directory: directory,
            now: { Date(timeIntervalSince1970: 1100) }
        )
        #expect(await late.value(for: "k") == nil)
    }

    @Test func rolesMapToOPGGAndLCU() {
        #expect(Role.bottom.opggPosition == "adc")
        #expect(Role(lcuPosition: "UTILITY") == .utility)
        #expect(Role.middle.lcuPosition == "MIDDLE")
        #expect(Role(lcuPosition: "") == nil)
    }
}
