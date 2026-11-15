import Foundation

/// Abstraction over HTTP GET so page-based OP.GG sources can be tested offline.
public protocol HTTPGetting: Sendable {
    func get(_ url: URL, headers: [String: String]) async throws -> Data
}

public struct URLSessionGetter: HTTPGetting {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func get(_ url: URL, headers: [String: String]) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 20)
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw OPGGError.http((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return data
    }
}
