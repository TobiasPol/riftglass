@testable import StatsKit
import Testing

struct BundledBuildProviderTests {
    @Test func bundledFileLoadsFiveChampionsWithSeveralOptions() async throws {
        let provider = try BundledBuildProvider.bundled()
        #expect(provider.championIds == [64, 86, 99, 103, 222])
        for championId in provider.championIds {
            let builds = try await provider.builds(championId: championId, role: nil, patch: nil)
            #expect(builds.count >= 2, "always several options")
            for build in builds {
                #expect(build.isPlaceholder)
                #expect(build.runes.perkIds.count == 9)
                #expect(build.runes.primaryStyleId != build.runes.subStyleId)
                #expect(build.summonerSpells.count == 2)
                #expect(Set(build.summonerSpells).count == 2)
            }
        }
    }

    @Test func filtersByRoleButFallsBackToAll() async throws {
        let provider = try BundledBuildProvider.bundled()
        let mid = try await provider.builds(championId: 103, role: .middle, patch: nil)
        #expect(mid.allSatisfy { $0.role == .middle })
        let offRole = try await provider.builds(championId: 103, role: .top, patch: nil)
        #expect(offRole.count == 2)
        #expect(try await provider.builds(championId: 1, role: nil, patch: nil).isEmpty)
    }

    @Test func rolesMapFromLCUPositions() {
        #expect(Role(lcuPosition: "UTILITY") == .utility)
        #expect(Role(lcuPosition: "") == nil)
        #expect(Role(lcuPosition: nil) == nil)
    }
}
