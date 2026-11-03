import Foundation
@testable import LeagueKit

/// Recorded, anonymized fixtures live in `<repo>/tests/fixtures` (outside the package, so they
/// are located relative to this source file instead of via SwiftPM resources).
enum Fixture {
    static let root: URL = {
        // Tests/LeagueKitTests/Fixture.swift → 7 levels up is the repo root.
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 7 {
            url.deleteLastPathComponent()
        }
        return url.appendingPathComponent("tests/fixtures", isDirectory: true)
    }()

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent(name))
    }

    static func decode<T: Decodable>(_ name: String, as _: T.Type = T.self) throws -> T {
        try JSONDecoder().decode(T.self, from: data(name))
    }
}

/// Records requests and answers from a path → JSON table.
actor FakeLCU: LCURequesting {
    struct Request: Equatable {
        let method: HTTPMethod
        let path: String
        let body: Data?
    }

    private(set) var requests: [Request] = []
    private let responses: [String: Data]

    init(responses: [String: Data]) {
        self.responses = responses
    }

    func data(_ method: HTTPMethod, _ path: String, body: Data?) async throws -> Data {
        requests.append(Request(method: method, path: path, body: body))
        if method != .get {
            return Data()
        }
        guard let response = responses[path] else { throw LCUError.http(status: 404, path: path) }
        return response
    }
}
