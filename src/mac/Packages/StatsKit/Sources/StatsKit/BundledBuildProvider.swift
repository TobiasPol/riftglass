import Foundation

/// Hand-maintained **placeholder** builds for a handful of champions (Phase 1 only).
/// Replaced by `RemoteBuildProvider` (own backend) in Phase 3.
public struct BundledBuildProvider: BuildProvider {
    private let buildsByChampion: [Int: [BuildOption]]

    public init(data: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: data)
        var byChampion: [Int: [BuildOption]] = [:]
        for entry in file.champions {
            byChampion[entry.championId] = entry.builds
        }
        buildsByChampion = byChampion
    }

    public static func bundled() throws -> BundledBuildProvider {
        guard let url = Bundle.module.url(forResource: "placeholder-builds", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try BundledBuildProvider(data: Data(contentsOf: url))
    }

    public var championIds: [Int] {
        buildsByChampion.keys.sorted()
    }

    public func builds(championId: Int, role: Role?, patch _: String?) async throws -> [BuildOption] {
        let all = buildsByChampion[championId] ?? []
        guard let role else { return all }
        let matching = all.filter { $0.role == role }
        return matching.isEmpty ? all : matching
    }
}

private struct File: Decodable {
    let champions: [FileEntry]
}

private struct FileEntry: Decodable {
    let championId: Int
    let builds: [BuildOption]
}
