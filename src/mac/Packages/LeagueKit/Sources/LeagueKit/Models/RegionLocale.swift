import Foundation

public extension LCURequesting {
    /// Platform region (e.g. `EUW`) for OP.GG rank lookups.
    func region() async throws -> String {
        let value: RegionLocale = try await get("/riotclient/region-locale")
        return value.region
    }
}

/// `GET /riotclient/region-locale`
struct RegionLocale: Decodable {
    let region: String
}
